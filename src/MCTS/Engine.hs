module MCTS.Engine
    ( Board (..)
    , initialBoard
    , legalMoves
    , applyMove
    , isTerminal
    , terminalWinner
    ) where

import Data.List (nub, sortOn)
import Data.Word (Word16, Word8)
import MCTS.Types
    ( Action (..)
    , Side (..)
    , Winner (..)
    , actionId
    , otherSide
    )

data Board = Board
    { boardHero :: !(Int, Int)
    , boardVillain :: !(Int, Int)
    , boardWallsH :: ![(Int, Int)]
    , boardWallsV :: ![(Int, Int)]
    , boardHeroWalls :: !Word8
    , boardVillainWalls :: !Word8
    , boardSideToMove :: !Side
    , boardPly :: !Word16
    }
    deriving (Eq, Show, Read)

initialBoard :: Board
initialBoard =
    Board
        { boardHero = (4, 0)
        , boardVillain = (4, 8)
        , boardWallsH = []
        , boardWallsV = []
        , boardHeroWalls = 10
        , boardVillainWalls = 10
        , boardSideToMove = Hero
        , boardPly = 0
        }

{-# INLINABLE legalMoves #-}
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
        WallH x y -> (x, y) `elem` boardWallsH board
        WallV x y -> (x, y) `elem` boardWallsV board
        Pawn _ _ -> False

applyWallOnly :: Action -> Board -> Board
applyWallOnly action board =
    case action of
        WallH x y -> board{boardWallsH = nub ((x, y) : boardWallsH board)}
        WallV x y -> board{boardWallsV = nub ((x, y) : boardWallsV board)}
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
         in any (`elem` boardWallsH board) [(x1 - 1, y), (x1, y)]
    | y1 == y2 && abs (x1 - x2) == 1 =
        let x = min x1 x2
         in any (`elem` boardWallsV board) [(x, y1 - 1), (x, y1)]
    | otherwise = False

pawnForSide :: Side -> Board -> (Int, Int)
pawnForSide side board =
    case side of
        Hero -> boardHero board
        Villain -> boardVillain board

{-# INLINABLE applyMove #-}
applyMove :: Action -> Board -> Board
applyMove action board =
    advancePly . toggleSide $
        case (boardSideToMove board, action) of
            (Hero, Pawn x y) -> board{boardHero = (x, y)}
            (Villain, Pawn x y) -> board{boardVillain = (x, y)}
            (Hero, WallH x y) ->
                board
                    { boardWallsH = nub ((x, y) : boardWallsH board)
                    , boardHeroWalls = decrement (boardHeroWalls board)
                    }
            (Villain, WallH x y) ->
                board
                    { boardWallsH = nub ((x, y) : boardWallsH board)
                    , boardVillainWalls = decrement (boardVillainWalls board)
                    }
            (Hero, WallV x y) ->
                board
                    { boardWallsV = nub ((x, y) : boardWallsV board)
                    , boardHeroWalls = decrement (boardHeroWalls board)
                    }
            (Villain, WallV x y) ->
                board
                    { boardWallsV = nub ((x, y) : boardWallsV board)
                    , boardVillainWalls = decrement (boardVillainWalls board)
                    }

decrement :: Word8 -> Word8
decrement n = if n == 0 then 0 else n - 1

toggleSide :: Board -> Board
toggleSide board = board{boardSideToMove = otherSide (boardSideToMove board)}

advancePly :: Board -> Board
advancePly board = board{boardPly = boardPly board + 1}

{-# INLINABLE isTerminal #-}
isTerminal :: Word16 -> Board -> Bool
isTerminal maxPlies board =
    terminalWinner maxPlies board /= Nothing

{-# INLINABLE terminalWinner #-}
terminalWinner :: Word16 -> Board -> Maybe Winner
terminalWinner maxPlies board
    | snd (boardHero board) == 8 = Just HeroWin
    | snd (boardVillain board) == 0 = Just VillainWin
    | boardPly board >= maxPlies = Just Draw
    | otherwise = Nothing

