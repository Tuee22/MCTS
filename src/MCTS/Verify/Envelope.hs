module MCTS.Verify.Envelope
    ( checkCohortInvariant
    , checkBackendSlot
    , checkTranscriptEnvelopes
    ) where

import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.Types

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
    mapM_ (checkOne (transcriptEnvelope first)) rest
  where
    checkOne expected actualTranscript = do
        let actual = transcriptEnvelope actualTranscript
        compareField "host_arch" envelopeHostArch expected actual
        compareField "envelope_version" (show . envelopeVersion) expected actual
        compareField "rng_source" (show . envelopeRngSource) expected actual
        compareField "shared_rng_build_id" (unByteString32 . envelopeSharedRngBuildId) expected actual
        compareField "cohort_config_hash" (unByteString32 . envelopeCohortConfigHash) expected actual

-- | The per-backend-slot fields are matched between the cached transcript's
-- envelope and the live binary's envelope. In the current logical baseline
-- the "live binary" envelope is the one `makeLogicalEnvelope` would
-- produce; once real foreign-engine FFI bindings exist the comparison runs
-- against `mcts_<backend>_get_envelope()`. Per the doctrine, mismatches
-- here are downgradeable to warnings via `--allow-stale`.
checkBackendSlot :: Bool -> Transcript -> Either AppError [AppError]
checkBackendSlot allowStale transcript =
    case mismatches of
        [] -> Right []
        firstMismatch : _
            | allowStale -> Right mismatches
            | otherwise -> Left firstMismatch
  where
    envelope = transcriptEnvelope transcript
    backend = runBackend (transcriptConfig transcript)
    expectedBuildId = backendIdentifier backend <> "-logical"
    mismatches =
        [ EngineEnvelopeMismatch (BackendSlot backend) "backend" (backendIdentifier backend) (backendIdentifier (envelopeBackend envelope))
        | envelopeBackend envelope /= backend
        ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "build_id" expectedBuildId (envelopeBuildId envelope)
               | envelopeBuildId envelope /= expectedBuildId
               ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "engine_build_id" (unByteString32 zeroDigest) (unByteString32 (envelopeEngineBuildId envelope))
               | envelopeEngineBuildId envelope /= zeroDigest
               ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "compiler_id" "3" (show (envelopeCompilerId envelope))
               | envelopeCompilerId envelope /= 3
               ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "fp_flags" "0" (show (envelopeFpFlags envelope))
               | envelopeFpFlags envelope /= 0
               ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "cpu_features" "0" (show (envelopeCpuFeatures envelope))
               | envelopeCpuFeatures envelope /= 0
               ]
            <> [ EngineEnvelopeMismatch (BackendSlot backend) "fp_env" "0" (show (envelopeFpEnv envelope))
               | envelopeFpEnv envelope /= 0
               ]

checkTranscriptEnvelopes :: Bool -> [Transcript] -> Either AppError [AppError]
checkTranscriptEnvelopes allowStale transcripts = do
    checkCohortInvariant transcripts
    concat <$> mapM (checkBackendSlot allowStale) transcripts

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

