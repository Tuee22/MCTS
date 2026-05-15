module MCTS.Verify.Divergence
    ( DivergenceMetrics (..)
    , divergenceRate
    , renderDivergenceMetrics
    ) where

import Data.List (sort)
import MCTS.Types
import Text.Printf (printf)

data DivergenceMetrics = DivergenceMetrics
    { visitDisagreementRate :: !Double
    , moveDisagreementRate :: !Double
    , equityL2Drift :: !Double
    }
    deriving (Eq, Show)

divergenceRate :: Transcript -> Transcript -> DivergenceMetrics
divergenceRate left right =
    DivergenceMetrics
        { visitDisagreementRate = rate visitDisagreements total
        , moveDisagreementRate = rate moveDisagreements total
        , equityL2Drift = 0.0
        }
  where
    pairs = zipLongest (flattenTranscript left) (flattenTranscript right)
    total = length pairs
    moveDisagreements = length [() | pair <- pairs, movesDiffer pair]
    visitDisagreements = length [() | pair <- pairs, visitsDiffer pair]

renderDivergenceMetrics :: String -> DivergenceMetrics -> String
renderDivergenceMetrics label metrics =
    label
        <> " "
        <> fixed4 (visitDisagreementRate metrics)
        <> " "
        <> fixed4 (moveDisagreementRate metrics)
        <> " "
        <> fixed4 (equityL2Drift metrics)

flattenTranscript :: Transcript -> [MoveRecord]
flattenTranscript transcript =
    concatMap gameMoves (transcriptGames transcript)

zipLongest :: [a] -> [b] -> [(Maybe a, Maybe b)]
zipLongest [] [] = []
zipLongest (left : leftRest) [] = (Just left, Nothing) : zipLongest leftRest []
zipLongest [] (right : rightRest) = (Nothing, Just right) : zipLongest [] rightRest
zipLongest (left : leftRest) (right : rightRest) = (Just left, Just right) : zipLongest leftRest rightRest

movesDiffer :: (Maybe MoveRecord, Maybe MoveRecord) -> Bool
movesDiffer pair =
    case pair of
        (Just left, Just right) -> moveChosen left /= moveChosen right
        _ -> True

visitsDiffer :: (Maybe MoveRecord, Maybe MoveRecord) -> Bool
visitsDiffer pair =
    case pair of
        (Just left, Just right) -> sort (moveVisits left) /= sort (moveVisits right)
        _ -> True

rate :: Int -> Int -> Double
rate _ 0 = 0.0
rate n total = fromIntegral n / fromIntegral total

fixed4 :: Double -> String
fixed4 = printf "%.4f"
