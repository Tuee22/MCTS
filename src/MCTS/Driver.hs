module MCTS.Driver
    ( RunInputs (..)
    , BatchResult (..)
    , defaultRunInputs
    , makeRunConfig
    , makeLogicalEnvelope
    , runGame
    , runBatch
    , runBatchNoWrite
    , runBatchWithGame
    , runBatchWithGameEnvelope
    , runBatchNoWriteWithGame
    , uctChooseMove
    ) where

import Control.Concurrent (MVar, forkIO, newEmptyMVar, newMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Data.Bits (xor)
import Data.List (sortOn)
import Data.Word (Word16, Word32, Word64)
import MCTS.Engine (Board, applyMove, initialBoard, terminalWinner)
import MCTS.Engine.Envelope (makeEngineEnvelope)
import MCTS.Rng.Mix (backendNativeSalt, mix)
import qualified MCTS.Search.UCT as UCT
import MCTS.Transcript (writeTranscript, writeTranscriptPerGame)
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
    -- ^ Sprint 7.5: legacy single-file batch hash + path retained
    -- for the bench-summary headline; the per-game write set is
    -- the authoritative on-disk layout going forward.
    , batchGameWrites :: ![(String, FilePath)]
    -- ^ Sprint 7.5 per-game writer migration: one (hash, path) entry
    -- per game in the batch, matching the doctrine's one-game-per-file
    -- wire format. Each per-game file is written with `runGames = 1`
    -- and the per-game seed `splitmix64(master_seed, game_index)`.
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
runBatch inputs = runBatchWithGame (\gid -> pure (Right (runGame inputs gid))) inputs

runBatchNoWrite :: RunInputs -> IO (Either String ())
runBatchNoWrite inputs = runBatchNoWriteWithGame (\gid -> pure (Right (runGame inputs gid))) inputs

-- | Run a batch with a caller-supplied per-game runner that may fail.
-- The default runner is the pure in-process `runGame`. Backend (i)
-- routes through this with `runGameCppLegacy` so FFI-backed batch
-- transcripts carry the legacy's real `(action_id, visits)` records;
-- on legacy ABI failure the runner returns `Left` and the whole
-- batch surfaces the error string.
runBatchWithGame
    :: (Word32 -> IO (Either String GameTranscript))
    -> RunInputs
    -> IO (Either String BatchResult)
runBatchWithGame runOne inputs = do
    let envelope = makeLogicalEnvelope (inputBackend inputs) (inputRng inputs)
    runBatchWithGameEnvelope envelope runOne inputs

runBatchWithGameEnvelope
    :: Envelope
    -> (Word32 -> IO (Either String GameTranscript))
    -> RunInputs
    -> IO (Either String BatchResult)
runBatchWithGameEnvelope envelope runOne inputs = do
    let config = makeRunConfig inputs
    gamesResult <- runGameBatchWith runOne inputs
    case gamesResult of
        Left err -> pure (Left err)
        Right games -> do
            let transcript = Transcript config envelope games
            written <- writeTranscript (inputCacheDir inputs) transcript
            perGame <- writeTranscriptPerGame (inputCacheDir inputs) transcript
            pure $
                case (written, perGame) of
                    (Right (hashValue, path), Right perGameWrites) ->
                        Right
                            BatchResult
                                { batchTranscript = transcript
                                , batchHash = hashValue
                                , batchPath = path
                                , batchGameWrites = perGameWrites
                                }
                    (Left err, _) -> Left (show err)
                    (_, Left err) -> Left (show err)

-- | Run the same per-game workload as 'runBatchWithGame' but do not
-- retain or write transcripts. The report-card timing path uses this
-- for large benchmark counts where retaining 100k game transcripts
-- would measure cache pressure instead of backend throughput.
runBatchNoWriteWithGame
    :: (Word32 -> IO (Either String GameTranscript))
    -> RunInputs
    -> IO (Either String ())
runBatchNoWriteWithGame runOne inputs =
    case inputThreading inputs of
        SingleThreaded -> go gameIds
        MultiThreaded workers ->
            unitSequence <$> runGamePool (max 1 workers) runForce gameIds
  where
    gameIds = [0 .. max 0 (inputGames inputs - 1)]
    go [] = pure (Right ())
    go (gid : rest) = do
        result <- runForce gid
        case result of
            Left err -> pure (Left err)
            Right () -> go rest
    runForce gameIndex = do
        result <- runOne (fromIntegral gameIndex)
        case result of
            Left err -> pure (Left err)
            Right game -> evaluate (forceGame game) >> pure (Right ())

unitSequence :: [Either String ()] -> Either String ()
unitSequence [] = Right ()
unitSequence (Right () : rest) = unitSequence rest
unitSequence (Left err : _) = Left err

runGameBatchWith
    :: (Word32 -> IO (Either String GameTranscript))
    -> RunInputs
    -> IO (Either String [GameTranscript])
runGameBatchWith runOne inputs =
    case inputThreading inputs of
        SingleThreaded -> sequenceEither <$> mapM runForce gameIds
        MultiThreaded workers ->
            sequenceEither <$> runGamePool (max 1 workers) runForce gameIds
  where
    gameIds = [0 .. max 0 (inputGames inputs - 1)]
    runForce gameIndex = fmap (fmap forceGame) (runOne (fromIntegral gameIndex))

sequenceEither :: [Either String a] -> Either String [a]
sequenceEither = go []
  where
    go acc [] = Right (reverse acc)
    go acc (Right x : rest) = go (x : acc) rest
    go _ (Left err : _) = Left err

runGamePool
    :: Int
    -> (Int -> IO (Either String a))
    -> [Int]
    -> IO [Either String a]
runGamePool workers runOne gameIds = do
    jobs <- newMVar (zip [0 :: Int ..] gameIds)
    results <- newMVar []
    done <- newEmptyMVar
    let worker = do
            next <- takeJob jobs
            case next of
                Nothing -> putMVar done ()
                Just (idx, gid) -> do
                    game <- runOne gid
                    forced <- case game of
                        Right g -> Right <$> evaluate g
                        Left err -> pure (Left err)
                    current <- takeMVar results
                    putMVar results ((idx, forced) : current)
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
    let backendSalt = backendNativeSalt rng backend
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
makeLogicalEnvelope = makeEngineEnvelope
