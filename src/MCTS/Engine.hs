{-# LANGUAGE BangPatterns #-}

module MCTS.Engine
    ( Board (..)
    , initialBoard
    , legalMoves
    , applyMove
    , isTerminal
    , terminalOutcome
    , nonTerminalOutcome
    , terminalWinner
    , nonTerminalRank
    ) where

import Data.Bits (complement, setBit, shiftL, shiftR, testBit, (.&.), (.|.))
import qualified Data.Bits
import Data.List (sortOn)
import Data.Word (Word16, Word64, Word8)
import MCTS.Types
    ( Action (..)
    , Side (..)
    , Winner (..)
    , actionId
    , otherSide
    )

data Board = Board
    { boardHero :: !Word64
    , boardVillain :: !Word64
    , boardWallsH :: !Word64
    , boardWallsV :: !Word64
    , boardHeroWalls :: !Word8
    , boardVillainWalls :: !Word8
    , boardSideToMove :: !Side
    , boardPly :: !Word16
    }
    deriving (Eq, Show, Read)

initialBoard :: Board
initialBoard =
    Board
        { boardHero = pawnSlot 4 0
        , boardVillain = pawnSlot 4 8
        , boardWallsH = 0
        , boardWallsV = 0
        , boardHeroWalls = 10
        , boardVillainWalls = 10
        , boardSideToMove = Hero
        , boardPly = 0
        }

{-# INLINEABLE legalMoves #-}
legalMoves :: Board -> [Action]
legalMoves board
    | isTerminal maxBound board = []
    | otherwise =
        sortOn
            actionId
            (pawnMoves board <> take 12 (wallMoves board))

pawnMoves :: Board -> [Action]
pawnMoves board =
    let (x, y) = pawnForSide (boardSideToMove board) board
        occupied = pawnForSide (otherSide (boardSideToMove board)) board
        candidates = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
     in [ Pawn nx ny
        | (nx, ny) <- candidates
        , nx >= 0
        , nx <= 8
        , ny >= 0
        , ny <= 8
        , (nx, ny) /= occupied
        , not (edgeBlocked board (x, y) (nx, ny))
        ]

wallMoves :: Board -> [Action]
wallMoves board
    | wallsRemaining board == 0 = []
    | otherwise =
        [ wall
        | wall <- [WallH x y | y <- [0 .. 7], x <- [0 .. 7]] <> [WallV x y | y <- [0 .. 7], x <- [0 .. 7]]
        , not (wallExists board wall)
        , pathExists Hero (applyWallOnly wall board)
        , pathExists Villain (applyWallOnly wall board)
        ]

wallsRemaining :: Board -> Word8
wallsRemaining board =
    case boardSideToMove board of
        Hero -> boardHeroWalls board
        Villain -> boardVillainWalls board

wallExists :: Board -> Action -> Bool
wallExists board action =
    case action of
        WallH x y -> wallBitSet (boardWallsH board) x y
        WallV x y -> wallBitSet (boardWallsV board) x y
        Pawn _ _ -> False

applyWallOnly :: Action -> Board -> Board
applyWallOnly action board =
    case action of
        WallH x y -> board{boardWallsH = setWallBit (boardWallsH board) x y}
        WallV x y -> board{boardWallsV = setWallBit (boardWallsV board) x y}
        Pawn _ _ -> board

-- | Sprint 8.2 wavefront-bitmap BFS over the 9x9 grid.
--
-- The grid has 81 cells (y*9 + x for x,y in [0..8]), which fits in a
-- strict pair of `Word64`s: the low word carries cells 0..63 and the
-- high word carries cells 64..80. Each BFS iteration expands the
-- frontier in four directions through bitwise shifts and direction-
-- specific block masks; convergence is bounded by the grid diameter
-- (≤ 16 iterations). This eliminates the per-cell list cons and
-- IntSet allocation overhead that dominated rounds 1 and 2.
--
-- The valid-cell mask is `(0xFFFFFFFFFFFFFFFF, 0x1FFFF)` covering
-- bits 0..80. Column masks suppress wrap-around between x=8 and
-- x=0 of the next row when shifting horizontally. The four
-- direction-block masks are derived once per call from
-- `boardWallsH` / `boardWallsV`.

-- | Strict-pair `Word64` bitmap for the 9x9 grid.
data Bits128 = Bits128 !Word64 !Word64

{-# INLINE bits128Zero #-}
bits128Zero :: Bits128
bits128Zero = Bits128 0 0

{-# INLINE bits128Or #-}
bits128Or :: Bits128 -> Bits128 -> Bits128
bits128Or (Bits128 a0 a1) (Bits128 b0 b1) = Bits128 (a0 .|. b0) (a1 .|. b1)

{-# INLINE bits128And #-}
bits128And :: Bits128 -> Bits128 -> Bits128
bits128And (Bits128 a0 a1) (Bits128 b0 b1) = Bits128 (a0 .&. b0) (a1 .&. b1)

{-# INLINE bits128AndNot #-}
bits128AndNot :: Bits128 -> Bits128 -> Bits128
bits128AndNot (Bits128 a0 a1) (Bits128 b0 b1) =
    Bits128 (a0 .&. complement b0) (a1 .&. complement b1)

{-# INLINE bits128IsZero #-}
bits128IsZero :: Bits128 -> Bool
bits128IsZero (Bits128 a0 a1) = a0 == 0 && a1 == 0

-- | Shift the 81-bit bitmap left by `n` (move bits to higher indices).
-- Used to expand frontier upward (+9) or right (+1).
{-# INLINE bits128ShiftL #-}
bits128ShiftL :: Bits128 -> Int -> Bits128
bits128ShiftL (Bits128 a0 a1) n =
    let hiFromLo = a0 `shiftR` (64 - n)
        newLo = a0 `shiftL` n
        newHi = (a1 `shiftL` n) .|. hiFromLo
     in Bits128 newLo newHi

{-# INLINE bits128ShiftR #-}
bits128ShiftR :: Bits128 -> Int -> Bits128
bits128ShiftR (Bits128 a0 a1) n =
    let loFromHi = a1 `shiftL` (64 - n)
        newLo = (a0 `shiftR` n) .|. loFromHi
        newHi = a1 `shiftR` n
     in Bits128 newLo newHi

-- | All bits at cell positions 0..80 set, higher bits cleared.
{-# INLINE validCells #-}
validCells :: Bits128
validCells = Bits128 0xFFFFFFFFFFFFFFFF 0x1FFFF

-- | Cells with x ≤ 7 (so a left-shift-by-1 lands within the same row).
-- For each row y, columns 0..7 are set (bit y*9 + x for x in [0..7]).
{-# INLINE rightShiftMask #-}
rightShiftMask :: Bits128
rightShiftMask =
    -- 0b011111111 for each row (9-bit pattern with x=8 zeroed)
    -- Row 0: bits 0..7 → 0xFF
    -- Row 1: bits 9..16 → 0xFF << 9
    -- ... 9 rows total, each 9 bits wide
    let rowPattern = 0x0FF :: Word64
        rows0to6 =
            (rowPattern `shiftL` 0)
                .|. (rowPattern `shiftL` 9)
                .|. (rowPattern `shiftL` 18)
                .|. (rowPattern `shiftL` 27)
                .|. (rowPattern `shiftL` 36)
                .|. (rowPattern `shiftL` 45)
                .|. (rowPattern `shiftL` 54)
        -- row 7 starts at bit 63, partially in low word and partially in high
        row7Lo = rowPattern `shiftL` 63
        row7Hi = rowPattern `shiftR` 1
        -- row 8 starts at bit 72 (in high word at offset 72-64 = 8)
        row8Hi = rowPattern `shiftL` 8
        lo = rows0to6 .|. row7Lo
        hi = row7Hi .|. row8Hi
     in Bits128 lo hi

-- | Cells with x ≥ 1 (so a right-shift-by-1 lands within the same row).
{-# INLINE leftShiftMask #-}
leftShiftMask :: Bits128
leftShiftMask =
    let rowPattern = 0x1FE :: Word64 -- bits 1..8
        rows0to6 =
            (rowPattern `shiftL` 0)
                .|. (rowPattern `shiftL` 9)
                .|. (rowPattern `shiftL` 18)
                .|. (rowPattern `shiftL` 27)
                .|. (rowPattern `shiftL` 36)
                .|. (rowPattern `shiftL` 45)
                .|. (rowPattern `shiftL` 54)
        row7Lo = rowPattern `shiftL` 63
        row7Hi = rowPattern `shiftR` 1
        row8Hi = rowPattern `shiftL` 8
        lo = rows0to6 .|. row7Lo
        hi = row7Hi .|. row8Hi
     in Bits128 lo hi

-- | Mask of cells where moving up is BLOCKED (a horizontal wall sits
-- between (x, y) and (x, y+1)). Derived from `boardWallsH`: a wall
-- at intersection (xw, yw) for xw, yw in [0..7] blocks both
-- (xw, yw)→up and (xw+1, yw)→up.
{-# INLINE upBlockMask #-}
upBlockMask :: Board -> Bits128
upBlockMask board = expandHorizontalWalls (boardWallsH board)

{-# INLINE downBlockMask #-}
downBlockMask :: Board -> Bits128
downBlockMask board =
    -- Down-blocked from (x, y) ⇔ horizontal wall at (x-1, y-1) || (x, y-1)
    -- = up-block at row (y-1) shifted up by 9 cells.
    bits128ShiftL (upBlockMask board) 9

{-# INLINE rightBlockMask #-}
rightBlockMask :: Board -> Bits128
rightBlockMask board = expandVerticalWalls (boardWallsV board)

{-# INLINE leftBlockMask #-}
leftBlockMask :: Board -> Bits128
leftBlockMask board =
    -- Left-blocked from (x, y) ⇔ vertical wall at (x-1, y-1) || (x-1, y)
    -- = right-block at column (x-1) shifted right by 1 cell.
    bits128ShiftL (rightBlockMask board) 1

-- | Expand 8x8 horizontal-wall bitmap (`boardWallsH`, bit yw*8 + xw)
-- to a 9x9 up-block mask (bit y*9 + x set if up-move from (x, y) is
-- blocked). Each wall at (xw, yw) sets bits at (xw, yw) and (xw+1, yw).
expandHorizontalWalls :: Word64 -> Bits128
expandHorizontalWalls walls = go walls bits128Zero
  where
    go !w !acc
        | w == 0 = acc
        | otherwise =
            let bit = countTrailingZeros64 w
                yw = bit `div` 8
                xw = bit `mod` 8
                idx1 = yw * 9 + xw
                idx2 = yw * 9 + xw + 1
                acc' = acc `bits128Or` bits128Bit idx1 `bits128Or` bits128Bit idx2
                w' = w .&. (w - 1)
             in go w' acc'

-- | Expand 8x8 vertical-wall bitmap (`boardWallsV`, bit yw*8 + xw) to
-- a 9x9 right-block mask (bit y*9 + x set if right-move from (x, y)
-- is blocked). Each wall at (xw, yw) sets bits at (xw, yw) and
-- (xw, yw+1).
expandVerticalWalls :: Word64 -> Bits128
expandVerticalWalls walls = go walls bits128Zero
  where
    go !w !acc
        | w == 0 = acc
        | otherwise =
            let bit = countTrailingZeros64 w
                yw = bit `div` 8
                xw = bit `mod` 8
                idx1 = yw * 9 + xw
                idx2 = (yw + 1) * 9 + xw
                acc' = acc `bits128Or` bits128Bit idx1 `bits128Or` bits128Bit idx2
                w' = w .&. (w - 1)
             in go w' acc'

{-# INLINE bits128Bit #-}
bits128Bit :: Int -> Bits128
bits128Bit i
    | i < 64 = Bits128 (1 `shiftL` i) 0
    | otherwise = Bits128 0 (1 `shiftL` (i - 64))

{-# INLINE bits128TestBit #-}
bits128TestBit :: Bits128 -> Int -> Bool
bits128TestBit (Bits128 lo hi) i
    | i < 64 = testBit lo i
    | otherwise = testBit hi (i - 64)

-- | Count trailing zero bits in a Word64 (using popCount of (w-1) ^ w
-- isolates the lowest set bit; we then take log2).
{-# INLINE countTrailingZeros64 #-}
countTrailingZeros64 :: Word64 -> Int
countTrailingZeros64 w =
    -- Use built-in `countTrailingZeros` from `Data.Bits`.
    -- (Re-exported below if not already imported.)
    ctzWord64 w

ctzWord64 :: Word64 -> Int
ctzWord64 = Data.Bits.countTrailingZeros

-- | Row-y mask: cells with y == targetY (bit y*9 + x for x in [0..8]).
{-# INLINE rowMask #-}
rowMask :: Int -> Bits128
rowMask y
    | y < 7 = Bits128 (0x1FF `shiftL` (y * 9)) 0
    | y == 7 = Bits128 (0x1FF `shiftL` 63) (0x1FF `shiftR` 1)
    | otherwise = Bits128 0 (0x1FF `shiftL` 8)

-- | Sprint 8.2 round 3: wavefront-bitmap BFS. Replaces the recursive
-- list-based BFS with a constant-depth iteration over a 128-bit
-- frontier representation.
{-# INLINEABLE pathExists #-}
pathExists :: Side -> Board -> Bool
pathExists side board = bits128TestBit reach target0Idx || reachesTarget
  where
    (sx, sy) = pawnForSide side board
    targetY = case side of
        Hero -> 8
        Villain -> 0
    target0Idx = targetY * 9 + 0 -- only used as a quick membership-test hint
    targetMask = rowMask targetY
    startBitmap = bits128Bit (sy * 9 + sx)

    upBlock = upBlockMask board
    downBlock = downBlockMask board
    rightBlock = rightBlockMask board
    leftBlock = leftBlockMask board

    -- Tight wavefront loop. The bound (`grid diameter ≤ 16`) ensures
    -- we always terminate; we additionally exit when no new bits
    -- appear or when the target row is reached.
    go !visited !frontier !iters
        | iters > 81 = visited -- safety cap; should never trip
        | bits128IsZero frontier = visited
        | not (bits128IsZero (visited `bits128And` targetMask)) = visited
        | otherwise =
            let upMoves =
                    bits128ShiftL (frontier `bits128AndNot` upBlock) 9
                        `bits128And` validCells
                downMoves =
                    bits128ShiftR (frontier `bits128AndNot` downBlock) 9
                rightMoves =
                    bits128ShiftL
                        ((frontier `bits128AndNot` rightBlock) `bits128And` rightShiftMask)
                        1
                leftMoves =
                    bits128ShiftR
                        ((frontier `bits128AndNot` leftBlock) `bits128And` leftShiftMask)
                        1
                expanded = upMoves `bits128Or` downMoves `bits128Or` rightMoves `bits128Or` leftMoves
                newFrontier = expanded `bits128AndNot` visited
                visited' = visited `bits128Or` newFrontier
             in go visited' newFrontier (iters + 1)

    reach = go startBitmap startBitmap (0 :: Int)
    reachesTarget = not (bits128IsZero (reach `bits128And` targetMask))

-- | Sprint 8.2 round 3 shortestDistance using the same wavefront BFS
-- but tracking the BFS-wave count. Returns 99 when unreachable.
{-# INLINEABLE shortestDistance #-}
shortestDistance :: Side -> Board -> Int
shortestDistance side board = go startBitmap startBitmap 0
  where
    (sx, sy) = pawnForSide side board
    targetY = case side of
        Hero -> 8
        Villain -> 0
    targetMask = rowMask targetY
    startBitmap = bits128Bit (sy * 9 + sx)

    upBlock = upBlockMask board
    downBlock = downBlockMask board
    rightBlock = rightBlockMask board
    leftBlock = leftBlockMask board

    go !visited !frontier !distance
        | not (bits128IsZero (visited `bits128And` targetMask)) = distance
        | bits128IsZero frontier = 99
        | distance > 81 = 99
        | otherwise =
            let upMoves =
                    bits128ShiftL (frontier `bits128AndNot` upBlock) 9
                        `bits128And` validCells
                downMoves =
                    bits128ShiftR (frontier `bits128AndNot` downBlock) 9
                rightMoves =
                    bits128ShiftL
                        ((frontier `bits128AndNot` rightBlock) `bits128And` rightShiftMask)
                        1
                leftMoves =
                    bits128ShiftR
                        ((frontier `bits128AndNot` leftBlock) `bits128And` leftShiftMask)
                        1
                expanded = upMoves `bits128Or` downMoves `bits128Or` rightMoves `bits128Or` leftMoves
                newFrontier = expanded `bits128AndNot` visited
                visited' = visited `bits128Or` newFrontier
             in go visited' newFrontier (distance + 1)

nonTerminalRank :: Board -> Int
nonTerminalRank board =
    shortestDistance Villain board - shortestDistance Hero board

edgeBlocked :: Board -> (Int, Int) -> (Int, Int) -> Bool
edgeBlocked board (x1, y1) (x2, y2)
    | x1 == x2 && abs (y1 - y2) == 1 =
        let y = min y1 y2
         in any (uncurry (wallBitSet (boardWallsH board))) [(x1 - 1, y), (x1, y)]
    | y1 == y2 && abs (x1 - x2) == 1 =
        let x = min x1 x2
         in any (uncurry (wallBitSet (boardWallsV board))) [(x, y1 - 1), (x, y1)]
    | otherwise = False

pawnForSide :: Side -> Board -> (Int, Int)
pawnForSide side board =
    case side of
        Hero -> pawnCoords (boardHero board)
        Villain -> pawnCoords (boardVillain board)

{-# INLINEABLE applyMove #-}
applyMove :: Action -> Board -> Board
applyMove action board =
    advancePly . toggleSide $
        case (boardSideToMove board, action) of
            (Hero, Pawn x y) -> board{boardHero = pawnSlot x y}
            (Villain, Pawn x y) -> board{boardVillain = pawnSlot x y}
            (Hero, WallH x y) ->
                board
                    { boardWallsH = setWallBit (boardWallsH board) x y
                    , boardHeroWalls = decrement (boardHeroWalls board)
                    }
            (Villain, WallH x y) ->
                board
                    { boardWallsH = setWallBit (boardWallsH board) x y
                    , boardVillainWalls = decrement (boardVillainWalls board)
                    }
            (Hero, WallV x y) ->
                board
                    { boardWallsV = setWallBit (boardWallsV board) x y
                    , boardHeroWalls = decrement (boardHeroWalls board)
                    }
            (Villain, WallV x y) ->
                board
                    { boardWallsV = setWallBit (boardWallsV board) x y
                    , boardVillainWalls = decrement (boardVillainWalls board)
                    }

decrement :: Word8 -> Word8
decrement n = if n == 0 then 0 else n - 1

toggleSide :: Board -> Board
toggleSide board = board{boardSideToMove = otherSide (boardSideToMove board)}

advancePly :: Board -> Board
advancePly board = board{boardPly = boardPly board + 1}

{-# INLINEABLE isTerminal #-}
isTerminal :: Word16 -> Board -> Bool
isTerminal maxPlies board =
    terminalOutcome maxPlies board /= nonTerminalOutcome

{-# INLINEABLE terminalOutcome #-}
terminalOutcome :: Word16 -> Board -> Float
terminalOutcome maxPlies board
    | snd (pawnCoords (boardHero board)) == 8 = 1.0
    | snd (pawnCoords (boardVillain board)) == 0 = -1.0
    | boardPly board >= maxPlies = 0.0
    | otherwise = nonTerminalOutcome

{-# INLINEABLE terminalWinner #-}
terminalWinner :: Word16 -> Board -> Maybe Winner
terminalWinner maxPlies board =
    let outcome = terminalOutcome maxPlies board
     in if outcome == 1.0
            then Just HeroWin
            else
                if outcome == -1.0
                    then Just VillainWin
                    else
                        if outcome == 0.0
                            then Just Draw
                            else Nothing

nonTerminalOutcome :: Float
nonTerminalOutcome = 2.0

pawnSlot :: Int -> Int -> Word64
pawnSlot x y = fromIntegral (y * 9 + x)

pawnCoords :: Word64 -> (Int, Int)
pawnCoords value =
    let idx = max 0 (min 80 (fromIntegral value))
     in (idx `mod` 9, idx `div` 9)

setWallBit :: Word64 -> Int -> Int -> Word64
setWallBit bits x y
    | validWallCoord x y = setBit bits (y * 8 + x)
    | otherwise = bits

wallBitSet :: Word64 -> Int -> Int -> Bool
wallBitSet bits x y =
    validWallCoord x y && testBit bits (y * 8 + x)

validWallCoord :: Int -> Int -> Bool
validWallCoord x y =
    x >= 0 && x <= 7 && y >= 0 && y <= 7
