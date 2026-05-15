-- | Manual `mcts-haskell-style` stanza. The supported path runs inside the
-- project container and requires pinned Fourmolu / HLint binaries from
-- `MCTS_STYLE_TOOLS_DIR`. Host-level fallback is deliberately unsupported.
module Main where

import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , listDirectory
    )
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import qualified System.Process as Process

main :: IO ()
main = do
    runStyleTool "fourmolu" ["--mode", "check", "app", "src", "test"]
    runStyleTool "hlint" ["--with-group=default", "--with-group=extra", "app", "src", "test"]
    runCabalFormatRoundTrip
    files <- walk "."
    problems <- fmap concat (mapM inspect files)
    if null problems
        then putStrLn "mcts-haskell-style PASS"
        else error (unlines problems)

runStyleTool :: String -> [String] -> IO ()
runStyleTool tool args = do
    path <- styleToolPath tool
    code <- runProcess path args
    case code of
        ExitSuccess -> pure ()
        ExitFailure n -> error (tool <> " failed with exit " <> show n)

styleToolPath :: String -> IO FilePath
styleToolPath tool = do
    toolsDir <- maybe "/opt/mcts-style-tools/bin" id <$> lookupEnv "MCTS_STYLE_TOOLS_DIR"
    let pinned = toolsDir </> tool
    pinnedExists <- doesFileExist pinned
    if pinnedExists
        then pure pinned
        else
            error
                ( "required pinned style tool is missing: "
                    <> pinned
                    <> "\nRun validation inside the project container via root compose.yaml; host PATH fallback is not supported."
                )

runCabalFormatRoundTrip :: IO ()
runCabalFormatRoundTrip = do
    createDirectoryIfMissing True ".build/mcts-style"
    original <- readFile "mcts.cabal"
    writeFile ".build/mcts-style/mcts.cabal" original
    code <- runProcess "cabal" ["format", ".build/mcts-style/mcts.cabal"]
    case code of
        ExitSuccess -> do
            formatted <- readFile ".build/mcts-style/mcts.cabal"
            if formatted == original
                then pure ()
                else error "cabal format drift: mcts.cabal does not round-trip byte-equally"
        ExitFailure n -> error ("cabal format failed with exit " <> show n)

runProcess :: FilePath -> [String] -> IO ExitCode
runProcess command args = do
    (code, out, err) <- Process.readProcessWithExitCode command args ""
    if null out then pure () else putStr out
    if null err then pure () else putStr err
    pure code

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
                            else pure [path | isFile && ".hs" `isSuffixOf` path]
            )
            names

ignored :: FilePath -> Bool
ignored path =
    any (`isPrefixOf` path) ["./.git", "./dist-newstyle", "./.mcts-cache", "./.build"]
        || "test/haskell-style/Main.hs" `isSuffixOf` path

inspect :: FilePath -> IO [String]
inspect path = do
    content <- readFile path
    let rows = zip [(1 :: Int) ..] (lines content)
        tabs =
            [ "tab character: " <> path <> ":" <> show n
            | (n, row) <- rows
            , '\t' `elem` row
            ]
        subprocessHits = forbiddenSymbolHits subprocessSymbols subprocessOwner path rows
        outputHits = forbiddenSymbolHits outputSymbols outputOwner path rows
    pure (tabs <> subprocessHits <> outputHits)

-- | Subprocess-boundary primitives are forbidden outside `MCTS.Subprocess`.
subprocessSymbols :: [String]
subprocessSymbols =
    [ "callProcess"
    , "readCreateProcess"
    , "readCreateProcessWithExitCode"
    , "createProcess"
    , "System.Process.proc"
    , "System.Process.shell"
    ]

subprocessOwner :: FilePath -> Bool
subprocessOwner path =
    "Subprocess.hs" `isSuffixOf` path

-- | Direct output primitives are forbidden outside `MCTS.CLI.Output`. We
-- only flag the unqualified `print`/`exitFailure` and `Data.Text.IO`
-- variants to avoid false positives on `putStrLn`-in-tests.
outputSymbols :: [String]
outputSymbols =
    [ "exitFailure"
    , "Data.Text.IO.putStrLn"
    , "Data.Text.IO.hPutStrLn"
    ]

outputOwner :: FilePath -> Bool
outputOwner path =
    "Output.hs" `isSuffixOf` path || "App.hs" `isSuffixOf` path

forbiddenSymbolHits
    :: [String]
    -> (FilePath -> Bool)
    -> FilePath
    -> [(Int, String)]
    -> [String]
forbiddenSymbolHits symbols isOwner path rows
    | isOwner path = []
    | otherwise =
        [ "forbidden symbol "
            <> symbol
            <> " at "
            <> path
            <> ":"
            <> show n
        | (n, row) <- rows
        , symbol <- symbols
        , symbol `isInfixOf` stripComment row
        , not (isImportLine row)
        ]

-- | Cheap: drop everything after a `--` comment so we don't flag
-- doctrine-pointer references in comments. Note that Haddock pragmas
-- starting with `{- ` survive; that's intentional — those are content,
-- not lint-suppressible.
stripComment :: String -> String
stripComment row =
    case findCommentStart row of
        Just i -> take i row
        Nothing -> row
  where
    findCommentStart input = go 0 input
    go _ [] = Nothing
    go i ('-' : '-' : _) = Just i
    go i (_ : rest) = go (i + 1) rest

-- | Don't flag lines that look like `import …`, since enumerating
-- forbidden modules in an import isn't itself a use of the symbol.
isImportLine :: String -> Bool
isImportLine row = "import " `isPrefixOf` dropSpace row
  where
    dropSpace = dropWhile (\c -> c == ' ' || c == '\t')
