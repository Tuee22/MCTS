module Main where

import MCTS.Driver
import MCTS.Types

main :: IO ()
main = do
    mapM_ sameBackend allBackends
    putStrLn "mcts-integration PASS"

sameBackend :: Backend -> IO ()
sameBackend backend = do
    let inputs =
            defaultRunInputs
                { inputBackend = backend
                , inputRng = CppRng
                , inputGames = 3
                , inputSeed = 42
                , inputSims = FixedSims 16
                , inputMaxPlies = 40
                }
        first = map (runGame inputs) [0, 1, 2]
        second = map (runGame inputs) [0, 1, 2]
    if first == second
        then pure ()
        else error ("same-backend determinism failed for " <> backendIdentifier backend)
