module MCTS.Generated.Sections
    ( GeneratedSectionRule (..)
    , generatedSectionRules
    , spliceMarkerRegion
    , applyGeneratedSection
    , checkGeneratedSection
    ) where

import Data.List (isPrefixOf)
import MCTS.CLI.Spec (CommandSpec (..), commandRows)
import MCTS.Error (AppError (..))

data GeneratedSectionRule = GeneratedSectionRule
    { sectionPath :: !FilePath
    , sectionKey :: !String
    , sectionStartMarker :: !String
    , sectionEndMarker :: !String
    , sectionOwner :: !String
    , sectionRender :: !String
    }

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules =
    [ GeneratedSectionRule
        { sectionPath = "documents/engineering/cli_command_surface.md"
        , sectionKey = "command-matrix"
        , sectionStartMarker = "<!-- mcts:command-matrix:start -->"
        , sectionEndMarker = "<!-- mcts:command-matrix:end -->"
        , sectionOwner = "MCTS.Generated.Sections.renderCommandMatrix"
        , sectionRender = renderCommandMatrix
        }
    ]

renderCommandMatrix :: String
renderCommandMatrix =
    unlines $
        [ "| Command | Purpose |"
        , "|---------|---------|"
        ]
            <> map renderRow commandRows
  where
    renderRow (path, spec) =
        "| `" <> renderCommandCell path <> "` | " <> renderPurpose path spec <> " |"

renderCommandCell :: String -> String
renderCommandCell path =
    case path of
        "mcts bench rollouts" -> path <> " [opts]"
        "mcts bench selfplay" -> path <> " [opts]"
        "mcts verify rollouts" -> path <> " [opts]"
        "mcts verify selfplay" -> path <> " [opts]"
        "mcts verify legacy-parity" -> path <> " {rollouts\\|selfplay} [opts]"
        "mcts play" -> path <> " [opts]"
        "mcts inspect show" -> path <> " <hash-prefix> [opts]"
        "mcts inspect replay" -> path <> " <hash-prefix> [opts]"
        "mcts inspect cache prune" -> path <> " [--keep-current] [--dry-run] [--plan-file <path>]"
        "mcts inspect divergence" -> path <> " <hash-prefix>"
        "mcts test all" -> path <> " [--dry-run] [--plan-file <path>]"
        "mcts lint files" -> path <> " [--write]"
        "mcts lint docs" -> path <> " [--write]"
        "mcts lint haskell" -> path <> " [--write]"
        "mcts docs generate" -> path <> " [--dry-run] [--plan-file <path>]"
        "mcts commands" -> path <> " [--tree\\|--json]"
        "mcts help" -> path <> " <subcommand>"
        "mcts build cpp-legacy" -> path <> " [--dry-run] [--plan-file <path>]"
        "mcts build cpp-imperative" -> path <> " [--dry-run] [--plan-file <path>]"
        "mcts build cpp-functional" -> path <> " [--dry-run] [--plan-file <path>]"
        "mcts build rust" -> path <> " [--dry-run] [--plan-file <path>]"
        _ -> path

renderPurpose :: String -> CommandSpec -> String
renderPurpose path spec =
    case path of
        "mcts bench rollouts" -> "Random-rollouts benchmark across the requested backend cohort"
        "mcts bench selfplay" -> "Self-play benchmark across the requested backend cohort"
        "mcts verify rollouts" -> "Round-robin visit-count equality across `(ii)..(v)` under `--rng cpp`"
        "mcts verify selfplay" -> "Round-robin self-play visit-count equality across `(ii)..(v)`"
        "mcts verify legacy-parity" -> "5-backend round-robin under the legacy parity envelope"
        "mcts play" -> "Interactive `brick` TUI; human vs AI or AI vs AI spectate"
        "mcts inspect list" -> "Non-interactive enumeration of the local transcript cache"
        "mcts inspect show" -> "Non-interactive transcript dump in legacy notation"
        "mcts inspect replay" -> "Interactive `brick` TUI for forward/back navigation with multi-backend equity overlay"
        "mcts inspect cache list" -> "Enumerate equity-sidecar entries per transcript"
        "mcts inspect cache prune" -> "Delete stale equity-sidecar entries"
        "mcts inspect divergence" -> "Emit the cross-backend divergence-rate matrix for a single transcript"
        "mcts test all" -> "Plan/Apply: every Cabal stanza plus pinned report card"
        "mcts test <stanza>" -> "Run a named Cabal test-suite stanza"
        "mcts lint files" -> "Check whitespace, final newlines, forbidden paths, and tracked generated-file drift"
        "mcts lint docs" -> "Run the generated-docs drift gate"
        "mcts lint haskell" -> "Run Fourmolu, HLint, and the Cabal-format round trip"
        "mcts lint all" -> "Run every lint gate"
        "mcts docs check" -> "Compare rendered output against on-disk markers and tracked paths"
        "mcts docs generate" -> "Splice rendered output into markers and write tracked generated paths"
        "mcts commands" -> "Flat, tree, or JSON rendering of the command registry"
        "mcts help" -> "Focused help; equivalent to `<subcommand> --help`"
        "mcts check-code" -> "Doctrine alignment, formatter, HLint, warning-clean build, docs check"
        "mcts build cpp-legacy" -> "Plan/Apply: legacy C++ backend build harness"
        "mcts build cpp-imperative" -> "Plan/Apply: imperative C++ backend build harness"
        "mcts build cpp-functional" -> "Plan/Apply: functional C++ backend build harness"
        "mcts build rust" -> "Plan/Apply: Rust backend build harness"
        _ -> summary spec

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
