module MCTS.Generated.Sections
    ( GeneratedSectionRule (..)
    , generatedSectionRules
    , spliceMarkerRegion
    , applyGeneratedSection
    , checkGeneratedSection
    ) where

import Data.List (isPrefixOf)
import MCTS.Error (AppError (..))

data GeneratedSectionRule = GeneratedSectionRule
    { sectionPath :: !FilePath
    , sectionKey :: !String
    , sectionStartMarker :: !String
    , sectionEndMarker :: !String
    , sectionRender :: !String
    }

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules = []

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

applyGeneratedSection :: String -> GeneratedSectionRule -> Either AppError String
applyGeneratedSection source rule =
    case spliceMarkerRegion (sectionStartMarker rule) (sectionEndMarker rule) (sectionRender rule) source of
        Just rendered -> Right rendered
        Nothing -> Left (DocsCheckDrift (sectionPath rule) (sectionKey rule))

checkGeneratedSection :: String -> GeneratedSectionRule -> Either AppError ()
checkGeneratedSection source rule =
    case applyGeneratedSection source rule of
        Left err -> Left err
        Right rendered ->
            if rendered == source
                then Right ()
                else Left (DocsCheckDrift (sectionPath rule) (sectionKey rule))
