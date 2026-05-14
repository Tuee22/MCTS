module MCTS.CLI.Output
    ( OutputFormat (..)
    , ColorMode (..)
    , OutputOptions (..)
    , defaultOutputOptions
    , parseGlobalOutputOptions
    , outputLine
    , errLine
    , renderError
    ) where

import MCTS.Error (renderError)
import System.IO (hPutStrLn, stderr, stdout)

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
defaultOutputOptions = OutputOptions PlainFormat ColorAuto

parseGlobalOutputOptions :: [String] -> (OutputOptions, [String])
parseGlobalOutputOptions = go defaultOutputOptions []
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
