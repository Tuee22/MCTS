module MCTS.CLI.Tui.Session
    ( GameSessionState (..)
    , PlayerControl (..)
    , SessionMode (..)
    , sessionFromLive
    , sessionFromReplay
    , sessionStatusLine
    ) where

import MCTS.Engine (Board)
import MCTS.Transcript.EquitySidecar (EqStream)
import MCTS.Types
    ( Backend
    , GameTranscript (..)
    , Side (..)
    , Transcript (..)
    , backendIdentifier
    , otherSide
    )

data SessionMode
    = LiveGame
    | SavedReplay
    deriving (Eq, Show)

data PlayerControl
    = HumanControl
    | BackendControl !Backend
    deriving (Eq, Show)

data GameSessionState = GameSessionState
    { sessionMode :: !SessionMode
    , sessionBoard :: !Board
    , sessionCursor :: !Int
    , sessionLiveCursor :: !Int
    , sessionControls :: ![(Side, PlayerControl)]
    , sessionTranscriptHash :: !(Maybe String)
    , sessionTranscript :: !(Maybe Transcript)
    , sessionOverlays :: ![EqStream]
    , sessionUnavailableBackends :: ![Backend]
    , sessionSaveStatus :: !(Maybe String)
    , sessionMessage :: !String
    }
    deriving (Eq, Show)

sessionFromLive
    :: Board
    -> Int
    -> Side
    -> Backend
    -> Maybe Backend
    -> Maybe String
    -> String
    -> GameSessionState
sessionFromLive board cursor aiSide aiBackend vsBackend saveStatus message =
    GameSessionState
        { sessionMode = LiveGame
        , sessionBoard = board
        , sessionCursor = cursor
        , sessionLiveCursor = cursor
        , sessionControls =
            case vsBackend of
                Nothing ->
                    [ (aiSide, BackendControl aiBackend)
                    , (otherSide aiSide, HumanControl)
                    ]
                Just opponent ->
                    [ (aiSide, BackendControl aiBackend)
                    , (otherSide aiSide, BackendControl opponent)
                    ]
        , sessionTranscriptHash = Nothing
        , sessionTranscript = Nothing
        , sessionOverlays = []
        , sessionUnavailableBackends = []
        , sessionSaveStatus = saveStatus
        , sessionMessage = message
        }

sessionFromReplay
    :: String
    -> Transcript
    -> Board
    -> Int
    -> [EqStream]
    -> [Backend]
    -> String
    -> GameSessionState
sessionFromReplay hashValue transcript board cursor overlays unavailable message =
    GameSessionState
        { sessionMode = SavedReplay
        , sessionBoard = board
        , sessionCursor = cursor
        , sessionLiveCursor = length (concatMap gameMoves (transcriptGames transcript))
        , sessionControls = []
        , sessionTranscriptHash = Just (take 8 hashValue)
        , sessionTranscript = Just transcript
        , sessionOverlays = overlays
        , sessionUnavailableBackends = unavailable
        , sessionSaveStatus = Nothing
        , sessionMessage = message
        }

sessionStatusLine :: GameSessionState -> String
sessionStatusLine session =
    modeLabel
        <> " | cursor "
        <> show (sessionCursor session)
        <> " / "
        <> show (sessionLiveCursor session)
        <> " | "
        <> controlsLabel
        <> saveLabel
  where
    modeLabel =
        case sessionMode session of
            LiveGame -> "live"
            SavedReplay ->
                case sessionTranscriptHash session of
                    Just hashValue -> "replay " <> hashValue
                    Nothing -> "replay"
    controlsLabel =
        case sessionControls session of
            [] -> "recorded"
            controls -> unwords (map renderControl controls)
    renderControl (side, control) =
        show side <> "=" <> case control of
            HumanControl -> "human"
            BackendControl backend -> backendIdentifier backend
    saveLabel =
        case sessionSaveStatus session of
            Nothing -> ""
            Just status -> " | " <> status
