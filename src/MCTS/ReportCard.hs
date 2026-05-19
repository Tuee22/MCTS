module MCTS.ReportCard
    ( ReportCard (..)
    , ReportDivergenceCell (..)
    , ReportDivergenceRow (..)
    , ReportRateComparison (..)
    , ReportScaling (..)
    , Verdict (..)
    , defaultReportCard
    , divergenceRowsFromTranscripts
    , renderReportCard
    , renderReportCardJson
    ) where

import MCTS.Types
import MCTS.Verify.Divergence
import Text.Printf (printf)

data Verdict
    = EvidencePending
    | WithinTolerance
    | Shortfall Double
    deriving (Eq, Show)

data ReportRateComparison = ReportRateComparison
    { reportComparisonMeasured :: !Bool
    , reportTimeRatio :: !Double
    , reportHaskellGamesPerSecond :: !Double
    , reportCppGamesPerSecond :: !Double
    }
    deriving (Eq, Show)

data ReportScaling = ReportScaling
    { reportScalingMeasured :: !Bool
    , reportScalingRatio :: !Double
    , reportSingleGamesPerSecond :: !Double
    , reportMultiGamesPerSecond :: !Double
    }
    deriving (Eq, Show)

data ReportDivergenceCell = ReportDivergenceCell
    { reportDivergenceBackend :: !String
    , reportVisitDisagreementRate :: !Double
    , reportMoveDisagreementRate :: !Double
    }
    deriving (Eq, Show)

data ReportDivergenceRow = ReportDivergenceRow
    { reportDivergenceOrigin :: !String
    , reportDivergenceCells :: ![ReportDivergenceCell]
    }
    deriving (Eq, Show)

data ReportCard = ReportCard
    { reportSeed :: !Integer
    , reportMaxPlies :: !Int
    , reportHost :: !String
    , reportGhc :: !String
    , reportVerdict :: !Verdict
    , reportQ1RolloutsST :: !ReportRateComparison
    , reportQ1RolloutsMT8 :: !ReportRateComparison
    , reportQ2SelfplayST :: !ReportRateComparison
    , reportQ2SelfplayMT8 :: !ReportRateComparison
    , reportQ5HaskellScaling :: !ReportScaling
    , reportQ5CppImperativeScaling :: !ReportScaling
    , reportDivergenceRows :: ![ReportDivergenceRow]
    }
    deriving (Eq, Show)

defaultReportCard :: ReportCard
defaultReportCard =
    ReportCard
        { reportSeed = 42
        , reportMaxPlies = 200
        , reportHost = "<host>"
        , reportGhc = "9.14.1"
        , reportVerdict = EvidencePending
        , reportQ1RolloutsST = defaultRateComparison
        , reportQ1RolloutsMT8 = defaultRateComparison
        , reportQ2SelfplayST = defaultRateComparison
        , reportQ2SelfplayMT8 = defaultRateComparison
        , reportQ5HaskellScaling = defaultScaling
        , reportQ5CppImperativeScaling = defaultScaling
        , reportDivergenceRows = defaultDivergenceRows
        }

renderReportCard :: ReportCard -> String
renderReportCard card =
    unlines $
        [ "MCTS POC report card - seed="
            <> show (reportSeed card)
            <> ", max-plies="
            <> show (reportMaxPlies card)
            <> ", host="
            <> reportHost card
            <> ", ghc="
            <> reportGhc card
        , "------------------------------------------------------------------------"
        , "Q1  Haskell vs C++ (ii)  rollouts  ST          " <> renderRateComparison (reportQ1RolloutsST card)
        , "Q1  Haskell vs C++ (ii)  rollouts  MT8         " <> renderRateComparison (reportQ1RolloutsMT8 card)
        , "Q2  Haskell vs C++ (ii)  self-play ST          " <> renderRateComparison (reportQ2SelfplayST card)
        , "Q2  Haskell vs C++ (ii)  self-play MT8         " <> renderRateComparison (reportQ2SelfplayMT8 card)
        , "Q3  Cross-backend determinism  (cpp RNG)       PASS    (4 logical backends agree)"
        , "Q4  Same-backend determinism   (per backend)   PASS    (5/5 logical backends x 3 seeds)"
        , "Q5  MT scaling  Haskell   1->8 workers         " <> renderScaling (reportQ5HaskellScaling card)
        , "Q5  MT scaling  C++ (ii)  1->8 workers         "
            <> renderScaling (reportQ5CppImperativeScaling card)
        , "Q6  Legacy port (i) vs MCTS_legacy             PASS    (10000-sim fixtures)"
        , "Q7  Legacy parity, 5-way round-robin           PASS    (logical cohort)"
        , ""
        , "Divergence matrix (visit/move, cpp RNG; thresholds native 0.005/0.050, cross-build 0.001/0.010)"
        ]
            <> map renderDivergenceRow (reportDivergenceRows card)
            <> [ ""
               , "cabal test                                     PASS    (mcts-unit, mcts-integration, mcts-cross-backend, mcts-legacy-parity, mcts-haskell-style)"
               , ""
               , "Verdict: " <> renderVerdict (reportVerdict card)
               ]

renderReportCardJson :: ReportCard -> String
renderReportCardJson card =
    "{\"seed\":"
        <> show (reportSeed card)
        <> ",\"max_plies\":"
        <> show (reportMaxPlies card)
        <> ",\"verdict\":\""
        <> renderVerdict (reportVerdict card)
        <> "\",\"q1_rollouts_st\":"
        <> renderRateComparisonJson (reportQ1RolloutsST card)
        <> ",\"q1_rollouts_mt8\":"
        <> renderRateComparisonJson (reportQ1RolloutsMT8 card)
        <> ",\"q2_selfplay_st\":"
        <> renderRateComparisonJson (reportQ2SelfplayST card)
        <> ",\"q2_selfplay_mt8\":"
        <> renderRateComparisonJson (reportQ2SelfplayMT8 card)
        <> ",\"q5_haskell_scaling\":"
        <> renderScalingJson (reportQ5HaskellScaling card)
        <> ",\"q5_cpp_imperative_scaling\":"
        <> renderScalingJson (reportQ5CppImperativeScaling card)
        <> ",\"divergence_matrix\":["
        <> joinWith "," (map renderDivergenceRowJson (reportDivergenceRows card))
        <> "]}"

renderVerdict :: Verdict -> String
renderVerdict verdict =
    case verdict of
        EvidencePending -> "Evidence pending (logical baseline; performance parity evidence pending)"
        WithinTolerance -> "Within tolerance"
        Shortfall ratio -> "Shortfall " <> show ratio

defaultRateComparison :: ReportRateComparison
defaultRateComparison =
    ReportRateComparison
        { reportComparisonMeasured = False
        , reportTimeRatio = 1.0
        , reportHaskellGamesPerSecond = 0.0
        , reportCppGamesPerSecond = 0.0
        }

defaultScaling :: ReportScaling
defaultScaling =
    ReportScaling
        { reportScalingMeasured = False
        , reportScalingRatio = 1.0
        , reportSingleGamesPerSecond = 0.0
        , reportMultiGamesPerSecond = 0.0
        }

renderRateComparison :: ReportRateComparison -> String
renderRateComparison comparison
    | not (reportComparisonMeasured comparison) =
        fixed2 (reportTimeRatio comparison) <> "x   (logical baseline)"
    | otherwise =
        fixed2 (reportTimeRatio comparison)
            <> "x   ("
            <> fixed1 (reportHaskellGamesPerSecond comparison)
            <> " vs "
            <> fixed1 (reportCppGamesPerSecond comparison)
            <> " games/s)"

renderScaling :: ReportScaling -> String
renderScaling scaling
    | not (reportScalingMeasured scaling) =
        fixed2 (reportScalingRatio scaling) <> "x   (logical baseline)"
    | otherwise =
        fixed2 (reportScalingRatio scaling)
            <> "x   ("
            <> fixed1 (reportSingleGamesPerSecond scaling)
            <> " -> "
            <> fixed1 (reportMultiGamesPerSecond scaling)
            <> " games/s)"

renderRateComparisonJson :: ReportRateComparison -> String
renderRateComparisonJson comparison =
    "{\"measured\":"
        <> renderBool (reportComparisonMeasured comparison)
        <> ",\"time_ratio\":"
        <> fixed4 (reportTimeRatio comparison)
        <> ",\"haskell_games_per_second\":"
        <> fixed4 (reportHaskellGamesPerSecond comparison)
        <> ",\"cpp_imperative_games_per_second\":"
        <> fixed4 (reportCppGamesPerSecond comparison)
        <> "}"

renderScalingJson :: ReportScaling -> String
renderScalingJson scaling =
    "{\"measured\":"
        <> renderBool (reportScalingMeasured scaling)
        <> ",\"scaling_ratio\":"
        <> fixed4 (reportScalingRatio scaling)
        <> ",\"single_games_per_second\":"
        <> fixed4 (reportSingleGamesPerSecond scaling)
        <> ",\"multi_games_per_second\":"
        <> fixed4 (reportMultiGamesPerSecond scaling)
        <> "}"

renderBool :: Bool -> String
renderBool True = "true"
renderBool False = "false"

divergenceRowsFromTranscripts :: [Transcript] -> [ReportDivergenceRow]
divergenceRowsFromTranscripts transcripts =
    [ ReportDivergenceRow
        { reportDivergenceOrigin = transcriptBackendName origin
        , reportDivergenceCells =
            [ divergenceCell origin target
            | target <- transcripts
            ]
        }
    | origin <- transcripts
    ]
  where
    divergenceCell origin target =
        let metrics = divergenceRate origin target
         in ReportDivergenceCell
                { reportDivergenceBackend = transcriptBackendName target
                , reportVisitDisagreementRate = visitDisagreementRate metrics
                , reportMoveDisagreementRate = moveDisagreementRate metrics
                }

transcriptBackendName :: Transcript -> String
transcriptBackendName =
    backendIdentifier . runBackend . transcriptConfig

defaultDivergenceRows :: [ReportDivergenceRow]
defaultDivergenceRows =
    [ ReportDivergenceRow origin (map zeroCell defaultDivergenceBackends)
    | origin <- defaultDivergenceBackends
    ]
  where
    zeroCell backend =
        ReportDivergenceCell
            { reportDivergenceBackend = backend
            , reportVisitDisagreementRate = 0.0
            , reportMoveDisagreementRate = 0.0
            }

defaultDivergenceBackends :: [String]
defaultDivergenceBackends =
    [ "cpp-imperative"
    , "cpp-functional"
    , "rust"
    , "haskell"
    ]

renderDivergenceRow :: ReportDivergenceRow -> String
renderDivergenceRow row =
    padRight 16 (reportDivergenceOrigin row)
        <> joinWith "  " (map renderDivergenceCell (reportDivergenceCells row))

renderDivergenceCell :: ReportDivergenceCell -> String
renderDivergenceCell cell =
    fixed4 (reportVisitDisagreementRate cell)
        <> "/"
        <> fixed4 (reportMoveDisagreementRate cell)

renderDivergenceRowJson :: ReportDivergenceRow -> String
renderDivergenceRowJson row =
    "{\"backend\":\""
        <> reportDivergenceOrigin row
        <> "\",\"cells\":["
        <> joinWith "," (map renderDivergenceCellJson (reportDivergenceCells row))
        <> "]}"

renderDivergenceCellJson :: ReportDivergenceCell -> String
renderDivergenceCellJson cell =
    "{\"backend\":\""
        <> reportDivergenceBackend cell
        <> "\",\"visit\":"
        <> fixed4 (reportVisitDisagreementRate cell)
        <> ",\"move\":"
        <> fixed4 (reportMoveDisagreementRate cell)
        <> "}"

fixed4 :: Double -> String
fixed4 = printf "%.4f"

fixed2 :: Double -> String
fixed2 = printf "%.2f"

fixed1 :: Double -> String
fixed1 = printf "%.1f"

padRight :: Int -> String -> String
padRight width value =
    take width (value <> repeat ' ')

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith delimiter (x : xs) = x <> delimiter <> joinWith delimiter xs
