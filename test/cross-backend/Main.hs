module Main where

import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Types
import MCTS.Verify

-- | Phase 7 Sprint 7.2 declares the four-backend `(ii)..(v)` round-robin under
-- `--rng cpp` as the canonical cross-backend cohort. The cpp-legacy backend
-- must be rejected at the verify boundary; the cohort minimum is two
-- backends.
main :: IO ()
main = do
    rolloutsCheck
    cohortConstraintsCheck
    putStrLn "mcts-cross-backend PASS"

rolloutsCheck :: IO ()
rolloutsCheck = do
    let inputs =
            defaultRunInputs
                { inputGames = 2
                , inputSeed = 42
                , inputSims = FixedSims 16
                , inputMaxPlies = 40
                }
    -- The full four-backend (ii)..(v) cohort under the (Sprint 7.2 doctrine)
    -- `--rng cpp` and `SingleThreaded` settings.
    detailed <-
        verifyRunDetailed
            False
            Rollouts
            [CppImperative, CppFunctional, Rust, Haskell]
            inputs{inputThreading = SingleThreaded}
    case detailed of
        Left err -> error ("cross-backend verify failed: " <> show err)
        Right result ->
            if length (verifyBatches result) /= 4
                then error "cross-backend verify did not produce 4 batches"
                else pure ()

cohortConstraintsCheck :: IO ()
cohortConstraintsCheck = do
    let inputs = defaultRunInputs{inputGames = 1, inputSeed = 42, inputSims = FixedSims 4, inputMaxPlies = 20}
    -- cpp-legacy is excluded from `mcts verify`; the runner must reject it.
    rejectsLegacy <- verifyRun Rollouts [CppLegacy, CppImperative, Haskell] inputs
    case rejectsLegacy of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> error ("expected VerifyCohortTooSmall rejecting cpp-legacy, got " <> show other)
    -- A single-backend cohort must fail the minimum-cohort check.
    rejectsSingle <- verifyRun Rollouts [Haskell] inputs
    case rejectsSingle of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> error ("expected VerifyCohortTooSmall on single-backend cohort, got " <> show other)
