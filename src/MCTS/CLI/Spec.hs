module MCTS.CLI.Spec
    ( CommandSpec (..)
    , OptionSpec (..)
    , Example (..)
    , commandSpec
    , leafSpecs
    , renderCommandList
    , renderCommandTree
    , renderCommandJson
    , renderCommandMarkdown
    ) where

import Data.List (intercalate)

data CommandSpec = CommandSpec
    { name :: !String
    , summary :: !String
    , description :: !String
    , children :: ![CommandSpec]
    , options :: ![OptionSpec]
    , examples :: ![Example]
    }
    deriving (Eq, Show)

data OptionSpec = OptionSpec
    { longName :: !String
    , shortName :: !(Maybe Char)
    , metavar :: !(Maybe String)
    , optionDescription :: !String
    , required :: !Bool
    }
    deriving (Eq, Show)

data Example = Example
    { exampleInvocation :: !String
    , exampleDescription :: !String
    }
    deriving (Eq, Show)

commandSpec :: CommandSpec
commandSpec =
    node
        "mcts"
        "Monte Carlo Tree Search runtime"
        [ node
            "bench"
            "Benchmark backends"
            [ leaf
                "rollouts"
                "Random-rollout benchmark"
                "mcts bench rollouts --backend haskell --games 8 --seed 42"
            , leaf
                "selfplay"
                "Self-play benchmark"
                "mcts bench selfplay --backend haskell --games 8 --seed 42 --sims 100"
            ]
        , node
            "verify"
            "Verify deterministic cohorts"
            [ leaf
                "rollouts"
                "Verify rollout visit counts"
                "mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42"
            , leaf
                "selfplay"
                "Verify self-play visit counts"
                "mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 100"
            , leaf
                "legacy-parity"
                "Verify legacy parity envelope"
                "mcts verify legacy-parity selfplay --backend cpp-legacy,haskell --games 1 --seed 42 --sims 10"
            ]
        , leaf "play" "Play or spectate a game" "mcts play --backend haskell --side hero --sims 100"
        , node
            "inspect"
            "Inspect transcript cache"
            [ leaf "list" "List cached transcripts" "mcts inspect list"
            , leaf "show" "Show one transcript" "mcts inspect show 7a2f --top 10"
            , leaf "replay" "Replay one transcript" "mcts inspect replay 7a2f --top 10"
            , node
                "cache"
                "Inspect sidecar cache"
                [ leaf "list" "List sidecars" "mcts inspect cache list"
                , leaf "prune" "Prune stale sidecars" "mcts inspect cache prune --keep-current"
                ]
            , leaf "divergence" "Show divergence matrix" "mcts inspect divergence 7a2f"
            ]
        , node
            "test"
            "Run tests"
            [ leaf "all" "Run full suite and report card" "mcts test all --dry-run"
            , leaf "<stanza>" "Run one cabal stanza" "mcts test mcts-unit"
            ]
        , node
            "lint"
            "Run lint gates"
            [ leaf "files" "Lint files" "mcts lint files"
            , leaf "docs" "Lint docs" "mcts lint docs"
            , leaf "haskell" "Lint Haskell" "mcts lint haskell"
            , leaf "all" "Run all linters" "mcts lint all"
            ]
        , node
            "docs"
            "Generated docs"
            [ leaf "check" "Check generated docs" "mcts docs check"
            , leaf "generate" "Generate docs" "mcts docs generate"
            ]
        , leaf "commands" "Show command registry" "mcts commands --tree"
        , leaf "help" "Focused help" "mcts help bench selfplay"
        , leaf "check-code" "Run code-quality gate" "mcts check-code"
        , node
            "build"
            "Build backend artefacts"
            [ leaf "cpp-legacy" "Build legacy C++ backend" "mcts build cpp-legacy --dry-run"
            , leaf "cpp-imperative" "Build imperative C++ backend" "mcts build cpp-imperative --dry-run"
            , leaf "cpp-functional" "Build functional C++ backend" "mcts build cpp-functional --dry-run"
            , leaf "rust" "Build Rust backend" "mcts build rust --dry-run"
            ]
        ]
  where
    node n s cs = CommandSpec n s s cs [] []
    leaf n s ex = CommandSpec n s s [] commonOptions [Example ex s]

commonOptions :: [OptionSpec]
commonOptions =
    [ OptionSpec "format" Nothing (Just "json|table|plain") "Output format" False
    , OptionSpec "color" Nothing (Just "auto|always|never") "Color mode" False
    ]

leafSpecs :: CommandSpec -> [CommandSpec]
leafSpecs spec
    | null (children spec) = [spec]
    | otherwise = concatMap leafSpecs (children spec)

renderCommandList :: String
renderCommandList =
    unlines [path | (path, spec) <- flatten [] commandSpec, null (children spec), path /= "mcts"]

renderCommandTree :: String
renderCommandTree = draw 0 commandSpec
  where
    draw indent spec =
        replicate indent ' '
            <> name spec
            <> " - "
            <> summary spec
            <> "\n"
            <> concatMap (draw (indent + 2)) (children spec)

renderCommandJson :: String
renderCommandJson =
    renderSpec commandSpec
  where
    renderSpec spec =
        "{"
            <> field "name" (name spec)
            <> ","
            <> field "summary" (summary spec)
            <> ",\"children\":["
            <> intercalate "," (map renderSpec (children spec))
            <> "],\"examples\":["
            <> intercalate "," [quote (exampleInvocation ex) | ex <- examples spec]
            <> "]}"
    field key value = quote key <> ":" <> quote value

renderCommandMarkdown :: String
renderCommandMarkdown =
    unlines $
        [ "# mcts command reference"
        , ""
        , "**Status**: Reference only"
        , "**Supersedes**: N/A"
        , "**Referenced by**: ../engineering/cli_command_surface.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md"
        , "**Generated sections**: none"
        , ""
        , "> **Purpose**: Generated reference list for the current `mcts` command registry."
        , ""
        ]
            <> concatMap markdownRow commandRows
  where
    commandRows =
        [ (path, spec)
        | (path, spec) <- flatten [] commandSpec
        , null (children spec)
        , path /= "mcts"
        ]
    markdownRow (path, spec)
        | path == "mcts verify legacy-parity" =
            ["- `" <> path <> " {rollouts|selfplay}` - " <> summary spec]
        | path == "mcts inspect show" =
            [ "- `" <> path <> "` - " <> summary spec
            , "- `" <> path <> " --envelope` - Show one transcript envelope"
            ]
        | path == "mcts help" =
            ["- `" <> path <> " <subcommand>` - " <> summary spec]
        | otherwise =
            ["- `" <> path <> "` - " <> summary spec]

flatten :: [String] -> CommandSpec -> [(String, CommandSpec)]
flatten prefix spec =
    let here = unwords (prefix <> [name spec])
     in (here, spec) : concatMap (flatten (prefix <> [name spec])) (children spec)

quote :: String -> String
quote value = "\"" <> concatMap escape value <> "\""
  where
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape ch = [ch]
