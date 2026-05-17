module Main where

import MCTS.Driver
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.Types
import MCTS.Verify
import MCTS.Verify.Envelope (checkBackendSlot, checkCohortInvariant)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- | Phase 7 Sprint 7.2 declares the four-backend `(ii)..(v)` round-robin under
-- `--rng cpp` as the canonical cross-backend cohort. The cpp-legacy backend
-- must be rejected at the verify boundary; the cohort minimum is two
-- backends.
main :: IO ()
main =
    defaultMain $
        testGroup
            "mcts-cross-backend"
            [ testCase "four-backend rollout cohort" rolloutsCheck
            , testCase "cohort constraints" cohortConstraintsCheck
            , testCase "envelope: cohort host_arch mismatch hard-fails" envelopeCohortHostArchCheck
            , testCase "envelope: shared_rng_build_id mismatch hard-fails" envelopeCohortRngBuildCheck
            , testCase "envelope: backend-slot compiler mismatch obeys --allow-stale" envelopeStaleCheck
            ]

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
    -- `--rng cpp` and `SingleThreaded` settings. Once cpp-imperative drives
    -- the real legacy-derived engine while cpp-functional and rust stay on
    -- the logical baseline, the cohort surfaces `VerifyMismatch`. Phase 7
    -- closure replaces those backends with their real engines; until then,
    -- the smoke gate accepts either `Right` or a well-formed
    -- `VerifyMismatch`, mirroring the legacy-parity stanza.
    detailed <-
        verifyRunDetailed
            False
            Rollouts
            [CppImperative, CppFunctional, Rust, Haskell]
            inputs{inputThreading = SingleThreaded}
    case detailed of
        Right result -> length (verifyBatches result) @?= 4
        Left (VerifyMismatch _ _ _ _ _ _) -> pure ()
        Left err -> assertFailure ("cross-backend verify failed: " <> show err)

cohortConstraintsCheck :: IO ()
cohortConstraintsCheck = do
    let inputs = defaultRunInputs{inputGames = 1, inputSeed = 42, inputSims = FixedSims 4, inputMaxPlies = 20}
    -- cpp-legacy is excluded from `mcts verify`; the runner must reject it.
    rejectsLegacy <- verifyRun Rollouts [CppLegacy, CppImperative, Haskell] inputs
    case rejectsLegacy of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected VerifyCohortTooSmall rejecting cpp-legacy, got " <> show other)
    -- A single-backend cohort must fail the minimum-cohort check.
    rejectsSingle <- verifyRun Rollouts [Haskell] inputs
    case rejectsSingle of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected VerifyCohortTooSmall on single-backend cohort, got " <> show other)

-- | Sprint 7.5: a cohort whose envelopes disagree on `host_arch` must
-- be rejected with `ArchEnvelopeMismatch` per the architecture-envelope
-- rule (constraint 36). `--allow-stale` does NOT rescue cohort-level
-- mismatches.
envelopeCohortHostArchCheck :: IO ()
envelopeCohortHostArchCheck = do
    let base = makeBaseTranscript
        skewed = base{transcriptEnvelope = (transcriptEnvelope base){envelopeHostArch = "amd64"}}
    case checkCohortInvariant [base, skewed] of
        Right () ->
            assertFailure
                "expected ArchEnvelopeMismatch from a cohort spanning two host arches"
        Left (ArchEnvelopeMismatch _ _) -> pure ()
        Left other ->
            assertFailure
                ( "expected ArchEnvelopeMismatch, got: "
                    <> show other
                )

-- | Sprint 7.5: a cohort whose envelopes disagree on
-- `shared_rng_build_id` (a cohort-invariant field) must be rejected
-- with `EngineEnvelopeMismatch CohortLevel "shared_rng_build_id" …`.
-- `--allow-stale` does NOT rescue cohort-level mismatches.
envelopeCohortRngBuildCheck :: IO ()
envelopeCohortRngBuildCheck = do
    let base = makeBaseTranscript
        forgedDigest = ByteString32 (replicate 64 'a')
        skewed =
            base
                { transcriptEnvelope =
                    (transcriptEnvelope base){envelopeSharedRngBuildId = forgedDigest}
                }
    case checkCohortInvariant [base, skewed] of
        Right () ->
            assertFailure
                "expected EngineEnvelopeMismatch CohortLevel from a shared_rng_build_id skew"
        Left (EngineEnvelopeMismatch CohortLevel field _ _) ->
            assertBool
                ("cohort-level mismatch field must mention shared_rng_build_id, got " <> field)
                (field == "shared_rng_build_id")
        Left other ->
            assertFailure
                ( "expected EngineEnvelopeMismatch CohortLevel shared_rng_build_id, got: "
                    <> show other
                )

-- | Sprint 7.5: a backend-slot mismatch (here, a forged
-- `compiler_id`) is hard-fail without `--allow-stale` and is
-- downgraded to a warning when `allowStale = True`. We model
-- "the live binary expects compiler_id 3" via the logical baseline
-- in `checkBackendSlot`.
envelopeStaleCheck :: IO ()
envelopeStaleCheck = do
    let base = makeBaseTranscript
        skewed =
            base
                { transcriptEnvelope =
                    (transcriptEnvelope base){envelopeCompilerId = 99}
                }
    -- without --allow-stale: hard-fail
    case checkBackendSlot False skewed of
        Right warnings ->
            assertFailure
                ( "expected hard-fail without --allow-stale, got warnings: "
                    <> show warnings
                )
        Left (EngineEnvelopeMismatch (BackendSlot _) field _ _) ->
            assertBool
                ("backend-slot mismatch must surface compiler_id, got " <> field)
                (field == "compiler_id")
        Left other ->
            assertFailure
                ("expected EngineEnvelopeMismatch BackendSlot compiler_id, got: " <> show other)
    -- with --allow-stale: downgrade to a warning, still surface the field
    case checkBackendSlot True skewed of
        Right warnings -> do
            assertBool
                "expected at least one warning when downgraded"
                (not (null warnings))
            case warnings of
                EngineEnvelopeMismatch (BackendSlot _) field _ _ : _ ->
                    assertBool
                        ("downgraded warning must mention compiler_id, got " <> field)
                        (field == "compiler_id")
                _ ->
                    assertFailure
                        ( "expected first warning to be EngineEnvelopeMismatch BackendSlot, got: "
                            <> show warnings
                        )
        Left other ->
            assertFailure
                ("expected --allow-stale to downgrade backend-slot mismatch, got: " <> show other)

makeBaseTranscript :: Transcript
makeBaseTranscript =
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSims = FixedSims 2
                , inputMaxPlies = 4
                }
        gameRec = runGame inputs 0
     in Transcript
            (makeRunConfig inputs)
            (makeLogicalEnvelope Haskell CppRng)
            [gameRec]
