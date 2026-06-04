{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module MCTS.CLI.Spec
    ( CommandSpec (..)
    , OptionSpec (..)
    , ArgumentSpec (..)
    , ChoiceSpec (..)
    , Example (..)
    , backendChoices
    , verifyBackendChoices
    , rngChoices
    , sideChoices
    , threadingChoices
    , outputFormatChoices
    , colorModeChoices
    , buildTargetChoices
    , testStanzaChoices
    , choiceTokens
    , renderChoiceTokens
    , renderChoiceSummary
    , commandSpec
    , commandRows
    , leafSpecs
    , findCommandSpec
    , renderCommandList
    , renderCommandTree
    , renderCommandJson
    , renderCommandMarkdown
    ) where

import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.List (intercalate)
import MCTS.Types
    ( Backend (..)
    , allBackends
    , backendIdentifier
    , backendRoman
    )

data CommandSpec = CommandSpec
    { name :: !String
    , summary :: !String
    , description :: !String
    , children :: ![CommandSpec]
    , positionals :: ![ArgumentSpec]
    , options :: ![OptionSpec]
    , examples :: ![Example]
    , notes :: ![String]
    }
    deriving (Eq, Show)

data OptionSpec = OptionSpec
    { longName :: !String
    , shortName :: !(Maybe Char)
    , metavar :: !(Maybe String)
    , description :: !String
    , required :: !Bool
    , defaultValue :: !(Maybe String)
    , choices :: ![ChoiceSpec]
    , listSyntax :: !(Maybe String)
    , optionNotes :: ![String]
    }
    deriving (Eq, Show)

data ArgumentSpec = ArgumentSpec
    { argumentName :: !String
    , argumentDescription :: !String
    , argumentRequired :: !Bool
    , argumentChoices :: ![ChoiceSpec]
    }
    deriving (Eq, Show)

data ChoiceSpec = ChoiceSpec
    { choiceToken :: !String
    , choiceSummary :: !String
    }
    deriving (Eq, Show)

data Example = Example
    { exampleInvocation :: !String
    , exampleDescription :: !String
    }
    deriving (Eq, Show)

backendChoices :: [ChoiceSpec]
backendChoices =
    map
        ( \backend ->
            ChoiceSpec
                (backendIdentifier backend)
                (backendRoman backend <> " " <> backendSummary backend)
        )
        allBackends
  where
    backendSummary backend =
        case backend of
            CppLegacy -> "C++ legacy port"
            CppImperative -> "C++ imperative steelman"
            CppFunctional -> "C++ functional-core steelman"
            Rust -> "Rust steelman"
            Haskell -> "in-process Haskell engine"

verifyBackendChoices :: [ChoiceSpec]
verifyBackendChoices =
    [ choice
    | choice <- backendChoices
    , choiceToken choice /= "cpp-legacy"
    ]

rngChoices :: [ChoiceSpec]
rngChoices =
    [ ChoiceSpec "native" "backend-native RNG"
    , ChoiceSpec "cpp" "legacy-compatible C++ RNG"
    ]

sideChoices :: [ChoiceSpec]
sideChoices =
    [ ChoiceSpec "hero" "the hero side"
    , ChoiceSpec "villain" "the villain side"
    ]

threadingChoices :: [ChoiceSpec]
threadingChoices =
    [ ChoiceSpec "single" "single-threaded dispatch"
    , ChoiceSpec "multi" "multi-threaded dispatch using --workers"
    ]

outputFormatChoices :: [ChoiceSpec]
outputFormatChoices =
    [ ChoiceSpec "json" "machine-readable JSON"
    , ChoiceSpec "table" "human-readable table output"
    , ChoiceSpec "plain" "plain text output"
    ]

colorModeChoices :: [ChoiceSpec]
colorModeChoices =
    [ ChoiceSpec "auto" "color when stdout is a terminal"
    , ChoiceSpec "always" "always emit ANSI color"
    , ChoiceSpec "never" "never emit ANSI color"
    ]

buildTargetChoices :: [ChoiceSpec]
buildTargetChoices =
    [ ChoiceSpec "cpp-legacy" "C++ legacy backend recipe"
    , ChoiceSpec "cpp-imperative" "C++ imperative backend recipe"
    , ChoiceSpec "cpp-functional" "C++ functional-core backend recipe"
    , ChoiceSpec "rust" "Rust backend recipe"
    , ChoiceSpec "legacy-fixtures" "external legacy audit fixture generator"
    ]

testStanzaChoices :: [ChoiceSpec]
testStanzaChoices =
    [ ChoiceSpec "mcts-haskell-style" "formatter, HLint, and source-walker checks"
    , ChoiceSpec "mcts-unit" "unit and pure semantic tests"
    , ChoiceSpec "mcts-integration" "integration and live-smoke tests"
    , ChoiceSpec "mcts-cross-backend" "Q3 cross-backend verifier tests"
    , ChoiceSpec "mcts-legacy-parity" "Q6 legacy-envelope tests"
    , ChoiceSpec "mcts-semantic-parity" "Q7 semantic-parity tests"
    ]

choiceTokens :: [ChoiceSpec] -> [String]
choiceTokens = map choiceToken

renderChoiceTokens :: [ChoiceSpec] -> String
renderChoiceTokens = intercalate ", " . choiceTokens

renderChoiceSummary :: [ChoiceSpec] -> String
renderChoiceSummary choiceSet =
    intercalate "; " [choiceToken choice <> " (" <> choiceSummary choice <> ")" | choice <- choiceSet]

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
                "Legacy played-game benchmark"
                "mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading single --rng native --games 100000 --seed 42"
                `withDescription` "Run the legacy-named played-game benchmark across an explicit backend cohort. Provide a comma-separated --backend list plus --games and --seed; use bench terminal-playouts for raw terminal playout throughput."
                `withOptions` runOptions True backendChoices "native" "multi" "10000" []
                `withNotes` [ "The legacy-named rollouts benchmark measures played games with one search iteration per real move."
                            ]
            , leaf
                "selfplay"
                "Self-play benchmark"
                "mcts bench selfplay --backend haskell --rng native --games 1000 --seed 42 --sims 10000"
                `withDescription` "Run full UCT self-play games for one or more backends. Provide --backend, --games, and --seed; --sims controls the per-move search budget and --workers controls multi-threaded dispatch."
                `withExample` "mcts bench selfplay --backend haskell --rng native --workers 32 --games 1000 --seed 42 --sims 10000"
                `withOptions` runOptions True backendChoices "native" "multi" "10000" []
            , leaf
                "terminal-playouts"
                "Terminal playout throughput"
                "mcts bench terminal-playouts --backend haskell --rng native --count 1000 --seed 42"
                `withDescription` "Measure direct random playout throughput without building a search tree. Provide --backend, --count, and --seed; output reports playouts/s rather than games/s."
                `withOptions` primitiveBenchOptions
            , leaf
                "search-iters"
                "Search-iteration throughput"
                "mcts bench search-iters --backend haskell --rng native --count 1000 --seed 42"
                `withDescription` "Measure direct UCT search-iteration throughput for the selected backend cohort. Provide --backend, --count, and --seed; output reports search-iters/s."
                `withOptions` primitiveBenchOptions
            ]
        , node
            "verify"
            "Verify deterministic cohorts"
            [ leaf
                "rollouts"
                "Verify rollout visit counts"
                "mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42"
                `withDescription` "Run the Q3 rollout verifier over at least two non-legacy backends. Provide a comma-separated --backend list, --games, and --seed; verification uses the cpp RNG path and rejects cpp-legacy."
                `withOptions` verifyOptions
            , leaf
                "selfplay"
                "Verify self-play visit counts"
                "mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 50 --seed 42 --max-plies 200 --sims 10000"
                `withDescription` "Run the Q3 self-play verifier over at least two non-legacy backends. Provide --backend, --games, and --seed; --sims controls per-move search and verification uses the cpp RNG path."
                `withOptions` verifyOptions
            , node
                "legacy-parity"
                "Verify the legacy envelope"
                [ leaf
                    "rollouts"
                    "Verify legacy-envelope rollout liveness"
                    "mcts verify legacy-parity rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42"
                    `withDescription` "Check Q6 legacy-envelope rollout liveness across all five backend slots. Provide each backend identifier exactly once in --backend plus --games and --seed."
                    `withOptions` legacyParityOptions
                , leaf
                    "selfplay"
                    "Verify legacy-envelope self-play liveness"
                    "mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 4"
                    `withDescription` "Check Q6 legacy-envelope self-play liveness across all five backend slots. Provide each backend identifier exactly once in --backend; --sims sets the small per-move search budget."
                    `withOptions` legacyParityOptions
                ]
            ]
        , leaf
            "play"
            "Play or spectate a game"
            "mcts play --backend haskell --side villain --rng native --max-plies 200 --sims 1000"
            `withDescription` "Open the interactive Brick TUI. Without --vs, --backend controls the side named by --side and the human plays the opposite side. With --vs, --backend controls --side, --vs controls the other side, and the operator spectates AI-vs-AI play from the terminal."
            `withExamples` [ Example
                                "mcts play --backend haskell --side villain --rng native --max-plies 200 --sims 1000"
                                "Human plays Hero; haskell controls Villain."
                           , Example
                                "mcts play --backend haskell --side hero --vs rust --rng native --max-plies 200 --sims 1000"
                                "Watch Haskell Hero vs Rust Villain in spectator mode."
                           ]
            `withOptions` playOptions
            `withNotes` [ "Accepted backend values are cpp-legacy, cpp-imperative, cpp-functional, rust, and haskell."
                        , "For human-vs-AI play, omit --vs; the selected backend controls --side and the human controls the other side."
                        , "For AI-vs-AI spectating, pass --vs BACKEND; press Space in the TUI to advance AI turns when prompted."
                        ]
        , node
            "inspect"
            "Inspect transcript cache"
            [ leaf "list" "List cached transcripts" "mcts inspect list"
                `withDescription` "List transcripts in the selected cache root with backend, seed, games, threading, sims, move count, mtime, and path metadata."
                `withOptions` [cacheDirOption]
            , leaf "show" "Show one transcript" "mcts inspect show 7a2f --top 10 --with-equity"
                `withDescription` "Resolve a transcript hash prefix and print its move history. Use --top to limit displayed candidate moves, --with-equity for originator equity evidence, and --envelope for v1 envelope fields."
                `withPositionals` [hashPrefixArgument]
                `withOptions` [ topOption
                              , flagOption "with-equity" "Recompute and render equity sidecar values"
                              , flagOption "envelope" "Render transcript envelope"
                              , cacheDirOption
                              ]
            , leaf "replay" "Replay one transcript" "mcts inspect replay 7a2f --top 15"
                `withDescription` "Open the interactive replay TUI for a transcript hash prefix. Navigate forward and backward through recorded moves while viewing multi-backend equity overlays when sidecars or live recompute paths are available."
                `withPositionals` [hashPrefixArgument]
                `withOptions` [ topOption
                              , option "cache-states" Nothing (Just "N") "Replay state cache size" False (Just "20") [] Nothing []
                              , cacheDirOption
                              ]
            , node
                "cache"
                "Inspect sidecar cache"
                [ leaf "list" "List sidecars" "mcts inspect cache list"
                    `withDescription` "List transcript equity sidecar entries under the cache root, including backend/build slots and envelope neighbours."
                    `withOptions` [cacheDirOption]
                , leaf "prune" "Prune stale sidecars" "mcts inspect cache prune --keep-current --dry-run"
                    `withDescription` "Plan or delete stale equity sidecars. Use --dry-run to review the deletion plan first; --keep-current keeps the logical current backend/build slot."
                    `withOptions` ([flagOption "keep-current" "Keep current backend/build sidecars", cacheDirOption] <> planOptions)
                ]
            , leaf "divergence" "Show divergence matrix" "mcts inspect divergence 7a2f"
                `withDescription` "Resolve one transcript and render a divergence matrix from cached sidecars plus any live foreign recompute rows available in the image."
                `withPositionals` [hashPrefixArgument]
                `withOptions` [cacheDirOption]
            ]
        , node
            "test"
            "Run tests"
            [ leaf "all" "Run full suite and report card" "mcts test all --dry-run"
                `withDescription` "Run the aggregate Plan/Apply validation gate over generated-doc checks, prebuilt Cabal test stanzas, live verification cohorts, and the report-card workload. Use --dry-run or --plan-file to inspect the plan."
                `withOptions` planOptions
            , leaf
                "parity-anchor"
                "Measure backend parity anchor"
                "mcts test parity-anchor rust haskell --format json"
                `withDescription` "Measure a focused Q1/Q2 parity anchor between two explicit backend identifiers. Use --dry-run or --plan-file to inspect the planned benchmark and verification steps."
                `withPositionals` [ ArgumentSpec "BASELINE" "Baseline backend" True backendChoices
                                  , ArgumentSpec "CANDIDATE" "Candidate backend" True backendChoices
                                  ]
                `withOptions` planOptions
            , leaf "<stanza>" "Run one prebuilt test stanza" "mcts test mcts-unit"
                `withDescription` "Run one Dockerfile-prebuilt Cabal test-suite executable by stanza name. Accepted stanza values are listed in help and command JSON."
                `withPositionals` [ArgumentSpec "STANZA" "Prebuilt Cabal test-suite executable" True testStanzaChoices]
            ]
        , node
            "lint"
            "Run lint gates"
            [ leaf "files" "Lint files" "mcts lint files"
                `withDescription` "Check file hygiene, forbidden workflow paths, and tracked generated-file drift. Pass --write to apply supported rewrites for this lint surface."
                `withOptions` [writeOption]
            , leaf "docs" "Lint docs" "mcts lint docs"
                `withDescription` "Check generated documentation sections and tracked generated command artefacts for drift. Pass --write to regenerate before rechecking."
                `withOptions` [writeOption]
            , leaf "haskell" "Lint Haskell" "mcts lint haskell"
                `withDescription` "Run the Haskell style gate through the pinned container toolchain: Fourmolu, HLint, and the Cabal-format round trip. Pass --write for formatter-supported rewrites."
                `withOptions` [writeOption]
            , leaf "all" "Run all linters" "mcts lint all"
                `withDescription` "Run every lint gate in the supported order: file hygiene, generated docs, and Haskell style."
            ]
        , node
            "docs"
            "Generated docs"
            [ leaf "check" "Check generated docs" "mcts docs check"
                `withDescription` "Compare every registered generated section and tracked generated path with the current renderer output. Fails with the drifted path, marker key, and regenerate remedy."
            , leaf "generate" "Generate docs" "mcts docs generate"
                `withDescription` "Regenerate marker-delimited docs and fully generated command artefacts from the typed registries. Use --dry-run or --plan-file to inspect the generation plan."
                `withOptions` docsGenerateOptions
            ]
        , leaf "commands" "Show command registry" "mcts commands --tree"
            `withDescription` "Print the command registry. Use --tree for a compact topology view or --json for the stable schema consumed by tools and generated docs."
            `withOptions` [ flagOption "tree" "Render command tree"
                          , flagOption "json" "Render enriched command schema as JSON"
                          ]
        , leaf "help" "Focused help" "mcts help bench selfplay"
            `withDescription` "Render focused parser help for a command path such as play or verify selfplay. Unknown targets report the nearest valid command-tree context."
            `withPositionals` [ArgumentSpec "COMMAND" "Command path such as play or verify selfplay" False []]
        , leaf "check-code" "Run code-quality gate" "mcts check-code"
            `withDescription` "Run the project code-quality gate that combines doctrine alignment, generated-doc checks, Haskell style, and forbidden-surface linting."
        , node
            "build"
            "Backend artefact recipes"
            [ leaf "cpp-legacy" "C++ legacy backend build recipe" "mcts build cpp-legacy --dry-run"
                `withDescription` "Plan or run the C++ legacy backend build recipe used by the Dockerfile. Use --dry-run or --plan-file to inspect subprocesses before execution."
                `withOptions` planOptions
            , leaf "cpp-imperative" "C++ imperative backend build recipe" "mcts build cpp-imperative --dry-run"
                `withDescription` "Plan or run the C++ imperative steelman backend recipe, including the mandatory PGO/BOLT path. Use --dry-run or --plan-file to inspect subprocesses."
                `withOptions` planOptions
            , leaf "cpp-functional" "C++ functional backend build recipe" "mcts build cpp-functional --dry-run"
                `withDescription` "Plan or run the C++ functional-core backend recipe, including the shared C++ PGO/BOLT flow. Use --dry-run or --plan-file to inspect subprocesses."
                `withOptions` planOptions
            , leaf "rust" "Rust backend build recipe" "mcts build rust --dry-run"
                `withDescription` "Plan or run the Rust cdylib backend recipe, including the mandatory PGO/BOLT path. Use --dry-run or --plan-file to inspect subprocesses."
                `withOptions` planOptions
            , leaf
                "legacy-fixtures"
                "Generate external legacy audit fixtures"
                "mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --seed 42 --games 10 --sims 10000 --dry-run"
                `withDescription` "Generate optional external legacy audit fixtures under an explicit output directory. The output is not a normal validation input; use --dry-run or --plan-file to inspect the recipe."
                `withOptions` (legacyFixtureOptions <> planOptions)
            ]
        ]
  where
    node n s cs = CommandSpec n s s cs [] [] [] []
    leaf n s ex = CommandSpec n s s [] [] commonOptions [Example ex s] []
    withDescription :: CommandSpec -> String -> CommandSpec
    withDescription (CommandSpec n s _ cs ps os es ns) desc = CommandSpec n s desc cs ps os es ns
    withExamples :: CommandSpec -> [Example] -> CommandSpec
    withExamples spec xs = spec{examples = xs}
    withExample :: CommandSpec -> String -> CommandSpec
    withExample spec ex = spec{examples = examples spec <> [Example ex (summary spec)]}
    withOptions :: CommandSpec -> [OptionSpec] -> CommandSpec
    withOptions spec extra = spec{options = options spec <> extra}
    withPositionals :: CommandSpec -> [ArgumentSpec] -> CommandSpec
    withPositionals spec extra = spec{positionals = positionals spec <> extra}
    withNotes :: CommandSpec -> [String] -> CommandSpec
    withNotes spec extra = spec{notes = notes spec <> extra}

commonOptions :: [OptionSpec]
commonOptions =
    [ option
        "format"
        Nothing
        (Just "json|table|plain")
        "Output format"
        False
        (Just "plain when stdout is not a TTY; table when stdout is a TTY")
        outputFormatChoices
        Nothing
        ["Global option parsed before command dispatch."]
    , option
        "color"
        Nothing
        (Just "auto|always|never")
        "Color mode"
        False
        (Just "auto")
        colorModeChoices
        Nothing
        ["Global option parsed before command dispatch."]
    , flagOption "no-color" "Alias for --color never"
    ]

planOptions :: [OptionSpec]
planOptions =
    [ flagOption "dry-run" "Render the plan without applying it"
    , option
        "plan-file"
        Nothing
        (Just "PATH")
        "Write the rendered plan to a file"
        False
        Nothing
        []
        Nothing
        []
    ]

legacyFixtureOptions :: [OptionSpec]
legacyFixtureOptions =
    [ option
        "output-dir"
        Nothing
        (Just "DIR")
        "Required legacy audit output root; use an external or ignored artifact directory"
        True
        Nothing
        []
        Nothing
        []
    , option "seed" Nothing (Just "U64") "Master seed" False (Just "42") [] Nothing []
    , option "games" Nothing (Just "N") "Games" False (Just "10") [] Nothing []
    , option "sims" Nothing (Just "N") "Sims per move" False (Just "10000") [] Nothing []
    ]

docsGenerateOptions :: [OptionSpec]
docsGenerateOptions =
    [ flagOption "dry-run" "Render the generated-docs plan without writing"
    , option
        "plan-file"
        Nothing
        (Just "PATH")
        "Write the generated-docs plan to a file"
        False
        Nothing
        []
        Nothing
        []
    ]

runOptions :: Bool -> [ChoiceSpec] -> String -> String -> String -> [String] -> [OptionSpec]
runOptions requiredBackend choiceSet defaultRng defaultThreading defaultSimsValue backendNotes =
    [ option
        "backend"
        Nothing
        (Just "BACKENDS")
        "Comma-separated backend list"
        requiredBackend
        Nothing
        choiceSet
        (Just "comma-separated non-empty list")
        backendNotes
    , option "rng" Nothing (Just "native|cpp") "RNG source" False (Just defaultRng) rngChoices Nothing []
    , option
        "threading"
        Nothing
        (Just "single|multi")
        "Threading mode"
        False
        (Just defaultThreading)
        threadingChoices
        Nothing
        []
    , option
        "workers"
        Nothing
        (Just "N")
        "Worker count for --threading multi"
        False
        (Just "8")
        []
        Nothing
        []
    , option "games" Nothing (Just "N") "Number of games" True Nothing [] Nothing []
    , option "seed" Nothing (Just "U64") "Master seed" True Nothing [] Nothing []
    , option "max-plies" Nothing (Just "N") "Maximum plies per game" False (Just "200") [] Nothing []
    , option
        "sims"
        Nothing
        (Just "N|A:B")
        "Simulation budget"
        False
        (Just defaultSimsValue)
        []
        (Just "N for fixed sims, A:B for ramped sims")
        []
    , cacheDirOption
    ]

verifyOptions :: [OptionSpec]
verifyOptions =
    [ flagOption "allow-stale" "Downgrade backend-slot envelope mismatches to warnings"
    ]
        <> runOptions
            True
            verifyBackendChoices
            "cpp"
            "single"
            "10000"
            ["Q3 excludes cpp-legacy; use mcts verify legacy-parity for all five backend slots."]

legacyParityOptions :: [OptionSpec]
legacyParityOptions =
    [ flagOption "allow-stale" "Downgrade backend-slot envelope mismatches to warnings"
    ]
        <> runOptions
            True
            backendChoices
            "cpp"
            "single"
            "10000"
            ["Legacy parity requires each of the five backend identifiers exactly once."]

primitiveBenchOptions :: [OptionSpec]
primitiveBenchOptions =
    [ option
        "backend"
        Nothing
        (Just "BACKENDS")
        "Comma-separated backend list"
        True
        Nothing
        backendChoices
        (Just "comma-separated non-empty list")
        []
    , option "rng" Nothing (Just "native|cpp") "RNG source" False (Just "native") rngChoices Nothing []
    , option
        "threading"
        Nothing
        (Just "single|multi")
        "Threading mode"
        False
        (Just "multi")
        threadingChoices
        Nothing
        []
    , option
        "workers"
        Nothing
        (Just "N")
        "Worker count for --threading multi"
        False
        (Just "8")
        []
        Nothing
        []
    , option
        "count"
        Nothing
        (Just "N")
        "Number of primitive benchmark units"
        False
        (Just "1000")
        []
        Nothing
        []
    , option "seed" Nothing (Just "U64") "Master seed" True Nothing [] Nothing []
    , option
        "max-plies"
        Nothing
        (Just "N")
        "Maximum plies for each primitive unit"
        False
        (Just "60")
        []
        Nothing
        []
    ]

playOptions :: [OptionSpec]
playOptions =
    [ option
        "backend"
        Nothing
        (Just "BACKEND")
        "AI backend that controls the side named by --side"
        True
        Nothing
        backendChoices
        Nothing
        ["Omit --vs for human play; the human controls the opposite side."]
    , option
        "side"
        Nothing
        (Just "hero|villain")
        "Side controlled by --backend; the human plays the opposite side unless --vs is set"
        True
        Nothing
        sideChoices
        Nothing
        []
    , option
        "vs"
        Nothing
        (Just "BACKEND")
        "Second AI backend for spectator mode; controls the side opposite --side"
        False
        Nothing
        backendChoices
        Nothing
        ["When --vs is set, the operator watches instead of entering human moves."]
    , option "rng" Nothing (Just "native|cpp") "RNG source" False (Just "native") rngChoices Nothing []
    , option
        "sims"
        Nothing
        (Just "N|A:B")
        "Simulation budget"
        False
        (Just "1000")
        []
        (Just "N for fixed sims, A:B for ramped sims")
        []
    , option
        "seed"
        Nothing
        (Just "U64")
        "Master seed; omitted means fresh random"
        False
        Nothing
        []
        Nothing
        []
    , option "max-plies" Nothing (Just "N") "Maximum plies per game" False (Just "200") [] Nothing []
    , cacheDirOption
    ]

cacheDirOption :: OptionSpec
cacheDirOption =
    option
        "cache-dir"
        Nothing
        (Just "DIR")
        "Transcript cache root"
        False
        (Just ".mcts-cache")
        []
        Nothing
        []

topOption :: OptionSpec
topOption =
    option "top" Nothing (Just "N") "Rows per move to show" False (Just "10") [] Nothing []

writeOption :: OptionSpec
writeOption =
    flagOption "write" "Apply fixes where supported"

hashPrefixArgument :: ArgumentSpec
hashPrefixArgument =
    ArgumentSpec "HASH-PREFIX" "Transcript hash prefix" True []

flagOption :: String -> String -> OptionSpec
flagOption nameValue descriptionValue =
    option nameValue Nothing Nothing descriptionValue False Nothing [] Nothing []

option
    :: String
    -> Maybe Char
    -> Maybe String
    -> String
    -> Bool
    -> Maybe String
    -> [ChoiceSpec]
    -> Maybe String
    -> [String]
    -> OptionSpec
option nameValue short metavarValue descriptionValue requiredValue defaultValueValue choicesValue listSyntaxValue notesValue =
    OptionSpec
        { longName = nameValue
        , shortName = short
        , metavar = metavarValue
        , description = descriptionValue
        , required = requiredValue
        , defaultValue = defaultValueValue
        , choices = choicesValue
        , listSyntax = listSyntaxValue
        , optionNotes = notesValue
        }

leafSpecs :: CommandSpec -> [CommandSpec]
leafSpecs spec
    | null (children spec) = [spec]
    | otherwise = concatMap leafSpecs (children spec)

commandRows :: [(String, CommandSpec)]
commandRows =
    [ (path, spec)
    | (path, spec) <- flatten [] commandSpec
    , null (children spec)
    , path /= "mcts"
    ]

findCommandSpec :: [String] -> Maybe CommandSpec
findCommandSpec target =
    lookup (unwords ("mcts" : normalize target)) [(path, spec) | (path, spec) <- flatten [] commandSpec]
  where
    normalize ("mcts" : rest) = rest
    normalize rest = rest

renderCommandList :: String
renderCommandList =
    unlines [path | (path, _) <- commandRows]

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
    LBS.unpack (Aeson.encode (renderSpec [] commandSpec))
  where
    renderSpec prefix spec@CommandSpec{description = commandDescription} =
        let pathWords = prefix <> [name spec]
         in Aeson.object
                [ "name" .= name spec
                , "path" .= unwords pathWords
                , "summary" .= summary spec
                , "description" .= commandDescription
                , "positionals" .= map renderArgument (positionals spec)
                , "options" .= map renderOption (options spec)
                , "examples" .= map renderExample (examples spec)
                , "notes" .= notes spec
                , "children" .= map (renderSpec pathWords) (children spec)
                ]
    renderArgument argument =
        Aeson.object
            [ "name" .= argumentName argument
            , "description" .= argumentDescription argument
            , "required" .= argumentRequired argument
            , "values" .= map renderChoice (argumentChoices argument)
            ]
    renderOption opt@OptionSpec{description = optionDescription} =
        Aeson.object
            [ "long" .= longName opt
            , "short" .= fmap (: []) (shortName opt)
            , "metavar" .= metavar opt
            , "description" .= optionDescription
            , "required" .= required opt
            , "default" .= defaultValue opt
            , "values" .= map renderChoice (choices opt)
            , "list_syntax" .= listSyntax opt
            , "notes" .= optionNotes opt
            ]
    renderChoice choice =
        Aeson.object
            [ "token" .= choiceToken choice
            , "summary" .= choiceSummary choice
            ]
    renderExample example =
        Aeson.object
            [ "invocation" .= exampleInvocation example
            , "description" .= exampleDescription example
            ]

renderCommandMarkdown :: String
renderCommandMarkdown =
    unlines
        . dropTrailingBlankRows
        $ [ "# mcts command reference"
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
    markdownRow (path, spec@CommandSpec{description = commandDescription}) =
        [ "## `" <> path <> "`"
        , ""
        , commandDescription
        , ""
        , "**Usage**: `" <> usageFor path spec <> "`"
        , ""
        ]
            <> positionalsBlock spec
            <> optionsBlock spec
            <> notesBlock spec
            <> examplesBlock spec

dropTrailingBlankRows :: [String] -> [String]
dropTrailingBlankRows = reverse . dropWhile null . reverse

usageFor :: String -> CommandSpec -> String
usageFor path spec =
    unwords $
        [path]
            <> [argumentUsage argument | argument <- positionals spec]
            <> ["[options]" | not (null (options spec))]
  where
    argumentUsage argument =
        if argumentRequired argument
            then "<" <> argumentName argument <> ">"
            else "[" <> argumentName argument <> "...]"

positionalsBlock :: CommandSpec -> [String]
positionalsBlock spec
    | null (positionals spec) = []
    | otherwise =
        [ "**Arguments**"
        , ""
        , "| Name | Required | Values | Description |"
        , "|------|----------|--------|-------------|"
        ]
            <> [renderArgumentRow argument | argument <- positionals spec]
            <> [""]

renderArgumentRow :: ArgumentSpec -> String
renderArgumentRow argument =
    "| `"
        <> argumentName argument
        <> "` | "
        <> yesNo (argumentRequired argument)
        <> " | "
        <> renderValues (argumentChoices argument)
        <> " | "
        <> argumentDescription argument
        <> " |"

optionsBlock :: CommandSpec -> [String]
optionsBlock spec
    | null (options spec) = []
    | otherwise =
        [ "**Options**"
        , ""
        , "| Option | Required | Default | Values | Description |"
        , "|--------|----------|---------|--------|-------------|"
        ]
            <> [renderOptionRow opt | opt <- options spec]
            <> [""]

renderOptionRow :: OptionSpec -> String
renderOptionRow opt@OptionSpec{description = optionDescription} =
    "| `--"
        <> longName opt
        <> maybe "" ((" " <>) . id) (metavar opt)
        <> "` | "
        <> yesNo (required opt)
        <> " | "
        <> maybe "-" id (defaultValue opt)
        <> " | "
        <> renderValues (choices opt)
        <> " | "
        <> optionDescription
        <> renderListSyntax opt
        <> renderOptionNotes opt
        <> " |"

renderValues :: [ChoiceSpec] -> String
renderValues [] = "-"
renderValues valueChoices = "`" <> intercalate "`, `" (choiceTokens valueChoices) <> "`"

renderListSyntax :: OptionSpec -> String
renderListSyntax opt =
    maybe "" (\syntax -> " Syntax: " <> syntax <> ".") (listSyntax opt)

renderOptionNotes :: OptionSpec -> String
renderOptionNotes opt =
    case optionNotes opt of
        [] -> ""
        rows -> " " <> intercalate " " rows

notesBlock :: CommandSpec -> [String]
notesBlock spec
    | null (notes spec) = []
    | otherwise = ["**Notes**", ""] <> ["- " <> row | row <- notes spec] <> [""]

examplesBlock :: CommandSpec -> [String]
examplesBlock spec =
    ["**Examples**", ""]
        <> concatMap
            ( \example ->
                [ "- " <> exampleDescription example
                , ""
                , "  ```bash"
                , "  " <> exampleInvocation example
                , "  ```"
                , ""
                ]
            )
            (examples spec)

yesNo :: Bool -> String
yesNo True = "yes"
yesNo False = "no"

flatten :: [String] -> CommandSpec -> [(String, CommandSpec)]
flatten prefix spec =
    let here = unwords (prefix <> [name spec])
     in (here, spec) : concatMap (flatten (prefix <> [name spec])) (children spec)
