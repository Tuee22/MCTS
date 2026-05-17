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

import MCTS.Engine
    ( Board (..)
    , initialBoard
    )

-- | Render the board's 9x9 grid with hero/villain markers and the
-- wall remaining counters. Walls are not rendered yet — the smoke
-- TUI's rendering shape is what matters; cell-level wall overlays
-- ship with the full play/replay TUI under the same Sprint.
renderBoard :: Board -> Widget String
renderBoard board =
    Brick.withBorderStyle BS.unicode $
        borderWithLabel (str "Corridors") $
            vBox [renderRow y board | y <- [8, 7 .. 0]]

renderRow :: Int -> Board -> Widget String
renderRow y board =
    hBox [renderCell x y board | x <- [0 .. 8]]

renderCell :: Int -> Int -> Board -> Widget String
renderCell x y board =
    let pawnHere
            | (x, y) == coords (boardHero board) = withAttr (attrName "hero") (str " H ")
            | (x, y) == coords (boardVillain board) = withAttr (attrName "villain") (str " V ")
            | otherwise = str " . "
     in pawnHere
  where
    coords w = (fromIntegral w `mod` 9, fromIntegral w `div` 9)

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
