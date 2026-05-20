module MCTS.Notation
    ( renderMove
    , parseMove
    , renderWinner
    ) where

import Data.Char (isDigit)
import MCTS.Types (Action (..), Winner (..))
import Text.Read (readMaybe)

renderMove :: Action -> String
renderMove action =
    case action of
        Pawn x y -> "*(" <> show x <> "," <> show y <> ")"
        WallH x y -> "H(" <> show x <> "," <> show y <> ")"
        WallV x y -> "V(" <> show x <> "," <> show y <> ")"

parseMove :: String -> Maybe Action
parseMove raw =
    case raw of
        '*' : rest -> uncurry Pawn <$> parseCoords rest 8
        'H' : rest -> uncurry WallH <$> parseCoords rest 7
        'V' : rest -> uncurry WallV <$> parseCoords rest 7
        _ -> Nothing

parseCoords :: String -> Int -> Maybe (Int, Int)
parseCoords raw maxCoord =
    case raw of
        '(' : xs ->
            let (left, afterLeft) = span isDigit xs
             in case afterLeft of
                    ',' : ys ->
                        let (right, afterRight) = span isDigit ys
                         in case afterRight of
                                ")"
                                    | not (null left) && not (null right) ->
                                        case (readMaybe left, readMaybe right) of
                                            (Just x, Just y)
                                                | x >= 0 && x <= maxCoord && y >= 0 && y <= maxCoord ->
                                                    Just (x, y)
                                            _ -> Nothing
                                _ -> Nothing
                    _ -> Nothing
        _ -> Nothing

renderWinner :: Winner -> String
renderWinner winner =
    case winner of
        HeroWin -> "hero"
        VillainWin -> "villain"
        Draw -> "draw"
