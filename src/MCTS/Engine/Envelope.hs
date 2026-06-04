module MCTS.Engine.Envelope
    ( makeEngineEnvelope
    ) where

import MCTS.Transcript (hostArch)
import MCTS.Types

makeEngineEnvelope :: Backend -> RngSource -> Envelope
makeEngineEnvelope backend rng =
    Envelope
        { envelopeVersion = 1
        , envelopeBackend = backend
        , envelopeRngSource = rng
        , envelopeHostArch = hostArch
        , envelopeSharedRngBuildId = zeroDigest
        , envelopeCohortConfigHash = zeroDigest
        , envelopeEngineBuildId = zeroDigest
        , envelopeEngineGitCommit = ""
        , envelopeCompilerId = 3
        , envelopeCompilerVersion = "9.12.4"
        , envelopeFpFlags = 0
        , envelopeLibmId = ""
        , envelopeCpuFeatures = 0
        , envelopeFpEnv = 0
        , envelopeBuildId = "logical"
        }
