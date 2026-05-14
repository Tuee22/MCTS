module MCTS.Driver
    ( RunInputs (..)
    , BatchResult (..)
    , defaultRunInputs
    , makeRunConfig
    , runGame
    , runBatch
    ) where

import Data.Word (Word16, Word32, Word64)
import MCTS.Engine (Board, applyMove, chooseMove, initialBoard, terminalWinner)
import MCTS.Rng.Mix (mix)
import MCTS.Transcript (hostArch, writeTranscript)
import MCTS.Types

data RunInputs = RunInputs
    { inputBackend :: !Backend
    , inputWorkload :: !Workload
    , inputRng :: !RngSource
    , inputThreading :: !Threading
    , inputGames :: !Int
    , inputSeed :: !Word64
    , inputMaxPlies :: !Word16
    , inputSims :: !SimBudget
    , inputCacheDir :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

data BatchResult = BatchResult
    { batchTranscript :: !Transcript
    , batchHash :: !String
    , batchPath :: !FilePath
    }
    deriving (Eq, Show)

defaultRunInputs :: RunInputs
defaultRunInputs =
    RunInputs
        { inputBackend = Haskell
        , inputWorkload = Selfplay
        , inputRng = NativeRng
        , inputThreading = MultiThreaded 8
        , inputGames = 1
        , inputSeed = 42
        , inputMaxPlies = 200
        , inputSims = FixedSims 100
        , inputCacheDir = Nothing
        }

makeRunConfig :: RunInputs -> RunConfig
makeRunConfig inputs =
    RunConfig
        { runBackend = inputBackend inputs
        , runWorkload = inputWorkload inputs
        , runThreading = inputThreading inputs
        , runRngSource = inputRng inputs
        , runMasterSeed = inputSeed inputs
        , runInitialSims = fromIntegral (simInitial (inputSims inputs))
        , runPerMoveSims = fromIntegral (simPerMove (inputSims inputs))
        , runMaxPlies = inputMaxPlies inputs
        , runGames = fromIntegral (inputGames inputs)
        , runCParamBits = 0x3fe6666666666666
        }

runBatch :: RunInputs -> IO (Either String BatchResult)
runBatch inputs = do
    let config = makeRunConfig inputs
        envelope =
            Envelope
                { envelopeVersion = 1
                , envelopeBackend = inputBackend inputs
                , envelopeHostArch = hostArch
                , envelopeBuildId = backendIdentifier (inputBackend inputs) <> "-logical"
                }
        games =
            [ runGame inputs (fromIntegral gameIndex)
            | gameIndex <- [0 .. max 0 (inputGames inputs - 1)]
            ]
        transcript = Transcript config envelope games
    written <- writeTranscript (inputCacheDir inputs) transcript
    pure $
        case written of
            Right (hashValue, path) -> Right BatchResult{batchTranscript = transcript, batchHash = hashValue, batchPath = path}
            Left err -> Left (show err)

runGame :: RunInputs -> Word32 -> GameTranscript
runGame inputs gid =
    let gameSeed = mix (inputSeed inputs) (fromIntegral gid)
        (records, finalBoard) = go gameSeed initialBoard 0 []
        winner =
            case terminalWinner (effectiveMaxPlies inputs) finalBoard of
                Just value -> value
                Nothing -> Draw
     in GameTranscript{gameId = gid, gameMoves = reverse records, gameWinner = winner}
  where
    go :: Word64 -> Board -> Int -> [MoveRecord] -> ([MoveRecord], Board)
    go seed board moveNo acc =
        case terminalWinner (effectiveMaxPlies inputs) board of
            Just _ -> (acc, board)
            Nothing
                | moveNo >= fromIntegral (effectiveMaxPlies inputs) -> (acc, board)
                | otherwise ->
                    let budget =
                            case inputWorkload inputs of
                                Rollouts -> FixedSims 1
                                Selfplay -> inputSims inputs
                        (chosen, visits) =
                            chooseMove
                                (inputBackend inputs)
                                (inputRng inputs)
                                seed
                                moveNo
                                board
                                budget
                        record =
                            MoveRecord
                                { moveIndex = fromIntegral moveNo
                                , moveChosen = chosen
                                , moveVisits = visits
                                }
                        nextBoard = applyMove chosen board
                     in go seed nextBoard (moveNo + 1) (record : acc)

effectiveMaxPlies :: RunInputs -> Word16
effectiveMaxPlies inputs =
    case inputBackend inputs of
        CppLegacy -> max 1 (inputMaxPlies inputs)
        _ -> max 1 (inputMaxPlies inputs)
