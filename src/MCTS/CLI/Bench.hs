module MCTS.CLI.Bench
    ( runBench
    ) where

import Data.Time.Clock.System (SystemTime (..), getSystemTime)
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine)
import MCTS.Driver
import MCTS.Types

runBench :: OutputOptions -> RunInputs -> IO Int
runBench output inputs = do
    start <- monotonicishNanos
    result <- runBatch inputs
    end <- monotonicishNanos
    case result of
        Left message -> outputLine message >> pure 1
        Right batch -> do
            let elapsed = max 1 (end - start)
                gamesPerSecond = fromIntegral (inputGames inputs) * 1000000000.0 / fromIntegral elapsed :: Double
                simsPerSecond = gamesPerSecond * fromIntegral (simPerMove (inputSims inputs) :: Int)
            outputLine (renderBench output inputs batch gamesPerSecond simsPerSecond)
            pure 0

renderBench :: OutputOptions -> RunInputs -> BatchResult -> Double -> Double -> String
renderBench output inputs batch gamesPerSecond simsPerSecond =
    case outputFormat output of
        JsonFormat ->
            "{"
                <> "\"backend\":\""
                <> backendIdentifier (inputBackend inputs)
                <> "\",\"workload\":\""
                <> workloadName (inputWorkload inputs)
                <> "\",\"games\":"
                <> show (inputGames inputs)
                <> ",\"hash\":\""
                <> batchHash batch
                <> "\",\"games_per_second\":"
                <> show gamesPerSecond
                <> ",\"sims_per_second\":"
                <> show simsPerSecond
                <> "}"
        _ ->
            unlines
                [ "backend  workload  games  threading  rng     hash      games/s  sims/s"
                , backendIdentifier (inputBackend inputs)
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
                    <> showFF gamesPerSecond
                    <> "  "
                    <> showFF simsPerSecond
                , "wrote " <> batchPath batch
                ]

monotonicishNanos :: IO Integer
monotonicishNanos = do
    MkSystemTime seconds nanos <- getSystemTime
    pure (fromIntegral seconds * 1000000000 + fromIntegral nanos)

showFF :: Double -> String
showFF value = show (fromInteger (round (value * 10)) / 10 :: Double)
