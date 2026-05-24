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
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))

runLint :: LintCommand -> Env.App ExitCode
runLint command =
    case command of
        LintFiles write -> do
            if write then liftIO fixLintFiles else pure ()
            report "files" =<< liftIO lintFiles
        LintDocs write ->
            if write
                then do
                    code <- runDocs (DocsGenerate False Nothing)
                    if code == ExitSuccess then runDocs DocsCheck else pure code
                else runDocs DocsCheck
        LintHaskell write -> do
            code <- if write then runStyleWrite else pure ExitSuccess
            if code == ExitSuccess then runStyleStanza else pure code
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

runStyleWrite :: Env.App ExitCode
runStyleWrite = do
    env <- Env.askEnv
    formatCode <-
        liftIO
            ( runStreaming
                ( Subprocess
                    "/opt/mcts-style-tools/bin/fourmolu"
                    ["--mode", "inplace", "app", "src", "test"]
                    Nothing
                    Nothing
                )
            )
    case formatCode of
        Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)
        Right code
            | code /= ExitSuccess -> pure code
            | otherwise -> do
                cabalCode <- liftIO (runStreaming (Subprocess "cabal" ["format", "mcts.cabal"] Nothing Nothing))
                case cabalCode of
                    Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)
                    Right code' -> pure code'

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

fixLintFiles :: IO ()
fixLintFiles = do
    files <- walk "."
    mapM_ fixTrailingFile files
    mapM_ writeGeneratedFile generatedFiles

fixTrailingFile :: FilePath -> IO ()
fixTrailingFile path = do
    content <- readFile path
    let fixed =
            if null content
                then content
                else unlines (map stripTrailing (lines content))
    if fixed == content then pure () else writeFile path fixed

stripTrailing :: String -> String
stripTrailing = reverse . dropWhile isTrailingSpace . reverse
  where
    isTrailingSpace ch = ch == ' ' || ch == '\t'

writeGeneratedFile :: (FilePath, String) -> IO ()
writeGeneratedFile (path, rendered) = do
    createDirectoryIfMissing True (takeDirectory path)
    writeFile path rendered

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
    , ForbiddenPath
        ".build"
        "Host-level .build/ is unsupported; build artefacts live inside the Compose-built container image"
    , ForbiddenPath
        "bootstrap"
        "Bootstrap directories invite host-side orchestration; project work enters through docker compose run --rm mcts mcts <command>"
    , ForbiddenPath
        "*.sh"
        "Shell-script wrappers duplicate the mcts command surface and bypass the Compose-only doctrine"
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
            names <- allPaths "."
            pure
                [ name
                | name <- names
                , prefix `isPrefixOf` name
                , suffix `isSuffixOf` name
                ]

allPaths :: FilePath -> IO [FilePath]
allPaths root = do
    names <- listDirectory root
    fmap concat $
        mapM
            ( \name -> do
                let path = root </> name
                    rendered = dropDotSlash path
                isDir <- doesDirectoryExist path
                isFile <- doesFileExist path
                if ignored path
                    then pure []
                    else
                        if isDir
                            then (rendered :) <$> allPaths path
                            else pure [rendered | isFile]
            )
            names

dropDotSlash :: FilePath -> FilePath
dropDotSlash ('.' : '/' : rest) = rest
dropDotSlash path = path

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
            if null content || endsWithNewline content
                then []
                else ["missing final newline: " <> path]
    pure (trailing <> finalNewline)

endsWithNewline :: String -> Bool
endsWithNewline [] = False
endsWithNewline [ch] = ch == '\n'
endsWithNewline (_ : rest) = endsWithNewline rest

hasTrailing :: String -> Bool
hasTrailing [] = False
hasTrailing [ch] = ch == ' ' || ch == '\t'
hasTrailing (_ : rest) = hasTrailing rest

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
