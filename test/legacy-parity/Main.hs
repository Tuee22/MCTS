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
            , testCase "full five-backend rollout cohort" fullRolloutCohortCheck
            , testCase "cohort constraints" cohortConstraintsCheck
            ]

-- The legacy-parity cohort is all five backends under the legacy envelope:
-- `max_plies = MAX_ROLLOUT_ITERS = 10000`, `--rng cpp`, single-threaded,
-- fixture seed `S_LP = 42`. Q6 owns byte-for-byte legacy visit parity and Q3
-- owns visit-count agreement across the steelman backends; this stanza checks
-- that the full five-backend legacy-envelope liveness path runs without
-- overflow or envelope errors at a low budget.
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
        Right detailed -> length (verifyBatches detailed) @?= length allBackends
        Left err -> assertFailure ("legacy parity failed: " <> show err)

fullRolloutCohortCheck :: IO ()
fullRolloutCohortCheck = do
    let inputs =
            defaultRunInputs
                { inputGames = 1
                , inputSeed = 42
                , inputSims = FixedSims 12
                , inputMaxPlies = 50
                }
    result <- legacyParityRunDetailed False Rollouts allBackends inputs
    case result of
        Right detailed -> length (verifyBatches detailed) @?= length allBackends
        Left err -> assertFailure ("legacy parity rollouts failed: " <> show err)

cohortConstraintsCheck :: IO ()
cohortConstraintsCheck = do
    let inputs = defaultRunInputs{inputGames = 1, inputSeed = 42, inputSims = FixedSims 4, inputMaxPlies = 20}
    -- Legacy parity requires backend (i): a cohort without cpp-legacy must
    -- be rejected.
    rejectsMissingLegacy <- legacyParityRun Selfplay [CppImperative, Haskell] inputs
    case rejectsMissingLegacy of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected VerifyCohortTooSmall when cpp-legacy missing, got " <> show other)
