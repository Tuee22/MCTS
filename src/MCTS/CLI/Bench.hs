module MCTS.CLI.Bench
    ( runBench
    , runBenchWithClock
    , monotonicNanos
    ) where

import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine)
import MCTS.Driver
import MCTS.Types

data BenchRow = BenchRow
    { rowInputs :: !RunInputs
    , rowBatch :: !BatchResult
    , rowGamesPerSecond :: !Double
    , rowSimsPerSecond :: !Double
    }

runBench :: OutputOptions -> [Backend] -> RunInputs -> IO Int
runBench = runBenchWithClock monotonicNanos

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

runBenchRows :: IO Word64 -> [Backend] -> RunInputs -> IO [Either String BenchRow]
runBenchRows clock backends inputs =
    mapM (runBenchRow clock inputs) backends

runBenchRow :: IO Word64 -> RunInputs -> Backend -> IO (Either String BenchRow)
runBenchRow clock inputs backend = do
    let backendInputs = inputs{inputBackend = backend}
    start <- clock
    result <- runBatch backendInputs
    end <- clock
    pure $
        case result of
            Left message -> Left message
            Right batch ->
                let elapsed = max 1 (fromIntegral end - fromIntegral start :: Integer)
                    gamesPerSecond = fromIntegral (inputGames backendInputs) * 1000000000.0 / fromIntegral elapsed :: Double
                    simsPerSecond = gamesPerSecond * fromIntegral (simPerMove (inputSims backendInputs) :: Int)
                 in Right
                        BenchRow
                            { rowInputs = backendInputs
                            , rowBatch = batch
                            , rowGamesPerSecond = gamesPerSecond
                            , rowSimsPerSecond = simsPerSecond
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
                        <> ",\"sims_per_second\":"
                        <> show (rowSimsPerSecond row)
                        <> "}"
                    | row <- rows
                    , let inputs = rowInputs row
                    , let batch = rowBatch row
                    ]
                <> "]"
        _ ->
            unlines $
                "backend  workload  games  threading  rng     hash      games/s  sims/s"
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
                <> "  "
                <> showFF (rowSimsPerSecond row)
            , "wrote " <> batchPath batch
            ]

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

showFF :: Double -> String
showFF value = show (fromInteger (round (value * 10)) / 10 :: Double)
