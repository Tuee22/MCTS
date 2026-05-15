module MCTS.Subprocess
    ( Subprocess (..)
    , ProcessOutput (..)
    , renderSubprocess
    , runStreaming
    , capture
    ) where

import qualified Data.ByteString.Lazy.Char8 as ByteString
import MCTS.Error (AppError (..))
import System.Exit (ExitCode (..))
import qualified System.Process.Typed as Process

{-# ANN module "HLint: ignore Use typed subprocess boundary" #-}

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
    code <- Process.runProcess (processConfig subprocess)
    pure $
        case code of
            ExitSuccess -> Right ExitSuccess
            ExitFailure n -> Left (SubprocessFailed (renderSubprocess subprocess) n)

capture :: Subprocess -> IO (Either AppError ProcessOutput)
capture subprocess = do
    (code, out, err) <- Process.readProcess (processConfig subprocess)
    pure $
        case code of
            ExitSuccess ->
                Right
                    ProcessOutput
                        { processStdout = ByteString.unpack out
                        , processStderr = ByteString.unpack err
                        , processExitCode = code
                        }
            ExitFailure n -> Left (SubprocessFailed (renderSubprocess subprocess <> "\n" <> ByteString.unpack err) n)

processConfig :: Subprocess -> Process.ProcessConfig () () ()
processConfig subprocess =
    withWorkingDirectory $
        withEnvironment $
            Process.proc (subprocessPath subprocess) (subprocessArguments subprocess)
  where
    withWorkingDirectory =
        case subprocessWorkingDirectory subprocess of
            Nothing -> id
            Just path -> Process.setWorkingDir path
    withEnvironment =
        case subprocessEnvironment subprocess of
            Nothing -> id
            Just env -> Process.setEnv env

shellQuote :: String -> String
shellQuote value
    | all safe value = value
    | otherwise = "'" <> concatMap quoteChar value <> "'"
  where
    safe ch = ch `elem` (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "-_./:=,+")
    quoteChar '\'' = "'\\''"
    quoteChar ch = [ch]
