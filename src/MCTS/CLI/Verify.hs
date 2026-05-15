module MCTS.CLI.Verify
    ( runVerifyCommand
    ) where

import MCTS.CLI.Command (VerifyCommand (..))
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), errLine, outputLine, renderError)
import MCTS.Types
import MCTS.Verify

runVerifyCommand :: OutputOptions -> VerifyCommand -> IO Int
runVerifyCommand output command =
    case command of
        VerifyRollouts allowStale backends inputs -> run "verify rollouts" (verifyRunDetailed allowStale Rollouts backends inputs)
        VerifySelfplay allowStale backends inputs -> run "verify selfplay" (verifyRunDetailed allowStale Selfplay backends inputs)
        VerifyLegacyParity workload allowStale backends inputs ->
            run
                ("verify legacy-parity " <> workloadName workload)
                (legacyParityRunDetailed allowStale workload backends inputs)
  where
    run label action = do
        result <- action
        case result of
            Left err -> outputLine (renderError err) >> pure 1
            Right verifyResult -> do
                mapM_ (errLine . renderError) (verifyWarnings verifyResult)
                let batches = verifyBatches verifyResult
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
                pure 0
