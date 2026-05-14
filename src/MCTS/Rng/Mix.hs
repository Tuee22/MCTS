module MCTS.Rng.Mix
    ( mix
    , splitmix64
    ) where

import Data.Bits (shiftR, xor)
import Data.Word (Word64)

mix :: Word64 -> Word64 -> Word64
mix masterSeed gameIndex =
    splitmix64 (masterSeed + 0x9e3779b97f4a7c15 * (gameIndex + 1))

splitmix64 :: Word64 -> Word64
splitmix64 input =
    let z1 = input + 0x9e3779b97f4a7c15
        z2 = (z1 `xor` (z1 `shiftR` 30)) * 0xbf58476d1ce4e5b9
        z3 = (z2 `xor` (z2 `shiftR` 27)) * 0x94d049bb133111eb
     in z3 `xor` (z3 `shiftR` 31)
