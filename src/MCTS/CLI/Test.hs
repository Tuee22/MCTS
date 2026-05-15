module MCTS.CLI.Test
    ( runTestCommand
    , testAllPlan
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (TestCommand (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForTest)
import MCTS.ReportCard
import MCTS.Subprocess
import System.Exit (ExitCode (..))

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
                                then
                                    liftIO
                                        ( outputLine
                                            ( if outputFormat output == JsonFormat
                                                then renderReportCardJson defaultReportCard
                                                else renderReportCard defaultReportCard
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
            , Subprocess "cabal" ["test", "mcts-haskell-style"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-unit"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-integration"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-cross-backend"] Nothing Nothing
            , Subprocess "cabal" ["test", "mcts-legacy-parity"] Nothing Nothing
            , mctsStep
                [ "bench"
                , "rollouts"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--rng"
                , "native"
                , "--games"
                , "100000"
                , "--seed"
                , "42"
                ]
            , mctsStep
                [ "bench"
                , "rollouts"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "multi"
                , "--workers"
                , "8"
                , "--rng"
                , "native"
                , "--games"
                , "100000"
                , "--seed"
                , "42"
                ]
            , mctsStep
                [ "bench"
                , "selfplay"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--rng"
                , "native"
                , "--games"
                , "1000"
                , "--seed"
                , "42"
                , "--sims"
                , "10000"
                ]
            , mctsStep
                [ "bench"
                , "selfplay"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "multi"
                , "--workers"
                , "8"
                , "--rng"
                , "native"
                , "--games"
                , "1000"
                , "--seed"
                , "42"
                , "--sims"
                , "10000"
                ]
            , mctsStep
                [ "verify"
                , "rollouts"
                , "--backend"
                , "cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--games"
                , "50"
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
                , "50"
                , "--seed"
                , "42"
                , "--max-plies"
                , "200"
                , "--sims"
                , "10000"
                ]
            , mctsStep
                [ "verify"
                , "legacy-parity"
                , "selfplay"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--games"
                , "10"
                , "--seed"
                , "42"
                , "--sims"
                , "10000"
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
