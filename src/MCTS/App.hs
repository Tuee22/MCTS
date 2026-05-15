module MCTS.App
    ( main
    , runWithArgs
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Bench (runBench)
import MCTS.CLI.Build (runBuild)
import MCTS.CLI.Command
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Inspect (runInspect)
import MCTS.CLI.Json (renderCommandJson)
import MCTS.CLI.Lint (runLint)
import MCTS.CLI.Output
import MCTS.CLI.Parser (parseCommand)
import MCTS.CLI.Test (runTestCommand)
import MCTS.CLI.Tree (renderCommandList, renderCommandTree)
import MCTS.CLI.Verify (runVerifyCommand)
import MCTS.CheckCode (runCheckCode)
import MCTS.Driver (defaultRunInputs, runBatch)
import qualified MCTS.Driver as Driver
import qualified MCTS.Env as Env
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
    (output, args) <- parseGlobalOutputOptionsIO rawArgs
    case parseCommand args of
        Left err -> errLine (renderErrorString output err) >> pure 2
        Right command -> do
            let env = Env.defaultEnv{Env.envOutputOptions = output, Env.envRawArguments = rawArgs}
            code <- Env.runAppIO env (runCommand command)
            pure (exitCodeToInt code)

runCommand :: Command -> Env.App ExitCode
runCommand command =
    case command of
        Bench (BenchRollouts backends inputs) -> runBench backends inputs
        Bench (BenchSelfplay backends inputs) -> runBench backends inputs
        Verify verifyCommand -> runVerifyCommand verifyCommand
        Inspect inspectCommand -> runInspect inspectCommand
        Test testCommand -> runTestCommand testCommand
        Lint lintCommand -> runLint lintCommand
        Docs docsCommand -> runDocs docsCommand
        Build buildCommand -> runBuild buildCommand
        Commands options ->
            liftIO
                ( outputLine
                    ( if commandsJson options
                        then renderCommandJson
                        else
                            if commandsTree options
                                then renderCommandTree
                                else renderCommandList
                    )
                )
                >> pure ExitSuccess
        Help (HelpOptions target) ->
            liftIO
                (outputLine ("help: mcts " <> unwords target <> "\nRun `mcts commands --tree` for the command tree."))
                >> pure ExitSuccess
        CheckCode -> runCheckCode
        Play options -> runPlay options

runPlay :: PlayOptions -> Env.App ExitCode
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
    result <- liftIO (runBatch inputs)
    case result of
        Left message -> liftIO (outputLine message) >> pure (ExitFailure 1)
        Right batch ->
            liftIO
                ( outputLine
                    ( "played one logical game with "
                        <> backendIdentifier (playBackend options)
                        <> " hash="
                        <> Driver.batchHash batch
                    )
                )
                >> pure ExitSuccess

exitCodeToInt :: ExitCode -> Int
exitCodeToInt ExitSuccess = 0
exitCodeToInt (ExitFailure n) = n

_keepBackend :: Backend -> Backend
_keepBackend = id
