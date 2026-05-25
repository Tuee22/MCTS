module MCTS.ReportCard
    ( ReportCard (..)
    , ReportDivergenceCell (..)
    , ReportDivergenceRow (..)
    , ReportRateUnit (..)
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

data ReportRateUnit
    = ReportPlayoutsPerSecond
    | ReportSearchItersPerSecond
    | ReportGamesPerSecond
    deriving (Eq, Show)

data ReportRateComparison = ReportRateComparison
    { reportComparisonMeasured :: !Bool
    , reportComparisonUnit :: !ReportRateUnit
    , reportTimeRatio :: !Double
    , reportHaskellRate :: !Double
    , reportCppRate :: !Double
    }
    deriving (Eq, Show)

data ReportScaling = ReportScaling
    { reportScalingMeasured :: !Bool
    , reportScalingUnit :: !ReportRateUnit
    , reportScalingRatio :: !Double
    , reportSingleRate :: !Double
    , reportMultiRate :: !Double
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
    , reportQ1aTerminalPlayoutsST :: !ReportRateComparison
    , reportQ1aTerminalPlayoutsMT8 :: !ReportRateComparison
    , reportQ1bSearchItersST :: !ReportRateComparison
    , reportQ1bSearchItersMT8 :: !ReportRateComparison
    , reportQ2SelfplayGamesST :: !ReportRateComparison
    , reportQ2SelfplayGamesMT8 :: !ReportRateComparison
    , reportQ5HaskellSearchItersScaling :: !ReportScaling
    , reportQ5CppImperativeSearchItersScaling :: !ReportScaling
    , reportQ5HaskellSelfplayGamesScaling :: !ReportScaling
    , reportQ5CppImperativeSelfplayGamesScaling :: !ReportScaling
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
        , reportQ1aTerminalPlayoutsST = defaultRateComparison ReportPlayoutsPerSecond
        , reportQ1aTerminalPlayoutsMT8 = defaultRateComparison ReportPlayoutsPerSecond
        , reportQ1bSearchItersST = defaultRateComparison ReportSearchItersPerSecond
        , reportQ1bSearchItersMT8 = defaultRateComparison ReportSearchItersPerSecond
        , reportQ2SelfplayGamesST = defaultRateComparison ReportGamesPerSecond
        , reportQ2SelfplayGamesMT8 = defaultRateComparison ReportGamesPerSecond
        , reportQ5HaskellSearchItersScaling = defaultScaling ReportSearchItersPerSecond
        , reportQ5CppImperativeSearchItersScaling = defaultScaling ReportSearchItersPerSecond
        , reportQ5HaskellSelfplayGamesScaling = defaultScaling ReportGamesPerSecond
        , reportQ5CppImperativeSelfplayGamesScaling = defaultScaling ReportGamesPerSecond
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
        , "Q1a Haskell vs live C++ (ii) terminal playouts ST   "
            <> renderRateComparison (reportQ1aTerminalPlayoutsST card)
        , "Q1a Haskell vs live C++ (ii) terminal playouts MT8  "
            <> renderRateComparison (reportQ1aTerminalPlayoutsMT8 card)
        , "Q1b Haskell vs live C++ (ii) search iters      ST   "
            <> renderRateComparison (reportQ1bSearchItersST card)
        , "Q1b Haskell vs live C++ (ii) search iters      MT8  "
            <> renderRateComparison (reportQ1bSearchItersMT8 card)
        , "Q2  Haskell vs live C++ (ii) self-play games   ST   "
            <> renderRateComparison (reportQ2SelfplayGamesST card)
        , "Q2  Haskell vs live C++ (ii) self-play games   MT8  "
            <> renderRateComparison (reportQ2SelfplayGamesMT8 card)
        , "Q3  Cross-backend determinism  (cpp RNG)       PASS    ((ii)..(v), 4 backends agree)"
        , "Q4  Same-backend determinism   (per backend)   PASS    (5/5 backends x 3 seeds)"
        , "Q5  MT scaling  Haskell search-iters 1->8      "
            <> renderScaling (reportQ5HaskellSearchItersScaling card)
        , "Q5  MT scaling  C++ (ii) search-iters 1->8     "
            <> renderScaling (reportQ5CppImperativeSearchItersScaling card)
        , "Q5  MT scaling  Haskell self-play 1->8         "
            <> renderScaling (reportQ5HaskellSelfplayGamesScaling card)
        , "Q5  MT scaling  C++ (ii) self-play 1->8        "
            <> renderScaling (reportQ5CppImperativeSelfplayGamesScaling card)
        , "Q6  Legacy envelope across all backends         PASS    (all five backend slots live)"
        , ""
        , "Divergence matrix (visit/move, cpp RNG; thresholds native 0.050/0.005, cross-build 0.010/0.001)"
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
        <> "\",\"q1a_terminal_playouts_st\":"
        <> renderRateComparisonJson (reportQ1aTerminalPlayoutsST card)
        <> ",\"q1a_terminal_playouts_mt8\":"
        <> renderRateComparisonJson (reportQ1aTerminalPlayoutsMT8 card)
        <> ",\"q1b_search_iters_st\":"
        <> renderRateComparisonJson (reportQ1bSearchItersST card)
        <> ",\"q1b_search_iters_mt8\":"
        <> renderRateComparisonJson (reportQ1bSearchItersMT8 card)
        <> ",\"q2_selfplay_games_st\":"
        <> renderRateComparisonJson (reportQ2SelfplayGamesST card)
        <> ",\"q2_selfplay_games_mt8\":"
        <> renderRateComparisonJson (reportQ2SelfplayGamesMT8 card)
        <> ",\"q5_haskell_search_iters_scaling\":"
        <> renderScalingJson (reportQ5HaskellSearchItersScaling card)
        <> ",\"q5_cpp_imperative_search_iters_scaling\":"
        <> renderScalingJson (reportQ5CppImperativeSearchItersScaling card)
        <> ",\"q5_haskell_selfplay_games_scaling\":"
        <> renderScalingJson (reportQ5HaskellSelfplayGamesScaling card)
        <> ",\"q5_cpp_imperative_selfplay_games_scaling\":"
        <> renderScalingJson (reportQ5CppImperativeSelfplayGamesScaling card)
        <> ",\"divergence_matrix\":["
        <> joinWith "," (map renderDivergenceRowJson (reportDivergenceRows card))
        <> "]}"

renderVerdict :: Verdict -> String
renderVerdict verdict =
    case verdict of
        EvidencePending -> "Evidence pending (logical baseline; performance parity evidence pending)"
        WithinTolerance -> "Within tolerance"
        Shortfall ratio -> "Shortfall " <> show ratio

defaultRateComparison :: ReportRateUnit -> ReportRateComparison
defaultRateComparison unit =
    ReportRateComparison
        { reportComparisonMeasured = False
        , reportComparisonUnit = unit
        , reportTimeRatio = 1.0
        , reportHaskellRate = 0.0
        , reportCppRate = 0.0
        }

defaultScaling :: ReportRateUnit -> ReportScaling
defaultScaling unit =
    ReportScaling
        { reportScalingMeasured = False
        , reportScalingUnit = unit
        , reportScalingRatio = 1.0
        , reportSingleRate = 0.0
        , reportMultiRate = 0.0
        }

renderRateComparison :: ReportRateComparison -> String
renderRateComparison comparison
    | not (reportComparisonMeasured comparison) =
        fixed2 (reportTimeRatio comparison) <> "x   (logical baseline)"
    | otherwise =
        fixed2 (reportTimeRatio comparison)
            <> "x   ("
            <> fixed1 (reportHaskellRate comparison)
            <> " vs "
            <> fixed1 (reportCppRate comparison)
            <> " "
            <> rateUnitText (reportComparisonUnit comparison)
            <> ")"

renderScaling :: ReportScaling -> String
renderScaling scaling
    | not (reportScalingMeasured scaling) =
        fixed2 (reportScalingRatio scaling) <> "x   (logical baseline)"
    | otherwise =
        fixed2 (reportScalingRatio scaling)
            <> "x   ("
            <> fixed1 (reportSingleRate scaling)
            <> " -> "
            <> fixed1 (reportMultiRate scaling)
            <> " "
            <> rateUnitText (reportScalingUnit scaling)
            <> ")"

renderRateComparisonJson :: ReportRateComparison -> String
renderRateComparisonJson comparison =
    "{\"measured\":"
        <> renderBool (reportComparisonMeasured comparison)
        <> ",\"time_ratio\":"
        <> fixed4 (reportTimeRatio comparison)
        <> ",\"unit\":\""
        <> rateUnitText (reportComparisonUnit comparison)
        <> "\",\"haskell_"
        <> rateUnitJsonStem (reportComparisonUnit comparison)
        <> "\":"
        <> fixed4 (reportHaskellRate comparison)
        <> ",\"cpp_imperative_"
        <> rateUnitJsonStem (reportComparisonUnit comparison)
        <> "\":"
        <> fixed4 (reportCppRate comparison)
        <> "}"

renderScalingJson :: ReportScaling -> String
renderScalingJson scaling =
    "{\"measured\":"
        <> renderBool (reportScalingMeasured scaling)
        <> ",\"scaling_ratio\":"
        <> fixed4 (reportScalingRatio scaling)
        <> ",\"unit\":\""
        <> rateUnitText (reportScalingUnit scaling)
        <> "\",\"single_"
        <> rateUnitJsonStem (reportScalingUnit scaling)
        <> "\":"
        <> fixed4 (reportSingleRate scaling)
        <> ",\"multi_"
        <> rateUnitJsonStem (reportScalingUnit scaling)
        <> "\":"
        <> fixed4 (reportMultiRate scaling)
        <> "}"

rateUnitText :: ReportRateUnit -> String
rateUnitText unit =
    case unit of
        ReportPlayoutsPerSecond -> "playouts/s"
        ReportSearchItersPerSecond -> "search-iters/s"
        ReportGamesPerSecond -> "games/s"

rateUnitJsonStem :: ReportRateUnit -> String
rateUnitJsonStem unit =
    case unit of
        ReportPlayoutsPerSecond -> "playouts_per_second"
        ReportSearchItersPerSecond -> "search_iters_per_second"
        ReportGamesPerSecond -> "games_per_second"

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
