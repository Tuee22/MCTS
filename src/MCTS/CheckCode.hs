module MCTS.CheckCode
    ( runCheckCode
    ) where

import MCTS.CLI.Command (LintCommand (LintAll))
import MCTS.CLI.Lint (runLint)
import qualified MCTS.Env as Env
import System.Exit (ExitCode)

runCheckCode :: Env.App ExitCode
runCheckCode = runLint LintAll
