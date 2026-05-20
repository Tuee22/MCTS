module MCTS.Generated.Paths
    ( generatedCommandsPath
    , generatedFiles
    , trackingGeneratedPaths
    , externallyTrackedPaths
    ) where

import MCTS.CLI.Spec (renderCommandList, renderCommandMarkdown)

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
