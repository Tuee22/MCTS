{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 7.4: brick TUI for `mcts inspect replay`. Navigates
-- through a stored `Transcript` move-by-move, rendering the board
-- after each ply plus the chosen action, visit-count list, and
-- short hash. Forward/back via arrow keys, jump-to-start/end via
-- Home/End, quit via q/Esc.
--
-- The pure `applyReplayKey` dispatcher is unit-testable; the
-- `runReplayTui` entry runs the full brick event loop. Multi-
-- backend equity overlays per Sprint 7.4 are passed in as a list of
-- `EqStream`s (one per cached sidecar) and rendered as a per-move
-- column showing each backend's chosen action and parent-perspective
-- equity for the current move.
module MCTS.CLI.Tui.Replay
    ( runReplayTui
    , runReplayTuiWithOverlays
    , runReplayTuiFromState
    , ReplayState (..)
    , initialReplayState
    , initialReplayStateWithOverlays
    , applyReplayKey
    , ReplayKey (..)
    , ReplayOverlayLoadResult (..)
    , nextOverlayBackend
    , applyOverlayLoadResult
    , renderOverlayRowsText
    , replayBoardAt
    , currentOverlayRows
    , OverlayRow (..)
    ) where

import qualified Brick.AttrMap as A
import Brick.Main (App (..), defaultMain, halt, neverShowCursor)
import Brick.Types (BrickEvent (..), EventM, Widget)
import Brick.Util (fg)
import Brick.Widgets.Border (border, borderWithLabel)
import Brick.Widgets.Core (str, vBox, withAttr)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (get, modify)
import Data.List (find)
import qualified Data.Map.Strict as Map
import qualified Graphics.Vty as V
import Text.Printf (printf)

import MCTS.CLI.Tui.Board (renderBoard, renderStatus)
import MCTS.Engine (Board, applyMove, initialBoard)
import MCTS.Notation (renderMove)
import MCTS.Transcript.EquitySidecar (EqRecord (..), EqStream (..))
import MCTS.Types
    ( Backend
    , Envelope (..)
    , GameTranscript (..)
    , MoveRecord (..)
    , Transcript (..)
    , allBackends
    , backendIdentifier
    )

data ReplayOverlayLoadResult
    = ReplayOverlayLoaded !EqStream
    | ReplayOverlaySkipped !String
    | ReplayOverlayFailed !String
    deriving (Eq, Show)

data ReplayState = ReplayState
    { replayTranscript :: !Transcript
    , replayHash :: !String
    , replayMoveIndex :: !Int
    -- ^ 0..N where N = total moves in the flattened transcript
    , replayMessage :: !String
    , replayOverlays :: ![EqStream]
    -- ^ Sprint 7.4: one EqStream per cached sidecar feeding the
    -- per-move equity overlay column.
    , replayOverlayLoader :: !(Maybe (Backend -> IO ReplayOverlayLoadResult))
    -- ^ Optional on-demand loader used by the `r` key to materialise
    -- another backend column.
    , replayOverlayCandidates :: ![Backend]
    -- ^ Ordered backend list used by the on-demand column loader.
    , replayUnavailableBackends :: ![Backend]
    -- ^ Backends already attempted and skipped/failed in this TUI
    -- session; excluded from the next `r` request.
    , replayBoardCache :: !(Map.Map Int Board)
    -- ^ Sprint 7.4: last N reconstructed `Board` snapshots, keyed
    -- by `replayMoveIndex`. Forward navigation reuses the cached
    -- board at `idx - 1` so we avoid replaying from move 0 every
    -- time. Size-bounded by `replayCacheStates`.
    , replayCacheStates :: !Int
    }

flattenMoves :: Transcript -> [MoveRecord]
flattenMoves = concatMap gameMoves . transcriptGames

flattenGameIds :: Transcript -> [(Int, MoveRecord)]
flattenGameIds transcript =
    concatMap
        ( \gameRec ->
            [(fromIntegral (gameId gameRec), record) | record <- gameMoves gameRec]
        )
        (transcriptGames transcript)

-- | Reconstruct the board after applying moves 0..n-1.
replayBoardAt :: Transcript -> Int -> Board
replayBoardAt transcript idx =
    let moves = take idx (flattenMoves transcript)
     in foldl (\b record -> applyMove (moveChosen record) b) initialBoard moves

initialReplayState :: String -> Transcript -> ReplayState
initialReplayState hashValue transcript =
    initialReplayStateWithOverlays hashValue transcript []

initialReplayStateWithOverlays :: String -> Transcript -> [EqStream] -> ReplayState
initialReplayStateWithOverlays hashValue transcript overlays =
    ReplayState
        { replayTranscript = transcript
        , replayHash = take 8 hashValue
        , replayMoveIndex = 0
        , replayMessage = "← prev  → next  Home start  End end  r column  q quit"
        , replayOverlays = overlays
        , replayOverlayLoader = Nothing
        , replayOverlayCandidates = allBackends
        , replayUnavailableBackends = []
        , replayBoardCache = Map.singleton 0 initialBoard
        , replayCacheStates = 20
        }

-- | Look up `idx` in the cache; if absent, reconstruct by replaying
-- from the nearest cached predecessor (defaults to move 0) and
-- insert the result into the cache, evicting older entries to keep
-- the cache size at most `replayCacheStates`. Pure on
-- (`Transcript`, `Map`) so testable.
boardWithCache
    :: Int
    -- ^ target move index
    -> ReplayState
    -> (Board, Map.Map Int Board)
boardWithCache idx st =
    case Map.lookup idx (replayBoardCache st) of
        Just board -> (board, replayBoardCache st)
        Nothing ->
            let cache = replayBoardCache st
                anchorIdx =
                    case Map.lookupLE idx cache of
                        Just (k, _) -> k
                        Nothing -> 0
                anchorBoard = Map.findWithDefault initialBoard anchorIdx cache
                flattened = flattenMoves (replayTranscript st)
                moves = take (idx - anchorIdx) (drop anchorIdx flattened)
                resolved = foldl (\b record -> applyMove (moveChosen record) b) anchorBoard moves
                inserted = Map.insert idx resolved cache
                trimmed =
                    if Map.size inserted <= max 1 (replayCacheStates st)
                        then inserted
                        else
                            -- Evict the entry farthest from `idx` (LRU-ish).
                            case Map.lookupMin inserted of
                                Just (k, _) | k /= 0 && k /= idx -> Map.delete k inserted
                                _ -> inserted
             in (resolved, trimmed)

-- | Keys the dispatcher handles. Pure data so the tests can exercise
-- behaviour without spinning up brick.
data ReplayKey
    = ReplayPrev
    | ReplayNext
    | ReplayStart
    | ReplayEnd
    | ReplayRequestOverlay
    | ReplayQuit
    deriving (Eq, Show)

-- | Returns `Nothing` for quit, `Just newState` otherwise. The
-- returned state preserves the cached-board map and warms it for
-- the new `replayMoveIndex` so subsequent renders are O(1).
applyReplayKey :: ReplayKey -> ReplayState -> Maybe ReplayState
applyReplayKey key st =
    case key of
        ReplayQuit -> Nothing
        ReplayPrev -> Just (warm (max 0 (replayMoveIndex st - 1)))
        ReplayNext ->
            let total = length (flattenMoves (replayTranscript st))
                next = min total (replayMoveIndex st + 1)
             in Just (warm next)
        ReplayStart -> Just (warm 0)
        ReplayEnd ->
            let total = length (flattenMoves (replayTranscript st))
             in Just (warm total)
        ReplayRequestOverlay -> Just st
  where
    warm idx =
        let (_, cache') = boardWithCache idx st
         in st{replayMoveIndex = idx, replayBoardCache = cache'}

data OverlayRow = OverlayRow
    { overlayBackendId :: !Backend
    , overlayBuildId :: !String
    , overlayChosen :: !(Maybe String)
    -- ^ Rendered move notation (e.g. `*(4,1)`) for this backend's
    -- chosen action at the current move, or `Nothing` if the
    -- backend's `EqStream` does not carry a record at this index.
    , overlayEquity :: !(Maybe Double)
    , overlayStatus :: !String
    , overlayDivergence :: !(Maybe String)
    }
    deriving (Eq, Show)

-- | Look up each overlay's record at the current move and produce a
-- list of rows for the renderer. Pure so tests can drive it.
currentOverlayRows :: ReplayState -> [OverlayRow]
currentOverlayRows st
    | idx <= 0 || idx > length flattened = map empty (replayOverlays st) <> unavailableRows
    | otherwise =
        case indexAt (idx - 1) flattened of
            Just (currentGameId, currentRecord) ->
                map (overlayAt currentRecord (currentGameId, moveIndex currentRecord)) (replayOverlays st)
                    <> unavailableRows
            Nothing -> map empty (replayOverlays st) <> unavailableRows
  where
    flattened = flattenGameIds (replayTranscript st)
    idx = replayMoveIndex st
    originEnvelope = transcriptEnvelope (replayTranscript st)
    empty stream =
        OverlayRow
            { overlayBackendId = eqBackend stream
            , overlayBuildId = eqBuildId stream
            , overlayChosen = Nothing
            , overlayEquity = Nothing
            , overlayStatus = overlayBaseStatus originEnvelope stream
            , overlayDivergence = Nothing
            }
    unavailableRows =
        [ OverlayRow
            { overlayBackendId = backend
            , overlayBuildId = "unavailable"
            , overlayChosen = Nothing
            , overlayEquity = Nothing
            , overlayStatus = "unavailable"
            , overlayDivergence = Nothing
            }
        | backend <- replayUnavailableBackends st
        ]
    overlayAt currentRecord (gid, mvi) stream =
        let recordMap =
                Map.fromList
                    [ ((eqGameId r, eqMoveIndex r), r)
                    | r <- eqRecords stream
                    ]
            located = Map.lookup (fromIntegral gid, mvi) recordMap
         in OverlayRow
                { overlayBackendId = eqBackend stream
                , overlayBuildId = eqBuildId stream
                , overlayChosen = renderMove . eqChosen <$> located
                , overlayEquity = eqEquity <$> located
                , overlayStatus = overlayStatusFor originEnvelope currentRecord located stream
                , overlayDivergence = overlayDivergenceFor currentRecord located
                }

overlayBaseStatus :: Envelope -> EqStream -> String
overlayBaseStatus envelope stream
    | eqBackend stream == envelopeBackend envelope
        && eqBuildId stream == envelopeBuildId envelope =
        "originator"
    | eqBackend stream == envelopeBackend envelope =
        "originator build-mismatch"
    | otherwise = "foreign-view"

overlayStatusFor :: Envelope -> MoveRecord -> Maybe EqRecord -> EqStream -> String
overlayStatusFor envelope currentRecord located stream =
    overlayBaseStatus envelope stream <> " " <> verificationStatus
  where
    verificationStatus =
        case located of
            Nothing -> "unavailable"
            Just record
                | eqChosen record == moveChosen currentRecord -> "verified"
                | otherwise -> "diverged"

overlayDivergenceFor :: MoveRecord -> Maybe EqRecord -> Maybe String
overlayDivergenceFor currentRecord located =
    case located of
        Just record
            | eqChosen record /= moveChosen currentRecord ->
                Just ("move " <> renderMove (moveChosen currentRecord) <> "!=" <> renderMove (eqChosen record))
        _ -> Nothing

drawUi :: ReplayState -> [Widget String]
drawUi st =
    [ vBox
        [ border (renderBoard (fst (boardWithCache (replayMoveIndex st) st)))
        , borderWithLabel (str "replay") $
            vBox
                [ renderStatus
                    (replayHash st)
                    (replayMoveIndex st)
                    (length (flattenMoves (replayTranscript st)))
                , str ("move played: " <> currentMoveText st)
                , overlayWidget (currentOverlayRows st)
                , withAttr (A.attrName "message") (str (replayMessage st))
                ]
        ]
    ]

overlayWidget :: [OverlayRow] -> Widget String
overlayWidget [] = str "" -- no sidecars cached; no overlay rendered
overlayWidget rows =
    withAttr (A.attrName "overlay") $
        vBox (map str (renderOverlayRowsText rows))

renderOverlayRowsText :: [OverlayRow] -> [String]
renderOverlayRowsText [] = []
renderOverlayRowsText rows =
    "backend          build      status                    chosen     equity   divergence"
        : map renderOverlayRowText rows

renderOverlayRowText :: OverlayRow -> String
renderOverlayRowText row =
    padEnd 16 (backendIdentifier (overlayBackendId row))
        <> " "
        <> padEnd 10 (overlayBuildId row)
        <> " "
        <> padEnd 25 (overlayStatus row)
        <> " "
        <> padEnd 10 (maybe "-" id (overlayChosen row))
        <> " "
        <> padEnd 8 (maybe "-" formatEquity (overlayEquity row))
        <> " "
        <> maybe "-" id (overlayDivergence row)

padEnd :: Int -> String -> String
padEnd n s = take n (s <> repeat ' ')

formatEquity :: Double -> String
formatEquity value
    | isNaN value = "NaN"
    | otherwise = printf "%+.4f" value

currentMoveText :: ReplayState -> String
currentMoveText st =
    let moves = flattenMoves (replayTranscript st)
        idx = replayMoveIndex st
     in if idx <= 0 || idx > length moves
            then "(start of transcript)"
            else maybe "(start of transcript)" (renderMove . moveChosen) (indexAt (idx - 1) moves)

indexAt :: Int -> [a] -> Maybe a
indexAt n _
    | n < 0 = Nothing
indexAt _ [] = Nothing
indexAt 0 (value : _) = Just value
indexAt n (_ : rest) = indexAt (n - 1) rest

handleEvent :: BrickEvent String () -> EventM String ReplayState ()
handleEvent (VtyEvent (V.EvKey key _mods)) =
    case toReplayKey key of
        Just ReplayQuit -> halt
        Just ReplayRequestOverlay -> loadNextOverlay
        Just k -> do
            st <- get
            case applyReplayKey k st of
                Nothing -> halt
                Just st' -> modify (const st')
        Nothing -> pure ()
handleEvent _ = pure ()

loadNextOverlay :: EventM String ReplayState ()
loadNextOverlay = do
    st <- get
    case replayOverlayLoader st of
        Nothing ->
            modify
                ( \current ->
                    current{replayMessage = "on-demand replay columns are unavailable in this context"}
                )
        Just loader ->
            case nextOverlayBackend st of
                Nothing ->
                    modify
                        ( \current ->
                            current{replayMessage = "all replay equity columns are loaded or unavailable"}
                        )
                Just backend -> do
                    result <- liftIO (loader backend)
                    modify (applyOverlayLoadResult backend result)

nextOverlayBackend :: ReplayState -> Maybe Backend
nextOverlayBackend st =
    find wantsColumn (replayOverlayCandidates st)
  where
    loaded = map eqBackend (replayOverlays st)
    unavailable = replayUnavailableBackends st
    wantsColumn backend =
        backend `notElem` loaded && backend `notElem` unavailable

applyOverlayLoadResult :: Backend -> ReplayOverlayLoadResult -> ReplayState -> ReplayState
applyOverlayLoadResult backend result st =
    case result of
        ReplayOverlayLoaded stream ->
            st
                { replayOverlays = replayOverlays st <> [stream]
                , replayUnavailableBackends = filter (/= backend) (replayUnavailableBackends st)
                , replayMessage =
                    "loaded "
                        <> backendIdentifier (eqBackend stream)
                        <> " replay equity column"
                }
        ReplayOverlaySkipped message ->
            st
                { replayUnavailableBackends = markUnavailable
                , replayMessage = message
                }
        ReplayOverlayFailed message ->
            st
                { replayUnavailableBackends = markUnavailable
                , replayMessage =
                    "recompute failed for "
                        <> backendIdentifier backend
                        <> ": "
                        <> message
                }
  where
    markUnavailable =
        if backend `elem` replayUnavailableBackends st
            then replayUnavailableBackends st
            else replayUnavailableBackends st <> [backend]

toReplayKey :: V.Key -> Maybe ReplayKey
toReplayKey key =
    case key of
        V.KEsc -> Just ReplayQuit
        V.KChar 'q' -> Just ReplayQuit
        V.KLeft -> Just ReplayPrev
        V.KChar 'h' -> Just ReplayPrev
        V.KRight -> Just ReplayNext
        V.KChar 'l' -> Just ReplayNext
        V.KHome -> Just ReplayStart
        V.KEnd -> Just ReplayEnd
        V.KChar 'r' -> Just ReplayRequestOverlay
        _ -> Nothing

replayApp :: App ReplayState () String
replayApp =
    App
        { appDraw = drawUi
        , appChooseCursor = neverShowCursor
        , appHandleEvent = handleEvent
        , appStartEvent = pure ()
        , appAttrMap =
            const
                ( A.attrMap
                    V.defAttr
                    [ (A.attrName "message", fg V.white)
                    , (A.attrName "overlay", fg V.cyan)
                    ]
                )
        }

-- | Entry point used by `mcts inspect replay` when a TTY is
-- available. Returns the final `ReplayState` so callers can drive
-- assertions in tests.
runReplayTui :: String -> Transcript -> IO ReplayState
runReplayTui hashValue transcript =
    defaultMain replayApp (initialReplayState hashValue transcript)

-- | Sprint 7.4: entry point with overlay sidecars; called from
-- `MCTS.CLI.Inspect.inspectReplay` after loading cached `EqStream`s.
runReplayTuiWithOverlays :: String -> Transcript -> [EqStream] -> IO ReplayState
runReplayTuiWithOverlays hashValue transcript overlays =
    runReplayTuiFromState (initialReplayStateWithOverlays hashValue transcript overlays)

-- | Run the brick event loop from a caller-constructed `ReplayState`,
-- exposing the cache-size knob plus any future replay-state fields
-- to the operator without forcing new function arguments.
runReplayTuiFromState :: ReplayState -> IO ReplayState
runReplayTuiFromState = defaultMain replayApp
