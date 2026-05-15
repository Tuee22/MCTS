module Main where

import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Types
import MCTS.Verify
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

main :: IO ()
main =
    defaultMain $
        testGroup
            "mcts-legacy-parity"
            [ testCase "full five-backend cohort" fullCohortCheck
            , testCase "cohort constraints" cohortConstraintsCheck
            ]

-- The legacy-parity cohort is all five backends under the legacy envelope:
-- `max_plies = MAX_ROLLOUT_ITERS = 10000`, `--rng cpp`, single-threaded,
-- fixture seed `S_LP = 42`. The Sprint 7.2 deliverable pins these knobs.
fullCohortCheck :: IO ()
fullCohortCheck = do
    let inputs =
            defaultRunInputs
                { inputGames = 1
                , inputSeed = 42
                , inputSims = FixedSims 12
                , inputMaxPlies = 50
                }
    result <- legacyParityRunDetailed False Selfplay allBackends inputs
    case result of
        Left err -> assertFailure ("legacy parity failed: " <> show err)
        Right detailed ->
            length (verifyBatches detailed) @?= length allBackends

cohortConstraintsCheck :: IO ()
cohortConstraintsCheck = do
    let inputs = defaultRunInputs{inputGames = 1, inputSeed = 42, inputSims = FixedSims 4, inputMaxPlies = 20}
    -- Legacy parity requires backend (i): a cohort without cpp-legacy must
    -- be rejected.
    rejectsMissingLegacy <- legacyParityRun Selfplay [CppImperative, Haskell] inputs
    case rejectsMissingLegacy of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected VerifyCohortTooSmall when cpp-legacy missing, got " <> show other)
