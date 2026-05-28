{-# LANGUAGE BangPatterns #-}

module MCTS.Engine
    ( Board (..)
    , ActionIds (..)
    , initialBoard
    , legalMoves
    , legalActionIds
    , legalActionSet
    , legalActionSetNonTerminal
    , actionIdsLength
    , actionIdsToList
    , actionIdAtUnsafe
    , applyMove
    , applyActionId
    , applyActionIdNoPly
    , isTerminal
    , terminalOutcome
    , nonTerminalOutcome
    , terminalWinner
    , nonTerminalRank
    ) where

import Data.Bits (complement, shiftL, shiftR, (.&.), (.|.))
import qualified Data.Bits
import Data.Word (Word16, Word64, Word8)
import MCTS.Types
    ( Action (..)
    , Side (..)
    , Winner (..)
    , actionFromId
    , actionId
    )

data Board = Board
    { boardHero :: !Word8
    , boardVillain :: !Word8
    , boardWallsH :: !Word64
    , boardWallsV :: !Word64
    , boardHeroWalls :: !Word8
    , boardVillainWalls :: !Word8
    , boardSideToMove :: !Side
    , boardPly :: !Word16
    }
    deriving (Eq, Show, Read)

data ActionIds = ActionIds !Int !Word64 !Word64

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
legalMoves board =
    [ action
    | ident <- legalActionIds board
    , Just action <- [actionFromId ident]
    ]

{-# INLINEABLE legalActionIds #-}
legalActionIds :: Board -> [Word8]
legalActionIds board
    | boardHero board >= 72 || boardVillain board <= 8 = []
    | otherwise = actionIdsToList (legalActionSetNonTerminal board)

{-# INLINEABLE legalActionSet #-}
legalActionSet :: Board -> ActionIds
legalActionSet board
    | boardHero board >= 72 || boardVillain board <= 8 = emptyActionIds
    | otherwise = legalActionSetNonTerminal board

{-# INLINEABLE legalActionSetNonTerminal #-}
legalActionSetNonTerminal :: Board -> ActionIds
legalActionSetNonTerminal board = appendWallActionIds board (pawnActionSet board)

{-# INLINE emptyActionIds #-}
emptyActionIds :: ActionIds
emptyActionIds = ActionIds 0 0 0

{-# INLINE snocActionId #-}
snocActionId :: ActionIds -> Word8 -> ActionIds
snocActionId (ActionIds n lo hi) ident
    | n < 8 =
        ActionIds
            (n + 1)
            (lo .|. (fromIntegral ident `shiftL` (n * 8)))
            hi
    | n < 16 =
        ActionIds
            (n + 1)
            lo
            (hi .|. (fromIntegral ident `shiftL` ((n - 8) * 8)))
    | otherwise = error "MCTS.Engine: too many legal action ids"

{-# INLINE actionIdsLength #-}
actionIdsLength :: ActionIds -> Int
actionIdsLength (ActionIds n _ _) = n

{-# INLINE actionIdAtUnsafe #-}
actionIdAtUnsafe :: ActionIds -> Int -> Word8
actionIdAtUnsafe (ActionIds _ lo hi) idx
    | idx < 8 = fromIntegral ((lo `shiftR` (idx * 8)) .&. 0xff)
    | otherwise = fromIntegral ((hi `shiftR` ((idx - 8) * 8)) .&. 0xff)

actionIdsToList :: ActionIds -> [Word8]
actionIdsToList ids = go (actionIdsLength ids - 1) []
  where
    go i acc
        | i < 0 = acc
        | otherwise = go (i - 1) (actionIdAtUnsafe ids i : acc)

{-# INLINE pawnActionSet #-}
pawnActionSet :: Board -> ActionIds
pawnActionSet board =
    let (!actorIdx, !occupiedIdx) =
            case boardSideToMove board of
                Hero -> (fromIntegral (boardHero board), fromIntegral (boardVillain board))
                Villain -> (fromIntegral (boardVillain board), fromIntegral (boardHero board))
        !x = actorIdx `rem` 9
        !y = actorIdx `quot` 9
        !h = boardWallsH board
        !v = boardWallsV board
        !a0 =
            if y > 0
                then appendUp h x y occupiedIdx emptyActionIds actorIdx
                else emptyActionIds
        !a1 =
            if x > 0
                then appendLeft v x y occupiedIdx a0 actorIdx
                else a0
        !a2 =
            if x < 8
                then appendRight v x y occupiedIdx a1 actorIdx
                else a1
     in if y < 8
            then appendDown h x y occupiedIdx a2 actorIdx
            else a2
  where
    appendUp h x y occupied acc actorIdx =
        let !target = actorIdx - 9
         in if target == occupied || upBlocked h x y
                then acc
                else snocActionId acc (fromIntegral target)

    appendLeft v x y occupied acc actorIdx =
        let !target = actorIdx - 1
         in if target == occupied || leftBlocked v x y
                then acc
                else snocActionId acc (fromIntegral target)

    appendRight v x y occupied acc actorIdx =
        let !target = actorIdx + 1
         in if target == occupied || rightBlocked v x y
                then acc
                else snocActionId acc (fromIntegral target)

    appendDown h x y occupied acc actorIdx =
        let !target = actorIdx + 9
         in if target == occupied || downBlocked h x y
                then acc
                else snocActionId acc (fromIntegral target)

    upBlocked h x y =
        let wallY = y - 1
         in (x > 0 && wallBitSetUnsafe h (x - 1) wallY)
                || (x < 8 && wallBitSetUnsafe h x wallY)

    downBlocked h x y =
        (x > 0 && wallBitSetUnsafe h (x - 1) y)
            || (x < 8 && wallBitSetUnsafe h x y)

    leftBlocked v x y =
        let wallX = x - 1
         in (y > 0 && wallBitSetUnsafe v wallX (y - 1))
                || (y < 8 && wallBitSetUnsafe v wallX y)

    rightBlocked v x y =
        (y > 0 && wallBitSetUnsafe v x (y - 1))
            || (y < 8 && wallBitSetUnsafe v x y)

{-# INLINE appendWallActionIds #-}
appendWallActionIds :: Board -> ActionIds -> ActionIds
appendWallActionIds board initial
    | wallsRemaining board == 0 = initial
    | boardWallsH board == 0 && boardWallsV board == 0 = appendEmptyBoardWalls 81 12 initial
    | otherwise = goHorizontal 81 0 initial
  where
    baseMasks = blockMasks board

    appendEmptyBoardWalls :: Int -> Int -> ActionIds -> ActionIds
    appendEmptyBoardWalls ident remaining acc
        | remaining <= 0 = acc
        | otherwise =
            appendEmptyBoardWalls
                (ident + 1)
                (remaining - 1)
                (snocActionId acc (fromIntegral ident))

    goHorizontal :: Int -> Int -> ActionIds -> ActionIds
    goHorizontal ident wallCount acc
        | wallCount >= 12 = acc
        | ident > 144 = goVertical 145 wallCount acc
        | legalWallId (fromIntegral ident) =
            goHorizontal (ident + 1) (wallCount + 1) (snocActionId acc (fromIntegral ident))
        | otherwise = goHorizontal (ident + 1) wallCount acc

    goVertical :: Int -> Int -> ActionIds -> ActionIds
    goVertical ident wallCount acc
        | wallCount >= 12 = acc
        | ident > 208 = acc
        | legalWallId (fromIntegral ident) =
            goVertical (ident + 1) (wallCount + 1) (snocActionId acc (fromIntegral ident))
        | otherwise = goVertical (ident + 1) wallCount acc
    legalWallId ident =
        not (wallIdExists board ident)
            && pathExistsWithMasks Hero board trialMasks
            && pathExistsWithMasks Villain board trialMasks
      where
        trialMasks = addWallIdToMasks ident baseMasks

{-# INLINE wallsRemaining #-}
wallsRemaining :: Board -> Word8
wallsRemaining board =
    case boardSideToMove board of
        Hero -> boardHeroWalls board
        Villain -> boardVillainWalls board

{-# INLINE wallIdExists #-}
wallIdExists :: Board -> Word8 -> Bool
wallIdExists board ident
    | ident >= 81 && ident <= 144 =
        let n = fromIntegral ident - 81
            !x = n `rem` 8
            !y = n `quot` 8
            h = boardWallsH board
            v = boardWallsV board
         in wallBitSetUnsafe h x y
                || (x > 0 && wallBitSetUnsafe h (x - 1) y)
                || (x < 7 && wallBitSetUnsafe h (x + 1) y)
                || wallBitSetUnsafe v x y
    | ident >= 145 && ident <= 208 =
        let n = fromIntegral ident - 145
            !x = n `rem` 8
            !y = n `quot` 8
            h = boardWallsH board
            v = boardWallsV board
         in wallBitSetUnsafe v x y
                || (y > 0 && wallBitSetUnsafe v x (y - 1))
                || (y < 7 && wallBitSetUnsafe v x (y + 1))
                || wallBitSetUnsafe h x y
    | otherwise = False

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

data BlockMasks = BlockMasks !Bits128 !Bits128 !Bits128 !Bits128

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
-- | Expand 8x8 horizontal-wall bitmap (`boardWallsH`, bit yw*8 + xw)
-- to a 9x9 up-block mask (bit y*9 + x set if up-move from (x, y) is
-- blocked). Each wall at (xw, yw) sets bits at (xw, yw) and (xw+1, yw).
{-# INLINE expandHorizontalWalls #-}
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
{-# INLINE expandVerticalWalls #-}
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

{-# INLINE blockMasks #-}
blockMasks :: Board -> BlockMasks
blockMasks board =
    let upBlock = expandHorizontalWalls (boardWallsH board)
        downBlock = bits128ShiftL upBlock 9
        rightBlock = expandVerticalWalls (boardWallsV board)
        leftBlock = bits128ShiftL rightBlock 1
     in BlockMasks upBlock downBlock rightBlock leftBlock

{-# INLINE addWallIdToMasks #-}
addWallIdToMasks :: Word8 -> BlockMasks -> BlockMasks
addWallIdToMasks ident masks@(BlockMasks upBlock downBlock rightBlock leftBlock)
    | ident >= 81 && ident <= 144 =
        let n = fromIntegral ident - 81
            !x = n `rem` 8
            !y = n `quot` 8
            up = horizontalUpBlock x y
            down = bits128ShiftL up 9
         in BlockMasks
                (upBlock `bits128Or` up)
                (downBlock `bits128Or` down)
                rightBlock
                leftBlock
    | ident >= 145 && ident <= 208 =
        let n = fromIntegral ident - 145
            !x = n `rem` 8
            !y = n `quot` 8
            right = verticalRightBlock x y
            left = bits128ShiftL right 1
         in BlockMasks
                upBlock
                downBlock
                (rightBlock `bits128Or` right)
                (leftBlock `bits128Or` left)
    | otherwise = masks

{-# INLINE horizontalUpBlock #-}
horizontalUpBlock :: Int -> Int -> Bits128
horizontalUpBlock x y =
    bits128Bit (y * 9 + x) `bits128Or` bits128Bit (y * 9 + x + 1)

{-# INLINE verticalRightBlock #-}
verticalRightBlock :: Int -> Int -> Bits128
verticalRightBlock x y =
    bits128Bit (y * 9 + x) `bits128Or` bits128Bit ((y + 1) * 9 + x)

{-# INLINE bits128Bit #-}
bits128Bit :: Int -> Bits128
bits128Bit i
    | i < 64 = Bits128 (1 `shiftL` i) 0
    | otherwise = Bits128 0 (1 `shiftL` (i - 64))

-- | Count trailing zero bits in a Word64 (using popCount of (w-1) ^ w
-- isolates the lowest set bit; we then take log2).
{-# INLINE countTrailingZeros64 #-}
countTrailingZeros64 :: Word64 -> Int
countTrailingZeros64 w =
    -- Use built-in `countTrailingZeros` from `Data.Bits`.
    -- (Re-exported below if not already imported.)
    ctzWord64 w

{-# INLINE ctzWord64 #-}
ctzWord64 :: Word64 -> Int
ctzWord64 = Data.Bits.countTrailingZeros

-- | Row-y mask: cells with y == targetY (bit y*9 + x for x in [0..8]).
{-# INLINE rowMask #-}
rowMask :: Int -> Bits128
rowMask y
    | y < 7 = Bits128 (0x1FF `shiftL` (y * 9)) 0
    | y == 7 = Bits128 (0x1FF `shiftL` 63) (0x1FF `shiftR` 1)
    | otherwise = Bits128 0 (0x1FF `shiftL` 8)

{-# INLINEABLE pathExistsWithMasks #-}
pathExistsWithMasks :: Side -> Board -> BlockMasks -> Bool
pathExistsWithMasks
    side
    board
    ( BlockMasks
            (Bits128 upLo upHi)
            (Bits128 downLo downHi)
            (Bits128 rightLo rightHi)
            (Bits128 leftLo leftHi)
        ) =
        atTarget || go startLo startHi startLo startHi
      where
        !startIdx =
            fromIntegral $
                case side of
                    Hero -> boardHero board
                    Villain -> boardVillain board
        !atTarget = case side of
            Hero -> startIdx >= 72
            Villain -> startIdx <= 8
        (!targetLo, !targetHi) =
            case side of
                Hero -> (0, 0x1FF00)
                Villain -> (0x1FF, 0)
        (!startLo, !startHi)
            | startIdx < 64 = (1 `shiftL` startIdx, 0)
            | otherwise = (0, 1 `shiftL` (startIdx - 64))

        validHi :: Word64
        validHi = 0x1FFFF

        rightMaskLo :: Word64
        rightMaskLo = 0xbfdfeff7fbfdfeff

        rightMaskHi :: Word64
        rightMaskHi = 0xff7f

        leftMaskLo :: Word64
        leftMaskLo = 0x7fbfdfeff7fbfdfe

        leftMaskHi :: Word64
        leftMaskHi = 0x1feff

        -- Tight wavefront loop. The frontier monotonically shrinks after
        -- visited cells are removed, so an explicit iteration cap is not
        -- needed in this hot legality path.
        go !visitedLo !visitedHi !frontierLo !frontierHi
            | frontierLo == 0 && frontierHi == 0 = False
            | otherwise =
                let upSrcLo = frontierLo .&. complement upLo
                    upSrcHi = frontierHi .&. complement upHi
                    upMovesLo = upSrcLo `shiftL` 9
                    upMovesHi = ((upSrcHi `shiftL` 9) .|. (upSrcLo `shiftR` 55)) .&. validHi
                    downSrcLo = frontierLo .&. complement downLo
                    downSrcHi = frontierHi .&. complement downHi
                    downMovesLo = (downSrcLo `shiftR` 9) .|. (downSrcHi `shiftL` 55)
                    downMovesHi = downSrcHi `shiftR` 9
                    rightSrcLo = frontierLo .&. complement rightLo .&. rightMaskLo
                    rightSrcHi = frontierHi .&. complement rightHi .&. rightMaskHi
                    rightMovesLo = rightSrcLo `shiftL` 1
                    rightMovesHi = ((rightSrcHi `shiftL` 1) .|. (rightSrcLo `shiftR` 63)) .&. validHi
                    leftSrcLo = frontierLo .&. complement leftLo .&. leftMaskLo
                    leftSrcHi = frontierHi .&. complement leftHi .&. leftMaskHi
                    leftMovesLo = (leftSrcLo `shiftR` 1) .|. (leftSrcHi `shiftL` 63)
                    leftMovesHi = leftSrcHi `shiftR` 1
                    expandedLo = upMovesLo .|. downMovesLo .|. rightMovesLo .|. leftMovesLo
                    expandedHi = upMovesHi .|. downMovesHi .|. rightMovesHi .|. leftMovesHi
                    !newFrontierLo = expandedLo .&. complement visitedLo
                    !newFrontierHi = expandedHi .&. complement visitedHi
                 in ((newFrontierLo .&. targetLo) /= 0 || (newFrontierHi .&. targetHi) /= 0)
                        || go
                            (visitedLo .|. newFrontierLo)
                            (visitedHi .|. newFrontierHi)
                            newFrontierLo
                            newFrontierHi

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

    BlockMasks upBlock downBlock rightBlock leftBlock = blockMasks board

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

{-# INLINE pawnForSide #-}
pawnForSide :: Side -> Board -> (Int, Int)
pawnForSide side board =
    case side of
        Hero -> pawnCoords (boardHero board)
        Villain -> pawnCoords (boardVillain board)

{-# INLINEABLE applyMove #-}
applyMove :: Action -> Board -> Board
applyMove action board = applyActionId (actionId action) board

{-# INLINE applyActionId #-}
applyActionId :: Word8 -> Board -> Board
applyActionId ident board = applyActionIdWithPlyIncrement 1 ident board

{-# INLINE applyActionIdNoPly #-}
applyActionIdNoPly :: Word8 -> Board -> Board
applyActionIdNoPly = applyActionIdWithPlyIncrement 0

{-# INLINE applyActionIdWithPlyIncrement #-}
applyActionIdWithPlyIncrement :: Word16 -> Word8 -> Board -> Board
applyActionIdWithPlyIncrement plyIncrement ident board
    | ident <= 80 =
        case boardSideToMove board of
            Hero ->
                Board
                    { boardHero = ident
                    , boardVillain = boardVillain board
                    , boardWallsH = boardWallsH board
                    , boardWallsV = boardWallsV board
                    , boardHeroWalls = boardHeroWalls board
                    , boardVillainWalls = boardVillainWalls board
                    , boardSideToMove = Villain
                    , boardPly = boardPly board + plyIncrement
                    }
            Villain ->
                Board
                    { boardHero = boardHero board
                    , boardVillain = ident
                    , boardWallsH = boardWallsH board
                    , boardWallsV = boardWallsV board
                    , boardHeroWalls = boardHeroWalls board
                    , boardVillainWalls = boardVillainWalls board
                    , boardSideToMove = Hero
                    , boardPly = boardPly board + plyIncrement
                    }
    | ident >= 81 && ident <= 144 =
        let n = fromIntegral ident - 81
            !x = n `rem` 8
            !y = n `quot` 8
         in case boardSideToMove board of
                Hero ->
                    Board
                        { boardHero = boardHero board
                        , boardVillain = boardVillain board
                        , boardWallsH = setWallBitUnsafe (boardWallsH board) x y
                        , boardWallsV = boardWallsV board
                        , boardHeroWalls = decrement (boardHeroWalls board)
                        , boardVillainWalls = boardVillainWalls board
                        , boardSideToMove = Villain
                        , boardPly = boardPly board + plyIncrement
                        }
                Villain ->
                    Board
                        { boardHero = boardHero board
                        , boardVillain = boardVillain board
                        , boardWallsH = setWallBitUnsafe (boardWallsH board) x y
                        , boardWallsV = boardWallsV board
                        , boardHeroWalls = boardHeroWalls board
                        , boardVillainWalls = decrement (boardVillainWalls board)
                        , boardSideToMove = Hero
                        , boardPly = boardPly board + plyIncrement
                        }
    | ident >= 145 && ident <= 208 =
        let n = fromIntegral ident - 145
            !x = n `rem` 8
            !y = n `quot` 8
         in case boardSideToMove board of
                Hero ->
                    Board
                        { boardHero = boardHero board
                        , boardVillain = boardVillain board
                        , boardWallsH = boardWallsH board
                        , boardWallsV = setWallBitUnsafe (boardWallsV board) x y
                        , boardHeroWalls = decrement (boardHeroWalls board)
                        , boardVillainWalls = boardVillainWalls board
                        , boardSideToMove = Villain
                        , boardPly = boardPly board + plyIncrement
                        }
                Villain ->
                    Board
                        { boardHero = boardHero board
                        , boardVillain = boardVillain board
                        , boardWallsH = boardWallsH board
                        , boardWallsV = setWallBitUnsafe (boardWallsV board) x y
                        , boardHeroWalls = boardHeroWalls board
                        , boardVillainWalls = decrement (boardVillainWalls board)
                        , boardSideToMove = Hero
                        , boardPly = boardPly board + plyIncrement
                        }
    | plyIncrement == 0 = board
    | otherwise = board{boardPly = boardPly board + plyIncrement}

{-# INLINE decrement #-}
decrement :: Word8 -> Word8
decrement n = if n == 0 then 0 else n - 1

{-# INLINE isTerminal #-}
isTerminal :: Word16 -> Board -> Bool
isTerminal maxPlies board =
    terminalOutcome maxPlies board /= nonTerminalOutcome

{-# INLINE terminalOutcome #-}
terminalOutcome :: Word16 -> Board -> Float
terminalOutcome maxPlies board
    | boardHero board >= 72 = 1.0
    | boardVillain board <= 8 = -1.0
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

{-# INLINE pawnSlot #-}
pawnSlot :: Int -> Int -> Word8
pawnSlot x y = fromIntegral (y * 9 + x)

{-# INLINE pawnCoords #-}
pawnCoords :: Word8 -> (Int, Int)
pawnCoords value =
    let idx = fromIntegral value
     in (idx `rem` 9, idx `quot` 9)

{-# INLINE setWallBitUnsafe #-}
setWallBitUnsafe :: Word64 -> Int -> Int -> Word64
setWallBitUnsafe bits x y = bits .|. (1 `shiftL` (y * 8 + x))

{-# INLINE wallBitSetUnsafe #-}
wallBitSetUnsafe :: Word64 -> Int -> Int -> Bool
wallBitSetUnsafe bits x y =
    (bits .&. (1 `shiftL` (y * 8 + x))) /= 0
