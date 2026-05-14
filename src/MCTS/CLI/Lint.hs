module MCTS.CLI.Lint
    ( runLint
    , lintFiles
    ) where

import Data.List (isPrefixOf, isSuffixOf)
import MCTS.CLI.Command (DocsCommand (..), LintCommand (..))
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.Subprocess (Subprocess (..), runStreaming)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

runLint :: LintCommand -> IO Int
runLint command =
    case command of
        LintFiles _ -> report "files" =<< lintFiles
        LintDocs _ -> runDocs DocsCheck
        LintHaskell _ -> runStyleStanza
        LintAll -> do
            a <- runLint (LintFiles False)
            b <- runLint (LintDocs False)
            c <- runLint (LintHaskell False)
            pure (maximum [a, b, c])
  where
    report label problems =
        if null problems
            then outputLine (label <> " lint PASS") >> pure 0
            else outputLine (unlines problems) >> pure 1

runStyleStanza :: IO Int
runStyleStanza = do
    result <- runStreaming (Subprocess "cabal" ["test", "mcts-haskell-style"] Nothing Nothing)
    case result of
        Right _ -> outputLine "haskell lint PASS" >> pure 0
        Left err -> outputLine (renderError err) >> pure 1

lintFiles :: IO [String]
lintFiles = do
    forbidden <- filterMPath exists forbiddenPaths
    files <- walk "."
    trailing <- fmap concat (mapM trailingProblems files)
    pure (map ("forbidden path exists: " <>) forbidden <> trailing)

forbiddenPaths :: [FilePath]
forbiddenPaths =
    [ ".github/workflows"
    , ".husky"
    , ".githooks"
    , ".pre-commit-config.yaml"
    , "Makefile"
    , "justfile"
    , "Taskfile.yml"
    ]

exists :: FilePath -> IO Bool
exists path = (||) <$> doesFileExist path <*> doesDirectoryExist path

filterMPath :: (a -> IO Bool) -> [a] -> IO [a]
filterMPath predicate = go
  where
    go [] = pure []
    go (x : xs) = do
        ok <- predicate x
        rest <- go xs
        pure (if ok then x : rest else rest)

walk :: FilePath -> IO [FilePath]
walk root = do
    names <- listDirectory root
    fmap concat $
        mapM
            ( \name -> do
                let path = root </> name
                isDir <- doesDirectoryExist path
                isFile <- doesFileExist path
                if ignored path
                    then pure []
                    else
                        if isDir
                            then walk path
                            else pure [path | isFile && sourceLike path]
            )
            names

ignored :: FilePath -> Bool
ignored path =
    any (`isPrefixOf` path) ["./.git", "./dist-newstyle", "./.mcts-cache", "./cpp-legacy/build", "./rust/target"]

sourceLike :: FilePath -> Bool
sourceLike path =
    any (`isSuffixOf` path) [".hs", ".md", ".cabal", ".yaml", ".yml", ".toml", ".rs", ".cc", ".h", ".hpp", ".cpp"]

trailingProblems :: FilePath -> IO [String]
trailingProblems path = do
    content <- readFile path
    let rows = zip [(1 :: Int) ..] (lines content)
        trailing = ["trailing whitespace: " <> path <> ":" <> show n | (n, row) <- rows, hasTrailing row]
        finalNewline =
            if null content || last content == '\n'
                then []
                else ["missing final newline: " <> path]
    pure (trailing <> finalNewline)

hasTrailing :: String -> Bool
hasTrailing [] = False
hasTrailing value = last value == ' ' || last value == '\t'
