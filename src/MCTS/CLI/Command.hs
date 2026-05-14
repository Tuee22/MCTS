module MCTS.CLI.Command
    ( Command (..)
    , BenchCommand (..)
    , VerifyCommand (..)
    , InspectCommand (..)
    , TestCommand (..)
    , LintCommand (..)
    , DocsCommand (..)
    , BuildCommand (..)
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
import MCTS.Types (Backend, Side, SimBudget, Transcript, Workload)

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
    = BenchRollouts RunInputs
    | BenchSelfplay RunInputs
    deriving (Eq, Show)

data VerifyCommand
    = VerifyRollouts Bool [Backend] RunInputs
    | VerifySelfplay Bool [Backend] RunInputs
    | VerifyLegacyParity Workload Bool [Backend] RunInputs
    deriving (Eq, Show)

data InspectCommand
    = InspectList (Maybe FilePath)
    | InspectShow ShowOptions
    | InspectReplay ReplayOptions
    | InspectCache CacheCommand
    | InspectDivergence DivergenceOptions
    deriving (Eq, Show)

data CacheCommand
    = CacheList (Maybe FilePath)
    | CachePrune Bool (Maybe FilePath)
    deriving (Eq, Show)

data TestCommand
    = TestAll PlanOptions
    | TestStanza String
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
