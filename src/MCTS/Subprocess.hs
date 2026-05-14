module MCTS.Subprocess
    ( Subprocess (..)
    , ProcessOutput (..)
    , renderSubprocess
    , runStreaming
    , capture
    ) where

import MCTS.Error (AppError (..))
import System.Exit (ExitCode (..))
import qualified System.Process as Process

data Subprocess = Subprocess
    { subprocessPath :: !FilePath
    , subprocessArguments :: ![String]
    , subprocessEnvironment :: !(Maybe [(String, String)])
    , subprocessWorkingDirectory :: !(Maybe FilePath)
    }
    deriving (Eq, Show, Read)

data ProcessOutput = ProcessOutput
    { processStdout :: !String
    , processStderr :: !String
    , processExitCode :: !ExitCode
    }
    deriving (Eq, Show)

renderSubprocess :: Subprocess -> String
renderSubprocess subprocess =
    unwords (subprocessPath subprocess : map shellQuote (subprocessArguments subprocess))

runStreaming :: Subprocess -> IO (Either AppError ExitCode)
runStreaming subprocess = do
    let process =
            (Process.proc (subprocessPath subprocess) (subprocessArguments subprocess))
                { Process.cwd = subprocessWorkingDirectory subprocess
                , Process.env = subprocessEnvironment subprocess
                }
    code <- Process.withCreateProcess process $ \_ _ _ handle -> Process.waitForProcess handle
    pure $
        case code of
            ExitSuccess -> Right ExitSuccess
            ExitFailure n -> Left (SubprocessFailed (renderSubprocess subprocess) n)

capture :: Subprocess -> IO (Either AppError ProcessOutput)
capture subprocess = do
    let process =
            (Process.proc (subprocessPath subprocess) (subprocessArguments subprocess))
                { Process.cwd = subprocessWorkingDirectory subprocess
                , Process.env = subprocessEnvironment subprocess
                }
    (code, out, err) <- Process.readCreateProcessWithExitCode process ""
    pure $
        case code of
            ExitSuccess -> Right ProcessOutput{processStdout = out, processStderr = err, processExitCode = code}
            ExitFailure n -> Left (SubprocessFailed (renderSubprocess subprocess <> "\n" <> err) n)

shellQuote :: String -> String
shellQuote value
    | all safe value = value
    | otherwise = "'" <> concatMap quoteChar value <> "'"
  where
    safe ch = ch `elem` (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "-_./:=,+")
    quoteChar '\'' = "'\\''"
    quoteChar ch = [ch]
