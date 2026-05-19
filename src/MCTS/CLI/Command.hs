module MCTS.CLI.Command
    ( Command (..)
    , BenchCommand (..)
    , VerifyCommand (..)
    , VerifyBackend (..)
    , verifyBackendToBackend
    , verifyBackendsToBackends
    , InspectCommand (..)
    , TestCommand (..)
    , RetirementAnchorOptions (..)
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

import MCTS.Driver (RunInputs)
import MCTS.Plan (PlanOptions)
import MCTS.Types
    ( Backend
    , Side
    , SimBudget
    , Transcript
    , VerifyBackend (..)
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
    deriving (Eq, Show)

data VerifyCommand
    = VerifyRollouts Bool [VerifyBackend] RunInputs
    | VerifySelfplay Bool [VerifyBackend] RunInputs
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
    | TestRetirementAnchor RetirementAnchorOptions
    | TestStanza String
    deriving (Eq, Show)

data RetirementAnchorOptions = RetirementAnchorOptions
    { retirementAnchorRetiring :: !Backend
    , retirementAnchorSuccessor :: !Backend
    , retirementAnchorPlanOptions :: !PlanOptions
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
    = BuildRust PlanOptions
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
    , playSims :: !SimBudget
    , playSeed :: !(Maybe Integer)
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
