module MCTS.CLI.Build
    ( runBuild
    , buildPlan
    ) where

import MCTS.CLI.Command (BuildCommand (..))
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.Plan
import MCTS.Subprocess

runBuild :: BuildCommand -> IO Int
runBuild command = do
    let (name, opts) =
            case command of
                BuildCppLegacy planOptions -> ("cpp-legacy", planOptions)
                BuildCppImperative planOptions -> ("cpp-imperative", planOptions)
                BuildCppFunctional planOptions -> ("cpp-functional", planOptions)
                BuildRust planOptions -> ("rust", planOptions)
        plan = buildPlan name
        rendered = renderPlan plan
    writePlanFile (planFile opts) rendered
    if planDryRun opts
        then outputLine rendered >> pure 0
        else applyPlan plan

buildPlan :: String -> Plan Subprocess
buildPlan backend =
    Plan
        { planName = "build " <> backend
        , planSteps =
            case backend of
                "rust" ->
                    [ Subprocess "cargo" ["build", "--release"] Nothing (Just "rust")
                    ]
                _ ->
                    [ Subprocess "make" ["-C", backend, "smoke"] Nothing Nothing
                    ]
        }

applyPlan :: Plan Subprocess -> IO Int
applyPlan plan = go (planSteps plan)
  where
    go [] = pure 0
    go (step : rest) = do
        result <- runStreaming step
        case result of
            Left err -> outputLine (renderError err) >> pure 1
            Right _ -> go rest
