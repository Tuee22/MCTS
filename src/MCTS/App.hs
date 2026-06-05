module MCTS.App
    ( main
    , runWithArgs
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Bits (shiftL, (.|.))
import qualified Data.ByteString as ByteString
import Data.Word (Word64, Word8)
import MCTS.CLI.Bench (runBench, runPrimitiveBench)
import MCTS.CLI.Build (runBuild)
import MCTS.CLI.Command
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Inspect (runInspect)
import MCTS.CLI.Json (renderCommandJson)
import MCTS.CLI.Lint (runLint)
import MCTS.CLI.Output
import MCTS.CLI.Parser (parseCommand, renderFocusedHelp)
import MCTS.CLI.Test (runTestCommand)
import MCTS.CLI.Tree (renderCommandList, renderCommandTree)
import qualified MCTS.CLI.Tui.Play as TuiPlay
import MCTS.CLI.Verify (runVerifyCommand)
import MCTS.CheckCode (runCheckCode)
import qualified MCTS.Env as Env
import MCTS.Types (simPerMove)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (IOMode (ReadMode), hIsTerminalDevice, stdin, stdout, withBinaryFile)

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
        Bench (BenchTerminalPlayouts backends options) -> runPrimitiveBench TerminalPlayouts backends options
        Bench (BenchSearchIters backends options) -> runPrimitiveBench SearchIters backends options
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
            case renderFocusedHelp target of
                Right rendered -> liftIO (outputLine rendered) >> pure ExitSuccess
                Left rendered -> liftIO (outputLine rendered) >> pure (ExitFailure 2)
        RenderHelp rendered ->
            liftIO (outputLine rendered) >> pure ExitSuccess
        CheckCode -> runCheckCode
        Play options -> runPlay options

runPlay :: PlayOptions -> Env.App ExitCode
runPlay options = do
    interactive <- liftIO ((&&) <$> hIsTerminalDevice stdin <*> hIsTerminalDevice stdout)
    if interactive
        then runPlayInteractive options
        else runPlayNonInteractive

runPlayInteractive :: PlayOptions -> Env.App ExitCode
runPlayInteractive options = do
    seed <- liftIO (resolvePlaySeed options)
    let sims = max 1 (simPerMove (playSims options))
    _ <-
        liftIO
            ( TuiPlay.runInteractivePlay
                (playBackend options)
                (playSide options)
                (playVs options)
                (playCacheDir options)
                (playRng options)
                seed
                (playMaxPlies options)
                sims
            )
    pure ExitSuccess

runPlayNonInteractive :: Env.App ExitCode
runPlayNonInteractive =
    liftIO
        ( outputLine
            ( "mcts play requires an interactive terminal. Run it from a TTY with "
                <> "`hostbootstrap run play`; use `mcts bench selfplay` or `mcts verify selfplay` "
                <> "for deliberate non-interactive game generation."
            )
        )
        >> pure (ExitFailure 1)

exitCodeToInt :: ExitCode -> Int
exitCodeToInt ExitSuccess = 0
exitCodeToInt (ExitFailure n) = n

resolvePlaySeed :: PlayOptions -> IO Word64
resolvePlaySeed options =
    case playSeed options of
        Just seed -> pure seed
        Nothing -> randomWord64

randomWord64 :: IO Word64
randomWord64 =
    withBinaryFile "/dev/urandom" ReadMode $ \handle -> do
        bytes <- ByteString.unpack <$> ByteString.hGet handle 8
        pure (foldl appendByte 0 bytes)
  where
    appendByte acc byte =
        (acc `shiftL` 8) .|. fromIntegral (byte :: Word8)
