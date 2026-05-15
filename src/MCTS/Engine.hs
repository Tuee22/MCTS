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

import Data.Bits (setBit, testBit)
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

pathExists :: Side -> Board -> Bool
pathExists side board = go [] [pawnForSide side board]
  where
    target (_, y) =
        case side of
            Hero -> y == 8
            Villain -> y == 0

    go _ [] = False
    go seen (p : rest)
        | target p = True
        | p `elem` seen = go seen rest
        | otherwise =
            let next =
                    [ q
                    | q <- neighbours p
                    , q `notElem` seen
                    , not (edgeBlocked board p q)
                    ]
             in go (p : seen) (rest <> next)

shortestDistance :: Side -> Board -> Int
shortestDistance side board = go [] [(pawnForSide side board, 0)]
  where
    target (_, y) =
        case side of
            Hero -> y == 8
            Villain -> y == 0

    go _ [] = 99
    go seen ((p, distance) : rest)
        | target p = distance
        | p `elem` seen = go seen rest
        | otherwise =
            let next =
                    [ (q, distance + 1)
                    | q <- neighbours p
                    , q `notElem` seen
                    , not (edgeBlocked board p q)
                    ]
             in go (p : seen) (rest <> next)

nonTerminalRank :: Board -> Int
nonTerminalRank board =
    shortestDistance Villain board - shortestDistance Hero board

neighbours :: (Int, Int) -> [(Int, Int)]
neighbours (x, y) =
    [ (nx, ny)
    | (nx, ny) <- [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    , nx >= 0
    , nx <= 8
    , ny >= 0
    , ny <= 8
    ]

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
