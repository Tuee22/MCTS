-- | Manual `mcts-haskell-style` stanza. The supported path runs inside the
-- project container and requires pinned Fourmolu / HLint binaries under
-- `/opt/hostbootstrap/haskell-style/bin`. Host-level fallback is deliberately unsupported.
module Main where

import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import System.Directory
    ( doesDirectoryExist
    , doesFileExist
    , listDirectory
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import qualified System.Process as Process

main :: IO ()
main = do
    runStyleTool "fourmolu" ["--mode", "check", "app", "src", "test"]
    runHlint
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

runHlint :: IO ()
runHlint = do
    path <- styleToolPath "hlint"
    (code, out, err) <-
        Process.readProcessWithExitCode
            path
            ["--with-group=default", "--with-group=extra", "app", "src", "test"]
            ""
    case code of
        ExitSuccess -> pure ()
        ExitFailure n ->
            if hardHlintFailure out err
                then do
                    if null out then pure () else putStr out
                    if null err then pure () else putStr err
                    error ("hlint failed with exit " <> show n)
                else pure ()

hardHlintFailure :: String -> String -> Bool
hardHlintFailure out err =
    not (null err) || "Error:" `isInfixOf` out || "Error:" `isInfixOf` err

styleToolPath :: String -> IO FilePath
styleToolPath tool = do
    let pinned = "/opt/hostbootstrap/haskell-style/bin" </> tool
    pinnedExists <- doesFileExist pinned
    if pinnedExists
        then pure pinned
        else
            error
                ( "required pinned style tool is missing: "
                    <> pinned
                    <> "\nRun validation via `hostbootstrap run check-code`; host PATH fallback is not supported."
                )

runCabalFormatRoundTrip :: IO ()
runCabalFormatRoundTrip = withSystemTempDirectory "mcts-style" $ \tmpDir -> do
    original <- readFile "mcts.cabal"
    let cabalCopy = tmpDir </> "mcts.cabal"
    writeFile cabalCopy original
    code <- runProcess "cabal" ["format", cabalCopy]
    case code of
        ExitSuccess -> do
            formatted <- readFile cabalCopy
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
        partialHits =
            if supportedSourcePath path
                then forbiddenSymbolHits partialFunctionSymbols partialFunctionOwner path rows
                else []
    pure (tabs <> subprocessHits <> outputHits <> partialHits)

-- | Subprocess-boundary primitives are forbidden outside `MCTS.Subprocess`.
subprocessSymbols :: [String]
subprocessSymbols =
    [ "callProcess"
    , "readCreateProcess"
    , "readCreateProcessWithExitCode"
    , "createProcess"
    , "System.Process.proc"
    , "System.Process.shell"
    , "System.Process.Typed.proc"
    , "System.Process.Typed.shell"
    , "System.Process.Typed.runProcess"
    , "System.Process.Typed.readProcess"
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

-- | Partial functions are rejected on supported source paths. Tests may
-- still use list indexing for fixtures and assertions.
partialFunctionSymbols :: [String]
partialFunctionSymbols =
    [ "!!"
    , "head "
    , "tail "
    , "init "
    , "last "
    , "read "
    , "fromJust"
    , "fromLeft"
    , "fromRight"
    , "Prelude.head"
    , "Prelude.tail"
    , "Prelude.init"
    , "Prelude.last"
    , "Prelude.read"
    , "Data.List.!!"
    , "Data.Maybe.fromJust"
    , "Data.Either.fromLeft"
    , "Data.Either.fromRight"
    ]

partialFunctionOwner :: FilePath -> Bool
partialFunctionOwner _ = False

supportedSourcePath :: FilePath -> Bool
supportedSourcePath path =
    "./src/" `isPrefixOf` path || "./app/" `isPrefixOf` path

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
        , symbol `isInfixOf` stripStrings (stripComment row)
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

stripStrings :: String -> String
stripStrings = go False
  where
    go _ [] = []
    go True ('\\' : _ : rest) = "  " <> go True rest
    go inString ('"' : rest) = ' ' : go (not inString) rest
    go True (_ : rest) = ' ' : go True rest
    go False (ch : rest) = ch : go False rest

-- | Don't flag lines that look like `import …`, since enumerating
-- forbidden modules in an import isn't itself a use of the symbol.
isImportLine :: String -> Bool
isImportLine row = "import " `isPrefixOf` dropSpace row
  where
    dropSpace = dropWhile (\c -> c == ' ' || c == '\t')
