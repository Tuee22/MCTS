-- | Sprint 8.2 criterion micro-benchmarks targeting the four hot
-- primitives named in the sprint deliverables: the search loop, the
-- rollout loop, the legal-move generator, and the UCT child-selection
-- routine. Each benchmark measures per-call cost in nanoseconds so
-- profile-driven hot-path tuning iterations can compare round-by-
-- round numbers against
-- `documents/engineering/compiler_runtime_tuning.md`.

module Main where

import Criterion.Main
    ( Benchmark
    , bench
    , bgroup
    , defaultMain
    , whnf
    )
import Data.Word (Word64)
import MCTS.Engine (Board, applyMove, initialBoard, legalMoves)
import MCTS.Rng.Mix (mix)
import MCTS.Search.UCT (uctSearch)

-- | A mid-game-ish board produced by deterministically advancing a
-- few plies. Keeps the legal-move generator off the empty-board fast
-- path without needing a transcript on disk.
midGameBoard :: Board
midGameBoard = foldl (\b _ -> stepOnce b) initialBoard (replicate 6 ())
  where
    stepOnce :: Board -> Board
    stepOnce b =
        case legalMoves b of
            (m : _) -> applyMove m b
            [] -> b

-- whnf is enough here: the criterion is per-call overhead of the
-- generator. Using length forces the spine which captures the real
-- per-action cost without needing an NFData instance for Action.
benchLegalMoves :: Benchmark
benchLegalMoves =
    bgroup
        "legal-moves"
        [ bench "initial" $ whnf (length . legalMoves) initialBoard
        , bench "mid-game" $ whnf (length . legalMoves) midGameBoard
        ]

benchApplyMove :: Benchmark
benchApplyMove =
    bgroup
        "apply-move"
        [ bench "initial first" $ whnf applyFirstMove initialBoard
        , bench "mid-game first" $ whnf applyFirstMove midGameBoard
        ]
  where
    applyFirstMove b =
        case legalMoves b of
            (m : _) -> applyMove m b
            [] -> b

benchSearch :: Benchmark
benchSearch =
    bgroup
        "uct-search"
        [ bench "initial sims=8 maxPlies=60" $
            whnf (\seed -> fst (uctSearch initialBoard seed 8 60)) (42 :: Word64)
        , bench "initial sims=64 maxPlies=60" $
            whnf (\seed -> fst (uctSearch initialBoard seed 64 60)) (42 :: Word64)
        , bench "mid sims=64 maxPlies=60" $
            whnf (\seed -> fst (uctSearch midGameBoard seed 64 60)) (42 :: Word64)
        ]

benchMix :: Benchmark
benchMix =
    bgroup
        "splitmix-mix"
        [ bench "mix 42 0" $ whnf (mix (42 :: Word64)) 0
        , bench "mix 42 1023" $ whnf (mix (42 :: Word64)) 1023
        ]

main :: IO ()
main =
    defaultMain
        [ benchLegalMoves
        , benchApplyMove
        , benchSearch
        , benchMix
        ]
