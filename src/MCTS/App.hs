module MCTS.App
    ( main
    , runWithArgs
    ) where

import MCTS.CLI.Bench (runBench)
import MCTS.CLI.Build (runBuild)
import MCTS.CLI.Command
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Inspect (runInspect)
import MCTS.CLI.Lint (runLint)
import MCTS.CLI.Output
import MCTS.CLI.Parser (parseCommand)
import MCTS.CLI.Spec (renderCommandJson, renderCommandList, renderCommandTree)
import MCTS.CLI.Test (runTestCommand)
import MCTS.CLI.Verify (runVerifyCommand)
import qualified MCTS.Driver as Driver
import MCTS.Driver (defaultRunInputs, runBatch)
import MCTS.Subprocess (Subprocess (..), runStreaming)
import MCTS.Types (Backend, RngSource (NativeRng), Workload (Selfplay), backendIdentifier)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)

main :: IO ()
main = do
    args <- getArgs
    code <- runWithArgs args
    exitWith (if code == 0 then ExitSuccess else ExitFailure code)

runWithArgs :: [String] -> IO Int
runWithArgs rawArgs = do
    let (output, args) = parseGlobalOutputOptions rawArgs
    case parseCommand args of
        Left err -> errLine (renderError err) >> pure 2
        Right command -> runCommand output command

runCommand :: OutputOptions -> Command -> IO Int
runCommand output command =
    case command of
        Bench (BenchRollouts inputs) -> runBench output inputs
        Bench (BenchSelfplay inputs) -> runBench output inputs
        Verify verifyCommand -> runVerifyCommand output verifyCommand
        Inspect inspectCommand -> runInspect output inspectCommand
        Test testCommand -> runTestCommand output testCommand
        Lint lintCommand -> runLint lintCommand
        Docs docsCommand -> runDocs docsCommand
        Build buildCommand -> runBuild buildCommand
        Commands options ->
            outputLine
                ( if commandsJson options
                    then renderCommandJson
                    else
                        if commandsTree options
                            then renderCommandTree
                            else renderCommandList
                )
                >> pure 0
        Help (HelpOptions target) ->
            outputLine ("help: mcts " <> unwords target <> "\nRun `mcts commands --tree` for the command tree.")
                >> pure 0
        CheckCode -> do
            a <- runLint LintAll
            b <- runDocs DocsCheck
            c <- runBuildGate
            pure (maximum [a, b, c])
        Play options -> runPlay options

runPlay :: PlayOptions -> IO Int
runPlay options = do
    let seed = maybe 42 fromIntegral (playSeed options)
        inputs =
            defaultRunInputs
                { Driver.inputBackend = playBackend options
                , Driver.inputWorkload = Selfplay
                , Driver.inputRng = NativeRng
                , Driver.inputGames = 1
                , Driver.inputSeed = fromIntegral (seed :: Integer)
                , Driver.inputSims = playSims options
                }
    result <- runBatch inputs
    case result of
        Left message -> outputLine message >> pure 1
        Right batch ->
            outputLine
                ( "played one logical game with "
                    <> backendIdentifier (playBackend options)
                    <> " hash="
                    <> Driver.batchHash batch
                )
                >> pure 0

_keepBackend :: Backend -> Backend
_keepBackend = id

runBuildGate :: IO Int
runBuildGate = do
    result <- runStreaming (Subprocess "cabal" ["build", "all"] Nothing Nothing)
    case result of
        Right _ -> outputLine "build all PASS" >> pure 0
        Left err -> outputLine (renderError err) >> pure 1
