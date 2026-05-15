module MCTS.CheckCode
    ( runCheckCode
    ) where

import MCTS.CLI.Command (DocsCommand (DocsCheck), LintCommand (LintAll))
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Lint (runLint)
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.Subprocess (Subprocess (..), runStreaming)

runCheckCode :: IO Int
runCheckCode = do
    lintCode <- runLint LintAll
    docsCode <- runDocs DocsCheck
    buildCode <- runBuildGate
    pure (maximum [lintCode, docsCode, buildCode])

runBuildGate :: IO Int
runBuildGate = do
    result <- runStreaming (Subprocess "cabal" ["build", "all"] Nothing Nothing)
    case result of
        Right _ -> outputLine "build all PASS" >> pure 0
        Left err -> outputLine (renderError err) >> pure 1
