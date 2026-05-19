-- | Sprint 7.4: pure `brick` widget renderer for the 9x9 Corridors
-- board. The widget itself does not own any state — it takes a
-- `Board` and produces a `Widget` so both the `mcts play` and
-- `mcts inspect replay` TUIs render through the same code path.
module MCTS.CLI.Tui.Board
    ( renderBoard
    , renderBoardText
    , renderStatus
    , renderStatusText
    ) where

import Brick.Types (Widget)
import Brick.Widgets.Border (borderWithLabel)
import qualified Brick.Widgets.Border.Style as BS
import Brick.Widgets.Core
    ( str
    , vBox
    )
import qualified Brick.Widgets.Core as Brick
import Data.Bits (testBit)
import Data.Word (Word64)

import MCTS.Engine
    ( Board (..)
    , initialBoard
    )

-- | Render the board's 9x9 grid with hero/villain markers and
-- horizontal / vertical wall overlays. Wall cells are derived from
-- the same bitfields the engine uses for move legality, so `play`
-- and `inspect replay` display the actual reconstructed position.
renderBoard :: Board -> Widget String
renderBoard board =
    Brick.withBorderStyle BS.unicode $
        borderWithLabel (str "Corridors") $
            vBox (map str (renderBoardRows board))

renderBoardText :: Board -> String
renderBoardText = unlines . renderBoardRows

renderBoardRows :: Board -> [String]
renderBoardRows board = concatMap (renderRank board) [8, 7 .. 0]

renderRank :: Board -> Int -> [String]
renderRank board y =
    renderCellRow board y
        : [renderHorizontalWallRow board (y - 1) | y > 0]

renderCellRow :: Board -> Int -> String
renderCellRow board y =
    trimRight (concat [renderCellWithEastWall board x y | x <- [0 .. 8]])

renderCellWithEastWall :: Board -> Int -> Int -> String
renderCellWithEastWall board x y =
    renderCell board x y <> [if verticalWallEastOf board x y then '|' else ' ']

renderCell :: Board -> Int -> Int -> String
renderCell board x y
    | (x, y) == coords (boardHero board) = " H "
    | (x, y) == coords (boardVillain board) = " V "
    | otherwise = " . "
  where
    coords w = (fromIntegral w `mod` 9, fromIntegral w `div` 9)

renderHorizontalWallRow :: Board -> Int -> String
renderHorizontalWallRow board wallY =
    trimRight (concat [cellSpan x <> [intersection x] | x <- [0 .. 8]])
  where
    cellSpan x = if horizontalWallBelow board x wallY then "---" else "   "
    intersection x =
        if horizontalWallBelow board x wallY || verticalWallAtIntersection board x wallY
            then '+'
            else ' '

horizontalWallBelow :: Board -> Int -> Int -> Bool
horizontalWallBelow board x wallY =
    wallBit (boardWallsH board) x wallY || wallBit (boardWallsH board) (x - 1) wallY

verticalWallEastOf :: Board -> Int -> Int -> Bool
verticalWallEastOf board x y =
    x < 8 && (wallBit (boardWallsV board) x y || wallBit (boardWallsV board) x (y - 1))

verticalWallAtIntersection :: Board -> Int -> Int -> Bool
verticalWallAtIntersection board x wallY =
    wallBit (boardWallsV board) x wallY || wallBit (boardWallsV board) (x - 1) wallY

wallBit :: Word64 -> Int -> Int -> Bool
wallBit bits x y =
    x >= 0 && x <= 7 && y >= 0 && y <= 7 && testBit bits (y * 8 + x)

-- | One-line status string suitable for the bottom-of-screen status
-- bar. Used by `inspect replay` per
-- `DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint 7.4`:
-- `<hash> | move M / total | press ? for help`.
renderStatus :: String -> Int -> Int -> Widget String
renderStatus hashPrefix moveIndex moveCount =
    str (renderStatusText hashPrefix moveIndex moveCount)

renderStatusText :: String -> Int -> Int -> String
renderStatusText hashPrefix moveIndex moveCount =
    hashPrefix
        <> " | move "
        <> show moveIndex
        <> " / "
        <> show moveCount
        <> " | press ? for help"

trimRight :: String -> String
trimRight = reverse . dropWhile (== ' ') . reverse

-- | Smoke entry that takes no input. Confirms the renderer compiles
-- and produces a Widget value for the initial board.
_smokeBoardWidget :: Widget String
_smokeBoardWidget = renderBoard initialBoard
