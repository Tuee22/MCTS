module MCTS.CLI.Test
    ( runTestCommand
    , testAllPlan
    ) where

import MCTS.CLI.Command (TestCommand (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), outputLine, renderError)
import MCTS.Plan
import MCTS.ReportCard
import MCTS.Subprocess

runTestCommand :: OutputOptions -> TestCommand -> IO Int
runTestCommand output command =
    case command of
        TestAll opts -> do
            let plan = testAllPlan
                rendered = renderPlan plan
            writePlanFile (planFile opts) rendered
            if planDryRun opts
                then outputLine rendered >> pure 0
                else do
                    code <- runStanzaPlan plan
                    if code == 0
                        then
                            outputLine
                                ( if outputFormat output == JsonFormat
                                    then renderReportCardJson defaultReportCard
                                    else renderReportCard defaultReportCard
                                )
                                >> pure 0
                        else pure code
        TestStanza stanza -> runStanzaPlan (Plan ("test " <> stanza) [Subprocess "cabal" ["test", stanza] Nothing Nothing])

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
            , mctsStep ["bench", "rollouts", "--backend", "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell", "--threading", "single", "--rng", "native", "--games", "100000", "--seed", "42"]
            , mctsStep ["bench", "rollouts", "--backend", "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell", "--threading", "multi", "--workers", "8", "--rng", "native", "--games", "100000", "--seed", "42"]
            , mctsStep ["bench", "selfplay", "--backend", "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell", "--threading", "single", "--rng", "native", "--games", "1000", "--seed", "42", "--sims", "10000"]
            , mctsStep ["bench", "selfplay", "--backend", "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell", "--threading", "multi", "--workers", "8", "--rng", "native", "--games", "1000", "--seed", "42", "--sims", "10000"]
            , mctsStep ["verify", "rollouts", "--backend", "cpp-imperative,cpp-functional,rust,haskell", "--threading", "single", "--games", "50", "--seed", "42", "--max-plies", "200"]
            , mctsStep ["verify", "selfplay", "--backend", "cpp-imperative,cpp-functional,rust,haskell", "--threading", "single", "--games", "50", "--seed", "42", "--max-plies", "200", "--sims", "10000"]
            , mctsStep ["verify", "legacy-parity", "selfplay", "--backend", "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell", "--games", "10", "--seed", "42", "--sims", "10000"]
            ]
        }

mctsStep :: [String] -> Subprocess
mctsStep args = Subprocess "cabal" (["exec", "mcts", "--"] <> args) Nothing Nothing

runStanzaPlan :: Plan Subprocess -> IO Int
runStanzaPlan plan = go (planSteps plan)
  where
    go [] = pure 0
    go (step : rest) = do
        result <- runStreaming step
        case result of
            Left err -> outputLine (renderError err) >> pure 1
            Right _ -> go rest
