module MCTS.CLI.Output
    ( OutputFormat (..)
    , ColorMode (..)
    , OutputOptions (..)
    , defaultOutputOptions
    , defaultOutputOptionsFor
    , parseGlobalOutputOptions
    , parseGlobalOutputOptionsIO
    , outputLine
    , errLine
    , renderError
    ) where

import qualified Data.Text as Text
import MCTS.Error (AppError)
import qualified MCTS.Error as Error
import System.IO (hIsTerminalDevice, hPutStrLn, stderr, stdout)

data OutputFormat = JsonFormat | TableFormat | PlainFormat
    deriving (Eq, Show)

data ColorMode = ColorAuto | ColorAlways | ColorNever
    deriving (Eq, Show)

data OutputOptions = OutputOptions
    { outputFormat :: !OutputFormat
    , outputColor :: !ColorMode
    }
    deriving (Eq, Show)

defaultOutputOptions :: OutputOptions
defaultOutputOptions = defaultOutputOptionsFor False

defaultOutputOptionsFor :: Bool -> OutputOptions
defaultOutputOptionsFor isTty =
    OutputOptions
        { outputFormat = if isTty then TableFormat else PlainFormat
        , outputColor = ColorAuto
        }

parseGlobalOutputOptions :: [String] -> (OutputOptions, [String])
parseGlobalOutputOptions = parseGlobalOutputOptionsWith defaultOutputOptions

parseGlobalOutputOptionsIO :: [String] -> IO (OutputOptions, [String])
parseGlobalOutputOptionsIO args = do
    isTty <- hIsTerminalDevice stdout
    pure (parseGlobalOutputOptionsWith (defaultOutputOptionsFor isTty) args)

parseGlobalOutputOptionsWith :: OutputOptions -> [String] -> (OutputOptions, [String])
parseGlobalOutputOptionsWith initial = go initial []
  where
    go opts kept args =
        case args of
            "--format" : value : rest -> go opts{outputFormat = parseFormat value} kept rest
            flag : rest
                | "--format=" `prefixOf` flag ->
                    go opts{outputFormat = parseFormat (drop (length "--format=") flag)} kept rest
            "--color" : value : rest -> go opts{outputColor = parseColor value} kept rest
            flag : rest
                | "--color=" `prefixOf` flag ->
                    go opts{outputColor = parseColor (drop (length "--color=") flag)} kept rest
            "--no-color" : rest -> go opts{outputColor = ColorNever} kept rest
            x : rest -> go opts (x : kept) rest
            [] -> (opts, reverse kept)

    parseFormat value =
        case value of
            "json" -> JsonFormat
            "table" -> TableFormat
            "plain" -> PlainFormat
            _ -> PlainFormat

    parseColor value =
        case value of
            "always" -> ColorAlways
            "never" -> ColorNever
            _ -> ColorAuto

prefixOf :: String -> String -> Bool
prefixOf prefix value = take (length prefix) value == prefix

outputLine :: String -> IO ()
outputLine = hPutStrLn stdout

errLine :: String -> IO ()
errLine = hPutStrLn stderr

renderError :: AppError -> String
renderError = Text.unpack . Error.renderError
