{-# LANGUAGE OverloadedStrings #-}

module MCTS.CLI.Test
    ( buildMeasuredReportCardWith
    , runTestCommand
    , testAllPlan
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.List (find)
import Data.Version (showVersion)
import Data.Word (Word64)
import MCTS.CLI.Bench (monotonicNanos)
import MCTS.CLI.Command (RetirementAnchorOptions (..), TestCommand (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderErrorString)
import MCTS.Driver (BatchResult (..), RunInputs (..), defaultRunInputs)
import MCTS.Driver.Dispatch (runBatchNoWriteDispatch)
import qualified MCTS.Env as Env
import MCTS.Error (AppError (..))
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
import System.Info (compilerVersion)
import Text.Printf (printf)

data RetirementAnchorResult = RetirementAnchorResult
    { anchorRetiring :: !Backend
    , anchorSuccessor :: !Backend
    , anchorRows :: ![RetirementAnchorRow]
    }
    deriving (Eq, Show)

data RetirementAnchorRow = RetirementAnchorRow
    { anchorQuestion :: !String
    , anchorWorkload :: !Workload
    , anchorThreading :: !Threading
    , anchorGames :: !Int
    , anchorSims :: !Int
    , anchorRetiringGamesPerSecond :: !Double
    , anchorSuccessorGamesPerSecond :: !Double
    , anchorTimeRatio :: !Double
    }
    deriving (Eq, Show)

data FrozenRetirementAnchor = FrozenRetirementAnchor
    { frozenAnchorRows :: ![FrozenRetirementAnchorRow]
    }
    deriving (Eq, Show)

data FrozenRetirementAnchorRow = FrozenRetirementAnchorRow
    { frozenAnchorWorkload :: !Workload
    , frozenAnchorThreading :: !Threading
    , frozenAnchorRetiringGamesPerSecond :: !Double
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
                                                >> pure ExitSuccess
                                else pure code
        TestRetirementAnchor opts -> do
            let plan = retirementAnchorPlan opts
                rendered = renderPlan plan
            liftIO (writePlanFile (planFile (retirementAnchorPlanOptions opts)) rendered)
            if planDryRun (retirementAnchorPlanOptions opts)
                then liftIO (outputLine rendered) >> pure ExitSuccess
                else
                    if retirementAnchorRetiring opts == retirementAnchorSuccessor opts
                        then do
                            liftIO
                                ( outputLine
                                    ( renderErrorString
                                        output
                                        (ParseError "retirement-anchor requires distinct retiring and successor backends")
                                    )
                                )
                            pure (ExitFailure 1)
                        else do
                            code <- runStanzaPlan output plan
                            if code == ExitSuccess
                                then do
                                    anchor <-
                                        liftIO
                                            ( buildRetirementAnchor
                                                monotonicNanos
                                                (retirementAnchorRetiring opts)
                                                (retirementAnchorSuccessor opts)
                                            )
                                    case anchor of
                                        Left err ->
                                            liftIO (outputLine (renderErrorString output err))
                                                >> pure (ExitFailure 1)
                                        Right result -> do
                                            liftIO
                                                ( outputLine
                                                    ( if outputFormat output == JsonFormat
                                                        then renderRetirementAnchorJson result
                                                        else renderRetirementAnchor result
                                                    )
                                                )
                                            pure $
                                                if retirementAnchorWithinTolerance result
                                                    then ExitSuccess
                                                    else ExitFailure 1
                                else pure code
        TestStanza stanza -> do
            prerequisites <- liftIO (checkPrerequisites prerequisitesForTest)
            case prerequisites of
                Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
                Right () ->
                    runStanzaPlan
                        output
                        (Plan ("test " <> stanza) [Subprocess "cabal" ["test", stanza] Nothing Nothing])

testAllPlan :: Plan Subprocess
testAllPlan =
    Plan
        { planName = "test all"
        , planSteps =
            [ mctsStep ["lint", "files"]
            , mctsStep ["lint", "docs"]
            , Subprocess "cabal" ["build", "all"] Nothing Nothing
            , mctsStep ["build", "rust"]
            , Subprocess "cabal" ["test", "mcts-haskell-style"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-unit"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-integration"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-cross-backend"] Nothing Nothing
            , mctsStep
                [ "verify"
                , "rollouts"
                , "--backend"
                , "rust,haskell"
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
                , "rust,haskell"
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
            ]
        }

retirementAnchorPlan :: RetirementAnchorOptions -> Plan Subprocess
retirementAnchorPlan opts =
    Plan
        { planName =
            "test retirement-anchor "
                <> backendIdentifier (retirementAnchorRetiring opts)
                <> " "
                <> backendIdentifier (retirementAnchorSuccessor opts)
        , planSteps =
            Subprocess "cabal" ["build", "all"] Nothing Nothing
                : concatMap buildStep (uniqueBackends [retirementAnchorRetiring opts, retirementAnchorSuccessor opts])
        }
  where
    buildStep backend =
        case backend of
            CppLegacy -> []
            CppImperative -> []
            CppFunctional -> []
            Rust -> [mctsStep ["build", "rust"]]
            Haskell -> []

uniqueBackends :: [Backend] -> [Backend]
uniqueBackends = go []
  where
    go _ [] = []
    go seen (backend : rest)
        | backend `elem` seen = go seen rest
        | otherwise = backend : go (backend : seen) rest

mctsStep :: [String] -> Subprocess
mctsStep args = Subprocess "cabal" (["exec", "mcts", "--"] <> args) Nothing Nothing

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
                (q1ST, q1MT8, q2ST, q2MT8) <- performance
                card <- divergence
                let ratios = map reportTimeRatio [q1ST, q1MT8, q2ST, q2MT8]
                Right
                    card
                        { reportQ1RolloutsST = q1ST
                        , reportQ1RolloutsMT8 = q1MT8
                        , reportQ2SelfplayST = q2ST
                        , reportQ2SelfplayMT8 = q2MT8
                        , reportQ5HaskellScaling =
                            scalingFrom
                                (reportHaskellGamesPerSecond q2ST)
                                (reportHaskellGamesPerSecond q2MT8)
                        , reportQ5CppImperativeScaling =
                            scalingFrom
                                (reportCppGamesPerSecond q2ST)
                                (reportCppGamesPerSecond q2MT8)
                        , reportVerdict = verdictFromRatios ratios
                        }

buildMeasuredReportCardWith :: [Backend] -> RunInputs -> IO (Either AppError ReportCard)
buildMeasuredReportCardWith backends inputs = do
    result <- verifyRunDetailed False Selfplay backends inputs
    pure $
        case result of
            Left err -> Left err
            Right verifyResult ->
                Right
                    defaultReportCard
                        { reportDivergenceRows =
                            divergenceRowsFromTranscripts
                                (map batchTranscript (verifyBatches verifyResult))
                        , reportHost = hostArch
                        , reportGhc = showVersion compilerVersion
                        }

buildReportPerformance
    :: IO Word64
    -> IO
        ( Either
            AppError
            ( ReportRateComparison
            , ReportRateComparison
            , ReportRateComparison
            , ReportRateComparison
            )
        )
buildReportPerformance clock = do
    q1ST <-
        measureFrozenComparison
            clock
            frozenCppImperativeAnchor
            Rollouts
            SingleThreaded
            reportCardRolloutGames
            reportCardBenchSims
    q1MT8 <-
        measureFrozenComparison
            clock
            frozenCppImperativeAnchor
            Rollouts
            (MultiThreaded 8)
            reportCardRolloutGames
            reportCardBenchSims
    q2ST <-
        measureFrozenComparison
            clock
            frozenCppImperativeAnchor
            Selfplay
            SingleThreaded
            reportCardSelfplayGames
            reportCardBenchSims
    q2MT8 <-
        measureFrozenComparison
            clock
            frozenCppImperativeAnchor
            Selfplay
            (MultiThreaded 8)
            reportCardSelfplayGames
            reportCardBenchSims
    pure $ (,,,) <$> q1ST <*> q1MT8 <*> q2ST <*> q2MT8

buildRetirementAnchor
    :: IO Word64
    -> Backend
    -> Backend
    -> IO (Either AppError RetirementAnchorResult)
buildRetirementAnchor clock retiring successor = do
    q1ST <-
        measureAnchorRow clock "Q1" Rollouts SingleThreaded reportCardRolloutGames reportCardBenchSims
    q1MT8 <-
        measureAnchorRow clock "Q1" Rollouts (MultiThreaded 8) reportCardRolloutGames reportCardBenchSims
    q2ST <-
        measureAnchorRow clock "Q2" Selfplay SingleThreaded reportCardSelfplayGames reportCardBenchSims
    q2MT8 <-
        measureAnchorRow clock "Q2" Selfplay (MultiThreaded 8) reportCardSelfplayGames reportCardBenchSims
    pure $
        RetirementAnchorResult retiring successor
            <$> sequence [q1ST, q1MT8, q2ST, q2MT8]
  where
    measureAnchorRow clockSource question workload threading games sims = do
        retiringRate <- measureBackend clockSource (inputs workload threading games sims) retiring
        successorRate <- measureBackend clockSource (inputs workload threading games sims) successor
        pure $ do
            retiringGamesPerSecond <- retiringRate
            successorGamesPerSecond <- successorRate
            Right
                RetirementAnchorRow
                    { anchorQuestion = question
                    , anchorWorkload = workload
                    , anchorThreading = threading
                    , anchorGames = games
                    , anchorSims = sims
                    , anchorRetiringGamesPerSecond = retiringGamesPerSecond
                    , anchorSuccessorGamesPerSecond = successorGamesPerSecond
                    , anchorTimeRatio = safeRatio retiringGamesPerSecond successorGamesPerSecond
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

measureFrozenComparison
    :: IO Word64
    -> FrozenRetirementAnchor
    -> Workload
    -> Threading
    -> Int
    -> Int
    -> IO (Either AppError ReportRateComparison)
measureFrozenComparison clock frozen workload threading games sims = do
    haskell <- measureBackend clock baseInputs Haskell
    pure $ do
        cppRate <- retiredRate frozen workload threading
        haskellRate <- haskell
        Right
            ReportRateComparison
                { reportComparisonMeasured = True
                , reportTimeRatio = safeRatio cppRate haskellRate
                , reportHaskellGamesPerSecond = haskellRate
                , reportCppGamesPerSecond = cppRate
                }
  where
    baseInputs =
        defaultRunInputs
            { inputWorkload = workload
            , inputRng = NativeRng
            , inputThreading = threading
            , inputGames = games
            , inputSeed = 42
            , inputMaxPlies = 200
            , inputSims = FixedSims sims
            }

retiredRate :: FrozenRetirementAnchor -> Workload -> Threading -> Either AppError Double
retiredRate frozen workload threading =
    case find matches (frozenAnchorRows frozen) of
        Just row -> Right (frozenAnchorRetiringGamesPerSecond row)
        Nothing ->
            Left $
                IOErrorText
                    ( "retired backend throughput anchor missing row for "
                        <> workloadName workload
                        <> "/"
                        <> threadingName threading
                    )
  where
    matches row =
        frozenAnchorWorkload row == workload
            && frozenAnchorThreading row == threading

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

scalingFrom :: Double -> Double -> ReportScaling
scalingFrom singleRate multiRate =
    ReportScaling
        { reportScalingMeasured = True
        , reportScalingRatio = safeRatio multiRate singleRate
        , reportSingleGamesPerSecond = singleRate
        , reportMultiGamesPerSecond = multiRate
        }

safeRatio :: Double -> Double -> Double
safeRatio numerator denominator =
    numerator / max denominator 1.0e-9

verdictFromRatios :: [Double] -> Verdict
verdictFromRatios ratios =
    let worst = maximum (1.0 : ratios)
        shortfall = worst - 1.0
     in if shortfall <= haskellParityTolerance
            then WithinTolerance
            else Shortfall shortfall

requireReportCardArtifacts :: IO (Either AppError ())
requireReportCardArtifacts =
    go [rustLibraryPath]
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
                                <> "; run `mcts test all` so the build steps and measurements share one container"
                            )
                        )
                    )

reportCardRolloutGames :: Int
reportCardRolloutGames = 1000

reportCardSelfplayGames :: Int
reportCardSelfplayGames = 4

reportCardBenchSims :: Int
reportCardBenchSims = 500

reportCardVerifyGames :: Int
reportCardVerifyGames = 4

reportCardVerifySims :: Int
reportCardVerifySims = 500

frozenCppImperativeAnchor :: FrozenRetirementAnchor
frozenCppImperativeAnchor =
    FrozenRetirementAnchor
        [ FrozenRetirementAnchorRow Rollouts SingleThreaded 26.0287
        , FrozenRetirementAnchorRow Rollouts (MultiThreaded 8) 185.8295
        , FrozenRetirementAnchorRow Selfplay SingleThreaded 0.0211
        , FrozenRetirementAnchorRow Selfplay (MultiThreaded 8) 0.0779
        ]

haskellParityTolerance :: Double
haskellParityTolerance = 0.05

retirementAnchorWithinTolerance :: RetirementAnchorResult -> Bool
retirementAnchorWithinTolerance result =
    all ((<= 1.0 + haskellParityTolerance) . anchorTimeRatio) (anchorRows result)

renderRetirementAnchor :: RetirementAnchorResult -> String
renderRetirementAnchor result =
    unlines $
        [ "retirement anchor: "
            <> backendIdentifier (anchorRetiring result)
            <> " "
            <> backendRoman (anchorRetiring result)
            <> " -> "
            <> backendIdentifier (anchorSuccessor result)
            <> " "
            <> backendRoman (anchorSuccessor result)
        , "question  workload  threading  retiring games/s  successor games/s  ratio"
        ]
            <> map renderRetirementAnchorRow (anchorRows result)
            <> [ "Verdict: "
                    <> if retirementAnchorWithinTolerance result
                        then "Within tolerance"
                        else "Shortfall " <> fixed4 (retirementAnchorShortfall result)
               ]

renderRetirementAnchorRow :: RetirementAnchorRow -> String
renderRetirementAnchorRow row =
    anchorQuestion row
        <> "  "
        <> workloadName (anchorWorkload row)
        <> "  "
        <> threadingName (anchorThreading row)
        <> "  "
        <> fixed4 (anchorRetiringGamesPerSecond row)
        <> "  "
        <> fixed4 (anchorSuccessorGamesPerSecond row)
        <> "  "
        <> fixed4 (anchorTimeRatio row)

renderRetirementAnchorJson :: RetirementAnchorResult -> String
renderRetirementAnchorJson result =
    "{"
        <> "\"schema\":\"mcts-retirement-anchor-v1\""
        <> ",\"retiring\":\""
        <> backendIdentifier (anchorRetiring result)
        <> "\""
        <> ",\"retiring_roman\":\""
        <> backendRoman (anchorRetiring result)
        <> "\""
        <> ",\"successor\":\""
        <> backendIdentifier (anchorSuccessor result)
        <> "\""
        <> ",\"successor_roman\":\""
        <> backendRoman (anchorSuccessor result)
        <> "\""
        <> ",\"seed\":42"
        <> ",\"max_plies\":200"
        <> ",\"tolerance\":"
        <> fixed4 haskellParityTolerance
        <> ",\"within_tolerance\":"
        <> renderBool (retirementAnchorWithinTolerance result)
        <> ",\"shortfall\":"
        <> fixed4 (retirementAnchorShortfall result)
        <> ",\"rows\":["
        <> joinWith "," (map renderRetirementAnchorRowJson (anchorRows result))
        <> "]}"

renderRetirementAnchorRowJson :: RetirementAnchorRow -> String
renderRetirementAnchorRowJson row =
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
        <> ",\"retiring_games_per_second\":"
        <> fixed4 (anchorRetiringGamesPerSecond row)
        <> ",\"successor_games_per_second\":"
        <> fixed4 (anchorSuccessorGamesPerSecond row)
        <> ",\"time_ratio\":"
        <> fixed4 (anchorTimeRatio row)
        <> "}"

retirementAnchorShortfall :: RetirementAnchorResult -> Double
retirementAnchorShortfall result =
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
    [ Rust
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
