module MCTS.CLI.Build
    ( runBuild
    , buildBackendPlan
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (BuildCommand (..))
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForBuild)
import MCTS.Subprocess
import System.Exit (ExitCode (..))

runBuild :: BuildCommand -> Env.App ExitCode
runBuild command = do
    env <- Env.askEnv
    let (name, opts) =
            case command of
                BuildCppLegacy planOptions -> ("cpp-legacy", planOptions)
                BuildCppImperative planOptions -> ("cpp-imperative", planOptions)
                BuildCppFunctional planOptions -> ("cpp-functional", planOptions)
                BuildRust planOptions -> ("rust", planOptions)
        plan = buildBackendPlan name
        rendered = renderPlan plan
    liftIO (writePlanFile (planFile opts) rendered)
    if planDryRun opts
        then liftIO (outputLine rendered) >> pure ExitSuccess
        else do
            prerequisites <- liftIO (checkPrerequisites (prerequisitesForBuild name))
            case prerequisites of
                Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)
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
runBackendPlan :: Plan Subprocess -> Env.App ExitCode
runBackendPlan = applySubprocessWithEnv
