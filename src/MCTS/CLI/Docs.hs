module MCTS.CLI.Docs
    ( runDocs
    , generatedCommandsPath
    , generatedFiles
    , trackingGeneratedPaths
    , GeneratedSectionRule (..)
    , generatedSectionRules
    , spliceMarkerRegion
    , applyGeneratedSection
    , checkGeneratedSection
    ) where

import Data.List (isPrefixOf)
import MCTS.CLI.Command (DocsCommand (..))
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.CLI.Spec (renderCommandList, renderCommandMarkdown)
import MCTS.Error (AppError (..))
import MCTS.Plan (writePlanFile)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

generatedCommandsPath :: FilePath
generatedCommandsPath = "documents/cli/commands.md"

trackingGeneratedPaths :: [FilePath]
trackingGeneratedPaths = map fst generatedFiles

generatedFiles :: [(FilePath, String)]
generatedFiles =
    [ (generatedCommandsPath, renderCommandMarkdown)
    , ("share/man/man1/mcts.1", renderManpage)
    , ("share/completion/bash/mcts", renderBashCompletion)
    , ("share/completion/zsh/_mcts", renderZshCompletion)
    , ("share/completion/fish/mcts.fish", renderFishCompletion)
    ]

runDocs :: DocsCommand -> IO Int
runDocs command =
    case command of
        DocsCheck -> do
            result <- docsCheck
            case result of
                Right () -> outputLine "docs check PASS" >> pure 0
                Left err -> outputLine (renderError err) >> pure 1
        DocsGenerate dryRun planFile -> do
            let plan =
                    unlines $
                        ["write " <> path | (path, _) <- generatedFiles]
                            <> ["splice " <> sectionPath rule <> " " <> sectionKey rule | rule <- generatedSectionRules]
            writePlanFile planFile plan
            if dryRun
                then outputLine plan >> pure 0
                else do
                    mapM_ writeGenerated generatedFiles
                    mapM_ writeSection generatedSectionRules
                    outputLine plan
                    pure 0

-- | `mcts docs check` walks both the fully-generated path registry and
-- the marker-delimited section registry. First drift in either layer
-- short-circuits with `AppError DocsCheckDrift path key`.
docsCheck :: IO (Either AppError ())
docsCheck = do
    pathResult <- checkPaths generatedFiles
    case pathResult of
        Left err -> pure (Left err)
        Right () -> checkSections generatedSectionRules

checkPaths :: [(FilePath, String)] -> IO (Either AppError ())
checkPaths [] = pure (Right ())
checkPaths ((path, expected) : rest) = do
    exists <- doesFileExist path
    if not exists
        then pure (Left (DocsCheckDrift path "fully-generated"))
        else do
            actual <- readFile path
            if actual == expected
                then checkPaths rest
                else pure (Left (DocsCheckDrift path "fully-generated"))

checkSections :: [GeneratedSectionRule] -> IO (Either AppError ())
checkSections [] = pure (Right ())
checkSections (rule : rest) = do
    exists <- doesFileExist (sectionPath rule)
    if not exists
        then pure (Left (DocsCheckDrift (sectionPath rule) (sectionKey rule)))
        else do
            actual <- readFile (sectionPath rule)
            case checkGeneratedSection actual rule of
                Right () -> checkSections rest
                Left err -> pure (Left err)

writeSection :: GeneratedSectionRule -> IO ()
writeSection rule = do
    exists <- doesFileExist (sectionPath rule)
    if not exists
        then pure ()
        else do
            current <- readFile (sectionPath rule)
            case applyGeneratedSection current rule of
                Right rendered ->
                    if rendered == current
                        then pure ()
                        else writeFile (sectionPath rule) rendered
                Left _ -> pure ()

writeGenerated :: (FilePath, String) -> IO ()
writeGenerated (path, rendered) = do
    createDirectoryIfMissing True (takeDirectory path)
    writeFile path rendered

renderManpage :: String
renderManpage =
    unlines
        [ ".TH MCTS 1"
        , ".SH NAME"
        , "mcts \\- Monte Carlo Tree Search runtime"
        , ".SH SYNOPSIS"
        , ".B mcts"
        , "[command] [options]"
        , ".SH COMMANDS"
        , escapeMan (renderCommandList)
        ]

renderBashCompletion :: String
renderBashCompletion =
    unlines
        [ "_mcts_complete()"
        , "{"
        , "    local words=\"bench verify play inspect test lint docs commands help check-code build\""
        , "    COMPREPLY=( $(compgen -W \"$words\" -- \"${COMP_WORDS[COMP_CWORD]}\") )"
        , "}"
        , "complete -F _mcts_complete mcts"
        ]

renderZshCompletion :: String
renderZshCompletion =
    unlines
        [ "#compdef mcts"
        , "_arguments '1:command:(bench verify play inspect test lint docs commands help check-code build)' '*::arg:->args'"
        ]

renderFishCompletion :: String
renderFishCompletion =
    unlines
        [ "complete -c mcts -f -a 'bench verify play inspect test lint docs commands help check-code build'"
        ]

escapeMan :: String -> String
escapeMan =
    concatMap escapeChar
  where
    escapeChar '-' = "\\-"
    escapeChar ch = [ch]

-- ---------------------------------------------------------------------------
-- Generated section registry (marker-delimited regions)
--
-- A `GeneratedSectionRule` names a target file, a marker key, and a pure
-- renderer. The marker convention follows
-- [../HASKELL_CLI_TOOL.md → Generated Artifacts → Marker conventions](../../HASKELL_CLI_TOOL.md):
--   Markdown:  <!-- mcts:<key>:start --> ... <!-- mcts:<key>:end -->
--   Haskell:   // mcts:<key>:start ... // mcts:<key>:end (treat as raw)
--   YAML:      # mcts:<key>:start ... # mcts:<key>:end
--
-- `applyGeneratedSection` splices the renderer output between the marker
-- pair (idempotent); `checkGeneratedSection` compares the marker region's
-- on-disk slice to the renderer output and returns `Left DocsCheckDrift`
-- on mismatch. Three-element error message contract: file, marker key,
-- literal remedy `mcts docs generate`.
-- ---------------------------------------------------------------------------

data GeneratedSectionRule = GeneratedSectionRule
    { sectionPath :: !FilePath
    , sectionKey :: !String
    , sectionStartMarker :: !String
    , sectionEndMarker :: !String
    , sectionRender :: !String
    }

-- | The registry of marker-delimited generated regions. Currently empty
-- because every governed doc that consumes a `CommandSpec`-derived
-- rendering is in the fully-generated `generatedFiles` list (rules in
-- that list overwrite the whole file). Add an entry here when a
-- governed doc needs a marker-delimited region inside an
-- otherwise-hand-authored file.
generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules = []

-- | Pure splice: replace the slice between `start` and `end` markers
-- (inclusive of both marker lines) with `start <newline> renderer
-- <newline> end`. Idempotent.
spliceMarkerRegion :: String -> String -> String -> String -> Maybe String
spliceMarkerRegion start end body source =
    case findMarker start (lines source) of
        Nothing -> Nothing
        Just (beforeStart, startLine, afterStart) ->
            case findMarker end afterStart of
                Nothing -> Nothing
                Just (_inner, endLine, afterEnd) ->
                    let bodyLines = lines body
                     in Just
                            ( unlines
                                ( beforeStart
                                    <> [startLine]
                                    <> bodyLines
                                    <> [endLine]
                                    <> afterEnd
                                )
                            )
  where
    findMarker marker rows =
        case break (marker `isPrefixOf`) rows of
            (_, []) -> Nothing
            (pre, m : rest) -> Just (pre, m, rest)

-- | Apply one `GeneratedSectionRule`. Returns the new file contents on
-- success or `Left DocsCheckDrift` if the markers aren't found.
applyGeneratedSection :: String -> GeneratedSectionRule -> Either AppError String
applyGeneratedSection source rule =
    case spliceMarkerRegion (sectionStartMarker rule) (sectionEndMarker rule) (sectionRender rule) source of
        Just rendered -> Right rendered
        Nothing -> Left (DocsCheckDrift (sectionPath rule) (sectionKey rule))

-- | Check that the marker region's on-disk slice already matches the
-- renderer output. Returns `Left DocsCheckDrift` on mismatch.
checkGeneratedSection :: String -> GeneratedSectionRule -> Either AppError ()
checkGeneratedSection source rule =
    case applyGeneratedSection source rule of
        Left err -> Left err
        Right rendered ->
            if rendered == source
                then Right ()
                else Left (DocsCheckDrift (sectionPath rule) (sectionKey rule))
