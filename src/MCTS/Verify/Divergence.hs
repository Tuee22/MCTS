module MCTS.Verify.Divergence
    ( DivergenceMetrics (..)
    , divergenceRate
    , divergenceVsEqStream
    , renderDivergenceMetrics
    ) where

import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Word (Word32)
import MCTS.Transcript.EquitySidecar (EqRecord (..), EqStream (..))
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

-- | Score a transcript against a sidecar-held EqStream produced by
-- the same or a different backend's foreign recompute. Sprint 7.5:
-- the equity_l2_drift is the root-mean-square delta between the
-- transcript's recorded chosen action equity (currently always 0.0
-- because equities are excluded from the wire format) and the
-- recompute's per-move chosen-action equity. The visit and move
-- disagreement rates are computed against the recompute records'
-- chosen action vs the transcript's chosen action.
divergenceVsEqStream :: Transcript -> EqStream -> DivergenceMetrics
divergenceVsEqStream transcript stream =
    DivergenceMetrics
        { visitDisagreementRate = rate visitDisagreements total
        , moveDisagreementRate = rate moveDisagreements total
        , equityL2Drift = l2Drift
        }
  where
    recordMap =
        Map.fromList
            [ ((eqGameId r, eqMoveIndex r), r)
            | r <- eqRecords stream
            ]
    paired =
        [ (moveRec, Map.lookup (gameId game, moveIndex moveRec) recordMap)
        | game <- transcriptGames transcript
        , moveRec <- gameMoves game
        ]
    total = length paired
    moveDisagreements =
        length
            [ ()
            | (moveRec, mRecompute) <- paired
            , case mRecompute of
                Nothing -> True
                Just r -> moveChosen moveRec /= eqChosen r
            ]
    -- visit disagreement is not derivable from an EqStream alone (the
    -- sidecar carries only chosen-action equity); we conservatively
    -- count a disagreement whenever the chosen action differs.
    visitDisagreements = moveDisagreements
    drifts =
        [ delta * delta
        | (_, Just r) <- paired
        , let delta = eqEquity r - 0.0
        , not (isNaN delta)
        ]
    l2Drift =
        if null drifts
            then 0.0
            else sqrt (sum drifts / fromIntegral (length drifts))

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
        (Just left, Just right) -> comparableVisits left /= comparableVisits right
        _ -> True

comparableVisits :: MoveRecord -> [(Action, Word32)]
comparableVisits =
    sort . filter ((> 0) . snd) . moveVisits

rate :: Int -> Int -> Double
rate _ 0 = 0.0
rate n total = fromIntegral n / fromIntegral total

fixed4 :: Double -> String
fixed4 = printf "%.4f"
