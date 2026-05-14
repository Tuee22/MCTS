module MCTS.Plan
    ( Plan (..)
    , PlanOptions (..)
    , renderPlan
    , renderPlanWith
    , writePlanFile
    , buildPlan
    , applyPlan
    , applySubprocessPlan
    , applyWithEnv
    , applySubprocessWithEnv
    ) where

import Control.Monad.IO.Class (liftIO)
import qualified MCTS.Env as Env
import MCTS.Error (AppError)
import MCTS.Subprocess (Subprocess, renderSubprocess, runStreaming)
import System.Exit (ExitCode (..))

data Plan a = Plan
    { planName :: !String
    , planSteps :: ![a]
    }
    deriving (Eq, Show)

data PlanOptions = PlanOptions
    { planDryRun :: !Bool
    , planFile :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

renderPlan :: Plan Subprocess -> String
renderPlan = renderPlanWith renderSubprocess

renderPlanWith :: (a -> String) -> Plan a -> String
renderPlanWith render plan =
    unlines $
        ("plan: " <> planName plan)
            : [show idx <> ". " <> render step | (idx, step) <- zip [(1 :: Int) ..] (planSteps plan)]

writePlanFile :: Maybe FilePath -> String -> IO ()
writePlanFile Nothing _ = pure ()
writePlanFile (Just path) rendered = writeFile path rendered

-- | Doctrine-shaped builder: turn typed inputs into either an error or a plan
-- without performing IO. Use this for state-mutating commands so the resulting
-- plan can be rendered for `--dry-run`, written via `--plan-file`, or executed
-- via `applyPlan`/`applySubprocessPlan`.
buildPlan
    :: String
    -> (input -> Either AppError [step])
    -> input
    -> Either AppError (Plan step)
buildPlan name fromInput input =
    case fromInput input of
        Left err -> Left err
        Right steps -> Right (Plan name steps)

-- | Apply a plan by running each step in IO; first failure short-circuits.
applyPlan
    :: (step -> IO (Either AppError ExitCode))
    -> Plan step
    -> IO ExitCode
applyPlan runStep plan = go (planSteps plan)
  where
    go [] = pure ExitSuccess
    go (step : rest) = do
        result <- runStep step
        case result of
            Left _ -> pure (ExitFailure 1)
            Right ExitSuccess -> go rest
            Right code -> pure code

-- | Apply a plan whose steps are `Subprocess` values through the typed
-- subprocess interpreter.
applySubprocessPlan :: Plan Subprocess -> IO ExitCode
applySubprocessPlan = applyPlan runStreaming

-- | Doctrine `apply :: Env -> Plan a -> IO ExitCode` shape per
-- [../HASKELL_CLI_TOOL.md → Plan / Apply](../../HASKELL_CLI_TOOL.md).
-- Threaded through `App` so command runners can use `askEnv` then call
-- `apply env plan`. The `Env` argument is reserved for future per-step
-- effects (logging, cache root resolution, prerequisite re-checks).
applyWithEnv
    :: (Env.Env -> step -> IO (Either AppError ExitCode))
    -> Plan step
    -> Env.App ExitCode
applyWithEnv runStep plan = do
    env <- Env.askEnv
    liftIO (applyPlan (runStep env) plan)

-- | Specialization of `applyWithEnv` to subprocess steps.
applySubprocessWithEnv :: Plan Subprocess -> Env.App ExitCode
applySubprocessWithEnv = applyWithEnv (\_env step -> runStreaming step)
