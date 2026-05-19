module MCTS.Verify.Envelope
    ( checkCohortInvariant
    , checkBackendSlot
    , checkBackendSlotAgainst
    , checkTranscriptEnvelopes
    , checkTranscriptEnvelopesLive
    ) where

import MCTS.Driver (makeLogicalEnvelope)
import MCTS.Driver.Dispatch (cppLegacyLibraryPath)
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.FFI.Common (engineEnvelopeToEnvelope)
import MCTS.FFI.CppFunctional (cppFunctionalLibraryPath, loadCppFunctionalEnvelope)
import MCTS.FFI.CppImperative (cppImperativeLibraryPath, loadCppImperativeEnvelope)
import MCTS.FFI.CppLegacy (loadCppLegacyEnvelope)
import MCTS.FFI.Rust (loadRustEnvelope, rustLibraryPath)
import MCTS.Types
import System.Directory (doesFileExist)

-- | Per the doctrine engine envelope, the cohort-invariant fields must
-- agree across every transcript in a verify cohort:
--   * `host_arch` (architecture envelope rule)
--   * `envelope_version`
--   * `rng_source`
--   * `shared_rng_build_id`
--   * `cohort_config_hash`
checkCohortInvariant :: [Transcript] -> Either AppError ()
checkCohortInvariant [] = Right ()
checkCohortInvariant (first : rest) =
    mapM_ (checkCohortPeer (transcriptEnvelope first)) rest
  where
    checkCohortPeer expected actualTranscript = do
        let actual = transcriptEnvelope actualTranscript
        compareField "host_arch" envelopeHostArch expected actual
        compareField "envelope_version" (show . envelopeVersion) expected actual
        compareField "rng_source" (show . envelopeRngSource) expected actual
        compareField "shared_rng_build_id" (unByteString32 . envelopeSharedRngBuildId) expected actual
        compareField "cohort_config_hash" (unByteString32 . envelopeCohortConfigHash) expected actual

-- | Pure logical fallback for comparing a transcript's per-backend-slot
-- fields. The live verifier uses `checkTranscriptEnvelopesLive` so foreign
-- transcripts are checked against `mcts_<backend>_get_envelope()` whenever
-- the matching cdylib is available.
checkBackendSlot :: Bool -> Transcript -> Either AppError [AppError]
checkBackendSlot allowStale transcript =
    checkBackendSlotAgainst
        allowStale
        (makeLogicalEnvelope backend (envelopeRngSource envelope))
        transcript
  where
    envelope = transcriptEnvelope transcript
    backend = runBackend (transcriptConfig transcript)

checkBackendSlotAgainst :: Bool -> Envelope -> Transcript -> Either AppError [AppError]
checkBackendSlotAgainst allowStale expected transcript = do
    compareLiveCohortField "host_arch" envelopeHostArch expected envelope
    compareLiveCohortField "envelope_version" (show . envelopeVersion) expected envelope
    compareLiveCohortField "rng_source" (show . envelopeRngSource) expected envelope
    compareLiveCohortField
        "shared_rng_build_id"
        (unByteString32 . envelopeSharedRngBuildId)
        expected
        envelope
    compareLiveCohortField
        "cohort_config_hash"
        (unByteString32 . envelopeCohortConfigHash)
        expected
        envelope
    case mismatches of
        [] -> Right []
        firstMismatch : _
            | allowStale -> Right mismatches
            | otherwise -> Left firstMismatch
  where
    envelope = transcriptEnvelope transcript
    backend = runBackend (transcriptConfig transcript)
    mismatches =
        [ EngineEnvelopeMismatch
            (BackendSlot backend)
            "backend"
            (backendIdentifier (envelopeBackend expected))
            (backendIdentifier (envelopeBackend envelope))
        | envelopeBackend envelope /= envelopeBackend expected
        ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "build_id"
                    (envelopeBuildId expected)
                    (envelopeBuildId envelope)
               | envelopeBuildId envelope /= envelopeBuildId expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "engine_build_id"
                    (unByteString32 (envelopeEngineBuildId expected))
                    (unByteString32 (envelopeEngineBuildId envelope))
               | envelopeEngineBuildId envelope /= envelopeEngineBuildId expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "engine_git_commit"
                    (envelopeEngineGitCommit expected)
                    (envelopeEngineGitCommit envelope)
               | envelopeEngineGitCommit envelope /= envelopeEngineGitCommit expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "compiler_id"
                    (show (envelopeCompilerId expected))
                    (show (envelopeCompilerId envelope))
               | envelopeCompilerId envelope /= envelopeCompilerId expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "compiler_version"
                    (envelopeCompilerVersion expected)
                    (envelopeCompilerVersion envelope)
               | envelopeCompilerVersion envelope /= envelopeCompilerVersion expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "fp_flags"
                    (show (envelopeFpFlags expected))
                    (show (envelopeFpFlags envelope))
               | envelopeFpFlags envelope /= envelopeFpFlags expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "libm_id"
                    (envelopeLibmId expected)
                    (envelopeLibmId envelope)
               | envelopeLibmId envelope /= envelopeLibmId expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "cpu_features"
                    (show (envelopeCpuFeatures expected))
                    (show (envelopeCpuFeatures envelope))
               | envelopeCpuFeatures envelope /= envelopeCpuFeatures expected
               ]
            <> [ EngineEnvelopeMismatch
                    (BackendSlot backend)
                    "fp_env"
                    (show (envelopeFpEnv expected))
                    (show (envelopeFpEnv envelope))
               | envelopeFpEnv envelope /= envelopeFpEnv expected
               ]

checkTranscriptEnvelopes :: Bool -> [Transcript] -> Either AppError [AppError]
checkTranscriptEnvelopes allowStale transcripts = do
    checkCohortInvariant transcripts
    concat <$> mapM (checkBackendSlot allowStale) transcripts

checkTranscriptEnvelopesLive :: Bool -> [Transcript] -> IO (Either AppError [AppError])
checkTranscriptEnvelopesLive allowStale transcripts =
    case checkCohortInvariant transcripts of
        Left err -> pure (Left err)
        Right () -> do
            checked <- mapM (checkTranscriptLive allowStale) transcripts
            pure $ concat <$> sequence checked

checkTranscriptLive :: Bool -> Transcript -> IO (Either AppError [AppError])
checkTranscriptLive allowStale transcript = do
    loaded <- loadExpectedEnvelope (transcriptEnvelope transcript)
    pure $ do
        expected <- loaded
        checkBackendSlotAgainst allowStale expected transcript

loadExpectedEnvelope :: Envelope -> IO (Either AppError Envelope)
loadExpectedEnvelope envelope =
    case envelopeBackend envelope of
        CppLegacy -> loadForeign cppLegacyLibraryPath loadCppLegacyEnvelope
        CppImperative -> loadForeign cppImperativeLibraryPath loadCppImperativeEnvelope
        CppFunctional -> loadForeign cppFunctionalLibraryPath loadCppFunctionalEnvelope
        Rust -> loadForeign rustLibraryPath loadRustEnvelope
        Haskell -> pure (Right (makeLogicalEnvelope Haskell (envelopeRngSource envelope)))
  where
    loadForeign libraryPath loader = do
        present <- doesFileExist libraryPath
        if present
            then fmap engineEnvelopeToEnvelope <$> loader
            else pure (Right (makeLogicalEnvelope (envelopeBackend envelope) (envelopeRngSource envelope)))

compareField :: String -> (Envelope -> String) -> Envelope -> Envelope -> Either AppError ()
compareField field getValue expected actual =
    let expectedValue = getValue expected
        actualValue = getValue actual
     in if expectedValue == actualValue
            then Right ()
            else
                if field == "host_arch"
                    then Left (ArchEnvelopeMismatch expectedValue actualValue)
                    else Left (EngineEnvelopeMismatch CohortLevel field expectedValue actualValue)

compareLiveCohortField
    :: String -> (Envelope -> String) -> Envelope -> Envelope -> Either AppError ()
compareLiveCohortField = compareField
