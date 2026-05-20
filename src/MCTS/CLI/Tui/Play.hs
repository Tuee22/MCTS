{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Sprint 7.4: interactive `brick` TUI for `mcts play`. The board
-- renders via `MCTS.CLI.Tui.Board.renderBoard`; the event loop
-- accepts legacy-notation move input via `MCTS.Notation.parseMove`,
-- applies it, then advances the AI through the selected backend's
-- search path. The in-app commands `:hint`, `:undo`,
-- `:save`, `:quit` are dispatched per
-- [DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint 7.4](../../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md).
module MCTS.CLI.Tui.Play
    ( runInteractivePlay
    , PlayState (..)
    , initialPlayState
    , applyUserInput
    , savePlayState
    , advanceAiState
    , UserInputOutcome (..)
    ) where

import qualified Brick.AttrMap as A
import Brick.Main (App (..), defaultMain, halt, neverShowCursor)
import Brick.Types (BrickEvent (..), EventM, Widget)
import Brick.Util (fg)
import Brick.Widgets.Border (border)
import Brick.Widgets.Core (str, vBox, withAttr)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (get, modify, put)
import qualified Data.Text as Text
import Data.Word (Word16, Word32, Word64)
import qualified Graphics.Vty as V
import System.Directory (doesFileExist)

import MCTS.CLI.Tui.Board (renderBoard, renderStatus)
import MCTS.Driver (makeLogicalEnvelope, uctChooseMove)
import MCTS.Driver.ForeignSearch (ForeignSearchOpener, foreignSearchMove)
import MCTS.Engine
    ( Board (..)
    , applyMove
    , initialBoard
    , legalMoves
    , terminalWinner
    )
import MCTS.Error (AppError (..), renderError)
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath, withCppFunctionalSearchGame)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath, withCppImperativeSearchGame)
import MCTS.FFI.CppLegacy (cppLegacyLibraryPath, withCppLegacySearchGame)
import MCTS.FFI.Rust (rustLibraryPath, withRustSearchGame)
import MCTS.Notation (parseMove, renderMove)
import MCTS.Rng.Mix (mix)
import MCTS.Transcript (writePlayTranscript)
import MCTS.Types
    ( Action
    , Backend (..)
    , GameTranscript (..)
    , MoveRecord (..)
    , RngSource (..)
    , RunConfig (..)
    , Side (..)
    , SimBudget (..)
    , Threading (..)
    , Transcript (..)
    , Winner (..)
    , Workload (..)
    , backendIdentifier
    , otherSide
    , shortHash
    )

data PlayState = PlayState
    { playStateBoard :: !Board
    , playStateHistory :: ![Board]
    -- ^ Snapshots before each played move; head is most-recent.
    , playStateRecords :: ![MoveRecord]
    -- ^ Chronological transcript records for played moves.
    , playStateBackend :: !Backend
    , playStateAiSide :: !Side
    , playStateVsBackend :: !(Maybe Backend)
    , playStateCacheDir :: !(Maybe FilePath)
    , playStateRng :: !RngSource
    , playStateMoveCount :: !Int
    , playStateSeed :: !Word64
    , playStateMaxPlies :: !Word16
    , playStateSims :: !Int
    , playStateMessage :: !String
    , playStateInput :: !String
    -- ^ Current text buffer being typed (between user keystrokes).
    , playStateLastHint :: !(Maybe Action)
    , playStateDone :: !(Maybe Winner)
    }

initialPlayState :: Word64 -> Word16 -> Int -> PlayState
initialPlayState = initialPlayStateFor Haskell Villain Nothing Nothing NativeRng

initialPlayStateFor
    :: Backend
    -> Side
    -> Maybe Backend
    -> Maybe FilePath
    -> RngSource
    -> Word64
    -> Word16
    -> Int
    -> PlayState
initialPlayStateFor backend aiSide vsBackend cacheDir rng seed maxPlies sims =
    PlayState
        { playStateBoard = initialBoard
        , playStateHistory = []
        , playStateRecords = []
        , playStateBackend = backend
        , playStateAiSide = aiSide
        , playStateVsBackend = vsBackend
        , playStateCacheDir = cacheDir
        , playStateRng = rng
        , playStateMoveCount = 0
        , playStateSeed = seed
        , playStateMaxPlies = maxPlies
        , playStateSims = sims
        , playStateMessage = initialPlayMessage aiSide vsBackend
        , playStateInput = ""
        , playStateLastHint = Nothing
        , playStateDone = Nothing
        }

initialPlayMessage :: Side -> Maybe Backend -> String
initialPlayMessage aiSide vsBackend =
    case vsBackend of
        Nothing ->
            "human "
                <> show (otherSide aiSide)
                <> "; type *(x,y) / H(x,y) / V(x,y); :hint :undo :quit"
        Just backend ->
            "spectator mode: "
                <> show aiSide
                <> " vs "
                <> backendIdentifier backend
                <> "; press Space"

-- | Outcome of dispatching a single text line.
data UserInputOutcome
    = OutcomeQuit
    | OutcomeContinue !PlayState
    | OutcomeSave !PlayState

-- | Pure dispatcher for one input line. Returns either `OutcomeQuit`
-- to terminate the event loop, or `OutcomeContinue` with an updated
-- `PlayState`. Pure so it can be unit-tested.
applyUserInput :: String -> PlayState -> UserInputOutcome
applyUserInput raw st =
    case dropWhile (== ' ') raw of
        "" -> OutcomeContinue st{playStateInput = ""}
        ":quit" -> OutcomeQuit
        ":q" -> OutcomeQuit
        ":hint" -> OutcomeContinue (issueHint st)
        ":undo" -> OutcomeContinue (issueUndo st)
        ":save" ->
            OutcomeSave
                st
                    { playStateMessage = "saving transcript"
                    , playStateInput = ""
                    }
        other -> OutcomeContinue (applyMoveText other st)

applyMoveText :: String -> PlayState -> PlayState
applyMoveText raw st =
    case backendForCurrentTurn st of
        Just backend ->
            st
                { playStateInput = ""
                , playStateMessage =
                    "waiting for "
                        <> backendIdentifier backend
                        <> " to move as "
                        <> show (boardSideToMove (playStateBoard st))
                        <> "; press Space"
                }
        Nothing -> applyHumanMove raw st

applyHumanMove :: String -> PlayState -> PlayState
applyHumanMove raw st =
    case parseMove raw of
        Nothing ->
            st
                { playStateInput = ""
                , playStateMessage = "InvalidMove: could not parse `" <> raw <> "`"
                }
        Just action ->
            if action `elem` legalMoves (playStateBoard st)
                then
                    let nextBoard = applyMove action (playStateBoard st)
                        terminal = terminalWinner (playStateMaxPlies st) nextBoard
                        record = playMoveRecord st action []
                     in st
                            { playStateBoard = nextBoard
                            , playStateHistory = playStateBoard st : playStateHistory st
                            , playStateRecords = playStateRecords st <> [record]
                            , playStateMoveCount = playStateMoveCount st + 1
                            , playStateInput = ""
                            , playStateLastHint = Nothing
                            , playStateMessage = "applied " <> renderMove action
                            , playStateDone = settleTerminal nextBoard terminal
                            }
                else
                    st
                        { playStateInput = ""
                        , playStateMessage = "InvalidMove: " <> renderMove action <> " is not legal here"
                        }

settleTerminal :: Board -> Maybe Winner -> Maybe Winner
settleTerminal board terminal =
    case terminal of
        Just w -> Just w
        Nothing
            | null (legalMoves board) -> Just Draw
            | otherwise -> Nothing

issueHint :: PlayState -> PlayState
issueHint st =
    let backend = maybe (playStateBackend st) id (backendForCurrentTurn st)
        (chosen, _) = logicalAiMoveFor backend st
     in st
            { playStateLastHint = Just chosen
            , playStateInput = ""
            , playStateMessage = "hint: " <> renderMove chosen
            }

issueUndo :: PlayState -> PlayState
issueUndo st =
    case playStateHistory st of
        [] -> st{playStateInput = "", playStateMessage = "nothing to undo"}
        (prev : rest) ->
            st
                { playStateBoard = prev
                , playStateHistory = rest
                , playStateRecords = dropLast (playStateRecords st)
                , playStateMoveCount = max 0 (playStateMoveCount st - 1)
                , playStateDone = Nothing
                , playStateLastHint = Nothing
                , playStateInput = ""
                , playStateMessage = "undid one move"
                }

drawUi :: PlayState -> [Widget String]
drawUi st =
    [ vBox
        [ border (renderBoard (playStateBoard st))
        , border $
            renderStatus
                "play"
                (playStateMoveCount st)
                (fromIntegral (playStateMaxPlies st))
        , withAttr (A.attrName "message") (str (playStateMessage st))
        , str ("> " <> playStateInput st)
        , case playStateLastHint st of
            Nothing -> str ""
            Just hint -> withAttr (A.attrName "hint") (str ("hint: " <> renderMove hint))
        , case playStateDone st of
            Nothing -> str ""
            Just winner -> withAttr (A.attrName "winner") (str ("Game over: " <> show winner))
        ]
    ]

handleEvent :: BrickEvent String () -> EventM String PlayState ()
handleEvent (VtyEvent (V.EvKey key _mods)) =
    case key of
        V.KEsc -> halt
        V.KEnter -> do
            st <- get
            case applyUserInput (playStateInput st) st of
                OutcomeQuit -> halt
                OutcomeContinue st' -> do
                    put st'
                    if playStateMoveCount st' > playStateMoveCount st
                        then case playStateDone st' of
                            Nothing -> advanceAi
                            Just _ -> pure ()
                        else pure ()
                OutcomeSave st' -> do
                    saved <- liftIO (savePlayState st')
                    put saved
        V.KChar ' ' -> do
            st <- get
            -- Space when buffer is empty advances AI as a smoke shortcut;
            -- otherwise treated as literal whitespace in the input.
            if null (playStateInput st)
                then case backendForCurrentTurn st of
                    Just _ -> advanceAi
                    Nothing -> modify $ \s -> s{playStateMessage = "human turn: enter a move or :hint"}
                else modify $ \s -> s{playStateInput = playStateInput s <> " "}
        V.KChar ch -> modify $ \s -> s{playStateInput = playStateInput s <> [ch]}
        V.KBS -> modify $ \s -> s{playStateInput = dropLast (playStateInput s)}
        V.KDel -> modify $ \s -> s{playStateInput = ""}
        _ -> pure ()
handleEvent _ = pure ()

dropLast :: [a] -> [a]
dropLast [] = []
dropLast [_] = []
dropLast (x : xs) = x : dropLast xs

advanceAi :: EventM String PlayState ()
advanceAi = do
    st <- get
    advanced <- liftIO (advanceAiState st)
    put advanced

advanceAiState :: PlayState -> IO PlayState
advanceAiState st =
    case playStateDone st of
        Just _ -> pure st
        Nothing ->
            case backendForCurrentTurn st of
                Nothing ->
                    pure
                        st
                            { playStateMessage = "human turn: enter a move or :hint"
                            , playStateInput = ""
                            }
                Just backend -> do
                    selected <- selectAiMove backend st
                    pure $
                        case selected of
                            Left err ->
                                st
                                    { playStateMessage = "AI search failed: " <> Text.unpack (renderError err)
                                    , playStateInput = ""
                                    }
                            Right (chosen, visits, sourceLabel) ->
                                let record = playMoveRecord st chosen visits
                                    nextBoard = applyMove chosen (playStateBoard st)
                                    terminal = terminalWinner (playStateMaxPlies st) nextBoard
                                 in st
                                        { playStateBoard = nextBoard
                                        , playStateHistory = playStateBoard st : playStateHistory st
                                        , playStateRecords = playStateRecords st <> [record]
                                        , playStateMoveCount = playStateMoveCount st + 1
                                        , playStateMessage = "AI played " <> renderMove chosen <> sourceLabel
                                        , playStateLastHint = Nothing
                                        , playStateInput = ""
                                        , playStateDone = settleTerminal nextBoard terminal
                                        }

backendForCurrentTurn :: PlayState -> Maybe Backend
backendForCurrentTurn st =
    backendForSide st (boardSideToMove (playStateBoard st))

backendForSide :: PlayState -> Side -> Maybe Backend
backendForSide st side
    | side == playStateAiSide st = Just (playStateBackend st)
    | otherwise = playStateVsBackend st

selectAiMove :: Backend -> PlayState -> IO (Either AppError (Action, [(Action, Word32)], String))
selectAiMove backend st =
    case backend of
        Haskell -> pure (Right (tagMove (" via " <> backendIdentifier backend) (logicalAiMoveFor backend st)))
        CppLegacy -> chooseForeign CppLegacy cppLegacyLibraryPath withCppLegacySearchGame st
        CppImperative -> chooseForeign CppImperative cppImperativeLibraryPath withCppImperativeSearchGame st
        CppFunctional -> chooseForeign CppFunctional cppFunctionalLibraryPath withCppFunctionalSearchGame st
        Rust -> chooseForeign Rust rustLibraryPath withRustSearchGame st

chooseForeign
    :: Backend
    -> FilePath
    -> ForeignSearchOpener
    -> PlayState
    -> IO (Either AppError (Action, [(Action, Word32)], String))
chooseForeign backend libraryPath opener st = do
    present <- doesFileExist libraryPath
    if present
        then do
            searched <-
                foreignSearchMove
                    backend
                    opener
                    (playStateRng st)
                    (playGameSeed st)
                    (playStateMaxPlies st)
                    (playStateSims st)
                    (playStateBoard st)
                    (playStateRecords st)
            pure ((\result -> (fst result, snd result, " via " <> backendIdentifier backend)) <$> searched)
        else
            pure $
                Right
                    ( tagMove
                        (" via " <> backendIdentifier backend <> " logical fallback")
                        (logicalAiMoveFor backend st)
                    )

tagMove :: String -> (Action, [(Action, Word32)]) -> (Action, [(Action, Word32)], String)
tagMove label (action, visits) = (action, visits, label)

logicalAiMoveFor :: Backend -> PlayState -> (Action, [(Action, Word32)])
logicalAiMoveFor backend st =
    uctChooseMove
        backend
        (playStateRng st)
        (playGameSeed st)
        (playStateMoveCount st)
        (playStateBoard st)
        (FixedSims (playStateSims st))
        (playStateMaxPlies st)

playGameSeed :: PlayState -> Word64
playGameSeed st = mix (playStateSeed st) 0

playApp :: App PlayState () String
playApp =
    App
        { appDraw = drawUi
        , appChooseCursor = neverShowCursor
        , appHandleEvent = handleEvent
        , appStartEvent = do
            st <- get
            case backendForCurrentTurn st of
                Just _ -> advanceAi
                Nothing -> pure ()
        , appAttrMap =
            const
                ( A.attrMap
                    V.defAttr
                    [ (A.attrName "winner", fg V.yellow)
                    , (A.attrName "hint", fg V.cyan)
                    , (A.attrName "message", fg V.white)
                    ]
                )
        }

-- | Run the interactive brick event loop. AI turns use the selected
-- backend's dynamic FFI search path when the shared library is present,
-- with the same logical fallback policy used by batch dispatch when it
-- is not.
runInteractivePlay
    :: Backend
    -> Side
    -> Maybe Backend
    -> Maybe FilePath
    -> RngSource
    -> Word64
    -> Word16
    -> Int
    -> IO PlayState
runInteractivePlay backend aiSide vsBackend cacheDir rng seed maxPlies sims =
    defaultMain playApp (initialPlayStateFor backend aiSide vsBackend cacheDir rng seed maxPlies sims)

playMoveRecord :: PlayState -> Action -> [(Action, Word32)] -> MoveRecord
playMoveRecord st action visits =
    MoveRecord
        { moveIndex = fromIntegral (playStateMoveCount st)
        , moveChosen = action
        , moveVisits = visits
        }

savePlayState :: PlayState -> IO PlayState
savePlayState st = do
    result <- writePlayTranscript (playStateCacheDir st) (playStateTranscript st)
    pure $
        case result of
            Right (hashValue, path) ->
                st
                    { playStateMessage = "saved " <> shortHash hashValue <> " to " <> path
                    , playStateInput = ""
                    }
            Left err ->
                st
                    { playStateMessage = "save failed: " <> show err
                    , playStateInput = ""
                    }

playStateTranscript :: PlayState -> Transcript
playStateTranscript st =
    Transcript
        (playRunConfig st)
        (makeLogicalEnvelope (playStateBackend st) (playStateRng st))
        [ GameTranscript
            { gameId = 0
            , gameMoves = playStateRecords st
            , gameWinner = maybe Draw id (playStateDone st)
            }
        ]

playRunConfig :: PlayState -> RunConfig
playRunConfig st =
    RunConfig
        { runBackend = playStateBackend st
        , runWorkload = Selfplay
        , runThreading = SingleThreaded
        , runRngSource = playStateRng st
        , runMasterSeed = playStateSeed st
        , runInitialSims = fromIntegral (playStateSims st)
        , runPerMoveSims = fromIntegral (playStateSims st)
        , runMaxPlies = playStateMaxPlies st
        , runGameIndex = 0
        , runGames = 1
        , runCParamBits = 0x3fe6666666666666
        }
