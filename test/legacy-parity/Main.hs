module Main where

import MCTS.Driver
import MCTS.Types
import MCTS.Verify

main :: IO ()
main = do
    let inputs =
            defaultRunInputs
                { inputGames = 1
                , inputSeed = 42
                , inputSims = FixedSims 12
                , inputMaxPlies = 50
                }
    result <- legacyParityRun Selfplay allBackends inputs
    case result of
        Right _ -> putStrLn "mcts-legacy-parity PASS"
        Left err -> error ("legacy parity failed: " <> show err)
