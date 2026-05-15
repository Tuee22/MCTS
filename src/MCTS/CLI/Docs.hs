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

import MCTS.CLI.Command (DocsCommand (..))
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.Error (AppError (..))
import MCTS.Generated.Paths (generatedCommandsPath, generatedFiles, trackingGeneratedPaths)
import MCTS.Generated.Sections
    ( GeneratedSectionRule (..)
    , applyGeneratedSection
    , checkGeneratedSection
    , generatedSectionRules
    , spliceMarkerRegion
    )
import MCTS.Plan (writePlanFile)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

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
