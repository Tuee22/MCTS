module MCTS.CLI.Verify
    ( runVerifyCommand
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (VerifyCommand (..))
import MCTS.CLI.Output
    ( OutputFormat (..)
    , OutputOptions (..)
    , errLine
    , outputLine
    , renderErrorString
    )
import qualified MCTS.Env as Env
import MCTS.Types
import MCTS.Verify
import System.Exit (ExitCode (..))

runVerifyCommand :: VerifyCommand -> Env.App ExitCode
runVerifyCommand command = do
    env <- Env.askEnv
    runWithOutput (Env.envOutputOptions env) command

runWithOutput :: OutputOptions -> VerifyCommand -> Env.App ExitCode
runWithOutput output command =
    case command of
        VerifyRollouts allowStale backends inputs -> run "verify rollouts" (verifyRunDetailed allowStale Rollouts backends inputs)
        VerifySelfplay allowStale backends inputs -> run "verify selfplay" (verifyRunDetailed allowStale Selfplay backends inputs)
        VerifyLegacyParity workload allowStale backends inputs ->
            run
                ("verify legacy-parity " <> workloadName workload)
                (legacyParityRunDetailed allowStale workload backends inputs)
  where
    run label action = do
        result <- liftIO action
        case result of
            Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
            Right verifyResult -> do
                liftIO (mapM_ (errLine . renderErrorString output) (verifyWarnings verifyResult))
                let batches = verifyBatches verifyResult
                liftIO $
                    outputLine $
                        case outputFormat output of
                            JsonFormat ->
                                "{\"status\":\"PASS\",\"cohort\":"
                                    <> show (length batches)
                                    <> ",\"warnings\":"
                                    <> show (length (verifyWarnings verifyResult))
                                    <> ",\"label\":\""
                                    <> label
                                    <> "\"}"
                            _ ->
                                label
                                    <> " PASS ("
                                    <> show (length batches)
                                    <> " backends agree on visit counts)"
                pure ExitSuccess
