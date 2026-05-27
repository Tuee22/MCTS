{-# LANGUAGE OverloadedStrings #-}

module MCTS.CLI.Test
    ( buildMeasuredReportCardWith
    , runTestCommand
    , testAllPlan
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Word (Word16, Word64)
import MCTS.CLI.Bench (measurePrimitiveBackendRate, monotonicNanos)
import MCTS.CLI.Command
    ( BenchPrimitive (..)
    , BenchPrimitiveOptions (..)
    , ParityAnchorOptions (..)
    , TestCommand (..)
    )
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderErrorString)
import MCTS.Driver (BatchResult (..), RunInputs (..), defaultRunInputs)
import MCTS.Driver.Dispatch (runBatchNoWriteDispatch)
import qualified MCTS.Env as Env
import MCTS.Error (AppError (..))
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath)
import MCTS.FFI.CppLegacy (cppLegacyLibraryPath)
import MCTS.FFI.Rust (rustLibraryPath)
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForTest)
import MCTS.ReportCard
import MCTS.Subprocess
import MCTS.Transcript (hostArch)
import MCTS.Types
import MCTS.Verify (VerifyResult (..), verifyRunDetailed)
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..))
import Text.Printf (printf)

data ParityAnchorResult = ParityAnchorResult
    { anchorBaseline :: !Backend
    , anchorCandidate :: !Backend
    , anchorRows :: ![ParityAnchorRow]
    }
    deriving (Eq, Show)

data ParityAnchorRow = ParityAnchorRow
    { anchorQuestion :: !String
    , anchorWorkload :: !Workload
    , anchorThreading :: !Threading
    , anchorGames :: !Int
    , anchorSims :: !Int
    , anchorBaselineGamesPerSecond :: !Double
    , anchorCandidateGamesPerSecond :: !Double
    , anchorTimeRatio :: !Double
    }
    deriving (Eq, Show)

data ReportPerformance = ReportPerformance
    { performanceQ1aTerminalPlayoutsST :: !ReportRateComparison
    , performanceQ1aTerminalPlayoutsMT8 :: !ReportRateComparison
    , performanceQ1bSearchItersST :: !ReportRateComparison
    , performanceQ1bSearchItersMT8 :: !ReportRateComparison
    , performanceQ2SelfplayGamesST :: !ReportRateComparison
    , performanceQ2SelfplayGamesMT8 :: !ReportRateComparison
    , performanceRawRows :: ![ReportRawPerformanceRow]
    }
    deriving (Eq, Show)

runTestCommand :: TestCommand -> Env.App ExitCode
runTestCommand command = do
    env <- Env.askEnv
    runWithOutput (Env.envOutputOptions env) command

runWithOutput :: OutputOptions -> TestCommand -> Env.App ExitCode
runWithOutput output command =
    case command of
        TestAll opts -> do
            let plan = testAllPlan
                rendered = renderPlan plan
            liftIO (writePlanFile (planFile opts) rendered)
            if planDryRun opts
                then liftIO (outputLine rendered) >> pure ExitSuccess
                else do
                    prerequisites <- liftIO (checkPrerequisites prerequisitesForTest)
                    case prerequisites of
                        Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
                        Right () -> do
                            code <- runStanzaPlan output plan
                            if code == ExitSuccess
                                then do
                                    reportCard <- liftIO buildMeasuredReportCard
                                    case reportCard of
                                        Left err ->
                                            liftIO (outputLine (renderErrorString output err))
                                                >> pure (ExitFailure 1)
                                        Right card ->
                                            liftIO
                                                ( outputLine
                                                    ( if outputFormat output == JsonFormat
                                                        then renderReportCardJson card
                                                        else renderReportCard card
                                                    )
                                                )
                                                >> pure
                                                    ( if reportCardPassed card
                                                        then ExitSuccess
                                                        else ExitFailure 1
                                                    )
                                else pure code
        TestParityAnchor opts -> do
            let plan = parityAnchorPlan opts
                rendered = renderPlan plan
            liftIO (writePlanFile (planFile (parityAnchorPlanOptions opts)) rendered)
            if planDryRun (parityAnchorPlanOptions opts)
                then liftIO (outputLine rendered) >> pure ExitSuccess
                else
                    if parityAnchorBaseline opts == parityAnchorCandidate opts
                        then do
                            liftIO
                                ( outputLine
                                    ( renderErrorString
                                        output
                                        (ParseError "parity-anchor requires distinct baseline and candidate backends")
                                    )
                                )
                            pure (ExitFailure 1)
                        else do
                            prerequisites <- liftIO (checkPrerequisites prerequisitesForTest)
                            case prerequisites of
                                Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
                                Right () -> do
                                    code <- runStanzaPlan output plan
                                    if code == ExitSuccess
                                        then do
                                            anchor <-
                                                liftIO
                                                    ( buildParityAnchor
                                                        monotonicNanos
                                                        (parityAnchorBaseline opts)
                                                        (parityAnchorCandidate opts)
                                                    )
                                            case anchor of
                                                Left err ->
                                                    liftIO (outputLine (renderErrorString output err))
                                                        >> pure (ExitFailure 1)
                                                Right result -> do
                                                    liftIO
                                                        ( outputLine
                                                            ( if outputFormat output == JsonFormat
                                                                then renderParityAnchorJson result
                                                                else renderParityAnchor result
                                                            )
                                                        )
                                                    pure $
                                                        if parityAnchorWithinTolerance result
                                                            then ExitSuccess
                                                            else ExitFailure 1
                                        else pure code
        TestStanza stanza ->
            case testStanzaPlan stanza of
                Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
                Right plan -> do
                    prerequisites <- liftIO (checkPrerequisites prerequisitesForTest)
                    case prerequisites of
                        Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
                        Right () -> runStanzaPlan output plan

testAllPlan :: Plan Subprocess
testAllPlan =
    Plan
        { planName = "test all"
        , planSteps =
            [ mctsStep ["lint", "files"]
            , mctsStep ["lint", "docs"]
            , testStep "mcts-haskell-style"
            , testStep "mcts-unit"
            , testStep "mcts-integration"
            , testStep "mcts-cross-backend"
            , testStep "mcts-legacy-parity"
            , mctsStep
                [ "verify"
                , "rollouts"
                , "--backend"
                , "cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--games"
                , show reportCardVerifyGames
                , "--seed"
                , "42"
                , "--max-plies"
                , "200"
                ]
            , mctsStep
                [ "verify"
                , "selfplay"
                , "--backend"
                , "cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--games"
                , show reportCardVerifyGames
                , "--seed"
                , "42"
                , "--max-plies"
                , "200"
                , "--sims"
                , show reportCardVerifySims
                ]
            , mctsStep
                [ "verify"
                , "legacy-parity"
                , "selfplay"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--games"
                , show reportCardLegacyParityGames
                , "--seed"
                , "42"
                , "--sims"
                , show reportCardLegacyParitySims
                ]
            ]
        }

parityAnchorPlan :: ParityAnchorOptions -> Plan Subprocess
parityAnchorPlan opts =
    Plan
        { planName =
            "test parity-anchor "
                <> backendIdentifier (parityAnchorBaseline opts)
                <> " "
                <> backendIdentifier (parityAnchorCandidate opts)
        , planSteps = []
        }

mctsStep :: [String] -> Subprocess
mctsStep args = Subprocess "mcts" args Nothing Nothing

testStep :: String -> Subprocess
testStep stanza = Subprocess stanza [] Nothing Nothing

testStanzaPlan :: String -> Either AppError (Plan Subprocess)
testStanzaPlan stanza
    | stanza `elem` testStanzaNames = Right (Plan ("test " <> stanza) [testStep stanza])
    | otherwise = Left (ParseError ("unknown test stanza: " <> stanza))

testStanzaNames :: [String]
testStanzaNames =
    [ "mcts-haskell-style"
    , "mcts-unit"
    , "mcts-integration"
    , "mcts-cross-backend"
    , "mcts-legacy-parity"
    ]

runStanzaPlan :: OutputOptions -> Plan Subprocess -> Env.App ExitCode
runStanzaPlan output = applyWithEnv (runTestStep output)
  where
    runTestStep outputOptions _env step = do
        result <- runStreaming step
        case result of
            Left err -> outputLine (renderErrorString outputOptions err) >> pure (Right (ExitFailure 1))
            Right code -> pure (Right code)

buildMeasuredReportCard :: IO (Either AppError ReportCard)
buildMeasuredReportCard = do
    artifacts <- requireReportCardArtifacts
    case artifacts of
        Left err -> pure (Left err)
        Right () -> do
            performance <- buildReportPerformance monotonicNanos
            divergence <- buildMeasuredReportCardWith reportCardBackends reportCardVerifyInputs
            pure $ do
                measured <- performance
                card <- divergence
                let q1aST = performanceQ1aTerminalPlayoutsST measured
                    q1aMT8 = performanceQ1aTerminalPlayoutsMT8 measured
                    q1bST = performanceQ1bSearchItersST measured
                    q1bMT8 = performanceQ1bSearchItersMT8 measured
                    q2ST = performanceQ2SelfplayGamesST measured
                    q2MT8 = performanceQ2SelfplayGamesMT8 measured
                    ratios = map reportTimeRatio [q1aST, q1aMT8, q1bST, q1bMT8, q2ST, q2MT8]
                Right
                    card
                        { reportQ1aTerminalPlayoutsST = q1aST
                        , reportQ1aTerminalPlayoutsMT8 = q1aMT8
                        , reportQ1bSearchItersST = q1bST
                        , reportQ1bSearchItersMT8 = q1bMT8
                        , reportQ2SelfplayGamesST = q2ST
                        , reportQ2SelfplayGamesMT8 = q2MT8
                        , reportQ5HaskellSearchItersScaling =
                            scalingFrom
                                ReportSearchItersPerSecond
                                (reportHaskellRate q1bST)
                                (reportHaskellRate q1bMT8)
                        , reportQ5CppImperativeSearchItersScaling =
                            scalingFrom
                                ReportSearchItersPerSecond
                                (reportCppRate q1bST)
                                (reportCppRate q1bMT8)
                        , reportQ5HaskellSelfplayGamesScaling =
                            scalingFrom
                                ReportGamesPerSecond
                                (reportHaskellRate q2ST)
                                (reportHaskellRate q2MT8)
                        , reportQ5CppImperativeSelfplayGamesScaling =
                            scalingFrom
                                ReportGamesPerSecond
                                (reportCppRate q2ST)
                                (reportCppRate q2MT8)
                        , reportRawPerformanceRows = performanceRawRows measured
                        , reportVerdict = verdictFromRatios ratios
                        }

buildMeasuredReportCardWith :: [Backend] -> RunInputs -> IO (Either AppError ReportCard)
buildMeasuredReportCardWith backends inputs = do
    ghcVersion <- currentGhcVersion
    result <- verifyRunDetailed False Selfplay backends inputs
    pure $
        case (ghcVersion, result) of
            (Left err, _) -> Left err
            (_, Left err) -> Left err
            (Right version, Right verifyResult) ->
                Right
                    defaultReportCard
                        { reportDivergenceRows =
                            divergenceRowsFromTranscripts
                                (map batchTranscript (verifyBatches verifyResult))
                        , reportHost = hostArch
                        , reportGhc = version
                        }

currentGhcVersion :: IO (Either AppError String)
currentGhcVersion = do
    result <- capture (Subprocess "ghc" ["--numeric-version"] Nothing Nothing)
    pure $
        case result of
            Left err -> Left err
            Right output -> Right (firstLine (processStdout output))
  where
    firstLine value =
        case lines value of
            [] -> ""
            line : _ -> line

buildReportPerformance
    :: IO Word64
    -> IO (Either AppError ReportPerformance)
buildReportPerformance clock = do
    q1aST <-
        measurePrimitiveRates
            clock
            TerminalPlayouts
            SingleThreaded
    q1aMT8 <-
        measurePrimitiveRates
            clock
            TerminalPlayouts
            (MultiThreaded 8)
    q1bST <-
        measurePrimitiveRates
            clock
            SearchIters
            SingleThreaded
    q1bMT8 <-
        measurePrimitiveRates
            clock
            SearchIters
            (MultiThreaded 8)
    q2ST <-
        measureSelfplayRates
            clock
            SingleThreaded
    q2MT8 <-
        measureSelfplayRates
            clock
            (MultiThreaded 8)
    pure $ do
        q1aSTRates <- q1aST
        q1aMT8Rates <- q1aMT8
        q1bSTRates <- q1bST
        q1bMT8Rates <- q1bMT8
        q2STRates <- q2ST
        q2MT8Rates <- q2MT8
        ReportPerformance
            <$> comparisonFromRates ReportPlayoutsPerSecond q1aSTRates
            <*> comparisonFromRates ReportPlayoutsPerSecond q1aMT8Rates
            <*> comparisonFromRates ReportSearchItersPerSecond q1bSTRates
            <*> comparisonFromRates ReportSearchItersPerSecond q1bMT8Rates
            <*> comparisonFromRates ReportGamesPerSecond q2STRates
            <*> comparisonFromRates ReportGamesPerSecond q2MT8Rates
            <*> pure
                ( rawPerformanceRowsFrom
                    q1aSTRates
                    q1aMT8Rates
                    q1bSTRates
                    q1bMT8Rates
                    q2STRates
                    q2MT8Rates
                )

buildParityAnchor
    :: IO Word64
    -> Backend
    -> Backend
    -> IO (Either AppError ParityAnchorResult)
buildParityAnchor clock baseline candidate = do
    q1ST <-
        measureAnchorRow clock "Q1" Rollouts SingleThreaded reportCardRolloutGames reportCardBenchSims
    q1MT8 <-
        measureAnchorRow clock "Q1" Rollouts (MultiThreaded 8) reportCardRolloutGames reportCardBenchSims
    q2ST <-
        measureAnchorRow clock "Q2" Selfplay SingleThreaded reportCardSelfplayGames reportCardBenchSims
    q2MT8 <-
        measureAnchorRow clock "Q2" Selfplay (MultiThreaded 8) reportCardSelfplayGames reportCardBenchSims
    pure $
        ParityAnchorResult baseline candidate
            <$> sequence [q1ST, q1MT8, q2ST, q2MT8]
  where
    measureAnchorRow clockSource question workload threading games sims = do
        baselineRate <- measureBackend clockSource (inputs workload threading games sims) baseline
        candidateRate <- measureBackend clockSource (inputs workload threading games sims) candidate
        pure $ do
            baselineGamesPerSecond <- baselineRate
            candidateGamesPerSecond <- candidateRate
            Right
                ParityAnchorRow
                    { anchorQuestion = question
                    , anchorWorkload = workload
                    , anchorThreading = threading
                    , anchorGames = games
                    , anchorSims = sims
                    , anchorBaselineGamesPerSecond = baselineGamesPerSecond
                    , anchorCandidateGamesPerSecond = candidateGamesPerSecond
                    , anchorTimeRatio = safeRatio baselineGamesPerSecond candidateGamesPerSecond
                    }
    inputs workload threading games sims =
        defaultRunInputs
            { inputWorkload = workload
            , inputRng = NativeRng
            , inputThreading = threading
            , inputGames = games
            , inputSeed = 42
            , inputMaxPlies = 200
            , inputSims = FixedSims sims
            }

measureBackend :: IO Word64 -> RunInputs -> Backend -> IO (Either AppError Double)
measureBackend clock inputs backend = do
    start <- clock
    result <- runBatchNoWriteDispatch inputs{inputBackend = backend, inputCacheDir = Nothing}
    end <- clock
    pure $
        case result of
            Left message -> Left (IOErrorText message)
            Right _ ->
                let elapsedNanos = max 1 (fromIntegral end - fromIntegral start :: Integer)
                 in Right
                        ( fromIntegral (inputGames inputs)
                            * 1000000000.0
                            / fromIntegral elapsedNanos
                        )

measurePrimitiveRates
    :: IO Word64
    -> BenchPrimitive
    -> Threading
    -> IO (Either AppError [(Backend, Double)])
measurePrimitiveRates clock primitive threading =
    sequenceRateResults <$> mapM measurePrimitive allBackends
  where
    options =
        BenchPrimitiveOptions
            { benchPrimitiveRng = NativeRng
            , benchPrimitiveThreading = threading
            , benchPrimitiveCount = reportCardPrimitiveCount
            , benchPrimitiveSeed = 42
            , benchPrimitiveMaxPlies = reportCardPrimitiveMaxPlies
            }
    measurePrimitive backend = do
        result <- measurePrimitiveBackendRate clock primitive options backend
        pure (backend, either (Left . IOErrorText) Right result)

measureSelfplayRates
    :: IO Word64
    -> Threading
    -> IO (Either AppError [(Backend, Double)])
measureSelfplayRates clock threading =
    sequenceRateResults <$> mapM measureSelfplay allBackends
  where
    inputs =
        defaultRunInputs
            { inputWorkload = Selfplay
            , inputRng = NativeRng
            , inputThreading = threading
            , inputGames = reportCardSelfplayGames
            , inputSeed = 42
            , inputMaxPlies = 200
            , inputSims = FixedSims reportCardBenchSims
            }
    measureSelfplay backend = do
        result <- measureBackend clock inputs backend
        pure (backend, result)

sequenceRateResults :: [(Backend, Either AppError Double)] -> Either AppError [(Backend, Double)]
sequenceRateResults [] = Right []
sequenceRateResults ((_, Left err) : _) = Left err
sequenceRateResults ((backend, Right rate) : rest) =
    ((backend, rate) :) <$> sequenceRateResults rest

comparisonFromRates :: ReportRateUnit -> [(Backend, Double)] -> Either AppError ReportRateComparison
comparisonFromRates unit rates = do
    cppRate <- lookupRate CppImperative rates
    haskellRate <- lookupRate Haskell rates
    Right
        ReportRateComparison
            { reportComparisonMeasured = True
            , reportComparisonUnit = unit
            , reportTimeRatio = safeRatio cppRate haskellRate
            , reportHaskellRate = haskellRate
            , reportCppRate = cppRate
            }

rawPerformanceRowsFrom
    :: [(Backend, Double)]
    -> [(Backend, Double)]
    -> [(Backend, Double)]
    -> [(Backend, Double)]
    -> [(Backend, Double)]
    -> [(Backend, Double)]
    -> [ReportRawPerformanceRow]
rawPerformanceRowsFrom q1aST q1aMT8 q1bST q1bMT8 q2ST q2MT8 =
    [ ReportRawPerformanceRow
        { reportRawBackend = backend
        , reportRawQ1aTerminalPlayoutsST = lookup backend q1aST
        , reportRawQ1aTerminalPlayoutsMT8 = lookup backend q1aMT8
        , reportRawQ1bSearchItersST = lookup backend q1bST
        , reportRawQ1bSearchItersMT8 = lookup backend q1bMT8
        , reportRawQ2SelfplayGamesST = lookup backend q2ST
        , reportRawQ2SelfplayGamesMT8 = lookup backend q2MT8
        }
    | backend <- allBackends
    ]

lookupRate :: Backend -> [(Backend, Double)] -> Either AppError Double
lookupRate backend rates =
    case lookup backend rates of
        Just rate -> Right rate
        Nothing -> Left (IOErrorText ("missing report-card rate for " <> backendIdentifier backend))

scalingFrom :: ReportRateUnit -> Double -> Double -> ReportScaling
scalingFrom unit singleRate multiRate =
    ReportScaling
        { reportScalingMeasured = True
        , reportScalingUnit = unit
        , reportScalingRatio = safeRatio multiRate singleRate
        , reportSingleRate = singleRate
        , reportMultiRate = multiRate
        }

safeRatio :: Double -> Double -> Double
safeRatio numerator denominator =
    numerator / max denominator 1.0e-9

verdictFromRatios :: [Double] -> Verdict
verdictFromRatios ratios =
    let worst = maximum (1.0 : ratios)
        shortfall = worst - 1.0
     in if shortfall <= reportCardParityTolerance
            then WithinTolerance
            else Shortfall shortfall

requireReportCardArtifacts :: IO (Either AppError ())
requireReportCardArtifacts =
    go [cppLegacyLibraryPath, cppImperativeLibraryPath, cppFunctionalLibraryPath, rustLibraryPath]
  where
    go [] = pure (Right ())
    go (path : rest) = do
        present <- doesFileExist path
        if present
            then go rest
            else
                pure
                    ( Left
                        ( IOErrorText
                            ( "report-card requires canonical backend artefact "
                                <> path
                                <> "; rebuild the Docker image so Dockerfile-owned backend artefacts are present"
                            )
                        )
                    )

reportCardRolloutGames :: Int
reportCardRolloutGames = 1000

reportCardPrimitiveCount :: Int
reportCardPrimitiveCount = 20000

reportCardPrimitiveMaxPlies :: Word16
reportCardPrimitiveMaxPlies = 60

reportCardSelfplayGames :: Int
reportCardSelfplayGames = 4

reportCardBenchSims :: Int
reportCardBenchSims = 500

reportCardVerifyGames :: Int
reportCardVerifyGames = 4

reportCardVerifySims :: Int
reportCardVerifySims = 500

reportCardLegacyParityGames :: Int
reportCardLegacyParityGames = 2

reportCardLegacyParitySims :: Int
reportCardLegacyParitySims = 4

parityAnchorWithinTolerance :: ParityAnchorResult -> Bool
parityAnchorWithinTolerance result =
    all ((<= 1.0 + reportCardParityTolerance) . anchorTimeRatio) (anchorRows result)

renderParityAnchor :: ParityAnchorResult -> String
renderParityAnchor result =
    unlines $
        [ "parity anchor: "
            <> backendIdentifier (anchorBaseline result)
            <> " "
            <> backendRoman (anchorBaseline result)
            <> " -> "
            <> backendIdentifier (anchorCandidate result)
            <> " "
            <> backendRoman (anchorCandidate result)
        , "question  workload  threading  baseline games/s  candidate games/s  ratio"
        ]
            <> map renderParityAnchorRow (anchorRows result)
            <> [ "Verdict: "
                    <> if parityAnchorWithinTolerance result
                        then "Within tolerance"
                        else "Shortfall " <> fixed4 (parityAnchorShortfall result)
               ]

renderParityAnchorRow :: ParityAnchorRow -> String
renderParityAnchorRow row =
    anchorQuestion row
        <> "  "
        <> workloadName (anchorWorkload row)
        <> "  "
        <> threadingName (anchorThreading row)
        <> "  "
        <> fixed4 (anchorBaselineGamesPerSecond row)
        <> "  "
        <> fixed4 (anchorCandidateGamesPerSecond row)
        <> "  "
        <> fixed4 (anchorTimeRatio row)

renderParityAnchorJson :: ParityAnchorResult -> String
renderParityAnchorJson result =
    "{"
        <> "\"schema\":\"mcts-parity-anchor-v1\""
        <> ",\"baseline\":\""
        <> backendIdentifier (anchorBaseline result)
        <> "\""
        <> ",\"baseline_roman\":\""
        <> backendRoman (anchorBaseline result)
        <> "\""
        <> ",\"candidate\":\""
        <> backendIdentifier (anchorCandidate result)
        <> "\""
        <> ",\"candidate_roman\":\""
        <> backendRoman (anchorCandidate result)
        <> "\""
        <> ",\"seed\":42"
        <> ",\"max_plies\":200"
        <> ",\"tolerance\":"
        <> fixed4 reportCardParityTolerance
        <> ",\"within_tolerance\":"
        <> renderBool (parityAnchorWithinTolerance result)
        <> ",\"shortfall\":"
        <> fixed4 (parityAnchorShortfall result)
        <> ",\"rows\":["
        <> joinWith "," (map renderParityAnchorRowJson (anchorRows result))
        <> "]}"

renderParityAnchorRowJson :: ParityAnchorRow -> String
renderParityAnchorRowJson row =
    "{"
        <> "\"question\":\""
        <> anchorQuestion row
        <> "\""
        <> ",\"workload\":\""
        <> workloadName (anchorWorkload row)
        <> "\""
        <> ",\"threading\":\""
        <> threadingName (anchorThreading row)
        <> "\""
        <> ",\"games\":"
        <> show (anchorGames row)
        <> ",\"sims\":"
        <> show (anchorSims row)
        <> ",\"baseline_games_per_second\":"
        <> fixed4 (anchorBaselineGamesPerSecond row)
        <> ",\"candidate_games_per_second\":"
        <> fixed4 (anchorCandidateGamesPerSecond row)
        <> ",\"time_ratio\":"
        <> fixed4 (anchorTimeRatio row)
        <> "}"

parityAnchorShortfall :: ParityAnchorResult -> Double
parityAnchorShortfall result =
    max 0.0 (maximum (1.0 : map anchorTimeRatio (anchorRows result)) - 1.0)

fixed4 :: Double -> String
fixed4 = printf "%.4f"

renderBool :: Bool -> String
renderBool True = "true"
renderBool False = "false"

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith separator (x : xs) = x <> separator <> joinWith separator xs

reportCardBackends :: [Backend]
reportCardBackends =
    [ CppImperative
    , CppFunctional
    , Rust
    , Haskell
    ]

reportCardVerifyInputs :: RunInputs
reportCardVerifyInputs =
    defaultRunInputs
        { inputBackend = Haskell
        , inputWorkload = Selfplay
        , inputRng = CppRng
        , inputThreading = SingleThreaded
        , inputGames = reportCardVerifyGames
        , inputSeed = 42
        , inputMaxPlies = 200
        , inputSims = FixedSims reportCardVerifySims
        }
