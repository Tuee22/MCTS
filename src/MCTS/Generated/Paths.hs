module MCTS.Generated.Paths
    ( generatedCommandsPath
    , generatedFiles
    , trackingGeneratedPaths
    , externallyTrackedPaths
    ) where

import Data.List (intercalate)
import MCTS.CLI.Spec
    ( ChoiceSpec
    , backendChoices
    , buildTargetChoices
    , choiceTokens
    , colorModeChoices
    , commandRows
    , outputFormatChoices
    , renderChoiceSummary
    , renderCommandList
    , renderCommandMarkdown
    , rngChoices
    , sideChoices
    , testStanzaChoices
    , threadingChoices
    , verifyBackendChoices
    )

generatedCommandsPath :: FilePath
generatedCommandsPath = "documents/cli/commands.md"

-- | Generated-or-tracked paths covered by `mcts lint files`. The
-- in-tree renderer set comes from `generatedFiles`; validation data is
-- deliberately excluded so clean-clone tests never depend on committed
-- generated fixtures.
trackingGeneratedPaths :: [FilePath]
trackingGeneratedPaths = map fst generatedFiles <> externallyTrackedPaths

-- | Paths whose contents are produced out-of-band (no Haskell renderer
-- module). Legacy evidence is now an explicit operator-generated
-- artifact outside normal validation, so this registry is empty.
externallyTrackedPaths :: [FilePath]
externallyTrackedPaths = []

generatedFiles :: [(FilePath, String)]
generatedFiles =
    [ (generatedCommandsPath, renderCommandMarkdown)
    , ("share/man/man1/mcts.1", renderManpage)
    , ("share/completion/bash/mcts", renderBashCompletion)
    , ("share/completion/zsh/_mcts", renderZshCompletion)
    , ("share/completion/fish/mcts.fish", renderFishCompletion)
    ]

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
        ]
        <> escapeMan renderCommandList
        <> unlines
            [ ".SH COMMON VALUE SETS"
            , ".SS Backends"
            , escapeMan (renderChoiceSummary backendChoices)
            , ".SS Q3 verify backends"
            , escapeMan (renderChoiceSummary verifyBackendChoices)
            , ".SS RNG sources"
            , escapeMan (renderChoiceSummary rngChoices)
            , ".SS Sides"
            , escapeMan (renderChoiceSummary sideChoices)
            , ".SS Threading"
            , escapeMan (renderChoiceSummary threadingChoices)
            , ".SS Output formats"
            , escapeMan (renderChoiceSummary outputFormatChoices)
            , ".SS Color modes"
            , escapeMan (renderChoiceSummary colorModeChoices)
            ]

renderBashCompletion :: String
renderBashCompletion =
    unlines
        [ "_mcts_complete()"
        , "{"
        , "    local cur prev words"
        , "    cur=\"${COMP_WORDS[COMP_CWORD]}\""
        , "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\""
        , "    case \"$prev\" in"
        , "        --backend|--vs|BASELINE|CANDIDATE)"
        , "            words=\"" <> completionWords backendChoices <> "\""
        , "            ;;"
        , "        --rng)"
        , "            words=\"" <> completionWords rngChoices <> "\""
        , "            ;;"
        , "        --side)"
        , "            words=\"" <> completionWords sideChoices <> "\""
        , "            ;;"
        , "        --threading)"
        , "            words=\"" <> completionWords threadingChoices <> "\""
        , "            ;;"
        , "        --format)"
        , "            words=\"" <> completionWords outputFormatChoices <> "\""
        , "            ;;"
        , "        --color)"
        , "            words=\"" <> completionWords colorModeChoices <> "\""
        , "            ;;"
        , "        *)"
        , "            words=\"" <> topLevelWords <> " " <> leafTailWords <> "\""
        , "            ;;"
        , "    esac"
        , "    COMPREPLY=( $(compgen -W \"$words\" -- \"$cur\") )"
        , "}"
        , "complete -F _mcts_complete mcts"
        ]

renderZshCompletion :: String
renderZshCompletion =
    unlines
        [ "#compdef mcts"
        , "_arguments \\"
        , "  '1:command:(" <> zshWords topLevelCommandNames <> ")' \\"
        , "  '--backend[backend or comma-separated backend list]:backend:("
            <> zshWords (choiceTokens backendChoices)
            <> ")' \\"
        , "  '--vs[opponent backend]:backend:(" <> zshWords (choiceTokens backendChoices) <> ")' \\"
        , "  '--rng[RNG source]:rng:(" <> zshWords (choiceTokens rngChoices) <> ")' \\"
        , "  '--side[controlled side]:side:(" <> zshWords (choiceTokens sideChoices) <> ")' \\"
        , "  '--threading[threading mode]:threading:(" <> zshWords (choiceTokens threadingChoices) <> ")' \\"
        , "  '--format[output format]:format:(" <> zshWords (choiceTokens outputFormatChoices) <> ")' \\"
        , "  '--color[color mode]:color:(" <> zshWords (choiceTokens colorModeChoices) <> ")' \\"
        , "  '*::arg:->args'"
        ]

renderFishCompletion :: String
renderFishCompletion =
    unlines
        [ "complete -c mcts -f -a '" <> completionWordsRaw topLevelCommandNames <> "'"
        , "complete -c mcts -l backend -x -a '" <> completionWords backendChoices <> "'"
        , "complete -c mcts -l vs -x -a '" <> completionWords backendChoices <> "'"
        , "complete -c mcts -l rng -x -a '" <> completionWords rngChoices <> "'"
        , "complete -c mcts -l side -x -a '" <> completionWords sideChoices <> "'"
        , "complete -c mcts -l threading -x -a '" <> completionWords threadingChoices <> "'"
        , "complete -c mcts -l format -x -a '" <> completionWords outputFormatChoices <> "'"
        , "complete -c mcts -l color -x -a '" <> completionWords colorModeChoices <> "'"
        , "complete -c mcts -n '__fish_seen_subcommand_from build' -a '"
            <> completionWords buildTargetChoices
            <> "'"
        , "complete -c mcts -n '__fish_seen_subcommand_from test' -a '"
            <> completionWords testStanzaChoices
            <> "'"
        ]

topLevelCommandNames :: [String]
topLevelCommandNames =
    [ "bench"
    , "verify"
    , "play"
    , "inspect"
    , "test"
    , "lint"
    , "docs"
    , "commands"
    , "help"
    , "check-code"
    , "build"
    ]

topLevelWords :: String
topLevelWords = completionWordsRaw topLevelCommandNames

leafTailWords :: String
leafTailWords =
    completionWordsRaw (foldr collectTail [] commandRows)
  where
    collectTail (path, _) tails =
        case finalWord (words path) of
            Just word -> word : tails
            Nothing -> tails

finalWord :: [String] -> Maybe String
finalWord [] = Nothing
finalWord [word] = Just word
finalWord (_ : rest) = finalWord rest

completionWords :: [ChoiceSpec] -> String
completionWords = completionWordsRaw . choiceTokens

completionWordsRaw :: [String] -> String
completionWordsRaw = unwords

zshWords :: [String] -> String
zshWords = intercalate " "

escapeMan :: String -> String
escapeMan =
    concatMap escapeChar
  where
    escapeChar '-' = "\\-"
    escapeChar ch = [ch]
