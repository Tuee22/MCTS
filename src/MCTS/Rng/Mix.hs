module MCTS.Rng.Mix
    ( mix
    , splitmix64
    , backendNativeSalt
    ) where

import Data.Bits (shiftR, xor)
import Data.Word (Word64)
import MCTS.Types (Backend, RngSource (..), backendId)

-- | Sprint 7.2: per-backend deterministic salt for the
-- `--rng native` seed schedule. Under `--rng cpp` the salt is zero
-- so every backend draws from a bit-identical seed stream; under
-- `--rng native` the salt is `(backendId backend + 1) * 0x100000001b3`,
-- which is a 64-bit prime multiplier that gives each backend a
-- distinct salt without producing aliasing on small backend ids.
--
-- Consumers: `MCTS.Driver.uctChooseMove`,
-- `MCTS.Engine.Recompute.recomputeGame`,
-- `MCTS.Engine.ForeignRecompute.recomputeGameMoves`.
{-# INLINE backendNativeSalt #-}
backendNativeSalt :: RngSource -> Backend -> Word64
backendNativeSalt rng backend =
    case rng of
        CppRng -> 0
        NativeRng -> fromIntegral (backendId backend + 1) * 0x100000001b3

{-# INLINEABLE mix #-}
mix :: Word64 -> Word64 -> Word64
mix masterSeed gameIndex =
    splitmix64 (masterSeed + 0x9e3779b97f4a7c15 * (gameIndex + 1))

{-# INLINEABLE splitmix64 #-}
splitmix64 :: Word64 -> Word64
splitmix64 input =
    let z1 = input + 0x9e3779b97f4a7c15
        z2 = (z1 `xor` (z1 `shiftR` 30)) * 0xbf58476d1ce4e5b9
        z3 = (z2 `xor` (z2 `shiftR` 27)) * 0x94d049bb133111eb
     in z3 `xor` (z3 `shiftR` 31)
