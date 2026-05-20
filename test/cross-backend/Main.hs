module Main where

import Data.List (isInfixOf)
import MCTS.Driver
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.Subprocess (ProcessOutput (..), Subprocess (..), capture)
import MCTS.Types
import MCTS.Verify
import MCTS.Verify.Envelope (checkBackendSlot, checkCohortInvariant)
import Test.Tasty (defaultMain, localOption, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)
import Test.Tasty.Runners (NumThreads (..))

-- | Q3 verifies the steelman cohort `(ii)..(v)` under `--rng cpp`.
-- Backend (i) remains outside Q3 and is covered by legacy parity.
main :: IO ()
main =
    defaultMain . localOption (NumThreads 1) $
        testGroup
            "mcts-cross-backend"
            [ testCase "Q3 rollout cohort" rolloutsCheck
            , testCase "Q3 selfplay cohort" selfplayCheck
            , testCase "length-aware verifier mismatches" comparatorMismatchCheck
            , testCase "cohort constraints" cohortConstraintsCheck
            , testCase "envelope: cohort host_arch mismatch hard-fails" envelopeCohortHostArchCheck
            , testCase "envelope: shared_rng_build_id mismatch hard-fails" envelopeCohortRngBuildCheck
            , testCase "envelope: backend-slot compiler mismatch obeys --allow-stale" envelopeStaleCheck
            ]

rolloutsCheck :: IO ()
rolloutsCheck =
    verifyCli "rollouts" "verify rollouts PASS" 2 "/tmp/mcts-cross-backend-rollouts"

selfplayCheck :: IO ()
selfplayCheck =
    verifyCli "selfplay" "verify selfplay PASS" 1 "/tmp/mcts-cross-backend-selfplay"

verifyCli :: String -> String -> Int -> FilePath -> IO ()
verifyCli workload expected games cacheRoot = do
    result <-
        capture
            ( Subprocess
                "mcts"
                [ "verify"
                , workload
                , "--backend"
                , "cpp-imperative,cpp-functional,rust,haskell"
                , "--threading"
                , "single"
                , "--games"
                , show games
                , "--seed"
                , "42"
                , "--sims"
                , "16"
                , "--max-plies"
                , "60"
                , "--cache-dir"
                , cacheRoot
                ]
                Nothing
                Nothing
            )
    case result of
        Left err -> assertFailure ("cross-backend " <> workload <> " subprocess failed: " <> show err)
        Right output ->
            assertBool
                ("cross-backend " <> workload <> " output should contain `" <> expected <> "`")
                (expected `isInfixOf` processStdout output)

comparatorMismatchCheck :: IO ()
comparatorMismatchCheck = do
    let base = makeBaseTranscript
    case transcriptGames base of
        [] -> assertFailure "makeBaseTranscript must produce a game"
        baseGame : _ -> do
            let extraMove =
                    base
                        { transcriptGames =
                            [baseGame{gameMoves = gameMoves baseGame <> [duplicateMove baseGame]}]
                        }
                extraGame =
                    base{transcriptGames = transcriptGames base <> [baseGame{gameId = gameId baseGame + 1}]}
                differentWinner =
                    base{transcriptGames = [baseGame{gameWinner = alternateWinner (gameWinner baseGame)}]}
            case compareTranscripts Haskell base Rust extraMove of
                Left (VerifyLengthMismatch Haskell Rust scope _ _) ->
                    assertBool "extra move scope names the game" (scope == "moves game=0")
                other -> assertFailure ("expected extra-move VerifyLengthMismatch, got " <> show other)
            case compareTranscripts Haskell base Rust extraGame of
                Left (VerifyLengthMismatch Haskell Rust "games" _ _) -> pure ()
                other -> assertFailure ("expected extra-game VerifyLengthMismatch, got " <> show other)
            case compareTranscripts Haskell base Rust differentWinner of
                Left (VerifyTerminatorMismatch Haskell Rust 0 _ _) -> pure ()
                other -> assertFailure ("expected VerifyTerminatorMismatch, got " <> show other)

duplicateMove :: GameTranscript -> MoveRecord
duplicateMove game =
    case gameMoves game of
        record : _ -> record{moveIndex = fromIntegral (length (gameMoves game))}
        [] -> MoveRecord 0 (Pawn 4 1) []

alternateWinner :: Winner -> Winner
alternateWinner winner =
    case winner of
        HeroWin -> VillainWin
        VillainWin -> HeroWin
        Draw -> HeroWin

cohortConstraintsCheck :: IO ()
cohortConstraintsCheck = do
    let inputs = defaultRunInputs{inputGames = 1, inputSeed = 42, inputSims = FixedSims 4, inputMaxPlies = 20}
    -- Backend (i) is excluded from Q3 verify; the steelman cohort is (ii)..(v).
    rejectsLegacy <- verifyRun Rollouts [CppLegacy, Rust, Haskell] inputs
    case rejectsLegacy of
        Left (VerifyCohortTooSmall _) -> pure ()
        other -> assertFailure ("expected VerifyCohortTooSmall rejecting cpp-legacy, got " <> show other)
    acceptsSteelman <- verifyRun Rollouts [CppImperative, CppFunctional, Rust, Haskell] inputs
    case acceptsSteelman of
        Right results -> assertEqual "Q3 cohort size" 4 (length results)
        other -> assertFailure ("expected Q3 steelman cohort to pass, got " <> show other)
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
        baseEnvelope = transcriptEnvelope base
        otherArch =
            if envelopeHostArch baseEnvelope == "amd64"
                then "arm64"
                else "amd64"
        skewed = base{transcriptEnvelope = baseEnvelope{envelopeHostArch = otherArch}}
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
-- downgraded to a warning when `allowStale = True`. This focused test
-- uses the pure logical fallback; `mcts-unit` covers the live-envelope
-- fixture comparison shape.
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
