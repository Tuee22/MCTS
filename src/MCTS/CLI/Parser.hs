module MCTS.CLI.Parser
    ( parseCommand
    , parseBackends
    , parsePlanOptions
    , commandParserInfo
    ) where

import Control.Applicative ((<**>), (<|>))
import Data.Foldable (fold)
import Data.Word (Word16, Word64)
import MCTS.CLI.Command
import qualified MCTS.CLI.Spec as Spec
import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Plan (PlanOptions (..))
import MCTS.Types
import qualified Options.Applicative as OA

parseCommand :: [String] -> Either AppError Command
parseCommand [] = Right (Commands (CommandsOptions True False))
parseCommand args =
    case OA.execParserPure OA.defaultPrefs commandParserInfo args of
        OA.Success command -> validateCommand command
        OA.Failure failure ->
            let (message, _) = OA.renderFailure failure "mcts"
             in Left (ParseError (trimTrailingNewlines message))
        OA.CompletionInvoked _ -> Right (Commands (CommandsOptions True False))

commandParserInfo :: OA.ParserInfo Command
commandParserInfo =
    OA.info
        (commandTreeParser <**> OA.helper)
        (OA.fullDesc <> OA.progDesc (Spec.summary Spec.commandSpec))

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
    | null (Spec.children spec) =
        case leafParser path of
            Just parser -> parser
            Nothing -> pure (Help (HelpOptions path))
    | otherwise = childrenParser path spec

leafParser :: [String] -> Maybe (OA.Parser Command)
leafParser path =
    case path of
        ["bench", "rollouts"] -> Just (benchParser Rollouts)
        ["bench", "selfplay"] -> Just (benchParser Selfplay)
        ["verify", "rollouts"] -> Just (verifyParser Rollouts)
        ["verify", "selfplay"] -> Just (verifyParser Selfplay)
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
        ["build", "rust"] -> Just (Build . BuildRust <$> planOptionsParser)
        ["build", "legacy-fixtures"] -> Just (Build . BuildLegacyFixtures <$> legacyFixtureParser)
        _ -> Nothing

benchParser :: Workload -> OA.Parser Command
benchParser workload =
    mk <$> runOptionsParser workload NativeRng True False backendListOption
  where
    mk opts =
        let inputs = runOptionsToInputs workload id opts
            backends = maybe [inputBackend inputs] id (runBackends opts)
         in Bench
                (if workload == Rollouts then BenchRollouts backends inputs else BenchSelfplay backends inputs)

verifyParser :: Workload -> OA.Parser Command
verifyParser workload =
    mk
        <$> allowStaleSwitch
        <*> runOptionsParser workload CppRng False True verifyBackendListOption
  where
    mk allowStale opts =
        let inputs = runOptionsToInputs workload verifyBackendToBackend opts
            backends = maybe [] id (runBackends opts)
         in Verify
                ( if workload == Rollouts
                    then VerifyRollouts allowStale backends inputs
                    else VerifySelfplay allowStale backends inputs
                )

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
    :: Workload -> RngSource -> Bool -> Bool -> OA.Parser [backend] -> OA.Parser (RunOptions backend)
runOptionsParser workload defaultRng allowNativeRng backendRequired backendList =
    RunOptions
        <$> backendParser
        <*> rngOption defaultRng allowNativeRng
        <*> threadingOption
        <*> OA.option
            OA.auto
            (OA.long "games" <> OA.metavar "N" <> OA.value 1 <> OA.showDefault <> OA.help "Number of games")
        <*> OA.option
            OA.auto
            (OA.long "seed" <> OA.metavar "U64" <> OA.value 42 <> OA.showDefault <> OA.help "Master seed")
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

threadingOption :: OA.Parser Threading
threadingOption =
    mk
        <$> OA.option
            threadingReader
            ( OA.long "threading"
                <> OA.metavar "single|multi"
                <> OA.value (MultiThreaded 8)
                <> OA.help "Threading mode"
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
                <> OA.help "Backend"
            )
        <*> OA.option
            sideReader
            ( OA.long "side"
                <> OA.metavar "hero|villain"
                <> OA.value Hero
                <> OA.showDefaultWith renderSide
                <> OA.help "Human side"
            )
        <*> OA.optional
            (OA.option backendReader (OA.long "vs" <> OA.metavar "BACKEND" <> OA.help "Opponent backend"))
        <*> OA.option
            simBudgetReader
            ( OA.long "sims"
                <> OA.metavar "N|A:B"
                <> OA.value (FixedSims 1000)
                <> OA.showDefaultWith renderSimBudget
                <> OA.help "Simulation budget"
            )
        <*> OA.optional (OA.option OA.auto (OA.long "seed" <> OA.metavar "U64" <> OA.help "Master seed"))

parseBackends :: String -> Either AppError [Backend]
parseBackends raw =
    let pieces = splitCommas raw
        parsed = traverse parseBackend pieces
     in case parsed of
            Just [] -> Left (ParseError "backend list is empty")
            Just values -> Right values
            Nothing -> Left (ParseError ("bad backend list: " <> raw))

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
    (Test . TestAll <$> allParser)
        <|> (Test . TestRetirementAnchor <$> retirementAnchorParser)
        <|> (Test . TestStanza <$> OA.strArgument (OA.metavar "STANZA"))
  where
    allParser =
        OA.hsubparser
            ( OA.command
                "all"
                (OA.info (planOptionsParser <**> OA.helper) (OA.progDesc "Run full suite and report card"))
            )
    retirementAnchorParser =
        OA.hsubparser
            ( OA.command
                "retirement-anchor"
                ( OA.info
                    (retirementAnchorOptionsParser <**> OA.helper)
                    (OA.progDesc "Measure backend retirement parity anchor")
                )
            )

retirementAnchorOptionsParser :: OA.Parser RetirementAnchorOptions
retirementAnchorOptionsParser =
    RetirementAnchorOptions
        <$> OA.argument backendReader (OA.metavar "RETIRING")
        <*> OA.argument backendReader (OA.metavar "SUCCESSOR")
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
                <> OA.value "test/golden/legacy/transcripts"
                <> OA.showDefault
                <> OA.help "Fixture transcript output root"
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
        (OA.long "backend" <> OA.metavar "BACKENDS" <> OA.help "Comma-separated backend list")

verifyBackendListOption :: OA.Parser [VerifyBackend]
verifyBackendListOption =
    OA.option
        verifyBackendListReader
        (OA.long "backend" <> OA.metavar "BACKENDS" <> OA.help "Comma-separated non-legacy backend list")

backendReader :: OA.ReadM Backend
backendReader =
    OA.eitherReader $ \raw ->
        case parseBackend raw of
            Just backend -> Right backend
            Nothing -> Left ("unknown backend: " <> raw)

backendListReader :: OA.ReadM [Backend]
backendListReader =
    OA.eitherReader $ \raw ->
        case parseBackends raw of
            Right backends -> Right backends
            Left err -> Left (show err)

verifyBackendListReader :: OA.ReadM [VerifyBackend]
verifyBackendListReader =
    OA.eitherReader $ \raw ->
        case parseBackends raw of
            Left err -> Left (show err)
            Right [] -> Left "backend list is empty"
            Right backends ->
                case traverse toVerifyBackend backends of
                    Nothing -> Left "retired backends are not live verify targets; use frozen anchors"
                    Just typedBackends -> Right typedBackends

rngOption :: RngSource -> Bool -> OA.Parser RngSource
rngOption defaultRng allowNativeRng =
    OA.option
        (rngReader allowNativeRng)
        ( OA.long "rng"
            <> OA.metavar "native|cpp"
            <> OA.value defaultRng
            <> OA.showDefaultWith renderRng
            <> OA.help "RNG source"
        )

rngReader :: Bool -> OA.ReadM RngSource
rngReader allowNativeRng =
    OA.eitherReader $ \raw ->
        case parseRngSource raw of
            Just NativeRng
                | not allowNativeRng -> Left "verify requires --rng cpp; omit --rng or pass --rng cpp"
            Just rng -> Right rng
            Nothing -> Left ("bad --rng: " <> raw)

threadingReader :: OA.ReadM Threading
threadingReader =
    OA.eitherReader $ \raw ->
        case raw of
            "single" -> Right SingleThreaded
            "multi" -> Right (MultiThreaded 8)
            _ -> Left ("bad --threading: " <> raw)

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
            _ -> Left ("bad --side: " <> raw)

allowStaleSwitch :: OA.Parser Bool
allowStaleSwitch =
    OA.switch
        (OA.long "allow-stale" <> OA.help "Downgrade backend-slot envelope mismatches to warnings")

writeSwitch :: OA.Parser Bool
writeSwitch = OA.switch (OA.long "write" <> OA.help "Apply fixes where supported")

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
        _ -> Right command
  where
    validateVerify backends inputs original
        | inputRng inputs == NativeRng =
            Left (ParseError "verify requires --rng cpp; omit --rng or pass --rng cpp")
        | length backends < 2 =
            Left (VerifyCohortTooSmall "at least two non-legacy backends are required")
        | any (`elem` [CppLegacy, CppImperative, CppFunctional]) backends =
            Left (VerifyCohortTooSmall "retired backends are not live verify targets")
        | otherwise = Right original

renderRng :: RngSource -> String
renderRng rng =
    case rng of
        NativeRng -> "native"
        CppRng -> "cpp"

renderSide :: Side -> String
renderSide side =
    case side of
        Hero -> "hero"
        Villain -> "villain"

splitCommas :: String -> [String]
splitCommas raw =
    case break (== ',') raw of
        (one, "") -> [one | not (null one)]
        (one, _ : rest) -> [one | not (null one)] <> splitCommas rest

trimTrailingNewlines :: String -> String
trimTrailingNewlines = reverse . dropWhile (== '\n') . reverse
