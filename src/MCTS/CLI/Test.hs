module MCTS.CLI.Test
    ( buildMeasuredReportCardWith
    , runTestCommand
    , testAllPlan
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Version (showVersion)
import Data.Word (Word64)
import MCTS.CLI.Bench (monotonicNanos)
import MCTS.CLI.Command (TestCommand (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderErrorString)
import MCTS.Driver (BatchResult (..), RunInputs (..), defaultRunInputs)
import MCTS.Driver.Dispatch (cppLegacyLibraryPath, runBatchNoWriteDispatch)
import qualified MCTS.Env as Env
import MCTS.Error (AppError (..))
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath)
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
            , mctsStep ["build", "cpp-legacy"]
            , mctsStep ["build", "cpp-imperative"]
            , mctsStep ["build", "cpp-functional"]
            , mctsStep ["build", "rust"]
            , Subprocess "cabal" ["test", "mcts-haskell-style"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-unit"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-integration"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-cross-backend"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-legacy-parity"] Nothing Nothing
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
                , show reportCardLegacyGames
                , "--seed"
                , "42"
                , "--sims"
                , show reportCardLegacySims
                ]
            ]
        }

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
    q1ST <- measureComparison clock Rollouts SingleThreaded reportCardRolloutGames reportCardBenchSims
    q1MT8 <-
        measureComparison clock Rollouts (MultiThreaded 8) reportCardRolloutGames reportCardBenchSims
    q2ST <- measureComparison clock Selfplay SingleThreaded reportCardSelfplayGames reportCardBenchSims
    q2MT8 <-
        measureComparison clock Selfplay (MultiThreaded 8) reportCardSelfplayGames reportCardBenchSims
    pure $ (,,,) <$> q1ST <*> q1MT8 <*> q2ST <*> q2MT8

measureComparison
    :: IO Word64
    -> Workload
    -> Threading
    -> Int
    -> Int
    -> IO (Either AppError ReportRateComparison)
measureComparison clock workload threading games sims = do
    cpp <- measureBackend clock baseInputs CppImperative
    haskell <- measureBackend clock baseInputs Haskell
    pure $ do
        cppRate <- cpp
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
    go
        [ cppLegacyLibraryPath
        , cppImperativeLibraryPath
        , cppFunctionalLibraryPath
        , rustLibraryPath
        ]
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

reportCardLegacyGames :: Int
reportCardLegacyGames = 2

reportCardLegacySims :: Int
reportCardLegacySims = 10000

haskellParityTolerance :: Double
haskellParityTolerance = 0.05

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
