module MCTS.CLI.Lint
    ( runLint
    , lintFiles
    , ForbiddenPath (..)
    , forbiddenPathRegistry
    , forbiddenPathPaths
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.List (isPrefixOf, isSuffixOf)
import MCTS.CLI.Command (DocsCommand (..), LintCommand (..))
import MCTS.CLI.Docs (runDocs)
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Generated.Paths (generatedFiles)
import MCTS.Subprocess (Subprocess (..), runStreaming)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

runLint :: LintCommand -> Env.App ExitCode
runLint command =
    case command of
        LintFiles _ -> report "files" =<< liftIO lintFiles
        LintDocs _ -> runDocs DocsCheck
        LintHaskell _ -> runStyleStanza
        LintAll -> do
            a <- runLint (LintFiles False)
            b <- runLint (LintDocs False)
            c <- runLint (LintHaskell False)
            pure (maxExitCode [a, b, c])
  where
    report label problems =
        if null problems
            then liftIO (outputLine (label <> " lint PASS")) >> pure ExitSuccess
            else liftIO (outputLine (unlines problems)) >> pure (ExitFailure 1)

runStyleStanza :: Env.App ExitCode
runStyleStanza = do
    env <- Env.askEnv
    result <- liftIO (runStreaming (Subprocess "cabal" ["test", "mcts-haskell-style"] Nothing Nothing))
    case result of
        Right _ -> liftIO (outputLine "haskell lint PASS") >> pure ExitSuccess
        Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)

maxExitCode :: [ExitCode] -> ExitCode
maxExitCode codes =
    if all (== ExitSuccess) codes
        then ExitSuccess
        else ExitFailure 1

lintFiles :: IO [String]
lintFiles = do
    forbidden <- forbiddenPathHits forbiddenPathRegistry
    files <- walk "."
    trailing <- fmap concat (mapM trailingProblems files)
    generated <- generatedDriftProblems
    pure (map ("forbidden path exists: " <>) forbidden <> trailing <> generated)

-- | A doctrine-forbidden path. Each entry records why it's forbidden so
-- a future operator-facing error message can cite the rationale rather
-- than just the offending path.
data ForbiddenPath = ForbiddenPath
    { forbiddenPath :: !FilePath
    , forbiddenReason :: !String
    }
    deriving (Eq, Show)

-- | The doctrine-pinned forbidden-path registry per
-- [../../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../../HASKELL_CLI_TOOL.md).
forbiddenPathRegistry :: [ForbiddenPath]
forbiddenPathRegistry =
    [ ForbiddenPath
        ".github/workflows"
        "CI workflow definitions live outside this repo; the doctrine binds the local lint stack to mcts check-code"
    , ForbiddenPath
        ".husky"
        "Husky-style hooks duplicate the local mcts check-code surface and tend to drift"
    , ForbiddenPath ".githooks" "Git hooks duplicate the local mcts check-code surface and tend to drift"
    , ForbiddenPath ".pre-commit-config.yaml" "pre-commit duplicates the local mcts check-code surface"
    , ForbiddenPath
        "pre-commit-*.yaml"
        "pre-commit YAML shims duplicate the local mcts check-code surface"
    , ForbiddenPath
        "Makefile"
        "Top-level Makefile competes with mcts build/test; backends keep their own per-backend Makefile under cpp-*/"
    , ForbiddenPath "justfile" "Justfile duplicates mcts test/lint commands"
    , ForbiddenPath "Taskfile.yml" "Taskfile duplicates mcts test/lint commands"
    ]

forbiddenPathPaths :: [FilePath]
forbiddenPathPaths = map forbiddenPath forbiddenPathRegistry

exists :: FilePath -> IO Bool
exists path = (||) <$> doesFileExist path <*> doesDirectoryExist path

forbiddenPathHits :: [ForbiddenPath] -> IO [FilePath]
forbiddenPathHits = fmap concat . mapM hits
  where
    hits entry
        | '*' `elem` forbiddenPath entry = globMatches (forbiddenPath entry)
        | otherwise = do
            present <- exists (forbiddenPath entry)
            pure [forbiddenPath entry | present]

globMatches :: FilePath -> IO [FilePath]
globMatches patternText =
    case break (== '*') patternText of
        (_, "") -> pure []
        (prefix, _ : suffix) -> do
            names <- listDirectory "."
            pure
                [ name
                | name <- names
                , prefix `isPrefixOf` name
                , suffix `isSuffixOf` name
                ]

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
    any
        (`isPrefixOf` path)
        ["./.git", "./dist-newstyle", "./.mcts-cache", "./.build", "./cpp-legacy/build", "./rust/target"]

sourceLike :: FilePath -> Bool
sourceLike path =
    any
        (`isSuffixOf` path)
        [".hs", ".md", ".cabal", ".yaml", ".yml", ".toml", ".rs", ".cc", ".h", ".hpp", ".cpp"]

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

generatedDriftProblems :: IO [String]
generatedDriftProblems =
    fmap concat $
        mapM
            ( \(path, expected) -> do
                fileExists <- doesFileExist path
                if not fileExists
                    then pure ["generated file missing: " <> path]
                    else do
                        actual <- readFile path
                        pure ["generated file drift: " <> path | actual /= expected]
            )
            generatedFiles
