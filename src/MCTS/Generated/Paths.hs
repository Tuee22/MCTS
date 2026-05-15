module MCTS.Generated.Paths
    ( generatedCommandsPath
    , generatedFiles
    , trackingGeneratedPaths
    ) where

import MCTS.CLI.Spec (renderCommandList, renderCommandMarkdown)

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
        , escapeMan renderCommandList
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
