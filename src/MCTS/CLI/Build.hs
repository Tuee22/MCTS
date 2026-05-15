module MCTS.CLI.Build
    ( runBuild
    , buildBackendPlan
    ) where

import MCTS.CLI.Command (BuildCommand (..))
import MCTS.CLI.Output (outputLine, renderError)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForBuild)
import MCTS.Subprocess
import System.Exit (ExitCode (..))

runBuild :: BuildCommand -> IO Int
runBuild command = do
    let (name, opts) =
            case command of
                BuildCppLegacy planOptions -> ("cpp-legacy", planOptions)
                BuildCppImperative planOptions -> ("cpp-imperative", planOptions)
                BuildCppFunctional planOptions -> ("cpp-functional", planOptions)
                BuildRust planOptions -> ("rust", planOptions)
        plan = buildBackendPlan name
        rendered = renderPlan plan
    writePlanFile (planFile opts) rendered
    if planDryRun opts
        then outputLine rendered >> pure 0
        else do
            prerequisites <- checkPrerequisites (prerequisitesForBuild name)
            case prerequisites of
                Left err -> outputLine (renderError err) >> pure 1
                Right () -> runBackendPlan plan

buildBackendPlan :: String -> Plan Subprocess
buildBackendPlan backend =
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

-- | Run a backend build plan through the doctrine `apply :: Env -> Plan
-- a -> IO ExitCode` shape. `Env.defaultEnv` is the production-default
-- environment; future runners can pass a custom env via `Env.runAppIO`.
runBackendPlan :: Plan Subprocess -> IO Int
runBackendPlan plan = do
    code <- Env.runAppIO Env.defaultEnv (applySubprocessWithEnv plan)
    case code of
        ExitSuccess -> pure 0
        ExitFailure n -> pure n
