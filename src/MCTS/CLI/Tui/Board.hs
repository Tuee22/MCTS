-- | Sprint 7.4: pure `brick` widget renderer for the 9x9 Corridors
-- board. The widget itself does not own any state — it takes a
-- `Board` and produces a `Widget` so both the `mcts play` and
-- `mcts inspect replay` TUIs render through the same code path.
module MCTS.CLI.Tui.Board
    ( renderBoard
    , renderStatus
    ) where

import Brick.AttrMap (attrName)
import Brick.Types (Widget)
import Brick.Widgets.Border (borderWithLabel)
import qualified Brick.Widgets.Border.Style as BS
import Brick.Widgets.Core
    ( hBox
    , str
    , vBox
    , withAttr
    , (<+>)
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
            vBox (concatMap (renderRank board) [8, 7 .. 0])

renderRank :: Board -> Int -> [Widget String]
renderRank board y =
    renderCellRow board y
        : [renderHorizontalWallRow board (y - 1) | y > 0]

renderCellRow :: Board -> Int -> Widget String
renderCellRow board y =
    hBox [renderCellWithEastWall board x y | x <- [0 .. 8]]

renderCellWithEastWall :: Board -> Int -> Int -> Widget String
renderCellWithEastWall board x y =
    renderCell board x y <+> str (if verticalWallEastOf board x y then "|" else " ")

renderCell :: Board -> Int -> Int -> Widget String
renderCell board x y =
    let pawnHere
            | (x, y) == coords (boardHero board) = withAttr (attrName "hero") (str " H ")
            | (x, y) == coords (boardVillain board) = withAttr (attrName "villain") (str " V ")
            | otherwise = str " . "
     in pawnHere
  where
    coords w = (fromIntegral w `mod` 9, fromIntegral w `div` 9)

renderHorizontalWallRow :: Board -> Int -> Widget String
renderHorizontalWallRow board wallY =
    hBox [str (cellSpan x) <+> str (intersection x) | x <- [0 .. 8]]
  where
    cellSpan x = if horizontalWallBelow board x wallY then "---" else "   "
    intersection x =
        if horizontalWallBelow board x wallY || verticalWallAtIntersection board x wallY
            then "+"
            else " "

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
    str hashPrefix
        <+> str " | move "
        <+> str (show moveIndex)
        <+> str " / "
        <+> str (show moveCount)
        <+> str " | press ? for help"

-- | Smoke entry that takes no input. Confirms the renderer compiles
-- and produces a Widget value for the initial board.
_smokeBoardWidget :: Widget String
_smokeBoardWidget = renderBoard initialBoard
