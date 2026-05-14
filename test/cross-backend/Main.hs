module Main where

import MCTS.Driver
import MCTS.Types
import MCTS.Verify

main :: IO ()
main = do
    let inputs =
            defaultRunInputs
                { inputGames = 2
                , inputSeed = 42
                , inputSims = FixedSims 16
                , inputMaxPlies = 40
                }
    result <- verifyRun Rollouts [CppImperative, CppFunctional, Rust, Haskell] inputs
    case result of
        Right _ -> putStrLn "mcts-cross-backend PASS"
        Left err -> error ("cross-backend verify failed: " <> show err)
