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
import Data.List (find, nub, sort)
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
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))

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
        Right () -> do
            metadataResult <- checkGeneratedSectionMetadata generatedSectionRules
            case metadataResult of
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

checkGeneratedSectionMetadata :: [GeneratedSectionRule] -> IO (Either AppError ())
checkGeneratedSectionMetadata rules = do
    metadataFiles <- markdownFilesWithGeneratedMetadata "."
    let paths = sort (nub (map sectionPath rules <> metadataFiles))
    checkMetadataPaths paths
  where
    checkMetadataPaths [] = pure (Right ())
    checkMetadataPaths (path : rest) = do
        exists <- doesFileExist path
        if not exists
            then pure (Left (DocsCheckDrift path "generated-section-metadata"))
            else do
                source <- readFileStrict path
                case checkMetadataForPath path source rules of
                    Left err -> pure (Left err)
                    Right () -> checkMetadataPaths rest

checkMetadataForPath :: FilePath -> String -> [GeneratedSectionRule] -> Either AppError ()
checkMetadataForPath path source rules = do
    declared <- declaredGeneratedSections path source
    physical <- physicalGeneratedSectionKeys path source
    let registered = sort [sectionKey rule | rule <- rules, sectionPath rule == path]
        declaredSorted = sort declared
        physicalSorted = sort physical
    if declaredSorted /= registered
        then Left (DocsCheckDrift path "generated-section-metadata")
        else
            if physicalSorted /= registered
                then Left (DocsCheckDrift path "generated-section-markers")
                else Right ()

declaredGeneratedSections :: FilePath -> String -> Either AppError [String]
declaredGeneratedSections path source =
    case find (generatedSectionsPrefix `starts`) (markdownContentLines source) of
        Nothing -> Right []
        Just row ->
            let value = trim (drop (length generatedSectionsPrefix) row)
             in case value of
                    "none" -> Right []
                    "" -> Left (DocsCheckDrift path "generated-section-metadata")
                    _ -> Right (map trim (splitCommas value))

physicalGeneratedSectionKeys :: FilePath -> String -> Either AppError [String]
physicalGeneratedSectionKeys path source =
    if all paired allKeys
        then Right allKeys
        else Left (DocsCheckDrift path "generated-section-markers")
  where
    markers = [marker | row <- markdownContentLines source, Just marker <- [generatedMarker row]]
    startKeys = [key | (key, MarkerStart) <- markers]
    endKeys = [key | (key, MarkerEnd) <- markers]
    allKeys = sort (nub (startKeys <> endKeys))
    paired key = key `elem` startKeys && key `elem` endKeys

data MarkerKind = MarkerStart | MarkerEnd
    deriving (Eq)

generatedMarker :: String -> Maybe (String, MarkerKind)
generatedMarker raw =
    let row = trim raw
        prefix = "<!-- mcts:"
        startSuffix = ":start -->"
        endSuffix = ":end -->"
     in case stripPrefixLocal prefix row of
            Nothing -> Nothing
            Just rest ->
                case stripSuffixLocal startSuffix rest of
                    Just key -> Just (key, MarkerStart)
                    Nothing ->
                        case stripSuffixLocal endSuffix rest of
                            Just key -> Just (key, MarkerEnd)
                            Nothing -> Nothing

markdownFilesWithGeneratedMetadata :: FilePath -> IO [FilePath]
markdownFilesWithGeneratedMetadata root = do
    files <- markdownFiles root
    filterM hasMetadata files
  where
    hasMetadata path = do
        source <- readFileStrict path
        pure (any (generatedSectionsPrefix `starts`) (markdownContentLines source))

markdownContentLines :: String -> [String]
markdownContentLines = go False . lines
  where
    go _ [] = []
    go inFence (row : rest)
        | "```" `starts` trim row = go (not inFence) rest
        | inFence = go inFence rest
        | otherwise = row : go inFence rest

markdownFiles :: FilePath -> IO [FilePath]
markdownFiles root = do
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
                            then markdownFiles path
                            else pure [rendered | isFile && ".md" `ends` path]
            )
            names

ignored :: FilePath -> Bool
ignored path =
    any
        (`starts` path)
        ["./.git", "./dist-newstyle", "./.mcts-cache", "./.build", "./cpp-legacy/build", "./rust/target"]

dropDotSlash :: FilePath -> FilePath
dropDotSlash ('.' : '/' : rest) = rest
dropDotSlash path = path

generatedSectionsPrefix :: String
generatedSectionsPrefix = "**Generated sections**:"

splitCommas :: String -> [String]
splitCommas value =
    case break (== ',') value of
        (prefix, []) -> [prefix]
        (prefix, _ : rest) -> prefix : splitCommas rest

trim :: String -> String
trim = dropWhile isSpaceLocal . reverse . dropWhile isSpaceLocal . reverse

isSpaceLocal :: Char -> Bool
isSpaceLocal ch = ch == ' ' || ch == '\t'

starts :: String -> String -> Bool
starts prefix value = take (length prefix) value == prefix

ends :: String -> String -> Bool
ends suffix value = suffix == drop (length value - length suffix) value

stripPrefixLocal :: String -> String -> Maybe String
stripPrefixLocal prefix value =
    if prefix `starts` value
        then Just (drop (length prefix) value)
        else Nothing

stripSuffixLocal :: String -> String -> Maybe String
stripSuffixLocal suffix value =
    if suffix `ends` value
        then Just (take (length value - length suffix) value)
        else Nothing

filterM :: (a -> IO Bool) -> [a] -> IO [a]
filterM predicate = go
  where
    go [] = pure []
    go (value : rest) = do
        keep <- predicate value
        tailValues <- go rest
        pure (if keep then value : tailValues else tailValues)

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
