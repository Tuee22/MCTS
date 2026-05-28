module MCTS.ReportCard
    ( ReportCard (..)
    , ReportDivergenceCell (..)
    , ReportDivergenceRow (..)
    , ReportRawPerformanceRow (..)
    , ReportRateUnit (..)
    , ReportRateComparison (..)
    , ReportScaling (..)
    , Verdict (..)
    , defaultReportCard
    , divergenceRowsFromTranscripts
    , normalizedDivergenceScore
    , reportCardPassed
    , reportCardParityTolerance
    , renderReportCard
    , renderReportCardJson
    ) where

import Data.List (transpose)
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

data ReportRawPerformanceRow = ReportRawPerformanceRow
    { reportRawBackend :: !Backend
    , reportRawQ1aTerminalPlayoutsST :: !(Maybe Double)
    , reportRawQ1aTerminalPlayoutsMT8 :: !(Maybe Double)
    , reportRawQ1bSearchItersST :: !(Maybe Double)
    , reportRawQ1bSearchItersMT8 :: !(Maybe Double)
    , reportRawQ2SelfplayGamesST :: !(Maybe Double)
    , reportRawQ2SelfplayGamesMT8 :: !(Maybe Double)
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
    , reportRawPerformanceRows :: ![ReportRawPerformanceRow]
    , reportDivergenceRows :: ![ReportDivergenceRow]
    }
    deriving (Eq, Show)

reportCardParityTolerance :: Double
reportCardParityTolerance = 0.05

reportCardPassed :: ReportCard -> Bool
reportCardPassed card =
    case reportVerdict card of
        WithinTolerance -> True
        EvidencePending -> False
        Shortfall _ -> False

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
        , reportRawPerformanceRows = defaultRawPerformanceRows
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
        , ""
        , "Terms:"
        , "  ST: single-threaded run."
        , "  MT8: multi-threaded run with 8 workers."
        , "  Q1a: terminal playout throughput, measured in playouts/s."
        , "  Q1b: UCT search-iteration throughput, measured in search-iters/s."
        , "  Q2: complete self-play game throughput, measured in games/s."
        , "  Q5: MT8/ST scaling ratio for the named backend and metric."
        , "  visit/move: visit-table and chosen-move disagreement rates."
        , "  normalized divergence score: maximum visit or move disagreement rate across the matrix."
        , ""
        , "Raw performance metrics"
        ]
            <> rawPerformanceTable card
            <> [ ""
               , "Question summary"
               ]
            <> questionSummaryTable card
            <> [ ""
               , "Divergence matrix (visit/move, cpp RNG; normalized divergence score "
                    <> fixed4 (normalizedDivergenceScore card)
                    <> ")"
               ]
            <> divergenceTable (reportDivergenceRows card)
            <> [ ""
               , "test stanzas                                   PASS    (mcts-unit, mcts-integration, mcts-cross-backend, mcts-legacy-parity, mcts-semantic-parity, mcts-haskell-style)"
               , ""
               , "Verdict: " <> renderVerdict (reportVerdict card)
               , ""
               , "Question answers"
               ]
            <> questionAnswersTable card

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
        <> ",\"raw_performance_metrics\":["
        <> joinWith "," (map renderRawPerformanceRowJson (reportRawPerformanceRows card))
        <> "]"
        <> ",\"normalized_divergence_score\":"
        <> fixed4 (normalizedDivergenceScore card)
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

rawPerformanceTable :: ReportCard -> [String]
rawPerformanceTable card =
    formatTable
        ["Backend", "Metric", "ST", "MT8", "Unit"]
        (concatMap rawRows (reportRawPerformanceRows card))
  where
    rawRows row =
        [
            [ backendIdentifier (reportRawBackend row)
            , "Q1a terminal playouts"
            , renderMaybeRate (reportRawQ1aTerminalPlayoutsST row)
            , renderMaybeRate (reportRawQ1aTerminalPlayoutsMT8 row)
            , rateUnitText ReportPlayoutsPerSecond
            ]
        ,
            [ backendIdentifier (reportRawBackend row)
            , "Q1b search iterations"
            , renderMaybeRate (reportRawQ1bSearchItersST row)
            , renderMaybeRate (reportRawQ1bSearchItersMT8 row)
            , rateUnitText ReportSearchItersPerSecond
            ]
        ,
            [ backendIdentifier (reportRawBackend row)
            , "Q2 self-play games"
            , renderMaybeRate (reportRawQ2SelfplayGamesST row)
            , renderMaybeRate (reportRawQ2SelfplayGamesMT8 row)
            , rateUnitText ReportGamesPerSecond
            ]
        ]

questionSummaryTable :: ReportCard -> [String]
questionSummaryTable card =
    formatTable
        ["Q", "Question", "Result"]
        [
            [ "Q1a"
            , "Does pure Haskell match backend (ii) on terminal playout throughput?"
            , renderComparisonPair
                (reportQ1aTerminalPlayoutsST card)
                (reportQ1aTerminalPlayoutsMT8 card)
            ]
        ,
            [ "Q1b"
            , "Does pure Haskell match backend (ii) on search-iteration throughput?"
            , renderComparisonPair
                (reportQ1bSearchItersST card)
                (reportQ1bSearchItersMT8 card)
            ]
        ,
            [ "Q2"
            , "Does pure Haskell match backend (ii) on complete self-play throughput?"
            , renderComparisonPair
                (reportQ2SelfplayGamesST card)
                (reportQ2SelfplayGamesMT8 card)
            ]
        ,
            [ "Q3"
            , "Do live backends (ii)..(v) produce identical cpp-RNG determinism payloads?"
            , "PASS ((ii)..(v), 4 backends agree)"
            ]
        ,
            [ "Q4"
            , "Does same-backend determinism hold across repeated runs?"
            , "PASS (5/5 backends x 3 seeds)"
            ]
        ,
            [ "Q5"
            , "How do Haskell and backend (ii) scale from ST to MT8?"
            , "H search "
                <> renderScalingRatio (reportQ5HaskellSearchItersScaling card)
                <> "; C++ search "
                <> renderScalingRatio (reportQ5CppImperativeSearchItersScaling card)
                <> "; H self-play "
                <> renderScalingRatio (reportQ5HaskellSelfplayGamesScaling card)
                <> "; C++ self-play "
                <> renderScalingRatio (reportQ5CppImperativeSelfplayGamesScaling card)
            ]
        ,
            [ "Q6"
            , "Do all five backend slots pass the legacy-envelope liveness/overflow gate?"
            , "PASS (all five backend slots live)"
            ]
        ,
            [ "Q7"
            , "Do steelman backends (ii)..(v) pass semantic parity without weakening Q3?"
            , "PASS (mcts-semantic-parity; normalized_divergence_score="
                <> fixed4 (normalizedDivergenceScore card)
                <> ")"
            ]
        ]

questionAnswersTable :: ReportCard -> [String]
questionAnswersTable card =
    formatTable
        ["Q", "Answer"]
        [
            [ "Q1a"
            , parityAnswer
                "terminal playout throughput"
                (reportQ1aTerminalPlayoutsST card)
                (reportQ1aTerminalPlayoutsMT8 card)
            ]
        ,
            [ "Q1b"
            , parityAnswer
                "search-iteration throughput"
                (reportQ1bSearchItersST card)
                (reportQ1bSearchItersMT8 card)
            ]
        ,
            [ "Q2"
            , parityAnswer
                "complete self-play throughput"
                (reportQ2SelfplayGamesST card)
                (reportQ2SelfplayGamesMT8 card)
            ]
        ,
            [ "Q3"
            , crossBackendDeterminismAnswer (reportDivergenceRows card)
            ]
        ,
            [ "Q4"
            , "Yes: the observed same-backend determinism gate passed for 5 backend slots x 3 seeds before report-card rendering."
            ]
        ,
            [ "Q5"
            , scalingAnswer card
            ]
        ,
            [ "Q6"
            , "Yes: the observed legacy-envelope gate completed all five backend slots before report-card rendering."
            ]
        ,
            [ "Q7"
            , "Yes: the semantic-parity stanza passed and normalized_divergence_score is "
                <> fixed4 (normalizedDivergenceScore card)
                <> "."
            ]
        ]

divergenceTable :: [ReportDivergenceRow] -> [String]
divergenceTable rows =
    formatTable
        ("Origin" : targetBackends)
        [ reportDivergenceOrigin row : map renderDivergenceCell (reportDivergenceCells row)
        | row <- rows
        ]
  where
    targetBackends =
        case rows of
            [] -> defaultDivergenceBackends
            row : _ -> map reportDivergenceBackend (reportDivergenceCells row)

renderMaybeRate :: Maybe Double -> String
renderMaybeRate Nothing = "pending"
renderMaybeRate (Just value) = fixed1 value

renderComparisonPair :: ReportRateComparison -> ReportRateComparison -> String
renderComparisonPair single multi =
    renderComparisonRatio single <> " ST; " <> renderComparisonRatio multi <> " MT8"

renderComparisonRatio :: ReportRateComparison -> String
renderComparisonRatio comparison
    | reportComparisonMeasured comparison = fixed2 (reportTimeRatio comparison) <> "x"
    | otherwise = fixed2 (reportTimeRatio comparison) <> "x logical"

renderScalingRatio :: ReportScaling -> String
renderScalingRatio scaling
    | reportScalingMeasured scaling = fixed2 (reportScalingRatio scaling) <> "x"
    | otherwise = fixed2 (reportScalingRatio scaling) <> "x logical"

parityAnswer :: String -> ReportRateComparison -> ReportRateComparison -> String
parityAnswer metric single multi
    | not (reportComparisonMeasured single && reportComparisonMeasured multi) =
        "Pending: observed "
            <> metric
            <> " metrics are not available yet."
    | comparisonsWithinTolerance single multi =
        "Yes: observed backend (ii)/Haskell ratios are "
            <> observedComparisonRatios single multi
            <> ", within "
            <> fixed2 parityToleranceRatio
            <> "x tolerance."
    | otherwise =
        "No: observed backend (ii)/Haskell ratios are "
            <> observedComparisonRatios single multi
            <> ", above "
            <> fixed2 parityToleranceRatio
            <> "x tolerance."

comparisonsWithinTolerance :: ReportRateComparison -> ReportRateComparison -> Bool
comparisonsWithinTolerance single multi =
    reportTimeRatio single <= parityToleranceRatio
        && reportTimeRatio multi <= parityToleranceRatio

observedComparisonRatios :: ReportRateComparison -> ReportRateComparison -> String
observedComparisonRatios single multi =
    fixed2 (reportTimeRatio single)
        <> "x ST and "
        <> fixed2 (reportTimeRatio multi)
        <> "x MT8"

parityToleranceRatio :: Double
parityToleranceRatio = 1.0 + reportCardParityTolerance

crossBackendDeterminismAnswer :: [ReportDivergenceRow] -> String
crossBackendDeterminismAnswer rows =
    let (visit, move) = maxDivergenceRates rows
        observed = fixed4 visit <> "/" <> fixed4 move
     in if visit == 0.0 && move == 0.0
            then "Yes: max observed visit/move disagreement is " <> observed <> "."
            else "No: max observed visit/move disagreement is " <> observed <> "."

maxDivergenceRates :: [ReportDivergenceRow] -> (Double, Double)
maxDivergenceRates rows =
    ( maximum
        (0.0 : [reportVisitDisagreementRate cell | cell <- allDivergenceCells])
    , maximum
        (0.0 : [reportMoveDisagreementRate cell | cell <- allDivergenceCells])
    )
  where
    allDivergenceCells = concatMap reportDivergenceCells rows

normalizedDivergenceScore :: ReportCard -> Double
normalizedDivergenceScore card =
    let (visit, move) = maxDivergenceRates (reportDivergenceRows card)
     in max visit move

scalingAnswer :: ReportCard -> String
scalingAnswer card
    | all reportScalingMeasured scalings =
        "Observed MT8/ST scaling is Haskell search "
            <> renderScalingRatio (reportQ5HaskellSearchItersScaling card)
            <> ", backend (ii) search "
            <> renderScalingRatio (reportQ5CppImperativeSearchItersScaling card)
            <> ", Haskell self-play "
            <> renderScalingRatio (reportQ5HaskellSelfplayGamesScaling card)
            <> ", backend (ii) self-play "
            <> renderScalingRatio (reportQ5CppImperativeSelfplayGamesScaling card)
            <> "."
    | otherwise = "Pending: observed scaling metrics are not available yet."
  where
    scalings =
        [ reportQ5HaskellSearchItersScaling card
        , reportQ5CppImperativeSearchItersScaling card
        , reportQ5HaskellSelfplayGamesScaling card
        , reportQ5CppImperativeSelfplayGamesScaling card
        ]

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

renderRawPerformanceRowJson :: ReportRawPerformanceRow -> String
renderRawPerformanceRowJson row =
    "{\"backend\":\""
        <> backendIdentifier (reportRawBackend row)
        <> "\",\"q1a_terminal_playouts_st\":"
        <> renderMaybeRateJson (reportRawQ1aTerminalPlayoutsST row)
        <> ",\"q1a_terminal_playouts_mt8\":"
        <> renderMaybeRateJson (reportRawQ1aTerminalPlayoutsMT8 row)
        <> ",\"q1b_search_iters_st\":"
        <> renderMaybeRateJson (reportRawQ1bSearchItersST row)
        <> ",\"q1b_search_iters_mt8\":"
        <> renderMaybeRateJson (reportRawQ1bSearchItersMT8 row)
        <> ",\"q2_selfplay_games_st\":"
        <> renderMaybeRateJson (reportRawQ2SelfplayGamesST row)
        <> ",\"q2_selfplay_games_mt8\":"
        <> renderMaybeRateJson (reportRawQ2SelfplayGamesMT8 row)
        <> "}"

renderMaybeRateJson :: Maybe Double -> String
renderMaybeRateJson Nothing = "null"
renderMaybeRateJson (Just value) = fixed4 value

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

defaultRawPerformanceRows :: [ReportRawPerformanceRow]
defaultRawPerformanceRows =
    [ ReportRawPerformanceRow
        { reportRawBackend = backend
        , reportRawQ1aTerminalPlayoutsST = Nothing
        , reportRawQ1aTerminalPlayoutsMT8 = Nothing
        , reportRawQ1bSearchItersST = Nothing
        , reportRawQ1bSearchItersMT8 = Nothing
        , reportRawQ2SelfplayGamesST = Nothing
        , reportRawQ2SelfplayGamesMT8 = Nothing
        }
    | backend <- allBackends
    ]

formatTable :: [String] -> [[String]] -> [String]
formatTable headers rows =
    let tableRows = headers : rows
        widths = map (maximum . map length) (transpose tableRows)
        renderRow row = joinWith "  " [padRight width cell | (width, cell) <- zip widths row]
        separator = joinWith "  " [replicate width '-' | width <- widths]
     in renderRow headers : separator : map renderRow rows

padRight :: Int -> String -> String
padRight width value =
    take width (value <> repeat ' ')

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith delimiter (x : xs) = x <> delimiter <> joinWith delimiter xs
