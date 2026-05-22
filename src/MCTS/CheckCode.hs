module MCTS.CheckCode
    ( runCheckCode
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (LintCommand (LintAll))
import MCTS.CLI.Lint (runLint)
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Subprocess (Subprocess (..), runStreaming)
import System.Exit (ExitCode (..))

runCheckCode :: Env.App ExitCode
runCheckCode = do
    lintCode <- runLint LintAll
    buildCode <- runBuildGate
    pure (maxExitCode [lintCode, buildCode])

runBuildGate :: Env.App ExitCode
runBuildGate = do
    env <- Env.askEnv
    result <- liftIO (runStreaming (Subprocess "cabal" ["build", "all"] Nothing Nothing))
    case result of
        Right _ -> liftIO (outputLine "build all PASS") >> pure ExitSuccess
        Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)

maxExitCode :: [ExitCode] -> ExitCode
maxExitCode codes =
    if all (== ExitSuccess) codes
        then ExitSuccess
        else ExitFailure 1
