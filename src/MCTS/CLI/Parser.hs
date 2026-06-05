module MCTS.CLI.Parser
    ( parseCommand
    , parseBackends
    , parsePlanOptions
    , commandParserInfo
    , renderFocusedHelp
    ) where

import Control.Applicative ((<**>), (<|>))
import Data.Foldable (fold)
import Data.List (inits)
import Data.Word (Word16, Word64)
import MCTS.CLI.Command
import qualified MCTS.CLI.Spec as Spec
import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Plan (PlanOptions (..))
import MCTS.Types
import qualified Options.Applicative as OA
import qualified Options.Applicative.Help.Pretty as Pretty
import System.Exit (ExitCode (..))

parseCommand :: [String] -> Either AppError Command
parseCommand args =
    case helpRequestTarget args of
        Just target ->
            case renderFocusedHelp target of
                Right rendered -> Right (RenderHelp rendered)
                Left rendered -> Left (ParseError rendered)
        Nothing ->
            case args of
                [] -> Right (Commands (CommandsOptions True False))
                _ -> parseCommandTree args

parseCommandTree :: [String] -> Either AppError Command
parseCommandTree args =
    case OA.execParserPure OA.defaultPrefs commandParserInfo args of
        OA.Success command -> validateCommand command
        OA.Failure failure ->
            let (message, code) = OA.renderFailure failure "mcts"
                rendered = trimTrailingNewlines message
             in case code of
                    ExitSuccess -> Right (RenderHelp rendered)
                    ExitFailure _ -> Left (ParseError rendered)
        OA.CompletionInvoked _ -> Right (Commands (CommandsOptions True False))

commandParserInfo :: OA.ParserInfo Command
commandParserInfo =
    OA.info
        (commandTreeParser <**> OA.helper)
        (OA.fullDesc <> OA.progDesc (Spec.summary Spec.commandSpec))

renderFocusedHelp :: [String] -> Either String String
renderFocusedHelp target
    | knownPath normalized = Right (renderParserHelp normalized)
    | otherwise =
        Left
            ( "unknown help target: mcts "
                <> unwords normalized
                <> "\n\nNearest valid context:\n"
                <> renderParserHelp (nearestKnownPrefix normalized)
            )
  where
    normalized =
        case target of
            "mcts" : rest -> rest
            rest -> rest
    knownPath [] = True
    knownPath path = maybe False (const True) (Spec.findCommandSpec path)
    nearestKnownPrefix path =
        foldl keepKnown [] (inits path)
    keepKnown _ prefix
        | knownPath prefix = prefix
    keepKnown previous _ = previous

renderParserHelp :: [String] -> String
renderParserHelp target =
    case OA.execParserPure OA.defaultPrefs (targetParserInfo target) ["--help"] of
        OA.Failure failure ->
            trimTrailingNewlines (fst (OA.renderFailure failure (programName target)))
        OA.Success _ -> "No focused help is available for mcts " <> unwords target
        OA.CompletionInvoked _ -> trimTrailingNewlines Spec.renderCommandTree

targetParserInfo :: [String] -> OA.ParserInfo Command
targetParserInfo [] = commandParserInfo
targetParserInfo target =
    case Spec.findCommandSpec target of
        Just spec ->
            OA.info
                (nodeParser target spec <**> OA.helper)
                (OA.fullDesc <> OA.progDesc (commandDescription spec) <> commandFooter spec)
        Nothing -> commandParserInfo

commandDescription :: Spec.CommandSpec -> String
commandDescription (Spec.CommandSpec _ _ commandDescriptionValue _ _ _ _ _) = commandDescriptionValue

commandFooter :: Spec.CommandSpec -> OA.InfoMod Command
commandFooter spec =
    case footerLines spec of
        [] -> mempty
        rows -> OA.footerDoc (Just (Pretty.vcat (map Pretty.pretty rows)))

footerLines :: Spec.CommandSpec -> [String]
footerLines spec =
    notesLines <> examplesLines
  where
    notesLines
        | null (Spec.notes spec) = []
        | otherwise = "" : "Notes:" : map ("  - " <>) (Spec.notes spec)
    examplesLines
        | null (Spec.examples spec) = []
        | otherwise = "" : "Examples:" : concatMap renderExample (Spec.examples spec)
    renderExample example =
        [ "  " <> Spec.exampleDescription example
        , "    " <> Spec.exampleInvocation example
        ]

programName :: [String] -> String
programName [] = "mcts"
programName target = unwords ("mcts" : target)

helpRequestTarget :: [String] -> Maybe [String]
helpRequestTarget args
    | any isHelpFlag args = Just (takeCommandPath (takeWhile (not . isHelpFlag) args))
    | otherwise = Nothing
  where
    takeCommandPath = takeWhile (not . isOption)
    isOption ('-' : _) = True
    isOption _ = False

isHelpFlag :: String -> Bool
isHelpFlag raw = raw == "--help" || raw == "-h"

commandTreeParser :: OA.Parser Command
commandTreeParser = childrenParser [] Spec.commandSpec

childrenParser :: [String] -> Spec.CommandSpec -> OA.Parser Command
childrenParser prefix spec =
    OA.hsubparser . fold $
        [ OA.command
            (Spec.name child)
            ( OA.info
                (nodeParser (prefix <> [Spec.name child]) child <**> OA.helper)
                (OA.progDesc (Spec.summary child))
            )
        | child <- Spec.children spec
        , Spec.name child /= "<stanza>"
        ]

nodeParser :: [String] -> Spec.CommandSpec -> OA.Parser Command
nodeParser path spec
    | path == ["test"] = testParser
    | path == ["inspect"] = inspectParser spec
    | null (Spec.children spec) =
        case leafParser path of
            Just parser -> withCommonOptions parser
            Nothing -> pure (Help (HelpOptions path))
    | otherwise = childrenParser path spec

inspectParser :: Spec.CommandSpec -> OA.Parser Command
inspectParser spec =
    childrenParser ["inspect"] spec
        <|> withCommonOptions
            (Inspect . InspectBrowse <$> optionalStringOption "cache-dir" "DIR" "Transcript cache root")

leafParser :: [String] -> Maybe (OA.Parser Command)
leafParser path =
    case path of
        ["bench", "rollouts"] -> Just (benchParser Rollouts)
        ["bench", "selfplay"] -> Just (benchParser Selfplay)
        ["bench", "terminal-playouts"] -> Just (benchPrimitiveParser TerminalPlayouts)
        ["bench", "search-iters"] -> Just (benchPrimitiveParser SearchIters)
        ["verify", "rollouts"] -> Just (verifyParser Rollouts)
        ["verify", "selfplay"] -> Just (verifyParser Selfplay)
        ["verify", "legacy-parity", "rollouts"] -> Just (legacyParityParser Rollouts)
        ["verify", "legacy-parity", "selfplay"] -> Just (legacyParityParser Selfplay)
        ["play"] -> Just (Play <$> playParser)
        ["inspect", "list"] -> Just (Inspect . InspectList <$> optionalStringOption "cache-dir" "DIR" "Transcript cache root")
        ["inspect", "show"] -> Just (Inspect . InspectShow <$> showParser)
        ["inspect", "replay"] -> Just (Inspect . InspectReplay <$> replayParser)
        ["inspect", "cache", "list"] ->
            Just
                ( Inspect . InspectCache . CacheList
                    <$> optionalStringOption "cache-dir" "DIR" "Transcript cache root"
                )
        ["inspect", "cache", "prune"] -> Just (Inspect . InspectCache <$> cachePruneParser)
        ["inspect", "divergence"] -> Just (Inspect . InspectDivergence <$> divergenceParser)
        ["lint", "files"] -> Just (Lint . LintFiles <$> writeSwitch)
        ["lint", "docs"] -> Just (Lint . LintDocs <$> writeSwitch)
        ["lint", "haskell"] -> Just (Lint . LintHaskell <$> writeSwitch)
        ["lint", "all"] -> Just (pure (Lint LintAll))
        ["docs", "check"] -> Just (pure (Docs DocsCheck))
        ["docs", "generate"] -> Just (Docs <$> docsGenerateParser)
        ["commands"] -> Just (Commands <$> commandsParser)
        ["help"] -> Just (Help . HelpOptions <$> manyStringArguments "COMMAND")
        ["check-code"] -> Just (pure CheckCode)
        ["test", "all"] -> Just (Test . TestAll <$> planOptionsParser)
        ["test", "parity-anchor"] -> Just (Test . TestParityAnchor <$> parityAnchorOptionsParser)
        ["build", "cpp-legacy"] -> Just (Build . BuildCppLegacy <$> planOptionsParser)
        ["build", "cpp-imperative"] -> Just (Build . BuildCppImperative <$> planOptionsParser)
        ["build", "cpp-functional"] -> Just (Build . BuildCppFunctional <$> planOptionsParser)
        ["build", "rust"] -> Just (Build . BuildRust <$> planOptionsParser)
        ["build", "legacy-fixtures"] -> Just (Build . BuildLegacyFixtures <$> legacyFixtureParser)
        _ -> Nothing

benchParser :: Workload -> OA.Parser Command
benchParser workload =
    mk <$> runOptionsParser workload NativeRng True True (MultiThreaded 8) True True backendListOption
  where
    mk opts =
        let inputs = runOptionsToInputs workload id opts
            backends = maybe [inputBackend inputs] id (runBackends opts)
         in Bench
                (if workload == Rollouts then BenchRollouts backends inputs else BenchSelfplay backends inputs)

benchPrimitiveParser :: BenchPrimitive -> OA.Parser Command
benchPrimitiveParser primitive =
    mk
        <$> backendListOption
        <*> rngOption NativeRng True
        <*> threadingOption (MultiThreaded 8)
        <*> OA.option
            OA.auto
            ( OA.long "count"
                <> OA.metavar "N"
                <> OA.value (1000 :: Int)
                <> OA.showDefault
                <> OA.help "Number of primitive benchmark units"
            )
        <*> OA.option
            OA.auto
            ( OA.long "seed"
                <> OA.metavar "U64"
                <> OA.help "Master seed"
            )
        <*> ( fromIntegral
                <$> OA.option
                    OA.auto
                    ( OA.long "max-plies"
                        <> OA.metavar "N"
                        <> OA.value (60 :: Int)
                        <> OA.showDefault
                        <> OA.help "Maximum plies for each primitive unit"
                    )
            )
  where
    mk backends rng threading count seed maxPlies =
        let options =
                BenchPrimitiveOptions
                    { benchPrimitiveRng = rng
                    , benchPrimitiveThreading = threading
                    , benchPrimitiveCount = count
                    , benchPrimitiveSeed = seed
                    , benchPrimitiveMaxPlies = maxPlies
                    }
         in Bench $
                case primitive of
                    TerminalPlayouts -> BenchTerminalPlayouts backends options
                    SearchIters -> BenchSearchIters backends options

verifyParser :: Workload -> OA.Parser Command
verifyParser workload =
    mk
        <$> allowStaleSwitch
        <*> runOptionsParser workload CppRng False True SingleThreaded True True verifyBackendListOption
  where
    mk allowStale opts =
        let inputs = runOptionsToInputs workload verifyBackendToBackend opts
            backends = maybe [] id (runBackends opts)
         in Verify
                ( if workload == Rollouts
                    then VerifyRollouts allowStale backends inputs
                    else VerifySelfplay allowStale backends inputs
                )

legacyParityParser :: Workload -> OA.Parser Command
legacyParityParser workload =
    mk
        <$> allowStaleSwitch
        <*> runOptionsParser workload CppRng False True SingleThreaded True True backendListOption
  where
    mk allowStale opts =
        let inputs = pinLegacyParityInputs (runOptionsToInputs workload id opts)
            backends = maybe [] id (runBackends opts)
         in Verify (VerifyLegacyParity allowStale workload backends inputs)

data RunOptions backend = RunOptions
    { runBackends :: !(Maybe [backend])
    , runRng :: !RngSource
    , runThreadingOption :: !Threading
    , runGamesOption :: !Int
    , runSeed :: !Word64
    , runMaxPliesOption :: !Word16
    , runSims :: !SimBudget
    , runCacheDir :: !(Maybe FilePath)
    }

runOptionsParser
    :: Workload
    -> RngSource
    -> Bool
    -> Bool
    -> Threading
    -> Bool
    -> Bool
    -> OA.Parser [backend]
    -> OA.Parser (RunOptions backend)
runOptionsParser workload defaultRng allowNativeRng backendRequired defaultThreading requireGames requireSeed backendList =
    RunOptions
        <$> backendParser
        <*> rngOption defaultRng allowNativeRng
        <*> threadingOption defaultThreading
        <*> gamesOption
        <*> seedOption
        <*> ( fromIntegral
                <$> OA.option
                    OA.auto
                    ( OA.long "max-plies"
                        <> OA.metavar "N"
                        <> OA.value (200 :: Int)
                        <> OA.showDefault
                        <> OA.help "Maximum plies per game"
                    )
            )
        <*> OA.option
            simBudgetReader
            ( OA.long "sims"
                <> OA.metavar "N|A:B"
                <> OA.value (defaultSims workload)
                <> OA.showDefaultWith renderSimBudget
                <> OA.help "Simulation budget"
            )
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"
  where
    backendParser =
        if backendRequired
            then Just <$> backendList
            else OA.optional backendList
    gamesOption =
        OA.option
            OA.auto
            ( fold
                [ OA.long "games"
                , OA.metavar "N"
                , OA.help "Number of games"
                , if requireGames then mempty else OA.value 1 <> OA.showDefault
                ]
            )
    seedOption =
        OA.option
            OA.auto
            ( fold
                [ OA.long "seed"
                , OA.metavar "U64"
                , OA.help "Master seed"
                , if requireSeed then mempty else OA.value 42 <> OA.showDefault
                ]
            )

runOptionsToInputs :: Workload -> (backend -> Backend) -> RunOptions backend -> RunInputs
runOptionsToInputs workload toBackend options =
    defaultRunInputs
        { inputBackend = selectedBackend
        , inputWorkload = workload
        , inputRng = runRng options
        , inputThreading = runThreadingOption options
        , inputGames = runGamesOption options
        , inputSeed = runSeed options
        , inputMaxPlies = runMaxPliesOption options
        , inputSims = runSims options
        , inputCacheDir = runCacheDir options
        }
  where
    selectedBackend =
        case runBackends options of
            Nothing -> Haskell
            Just [] -> Haskell
            Just (backend : _) -> toBackend backend

pinLegacyParityInputs :: RunInputs -> RunInputs
pinLegacyParityInputs inputs =
    inputs
        { inputRng = CppRng
        , inputThreading = SingleThreaded
        , inputMaxPlies = 10000
        }

defaultSims :: Workload -> SimBudget
defaultSims workload =
    case workload of
        Rollouts -> FixedSims 10000
        Selfplay -> FixedSims 10000

renderSimBudget :: SimBudget -> String
renderSimBudget budget =
    case budget of
        FixedSims n -> show n
        RampedSims first perMove -> show first <> ":" <> show perMove

threadingOption :: Threading -> OA.Parser Threading
threadingOption defaultThreading =
    mk
        <$> OA.option
            threadingReader
            ( OA.long "threading"
                <> OA.metavar "single|multi"
                <> OA.value defaultThreading
                <> OA.showDefaultWith renderThreading
                <> OA.help (choiceHelp "Threading mode" Spec.threadingChoices)
            )
        <*> OA.option
            OA.auto
            ( OA.long "workers"
                <> OA.metavar "N"
                <> OA.value (8 :: Int)
                <> OA.showDefault
                <> OA.help "Worker count for --threading multi"
            )
  where
    mk mode workers =
        case mode of
            SingleThreaded -> SingleThreaded
            MultiThreaded _ -> MultiThreaded (max 1 workers)

playParser :: OA.Parser PlayOptions
playParser =
    PlayOptions
        <$> OA.option
            backendReader
            ( OA.long "backend"
                <> OA.metavar "BACKEND"
                <> OA.value Haskell
                <> OA.showDefaultWith backendIdentifier
                <> OA.help
                    ( choiceHelp
                        "AI backend that controls the side named by --side; omit --vs for human play"
                        Spec.backendChoices
                    )
            )
        <*> OA.option
            sideReader
            ( OA.long "side"
                <> OA.metavar "hero|villain"
                <> OA.value Villain
                <> OA.showDefaultWith renderSide
                <> OA.help
                    ( choiceHelp
                        "Side controlled by --backend; the human plays the opposite side unless --vs is set"
                        Spec.sideChoices
                    )
            )
        <*> OA.optional
            ( OA.option
                backendReader
                ( OA.long "vs"
                    <> OA.metavar "BACKEND"
                    <> OA.help
                        ( choiceHelp
                            "Second AI backend for spectator mode; controls the side opposite --side"
                            Spec.backendChoices
                        )
                )
            )
        <*> rngOption NativeRng True
        <*> OA.option
            simBudgetReader
            ( OA.long "sims"
                <> OA.metavar "N|A:B"
                <> OA.value (FixedSims 1000)
                <> OA.showDefaultWith renderSimBudget
                <> OA.help "Simulation budget"
            )
        <*> OA.optional (OA.option OA.auto (OA.long "seed" <> OA.metavar "U64" <> OA.help "Master seed"))
        <*> ( fromIntegral
                <$> OA.option
                    OA.auto
                    ( OA.long "max-plies"
                        <> OA.metavar "N"
                        <> OA.value (200 :: Int)
                        <> OA.showDefault
                        <> OA.help "Maximum plies per game"
                    )
            )
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"

renderSide :: Side -> String
renderSide side =
    case side of
        Hero -> "hero"
        Villain -> "villain"

parseBackends :: String -> Either AppError [Backend]
parseBackends raw =
    case parseChoiceList "backend" Spec.backendChoices parseBackend raw of
        Right [] ->
            Left
                ( ParseError
                    ("backend list is empty; accepted values: " <> Spec.renderChoiceTokens Spec.backendChoices)
                )
        Right values -> Right values
        Left message -> Left (ParseError message)

showParser :: OA.Parser ShowOptions
showParser =
    ShowOptions
        <$> OA.strArgument (OA.metavar "HASH-PREFIX")
        <*> OA.option
            OA.auto
            (OA.long "top" <> OA.metavar "N" <> OA.value 10 <> OA.showDefault <> OA.help "Rows per move to show")
        <*> OA.switch (OA.long "with-equity" <> OA.help "Recompute and render equity sidecar values")
        <*> OA.switch (OA.long "envelope" <> OA.help "Render transcript envelope")
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"

replayParser :: OA.Parser ReplayOptions
replayParser =
    ReplayOptions
        <$> OA.strArgument (OA.metavar "HASH-PREFIX")
        <*> OA.option
            OA.auto
            (OA.long "top" <> OA.metavar "N" <> OA.value 10 <> OA.showDefault <> OA.help "Rows per move to show")
        <*> OA.option
            OA.auto
            ( OA.long "cache-states"
                <> OA.metavar "N"
                <> OA.value 20
                <> OA.showDefault
                <> OA.help "Replay state cache size"
            )
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"

cachePruneParser :: OA.Parser CacheCommand
cachePruneParser =
    CachePrune
        <$> OA.switch (OA.long "keep-current" <> OA.help "Keep current backend/build sidecars")
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"
        <*> planOptionsParser

divergenceParser :: OA.Parser DivergenceOptions
divergenceParser =
    DivergenceOptions
        <$> OA.strArgument (OA.metavar "HASH-PREFIX")
        <*> optionalStringOption "cache-dir" "DIR" "Transcript cache root"

testParser :: OA.Parser Command
testParser =
    allParser
        <|> parityAnchorParser
        <|> withCommonOptions (Test . TestStanza <$> OA.strArgument (OA.metavar "STANZA"))
  where
    allParser =
        OA.hsubparser
            ( OA.command
                "all"
                ( OA.info
                    (withCommonOptions (Test . TestAll <$> planOptionsParser) <**> OA.helper)
                    (OA.progDesc "Run full suite and report card")
                )
            )
    parityAnchorParser =
        OA.hsubparser
            ( OA.command
                "parity-anchor"
                ( OA.info
                    (withCommonOptions (Test . TestParityAnchor <$> parityAnchorOptionsParser) <**> OA.helper)
                    (OA.progDesc "Measure backend parity anchor")
                )
            )

parityAnchorOptionsParser :: OA.Parser ParityAnchorOptions
parityAnchorOptionsParser =
    ParityAnchorOptions
        <$> OA.argument backendReader (OA.metavar "BASELINE")
        <*> OA.argument backendReader (OA.metavar "CANDIDATE")
        <*> planOptionsParser

docsGenerateParser :: OA.Parser DocsCommand
docsGenerateParser =
    DocsGenerate
        <$> OA.switch (OA.long "dry-run" <> OA.help "Render the plan without writing")
        <*> optionalStringOption "plan-file" "PATH" "Write the generated plan to a file"

commandsParser :: OA.Parser CommandsOptions
commandsParser =
    CommandsOptions
        <$> OA.switch (OA.long "tree" <> OA.help "Render command tree")
        <*> OA.switch (OA.long "json" <> OA.help "Render command schema as JSON")

planOptionsParser :: OA.Parser PlanOptions
planOptionsParser =
    PlanOptions
        <$> OA.switch (OA.long "dry-run" <> OA.help "Render the plan without applying it")
        <*> optionalStringOption "plan-file" "PATH" "Write the generated plan to a file"

legacyFixtureParser :: OA.Parser LegacyFixtureOptions
legacyFixtureParser =
    LegacyFixtureOptions
        <$> OA.strOption
            ( OA.long "output-dir"
                <> OA.metavar "DIR"
                <> OA.help "Required legacy audit output root; use an external or ignored artifact directory"
            )
        <*> OA.option
            OA.auto
            (OA.long "seed" <> OA.metavar "U64" <> OA.value 42 <> OA.showDefault <> OA.help "Master seed")
        <*> OA.option
            OA.auto
            (OA.long "games" <> OA.metavar "N" <> OA.value 10 <> OA.showDefault <> OA.help "Games")
        <*> OA.option
            OA.auto
            (OA.long "sims" <> OA.metavar "N" <> OA.value 10000 <> OA.showDefault <> OA.help "Sims per move")
        <*> planOptionsParser

parsePlanOptions :: [String] -> PlanOptions
parsePlanOptions args =
    case OA.execParserPure OA.defaultPrefs (OA.info planOptionsParser OA.fullDesc) args of
        OA.Success options -> options
        _ -> PlanOptions False Nothing

backendListOption :: OA.Parser [Backend]
backendListOption =
    OA.option
        backendListReader
        ( OA.long "backend"
            <> OA.metavar "BACKENDS"
            <> OA.help
                ( choiceHelp "Comma-separated backend list" Spec.backendChoices
                    <> ". Syntax: comma-separated non-empty list"
                )
        )

verifyBackendListOption :: OA.Parser [VerifyBackend]
verifyBackendListOption =
    OA.option
        verifyBackendListReader
        ( OA.long "backend"
            <> OA.metavar "BACKENDS"
            <> OA.help
                ( choiceHelp "Comma-separated Q3 backend list" Spec.verifyBackendChoices
                    <> ". Syntax: comma-separated non-empty list. Use mcts verify legacy-parity for all five backend slots"
                )
        )

backendReader :: OA.ReadM Backend
backendReader =
    choiceReader "backend" Spec.backendChoices parseBackend

backendListReader :: OA.ReadM [Backend]
backendListReader =
    OA.eitherReader $ \raw ->
        case parseBackends raw of
            Right backends -> Right backends
            Left (ParseError message) -> Left message
            Left err -> Left (show err)

verifyBackendListReader :: OA.ReadM [VerifyBackend]
verifyBackendListReader =
    OA.eitherReader $ \raw ->
        case parseBackends raw of
            Left (ParseError message) -> Left message
            Left err -> Left (show err)
            Right [] -> Left "backend list is empty"
            Right backends ->
                case traverse toVerifyBackend backends of
                    Nothing ->
                        Left
                            ( "cpp-legacy is not in the Q3 verify cohort; accepted values: "
                                <> Spec.renderChoiceTokens Spec.verifyBackendChoices
                                <> "; use mcts verify legacy-parity for all-five legacy-envelope checks"
                            )
                    Just typedBackends -> Right typedBackends

rngOption :: RngSource -> Bool -> OA.Parser RngSource
rngOption defaultRng allowNativeRng =
    OA.option
        (rngReader allowNativeRng)
        ( OA.long "rng"
            <> OA.metavar "native|cpp"
            <> OA.value defaultRng
            <> OA.showDefaultWith renderRng
            <> OA.help (choiceHelp "RNG source" Spec.rngChoices)
        )

rngReader :: Bool -> OA.ReadM RngSource
rngReader allowNativeRng =
    OA.eitherReader $ \raw ->
        case parseRngSource raw of
            Just NativeRng
                | not allowNativeRng -> Left "verify requires --rng cpp; omit --rng or pass --rng cpp"
            Just rng -> Right rng
            Nothing -> Left (unknownChoiceMessage "rng" Spec.rngChoices raw)

threadingReader :: OA.ReadM Threading
threadingReader =
    OA.eitherReader $ \raw ->
        case raw of
            "single" -> Right SingleThreaded
            "multi" -> Right (MultiThreaded 8)
            _ -> Left (unknownChoiceMessage "threading" Spec.threadingChoices raw)

simBudgetReader :: OA.ReadM SimBudget
simBudgetReader =
    OA.eitherReader $ \raw ->
        case parseSimBudget raw of
            Just budget -> Right budget
            Nothing -> Left ("bad --sims: " <> raw)

sideReader :: OA.ReadM Side
sideReader =
    OA.eitherReader $ \raw ->
        case raw of
            "hero" -> Right Hero
            "villain" -> Right Villain
            _ -> Left (unknownChoiceMessage "side" Spec.sideChoices raw)

allowStaleSwitch :: OA.Parser Bool
allowStaleSwitch =
    OA.switch
        (OA.long "allow-stale" <> OA.help "Downgrade backend-slot envelope mismatches to warnings")

writeSwitch :: OA.Parser Bool
writeSwitch = OA.switch (OA.long "write" <> OA.help "Apply fixes where supported")

withCommonOptions :: OA.Parser Command -> OA.Parser Command
withCommonOptions parser =
    parser <* commonOutputOptionsParser

commonOutputOptionsParser :: OA.Parser ()
commonOutputOptionsParser =
    ()
        <$ OA.optional
            ( OA.option
                (choiceUnitReader "format" Spec.outputFormatChoices)
                ( OA.long "format"
                    <> OA.metavar "json|table|plain"
                    <> OA.help
                        ( choiceHelp "Output format" Spec.outputFormatChoices
                            <> ". Default: plain when stdout is not a TTY; table when stdout is a TTY"
                        )
                )
            )
        <* OA.optional
            ( OA.option
                (choiceUnitReader "color" Spec.colorModeChoices)
                ( OA.long "color"
                    <> OA.metavar "auto|always|never"
                    <> OA.help (choiceHelp "Color mode" Spec.colorModeChoices <> ". Default: auto")
                )
            )
        <* OA.switch (OA.long "no-color" <> OA.help "Alias for --color never")

choiceReader :: String -> [Spec.ChoiceSpec] -> (String -> Maybe a) -> OA.ReadM a
choiceReader label choiceSet parseValue =
    OA.eitherReader $ \raw ->
        case parseValue raw of
            Just value -> Right value
            Nothing -> Left (unknownChoiceMessage label choiceSet raw)

choiceUnitReader :: String -> [Spec.ChoiceSpec] -> OA.ReadM ()
choiceUnitReader label choiceSet =
    choiceReader label choiceSet parse
  where
    parse raw =
        if raw `elem` Spec.choiceTokens choiceSet
            then Just ()
            else Nothing

parseChoiceList :: String -> [Spec.ChoiceSpec] -> (String -> Maybe a) -> String -> Either String [a]
parseChoiceList label choiceSet parseValue raw =
    let pieces = splitCommas raw
     in if null raw || null pieces || any null pieces
            then
                Left
                    (label <> " list is empty or malformed; accepted values: " <> Spec.renderChoiceTokens choiceSet)
            else traverse parsePiece pieces
  where
    parsePiece piece =
        case parseValue piece of
            Just value -> Right value
            Nothing -> Left (unknownChoiceMessage label choiceSet piece)

unknownChoiceMessage :: String -> [Spec.ChoiceSpec] -> String -> String
unknownChoiceMessage label choiceSet raw =
    "unknown "
        <> label
        <> ": "
        <> raw
        <> "; accepted values: "
        <> Spec.renderChoiceTokens choiceSet

choiceHelp :: String -> [Spec.ChoiceSpec] -> String
choiceHelp label choiceSet =
    label <> ". Accepted values: " <> Spec.renderChoiceTokens choiceSet

optionalStringOption :: String -> String -> String -> OA.Parser (Maybe String)
optionalStringOption longName metavar helpText =
    OA.optional (OA.strOption (OA.long longName <> OA.metavar metavar <> OA.help helpText))

manyStringArguments :: String -> OA.Parser [String]
manyStringArguments metavar =
    OA.many (OA.strArgument (OA.metavar metavar))

validateCommand :: Command -> Either AppError Command
validateCommand command =
    case command of
        Verify (VerifyRollouts _ backends inputs) -> validateVerify (verifyBackendsToBackends backends) inputs command
        Verify (VerifySelfplay _ backends inputs) -> validateVerify (verifyBackendsToBackends backends) inputs command
        Verify (VerifyLegacyParity _ _ backends inputs) -> validateLegacyParity backends inputs command
        _ -> Right command
  where
    validateVerify backends inputs original
        | inputRng inputs == NativeRng =
            Left (ParseError "verify requires --rng cpp; omit --rng or pass --rng cpp")
        | length backends < 2 =
            Left (VerifyCohortTooSmall "at least two non-legacy backends are required")
        | CppLegacy `elem` backends =
            Left (VerifyCohortTooSmall "cpp-legacy is not in the Q3 verify cohort")
        | otherwise = Right original
    validateLegacyParity backends inputs original
        | inputRng inputs == NativeRng =
            Left (ParseError "verify legacy-parity requires --rng cpp; omit --rng or pass --rng cpp")
        | hasDuplicates backends || not (all (`elem` backends) allBackends) =
            Left (VerifyCohortTooSmall "legacy parity requires each of the five backend slots exactly once")
        | otherwise = Right original

hasDuplicates :: (Eq a) => [a] -> Bool
hasDuplicates = go []
  where
    go _ [] = False
    go seen (x : xs)
        | x `elem` seen = True
        | otherwise = go (x : seen) xs

renderRng :: RngSource -> String
renderRng rng =
    case rng of
        NativeRng -> "native"
        CppRng -> "cpp"

renderThreading :: Threading -> String
renderThreading threading =
    case threading of
        SingleThreaded -> "single"
        MultiThreaded _ -> "multi"

splitCommas :: String -> [String]
splitCommas raw =
    case break (== ',') raw of
        (one, "") -> [one]
        (one, _ : rest) -> one : splitCommas rest

trimTrailingNewlines :: String -> String
trimTrailingNewlines = reverse . dropWhile (== '\n') . reverse
