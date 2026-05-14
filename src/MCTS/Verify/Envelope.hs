module MCTS.Verify.Envelope
    ( checkCohortInvariant
    , checkBackendSlot
    , checkTranscriptEnvelopes
    ) where

import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.Types

checkCohortInvariant :: [Transcript] -> Either AppError ()
checkCohortInvariant [] = Right ()
checkCohortInvariant (first : rest) =
    mapM_ (checkOne (transcriptEnvelope first)) rest
  where
    checkOne expected actualTranscript = do
        let actual = transcriptEnvelope actualTranscript
        compareField "host_arch" envelopeHostArch expected actual
        compareField "envelope_version" (show . envelopeVersion) expected actual

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

