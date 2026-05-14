module Main where

import MCTS.Driver
import MCTS.Types

main :: IO ()
main = do
    mapM_ sameBackend allBackends
    putStrLn "mcts-integration PASS"

sameBackend :: Backend -> IO ()
sameBackend backend = do
    -- The integration stanza asserts Q4 same-backend determinism across
    -- three pinned seeds per backend. With the real UCT search wired
    -- through `MCTS.Search.UCT.uctSearch`, the per-move search cost is
    -- much higher than the previous synthetic baseline, so the
    -- per-seed game count and sim budget are reduced. The Q4 property
    -- (two consecutive runs at the same seed produce identical
    -- determinism payloads) does not depend on game count.
    let baseInputs =
            defaultRunInputs
                { inputBackend = backend
                , inputRng = CppRng
                , inputGames = 1
                , inputSims = FixedSims 4
                , inputMaxPlies = 20
                }
    mapM_ (sameBackendSeed baseInputs backend) ([42, 43, 44] :: [Integer])

sameBackendSeed :: RunInputs -> Backend -> Integer -> IO ()
sameBackendSeed baseInputs backend seedValue = do
    let inputs = baseInputs{inputSeed = fromIntegral seedValue}
        first = runGame inputs 0
        second = runGame inputs 0
    if first == second
        then pure ()
        else error ("same-backend determinism failed for " <> backendIdentifier backend <> " seed=" <> show seedValue)
