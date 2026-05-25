module MCTS.CLI.Bench
    ( runBench
    , runBenchWithClock
    , runPrimitiveBench
    , runPrimitiveBenchWithClock
    , runPrimitiveBenchRows
    , measurePrimitiveBackendRate
    , PrimitiveBenchRow (..)
    , monotonicNanos
    ) where

import Control.Concurrent (MVar, forkIO, newEmptyMVar, newMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import Data.Bits (xor)
import qualified Data.Text as Text
import Data.Word (Word32, Word64)
import GHC.Clock (getMonotonicTimeNSec)
import MCTS.CLI.Command (BenchPrimitive (..), BenchPrimitiveOptions (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine)
import MCTS.Driver
import MCTS.Driver.Dispatch (runBatchDispatch)
import MCTS.Engine (initialBoard)
import qualified MCTS.Env as Env
import MCTS.Error (renderError)
import MCTS.FFI.Common (DynamicBenchmarkGame (..), withDynamicBenchmarkGame)
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath)
import MCTS.FFI.CppLegacy (cppLegacyLibraryPath)
import MCTS.FFI.Rust (rustLibraryPath)
import MCTS.Rng.Mix (backendNativeSalt, mix)
import qualified MCTS.Search.UCT as UCT
import MCTS.Types
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))

data BenchRow = BenchRow
    { rowInputs :: !RunInputs
    , rowBatch :: !BatchResult
    , rowGamesPerSecond :: !Double
    }

data PrimitiveBenchRow = PrimitiveBenchRow
    { primitiveRowBackend :: !Backend
    , primitiveRowKind :: !BenchPrimitive
    , primitiveRowOptions :: !BenchPrimitiveOptions
    , primitiveRowRate :: !Double
    , primitiveRowChecksum :: !Word64
    }
    deriving (Eq, Show)

runBench :: [Backend] -> RunInputs -> Env.App ExitCode
runBench backends inputs = do
    env <- Env.askEnv
    code <- liftIO (runBenchWithClock (Env.envClock env) (Env.envOutputOptions env) backends inputs)
    pure (intToExitCode code)

-- | Test-injectable variant: the caller can supply a custom monotonic
-- clock (e.g., an `IORef`-backed counter under `mcts-integration`'s
-- monotonic-clock bracket assertion). The production runner uses
-- `monotonicNanos`.
runBenchWithClock :: IO Word64 -> OutputOptions -> [Backend] -> RunInputs -> IO Int
runBenchWithClock clock output backends inputs = do
    rows <- runBenchRows clock backends inputs
    case sequence rows of
        Left message -> outputLine message >> pure 1
        Right benchRows -> do
            outputLine (renderBench output benchRows)
            pure 0

runPrimitiveBench :: BenchPrimitive -> [Backend] -> BenchPrimitiveOptions -> Env.App ExitCode
runPrimitiveBench primitive backends options = do
    env <- Env.askEnv
    code <-
        liftIO
            ( runPrimitiveBenchWithClock
                (Env.envClock env)
                (Env.envOutputOptions env)
                primitive
                backends
                options
            )
    pure (intToExitCode code)

runPrimitiveBenchWithClock
    :: IO Word64
    -> OutputOptions
    -> BenchPrimitive
    -> [Backend]
    -> BenchPrimitiveOptions
    -> IO Int
runPrimitiveBenchWithClock clock output primitive backends options = do
    rows <- runPrimitiveBenchRows clock primitive backends options
    case sequence rows of
        Left message -> outputLine message >> pure 1
        Right benchRows -> outputLine (renderPrimitiveBench output benchRows) >> pure 0

runPrimitiveBenchRows
    :: IO Word64
    -> BenchPrimitive
    -> [Backend]
    -> BenchPrimitiveOptions
    -> IO [Either String PrimitiveBenchRow]
runPrimitiveBenchRows clock primitive backends options =
    mapM (runPrimitiveBenchRow clock primitive options) backends

runPrimitiveBenchRow
    :: IO Word64
    -> BenchPrimitive
    -> BenchPrimitiveOptions
    -> Backend
    -> IO (Either String PrimitiveBenchRow)
runPrimitiveBenchRow clock primitive options backend
    | benchPrimitiveCount options <= 0 = pure (Left "--count must be positive")
    | otherwise = do
        start <- clock
        result <- runPrimitiveBackend primitive options backend
        end <- clock
        pure $
            case result of
                Left message -> Left message
                Right checksum ->
                    let elapsed = max 1 (fromIntegral end - fromIntegral start :: Integer)
                        rate =
                            fromIntegral (benchPrimitiveCount options)
                                * 1000000000.0
                                / fromIntegral elapsed
                     in Right
                            PrimitiveBenchRow
                                { primitiveRowBackend = backend
                                , primitiveRowKind = primitive
                                , primitiveRowOptions = options
                                , primitiveRowRate = rate
                                , primitiveRowChecksum = checksum
                                }

measurePrimitiveBackendRate
    :: IO Word64
    -> BenchPrimitive
    -> BenchPrimitiveOptions
    -> Backend
    -> IO (Either String Double)
measurePrimitiveBackendRate clock primitive options backend = do
    row <- runPrimitiveBenchRow clock primitive options backend
    pure (primitiveRowRate <$> row)

runPrimitiveBackend
    :: BenchPrimitive -> BenchPrimitiveOptions -> Backend -> IO (Either String Word64)
runPrimitiveBackend primitive options backend =
    case backend of
        Haskell -> Right <$> runHaskellPrimitive primitive options backend
        _ -> runForeignPrimitive primitive options backend

runHaskellPrimitive :: BenchPrimitive -> BenchPrimitiveOptions -> Backend -> IO Word64
runHaskellPrimitive primitive options backend =
    runThreadedChunks (benchPrimitiveThreading options) (benchPrimitiveCount options) $ \offset count ->
        evaluate (haskellChunk primitive options backend offset count)

haskellChunk :: BenchPrimitive -> BenchPrimitiveOptions -> Backend -> Int -> Int -> Word64
haskellChunk primitive options backend offset count =
    case primitive of
        TerminalPlayouts ->
            foldl' xor 0 [terminalChecksum i | i <- [0 .. count - 1]]
        SearchIters ->
            let seed = primitiveSeed options backend offset
                (chosen, visits) =
                    UCT.uctSearch
                        initialBoard
                        seed
                        count
                        (fromIntegral (benchPrimitiveMaxPlies options))
             in searchChecksum seed chosen visits
  where
    terminalChecksum i =
        let seed = primitiveSeed options backend (offset + i)
            outcome =
                UCT.terminalPlayout
                    initialBoard
                    seed
                    (fromIntegral (benchPrimitiveMaxPlies options))
         in seed `xor` outcomeChecksum outcome

primitiveSeed :: BenchPrimitiveOptions -> Backend -> Int -> Word64
primitiveSeed options backend index =
    mix
        (benchPrimitiveSeed options `xor` backendNativeSalt (benchPrimitiveRng options) backend)
        (fromIntegral index)

outcomeChecksum :: Float -> Word64
outcomeChecksum outcome
    | outcome > 0 = 0x9e3779b97f4a7c15
    | outcome < 0 = 0xbf58476d1ce4e5b9
    | otherwise = 0x94d049bb133111eb

searchChecksum :: Word64 -> Action -> [(Action, Word32)] -> Word64
searchChecksum seed chosen visits =
    foldl'
        xor
        (seed `xor` fromIntegral (actionId chosen))
        [ fromIntegral (actionId action) `xor` fromIntegral n
        | (action, n) <- visits
        ]

runForeignPrimitive
    :: BenchPrimitive -> BenchPrimitiveOptions -> Backend -> IO (Either String Word64)
runForeignPrimitive primitive options backend =
    case foreignBenchmarkSpec backend of
        Nothing -> pure (Left ("no foreign benchmark backend for " <> backendIdentifier backend))
        Just (libraryPath, symbolPrefix) -> do
            present <- doesFileExist libraryPath
            if present
                then do
                    result <-
                        withDynamicBenchmarkGame backend libraryPath symbolPrefix $ \game ->
                            runThreadedChunks
                                (benchPrimitiveThreading options)
                                (benchPrimitiveCount options)
                                (foreignChunk primitive options backend game)
                    pure $ case result of
                        Left err -> Left (Text.unpack (renderError err))
                        Right checksum -> Right checksum
                else pure (Left ("backend artifact not found: " <> libraryPath))

foreignChunk
    :: BenchPrimitive
    -> BenchPrimitiveOptions
    -> Backend
    -> DynamicBenchmarkGame
    -> Int
    -> Int
    -> IO Word64
foreignChunk primitive options backend game offset count =
    case primitive of
        TerminalPlayouts ->
            benchmarkGameTerminalPlayouts
                game
                seed
                (fromIntegral count)
                (benchPrimitiveMaxPlies options)
        SearchIters ->
            benchmarkGameSearchIters
                game
                seed
                (fromIntegral count)
                (benchPrimitiveMaxPlies options)
  where
    seed = primitiveSeed options backend offset

foreignBenchmarkSpec :: Backend -> Maybe (FilePath, String)
foreignBenchmarkSpec backend =
    case backend of
        CppLegacy -> Just (cppLegacyLibraryPath, "mcts_legacy")
        CppImperative -> Just (cppImperativeLibraryPath, "mcts_imperative")
        CppFunctional -> Just (cppFunctionalLibraryPath, "mcts_functional")
        Rust -> Just (rustLibraryPath, "mcts_rust")
        Haskell -> Nothing

runThreadedChunks :: Threading -> Int -> (Int -> Int -> IO Word64) -> IO Word64
runThreadedChunks threading total runChunk =
    case threading of
        SingleThreaded -> runChunk 0 total
        MultiThreaded workers -> runChunkPool (max 1 workers) runChunk (countChunks total (max 1 workers))

countChunks :: Int -> Int -> [(Int, Int)]
countChunks total workers =
    [ (startFor i, sizeFor i)
    | i <- [0 .. activeWorkers - 1]
    , sizeFor i > 0
    ]
  where
    activeWorkers = max 1 (min workers (max 1 total))
    base = total `div` activeWorkers
    extra = total `mod` activeWorkers
    sizeFor i = base + if i < extra then 1 else 0
    startFor i = i * base + min i extra

runChunkPool :: Int -> (Int -> Int -> IO Word64) -> [(Int, Int)] -> IO Word64
runChunkPool workers runChunk chunks = do
    jobs <- newMVar chunks
    results <- newMVar []
    done <- newEmptyMVar
    let worker = do
            next <- takeChunk jobs
            case next of
                Nothing -> putMVar done ()
                Just (offset, count) -> do
                    value <- runChunk offset count
                    current <- takeMVar results
                    putMVar results (value : current)
                    worker
        nWorkers = min workers (max 1 (length chunks))
    mapM_ (\_ -> forkIO worker) [1 .. nWorkers]
    mapM_ (\_ -> takeMVar done) [1 .. nWorkers]
    foldl' xor 0 <$> takeMVar results

takeChunk :: MVar [(Int, Int)] -> IO (Maybe (Int, Int))
takeChunk jobs = do
    current <- takeMVar jobs
    case current of
        [] -> putMVar jobs [] >> pure Nothing
        job : rest -> putMVar jobs rest >> pure (Just job)

runBenchRows :: IO Word64 -> [Backend] -> RunInputs -> IO [Either String BenchRow]
runBenchRows clock backends inputs =
    mapM (runBenchRow clock inputs) backends

runBenchRow :: IO Word64 -> RunInputs -> Backend -> IO (Either String BenchRow)
runBenchRow clock inputs backend = do
    let backendInputs = inputs{inputBackend = backend}
    start <- clock
    result <- runBatchDispatch backendInputs
    end <- clock
    pure $
        case result of
            Left message -> Left message
            Right batch ->
                let elapsed = max 1 (fromIntegral end - fromIntegral start :: Integer)
                    gamesPerSecond = fromIntegral (inputGames backendInputs) * 1000000000.0 / fromIntegral elapsed :: Double
                 in Right
                        BenchRow
                            { rowInputs = backendInputs
                            , rowBatch = batch
                            , rowGamesPerSecond = gamesPerSecond
                            }

renderBench :: OutputOptions -> [BenchRow] -> String
renderBench output rows =
    case outputFormat output of
        JsonFormat ->
            "["
                <> joinWith
                    ","
                    [ "{"
                        <> "\"backend\":\""
                        <> backendIdentifier (inputBackend inputs)
                        <> "\",\"workload\":\""
                        <> workloadName (inputWorkload inputs)
                        <> "\",\"games\":"
                        <> show (inputGames inputs)
                        <> ",\"hash\":\""
                        <> batchHash batch
                        <> "\",\"games_per_second\":"
                        <> show (rowGamesPerSecond row)
                        <> "}"
                    | row <- rows
                    , let inputs = rowInputs row
                    , let batch = rowBatch row
                    ]
                <> "]"
        _ ->
            unlines $
                "backend  workload  games  threading  rng     hash      games/s"
                    : concatMap renderPlainRow rows
  where
    renderPlainRow row =
        let inputs = rowInputs row
            batch = rowBatch row
         in [ backendIdentifier (inputBackend inputs)
                <> "  "
                <> workloadName (inputWorkload inputs)
                <> "  "
                <> show (inputGames inputs)
                <> "  "
                <> threadingName (inputThreading inputs)
                <> "  "
                <> show (inputRng inputs)
                <> "  "
                <> shortHash (batchHash batch)
                <> "  "
                <> showFF (rowGamesPerSecond row)
            , wroteLine batch
            ]
    wroteLine batch =
        case batchGameWrites batch of
            [] -> "wrote " <> batchPath batch
            [(_, p)] -> "wrote " <> p
            xs -> "wrote " <> show (length xs) <> " per-game transcripts under " <> batchPath batch

renderPrimitiveBench :: OutputOptions -> [PrimitiveBenchRow] -> String
renderPrimitiveBench output rows =
    case outputFormat output of
        JsonFormat ->
            "["
                <> joinWith
                    ","
                    [ "{"
                        <> "\"backend\":\""
                        <> backendIdentifier (primitiveRowBackend row)
                        <> "\",\"metric\":\""
                        <> primitiveName (primitiveRowKind row)
                        <> "\",\"count\":"
                        <> show (benchPrimitiveCount options)
                        <> ",\"threading\":\""
                        <> threadingName (benchPrimitiveThreading options)
                        <> "\",\"rng\":\""
                        <> rngName (benchPrimitiveRng options)
                        <> "\",\"unit\":\""
                        <> primitiveUnit (primitiveRowKind row)
                        <> "\",\"checksum\":"
                        <> show (primitiveRowChecksum row)
                        <> ",\""
                        <> primitiveRateField (primitiveRowKind row)
                        <> "\":"
                        <> show (primitiveRowRate row)
                        <> "}"
                    | row <- rows
                    , let options = primitiveRowOptions row
                    ]
                <> "]"
        _ ->
            unlines $
                "backend  metric  count  threading  rng     checksum  unit  rate"
                    : map renderPlainPrimitiveRow rows
  where
    renderPlainPrimitiveRow row =
        let options = primitiveRowOptions row
         in backendIdentifier (primitiveRowBackend row)
                <> "  "
                <> primitiveName (primitiveRowKind row)
                <> "  "
                <> show (benchPrimitiveCount options)
                <> "  "
                <> threadingName (benchPrimitiveThreading options)
                <> "  "
                <> rngName (benchPrimitiveRng options)
                <> "  "
                <> shortChecksum (primitiveRowChecksum row)
                <> "  "
                <> primitiveUnit (primitiveRowKind row)
                <> "  "
                <> showFF (primitiveRowRate row)

primitiveName :: BenchPrimitive -> String
primitiveName primitive =
    case primitive of
        TerminalPlayouts -> "terminal-playouts"
        SearchIters -> "search-iters"

primitiveUnit :: BenchPrimitive -> String
primitiveUnit primitive =
    case primitive of
        TerminalPlayouts -> "playouts/s"
        SearchIters -> "search-iters/s"

primitiveRateField :: BenchPrimitive -> String
primitiveRateField primitive =
    case primitive of
        TerminalPlayouts -> "playouts_per_second"
        SearchIters -> "search_iters_per_second"

rngName :: RngSource -> String
rngName rng =
    case rng of
        NativeRng -> "native"
        CppRng -> "cpp"

shortChecksum :: Word64 -> String
shortChecksum value = take 8 (show value)

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith separator (x : xs) = x <> separator <> joinWith separator xs

-- | Pinned monotonic clock per
-- [../../README.md → Benchmarks](../../README.md) (line 177) and
-- [phase-3-haskell-engine.md → Sprint 3.5](../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md).
-- Returns nanoseconds since some unspecified monotonic epoch; the same
-- clock is used by every backend so cross-backend numbers are directly
-- comparable.
monotonicNanos :: IO Word64
monotonicNanos = getMonotonicTimeNSec

intToExitCode :: Int -> ExitCode
intToExitCode 0 = ExitSuccess
intToExitCode n = ExitFailure n

showFF :: Double -> String
showFF value = show (fromInteger (round (value * 10)) / 10 :: Double)
