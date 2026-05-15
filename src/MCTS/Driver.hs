module MCTS.Driver
    ( RunInputs (..)
    , BatchResult (..)
    , defaultRunInputs
    , makeRunConfig
    , makeLogicalEnvelope
    , runGame
    , runBatch
    ) where

import Control.Concurrent (MVar, forkIO, newEmptyMVar, newMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Data.Bits (xor)
import Data.List (sortOn)
import Data.Word (Word16, Word32, Word64)
import MCTS.Engine (Board, applyMove, initialBoard, terminalWinner)
import MCTS.Rng.Mix (mix)
import qualified MCTS.Search.UCT as UCT
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
        envelope = makeLogicalEnvelope (inputBackend inputs) (inputRng inputs)
    games <- runGameBatch inputs
    let transcript = Transcript config envelope games
    written <- writeTranscript (inputCacheDir inputs) transcript
    pure $
        case written of
            Right (hashValue, path) -> Right BatchResult{batchTranscript = transcript, batchHash = hashValue, batchPath = path}
            Left err -> Left (show err)

runGameBatch :: RunInputs -> IO [GameTranscript]
runGameBatch inputs =
    case inputThreading inputs of
        SingleThreaded -> pure (map runOne gameIds)
        MultiThreaded workers -> runGamePool (max 1 workers) runOne gameIds
  where
    gameIds = [0 .. max 0 (inputGames inputs - 1)]
    runOne gameIndex = forceGame (runGame inputs (fromIntegral gameIndex))

runGamePool :: Int -> (Int -> GameTranscript) -> [Int] -> IO [GameTranscript]
runGamePool workers runOne gameIds = do
    jobs <- newMVar (zip [0 :: Int ..] gameIds)
    results <- newMVar []
    done <- newEmptyMVar
    let worker = do
            next <- takeJob jobs
            case next of
                Nothing -> putMVar done ()
                Just (idx, gid) -> do
                    game <- evaluate (runOne gid)
                    current <- takeMVar results
                    putMVar results ((idx, game) : current)
                    worker
    mapM_ (\_ -> forkIO worker) [1 .. min workers (max 1 (length gameIds))]
    mapM_ (\_ -> takeMVar done) [1 .. min workers (max 1 (length gameIds))]
    ordered <- sortOn fst <$> takeMVar results
    pure (map snd ordered)

takeJob :: MVar [(Int, Int)] -> IO (Maybe (Int, Int))
takeJob jobs = do
    current <- takeMVar jobs
    case current of
        [] -> putMVar jobs [] >> pure Nothing
        job : rest -> putMVar jobs rest >> pure (Just job)

forceGame :: GameTranscript -> GameTranscript
forceGame game =
    sum (map (length . moveVisits) (gameMoves game)) `seq` game

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
                            uctChooseMove
                                (inputBackend inputs)
                                (inputRng inputs)
                                seed
                                moveNo
                                board
                                budget
                                (effectiveMaxPlies inputs)
                        record =
                            MoveRecord
                                { moveIndex = fromIntegral moveNo
                                , moveChosen = chosen
                                , moveVisits = visits
                                }
                        nextBoard = applyMove chosen board
                     in go seed nextBoard (moveNo + 1) (record : acc)

-- | Dispatch the per-move search through `MCTS.Search.UCT.uctSearch`.
-- Under `--rng cpp` every backend uses an identical effective seed
-- (no backend salt) so cross-backend verify produces bit-equal visit
-- counts. Under `--rng native` each backend gets a backend-derived salt
-- so per-backend transcripts hash differently in bench output.
uctChooseMove
    :: Backend
    -> RngSource
    -> Word64
    -> Int
    -> Board
    -> SimBudget
    -> Word16
    -> (Action, [(Action, Word32)])
uctChooseMove backend rng seed moveNo board budget maxPlies =
    let backendSalt = case rng of
            CppRng -> 0
            NativeRng -> fromIntegral (fromEnum backend + 1) * 0x100000001b3
        effectiveSeed = seed `xor` backendSalt `xor` fromIntegral (moveNo * 257 + 1)
        sims = max 1 (simPerMove budget)
        -- Rollout cap per simulation. The full game ply cap may be
        -- 10_000 under the legacy parity envelope; that's intractable
        -- as a rollout depth, so the rollout-only cap is 60.
        rolloutCap = min 60 (fromIntegral maxPlies)
     in UCT.uctSearch board effectiveSeed sims rolloutCap

effectiveMaxPlies :: RunInputs -> Word16
effectiveMaxPlies inputs =
    case inputBackend inputs of
        CppLegacy -> max 1 (inputMaxPlies inputs)
        _ -> max 1 (inputMaxPlies inputs)

-- | Build the engine envelope for the in-process logical baseline. The
-- per-backend-slot fields are zero-initialized stand-ins until real
-- backend drivers exist (see Phase 3.6 / 4.7 / 5.5 / 6.5). The
-- cohort-invariant fields (`envelopeRngSource`, `envelopeHostArch`) are
-- captured from the active run.
makeLogicalEnvelope :: Backend -> RngSource -> Envelope
makeLogicalEnvelope backend rng =
    Envelope
        { envelopeVersion = 1
        , envelopeBackend = backend
        , envelopeRngSource = rng
        , envelopeHostArch = hostArch
        , envelopeSharedRngBuildId = zeroDigest
        , envelopeCohortConfigHash = zeroDigest
        , envelopeEngineBuildId = zeroDigest
        , envelopeEngineGitCommit = ""
        , envelopeCompilerId = 3 -- ghc
        , envelopeCompilerVersion = "9.14.1"
        , envelopeFpFlags = 0
        , envelopeLibmId = ""
        , envelopeCpuFeatures = 0
        , envelopeFpEnv = 0
        , envelopeBuildId = backendIdentifier backend <> "-logical"
        }
