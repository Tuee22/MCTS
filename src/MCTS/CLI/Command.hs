module MCTS.CLI.Command
    ( Command (..)
    , BenchCommand (..)
    , BenchPrimitive (..)
    , BenchPrimitiveOptions (..)
    , VerifyCommand (..)
    , VerifyBackend (..)
    , verifyBackendToBackend
    , verifyBackendsToBackends
    , InspectCommand (..)
    , TestCommand (..)
    , ParityAnchorOptions (..)
    , LintCommand (..)
    , DocsCommand (..)
    , BuildCommand (..)
    , LegacyFixtureOptions (..)
    , CommandsOptions (..)
    , HelpOptions (..)
    , PlayOptions (..)
    , ShowOptions (..)
    , ReplayOptions (..)
    , CacheCommand (..)
    , DivergenceOptions (..)
    ) where

import Data.Word (Word16, Word64)
import MCTS.Driver (RunInputs)
import MCTS.Plan (PlanOptions)
import MCTS.Types
    ( Backend
    , RngSource
    , Side
    , SimBudget
    , Threading
    , Transcript
    , VerifyBackend (..)
    , Workload
    , verifyBackendToBackend
    )

data Command
    = Bench BenchCommand
    | Verify VerifyCommand
    | Play PlayOptions
    | Inspect InspectCommand
    | Test TestCommand
    | Lint LintCommand
    | Docs DocsCommand
    | Commands CommandsOptions
    | Help HelpOptions
    | CheckCode
    | Build BuildCommand
    deriving (Eq, Show)

data BenchCommand
    = BenchRollouts [Backend] RunInputs
    | BenchSelfplay [Backend] RunInputs
    | BenchTerminalPlayouts [Backend] BenchPrimitiveOptions
    | BenchSearchIters [Backend] BenchPrimitiveOptions
    deriving (Eq, Show)

data BenchPrimitive
    = TerminalPlayouts
    | SearchIters
    deriving (Eq, Ord, Show, Read)

data BenchPrimitiveOptions = BenchPrimitiveOptions
    { benchPrimitiveRng :: !RngSource
    , benchPrimitiveThreading :: !Threading
    , benchPrimitiveCount :: !Int
    , benchPrimitiveSeed :: !Word64
    , benchPrimitiveMaxPlies :: !Word16
    }
    deriving (Eq, Show)

data VerifyCommand
    = VerifyRollouts Bool [VerifyBackend] RunInputs
    | VerifySelfplay Bool [VerifyBackend] RunInputs
    | VerifyLegacyParity Bool Workload [Backend] RunInputs
    deriving (Eq, Show)

verifyBackendsToBackends :: [VerifyBackend] -> [Backend]
verifyBackendsToBackends = map verifyBackendToBackend

data InspectCommand
    = InspectList (Maybe FilePath)
    | InspectShow ShowOptions
    | InspectReplay ReplayOptions
    | InspectCache CacheCommand
    | InspectDivergence DivergenceOptions
    deriving (Eq, Show)

data CacheCommand
    = CacheList (Maybe FilePath)
    | CachePrune Bool (Maybe FilePath) PlanOptions
    deriving (Eq, Show)

data TestCommand
    = TestAll PlanOptions
    | TestParityAnchor ParityAnchorOptions
    | TestStanza String
    deriving (Eq, Show)

data ParityAnchorOptions = ParityAnchorOptions
    { parityAnchorBaseline :: !Backend
    , parityAnchorCandidate :: !Backend
    , parityAnchorPlanOptions :: !PlanOptions
    }
    deriving (Eq, Show)

data LintCommand
    = LintFiles Bool
    | LintDocs Bool
    | LintHaskell Bool
    | LintAll
    deriving (Eq, Show)

data DocsCommand
    = DocsCheck
    | DocsGenerate Bool (Maybe FilePath)
    deriving (Eq, Show)

data BuildCommand
    = BuildCppLegacy PlanOptions
    | BuildCppImperative PlanOptions
    | BuildCppFunctional PlanOptions
    | BuildRust PlanOptions
    | BuildLegacyFixtures LegacyFixtureOptions
    deriving (Eq, Show)

data LegacyFixtureOptions = LegacyFixtureOptions
    { legacyFixtureOutputDir :: !FilePath
    , legacyFixtureSeed :: !Integer
    , legacyFixtureGames :: !Int
    , legacyFixtureSims :: !Int
    , legacyFixturePlanOptions :: !PlanOptions
    }
    deriving (Eq, Show)

data CommandsOptions = CommandsOptions
    { commandsTree :: !Bool
    , commandsJson :: !Bool
    }
    deriving (Eq, Show)

newtype HelpOptions = HelpOptions {helpTarget :: [String]}
    deriving (Eq, Show)

data PlayOptions = PlayOptions
    { playBackend :: !Backend
    , playSide :: !Side
    , playVs :: !(Maybe Backend)
    , playRng :: !RngSource
    , playSims :: !SimBudget
    , playSeed :: !(Maybe Word64)
    , playMaxPlies :: !Word16
    , playCacheDir :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

data ShowOptions = ShowOptions
    { showRef :: !String
    , showTopN :: !Int
    , showWithEquity :: !Bool
    , showEnvelope :: !Bool
    , showCacheDir :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

data ReplayOptions = ReplayOptions
    { replayRef :: !String
    , replayTopN :: !Int
    , replayCacheStates :: !Int
    , replayCacheDir :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

data DivergenceOptions = DivergenceOptions
    { divergenceRef :: !String
    , divergenceCacheDir :: !(Maybe FilePath)
    }
    deriving (Eq, Show)

_keepTranscript :: Transcript -> Transcript
_keepTranscript = id
