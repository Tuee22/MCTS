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

import Control.Exception (evaluate)
import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (DocsCommand (..))
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
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
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)

runDocs :: DocsCommand -> Env.App ExitCode
runDocs command = do
    env <- Env.askEnv
    let output = Env.envOutputOptions env
    case command of
        DocsCheck -> do
            result <- liftIO docsCheck
            case result of
                Right () -> liftIO (outputLine "docs check PASS") >> pure ExitSuccess
                Left err -> liftIO (outputLine (renderErrorString output err)) >> pure (ExitFailure 1)
        DocsGenerate dryRun planFile -> do
            let plan =
                    unlines $
                        ["write " <> path | (path, _) <- generatedFiles]
                            <> ["splice " <> sectionPath rule <> " " <> sectionKey rule | rule <- generatedSectionRules]
            liftIO (writePlanFile planFile plan)
            if dryRun
                then liftIO (outputLine plan) >> pure ExitSuccess
                else do
                    liftIO (mapM_ writeGenerated generatedFiles)
                    liftIO (mapM_ writeSection generatedSectionRules)
                    liftIO (outputLine plan)
                    pure ExitSuccess

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
            actual <- readFileStrict path
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
            actual <- readFileStrict (sectionPath rule)
            case checkGeneratedSection actual rule of
                Right () -> checkSections rest
                Left err -> pure (Left err)

writeSection :: GeneratedSectionRule -> IO ()
writeSection rule = do
    exists <- doesFileExist (sectionPath rule)
    if not exists
        then pure ()
        else do
            current <- readFileStrict (sectionPath rule)
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

readFileStrict :: FilePath -> IO String
readFileStrict path = do
    content <- readFile path
    _ <- evaluate (length content)
    pure content
