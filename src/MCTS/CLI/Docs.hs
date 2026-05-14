module MCTS.CLI.Docs
    ( runDocs
    , generatedCommandsPath
    , generatedFiles
    ) where

import MCTS.CLI.Command (DocsCommand (..))
import MCTS.CLI.Output (outputLine, renderError)
import MCTS.CLI.Spec (renderCommandList, renderCommandMarkdown)
import MCTS.Error (AppError (..))
import MCTS.Plan (writePlanFile)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

generatedCommandsPath :: FilePath
generatedCommandsPath = "documents/cli/commands.md"

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
            let plan = unlines ["write " <> path | (path, _) <- generatedFiles]
            writePlanFile planFile plan
            if dryRun
                then outputLine plan >> pure 0
                else do
                    mapM_ writeGenerated generatedFiles
                    outputLine plan
                    pure 0

docsCheck :: IO (Either AppError ())
docsCheck = go generatedFiles
  where
    go [] = pure (Right ())
    go ((path, expected) : rest) = do
        exists <- doesFileExist path
        if not exists
            then pure (Left (DocsCheckDrift path "fully-generated"))
            else do
                actual <- readFile path
                if actual == expected
                    then go rest
                    else pure (Left (DocsCheckDrift path "fully-generated"))

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
