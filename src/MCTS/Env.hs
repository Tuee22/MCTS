{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | Application environment record threaded through every command runner via
-- a single `ReaderT Env IO` per
-- [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md).
--
-- This module also carries the `App` newtype and `runAppIO` helper used by
-- `MCTS.App` to run the command dispatcher inside the shared environment.
module MCTS.Env
    ( Env (..)
    , defaultEnv
    , App
    , runAppIO
    , askEnv
    , envCacheRoot
    , envClock
    , withTestClock
    ) where

import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ReaderT (..), ask, local, runReaderT)
import Data.Word (Word64)
import qualified MCTS.CLI.Output as Output
import qualified MCTS.CLI.Spec as Spec
import qualified MCTS.Generated.Paths as GeneratedPaths
import qualified MCTS.Generated.Sections as GeneratedSections
import qualified MCTS.Prerequisite as Prerequisite
import System.IO (Handle, stdout)

-- | One shared record that every doctrine-aligned command runner receives.
--
-- Fields:
--
--   * `envOutputOptions` — output discipline (`--format`, `--color`)
--   * `envCommandSpec` — the `CommandSpec` registry (single source of truth)
--   * `envGeneratedSectionRules` — marker-delimited generated doc registry
--   * `envTrackingGeneratedPaths` — fully-generated path registry
--   * `envPrerequisites` — the `prerequisiteRegistry` value
--   * `envCacheDir` — explicit `--cache-dir` override; `Nothing` means resolve
--     to the project-local cache
--   * `envLogHandle` — process log/output handle for future output-boundary unification
--   * `envRawArguments` — parsed invocation context retained for diagnostics
--   * `envClockMonotonic` — monotonic clock test-hook returning nanoseconds
--     since some fixed epoch; production runners use the system monotonic
--     clock, but the Phase 3 Sprint 3.5 timing-bracket assertion overrides
--     this hook to capture call sites
data Env = Env
    { envOutputOptions :: !Output.OutputOptions
    , envCommandSpec :: !Spec.CommandSpec
    , envGeneratedSectionRules :: ![GeneratedSections.GeneratedSectionRule]
    , envTrackingGeneratedPaths :: ![FilePath]
    , envPrerequisites :: ![Prerequisite.PrerequisiteNode]
    , envCacheDir :: !(Maybe FilePath)
    , envLogHandle :: !Handle
    , envRawArguments :: ![String]
    , envClockMonotonic :: IO Word64
    }

-- | Defaults match the worktree baseline: standard output, the canonical
-- command spec, the full prerequisite registry, project-local cache, and
-- a production clock stub that always returns zero. The Sprint 3.5 test
-- hook overrides `envClockMonotonic` before the bench runner is invoked.
defaultEnv :: Env
defaultEnv =
    Env
        { envOutputOptions = Output.defaultOutputOptions
        , envCommandSpec = Spec.commandSpec
        , envGeneratedSectionRules = GeneratedSections.generatedSectionRules
        , envTrackingGeneratedPaths = GeneratedPaths.trackingGeneratedPaths
        , envPrerequisites = Prerequisite.prerequisiteRegistry
        , envCacheDir = Nothing
        , envLogHandle = stdout
        , envRawArguments = []
        , envClockMonotonic = pure 0
        }

-- | The doctrine-shaped application monad.
newtype App a = App {unApp :: ReaderT Env IO a}
    deriving newtype (Functor, Applicative, Monad, MonadIO)

-- | Run an `App` computation with an `Env`. `MCTS.App` uses this as the single
-- IO adapter for the `... -> App ExitCode` command runners.
runAppIO :: Env -> App a -> IO a
runAppIO env action = runReaderT (unApp action) env

-- | Retrieve the current environment inside `App`.
askEnv :: App Env
askEnv = App ask

-- | Convenience accessor for the cache-root override field.
envCacheRoot :: Env -> Maybe FilePath
envCacheRoot = envCacheDir

-- | Run the monotonic clock hook.
envClock :: Env -> IO Word64
envClock = envClockMonotonic

-- | Override the clock for a single `App` action; used by the Phase 3
-- Sprint 3.5 timing-bracket assertion to capture start/stop call sites.
withTestClock :: IO Word64 -> App a -> App a
withTestClock fakeClock (App action) =
    App (local (\env -> env{envClockMonotonic = fakeClock}) action)
