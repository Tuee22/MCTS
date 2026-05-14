module MCTS.CLI.Parser
    ( parseCommand
    , parseBackends
    , parsePlanOptions
    ) where

import Data.Char (isDigit)
import Data.List (isPrefixOf)
import Data.Word (Word16, Word64)
import MCTS.CLI.Command
import MCTS.Driver
import MCTS.Error (AppError (..))
import MCTS.Plan (PlanOptions (..))
import MCTS.Types

parseCommand :: [String] -> Either AppError Command
parseCommand args =
    case args of
        [] -> Right (Commands (CommandsOptions True False))
        "commands" : rest ->
            Right (Commands (CommandsOptions ("--tree" `elem` rest) ("--json" `elem` rest)))
        "help" : rest -> Right (Help (HelpOptions rest))
        ["check-code"] -> Right CheckCode
        "bench" : "rollouts" : rest -> parseBench Rollouts rest
        "bench" : "selfplay" : rest -> parseBench Selfplay rest
        "verify" : "rollouts" : rest -> parseVerify Rollouts rest
        "verify" : "selfplay" : rest -> parseVerify Selfplay rest
        "verify" : "legacy-parity" : workload : rest ->
            case parseWorkload workload of
                Just wl -> parseLegacy wl rest
                Nothing -> Left (ParseError "legacy-parity workload must be rollouts or selfplay")
        "inspect" : "list" : rest -> Right (Inspect (InspectList (flagValue "--cache-dir" rest)))
        "inspect" : "show" : ref : rest ->
            Right
                ( Inspect
                    ( InspectShow
                        ShowOptions
                            { showRef = ref
                            , showTopN = intFlag "--top" 10 rest
                            , showWithEquity = "--with-equity" `elem` rest
                            , showEnvelope = "--envelope" `elem` rest
                            , showCacheDir = flagValue "--cache-dir" rest
                            }
                    )
                )
        "inspect" : "replay" : ref : rest ->
            Right
                ( Inspect
                    ( InspectReplay
                        ReplayOptions
                            { replayRef = ref
                            , replayTopN = intFlag "--top" 10 rest
                            , replayCacheStates = intFlag "--cache-states" 20 rest
                            , replayCacheDir = flagValue "--cache-dir" rest
                            }
                    )
                )
        "inspect" : "cache" : "list" : rest ->
            Right (Inspect (InspectCache (CacheList (flagValue "--cache-dir" rest))))
        "inspect" : "cache" : "prune" : rest ->
            Right (Inspect (InspectCache (CachePrune ("--keep-current" `elem` rest) (flagValue "--cache-dir" rest))))
        "inspect" : "divergence" : ref : rest ->
            Right (Inspect (InspectDivergence (DivergenceOptions ref (flagValue "--cache-dir" rest))))
        "test" : "all" : rest -> Right (Test (TestAll (parsePlanOptions rest)))
        "test" : stanza : _ -> Right (Test (TestStanza stanza))
        "lint" : "files" : rest -> Right (Lint (LintFiles ("--write" `elem` rest)))
        "lint" : "docs" : rest -> Right (Lint (LintDocs ("--write" `elem` rest)))
        "lint" : "haskell" : rest -> Right (Lint (LintHaskell ("--write" `elem` rest)))
        ["lint", "all"] -> Right (Lint LintAll)
        "docs" : "check" : _ -> Right (Docs DocsCheck)
        "docs" : "generate" : rest -> Right (Docs (DocsGenerate ("--dry-run" `elem` rest) (flagValue "--plan-file" rest)))
        "build" : backend : rest -> parseBuild backend rest
        "play" : rest -> Play <$> parsePlay rest
        command : _ -> Left (UnknownCommand command)

parseBuild :: String -> [String] -> Either AppError Command
parseBuild backend rest =
    let opts = parsePlanOptions rest
     in case backend of
            "cpp-legacy" -> Right (Build (BuildCppLegacy opts))
            "cpp-imperative" -> Right (Build (BuildCppImperative opts))
            "cpp-functional" -> Right (Build (BuildCppFunctional opts))
            "rust" -> Right (Build (BuildRust opts))
            _ -> Left (ParseError ("unknown build backend: " <> backend))

parseBench :: Workload -> [String] -> Either AppError Command
parseBench workload rest = do
    inputs <- parseRunInputs workload rest
    backends <-
        case flagValue "--backend" rest of
            Nothing -> Right [inputBackend inputs]
            Just raw -> parseBackends raw
    Right (Bench (if workload == Rollouts then BenchRollouts backends inputs else BenchSelfplay backends inputs))

parseVerify :: Workload -> [String] -> Either AppError Command
parseVerify workload rest = do
    rejectNativeVerifyRng rest
    inputs <- parseRunInputs workload rest
    backends <- parseBackends =<< requiredFlag "--backend" rest
    if any (== CppLegacy) backends
        then Left (VerifyCohortTooSmall "cpp-legacy is excluded from verify")
        else Right (Verify (if workload == Rollouts then VerifyRollouts allowStale backends inputs else VerifySelfplay allowStale backends inputs))
  where
    allowStale = "--allow-stale" `elem` rest

parseLegacy :: Workload -> [String] -> Either AppError Command
parseLegacy workload rest = do
    rejectNativeVerifyRng rest
    inputs <- parseRunInputs workload rest
    backends <- parseBackends =<< requiredFlag "--backend" rest
    Right (Verify (VerifyLegacyParity workload ("--allow-stale" `elem` rest) backends inputs))

rejectNativeVerifyRng :: [String] -> Either AppError ()
rejectNativeVerifyRng rest =
    case flagValue "--rng" rest of
        Just "native" -> Left (ParseError "verify requires --rng cpp; omit --rng or pass --rng cpp")
        _ -> Right ()

parseRunInputs :: Workload -> [String] -> Either AppError RunInputs
parseRunInputs workload rest = do
    let backend = maybe Haskell id (flagValue "--backend" rest >>= parseBackend . takeWhile (/= ','))
        rng = maybe NativeRng id (flagValue "--rng" rest >>= parseRngSource)
        threading =
            case flagValue "--threading" rest of
                Just "single" -> SingleThreaded
                Just "multi" -> MultiThreaded (intFlag "--workers" 8 rest)
                _ -> if "--workers" `elem` map (takeWhile (/= '=')) rest then MultiThreaded (intFlag "--workers" 8 rest) else MultiThreaded 8
        games = intFlag "--games" 1 rest
        seed = integerFlag "--seed" 42 rest
        maxPlies = fromIntegral (intFlag "--max-plies" 200 rest) :: Word16
        sims = maybe (FixedSims 10000) id (flagValue "--sims" rest >>= parseSimBudget)
    Right
        defaultRunInputs
            { inputBackend = backend
            , inputWorkload = workload
            , inputRng = rng
            , inputThreading = threading
            , inputGames = games
            , inputSeed = fromIntegral (seed :: Integer) :: Word64
            , inputMaxPlies = maxPlies
            , inputSims = sims
            , inputCacheDir = flagValue "--cache-dir" rest
            }

parsePlay :: [String] -> Either AppError PlayOptions
parsePlay rest = do
    backend <- maybe (Right Haskell) (maybe (Left (ParseError "bad --backend")) Right . parseBackend) (flagValue "--backend" rest)
    side <-
        case flagValue "--side" rest of
            Just "hero" -> Right Hero
            Just "villain" -> Right Villain
            Nothing -> Right Hero
            Just value -> Left (ParseError ("bad --side: " <> value))
    let vs = flagValue "--vs" rest >>= parseBackend
        sims = maybe (FixedSims 1000) id (flagValue "--sims" rest >>= parseSimBudget)
        seed = integerFlagMaybe "--seed" rest
    Right PlayOptions{playBackend = backend, playSide = side, playVs = vs, playSims = sims, playSeed = seed}

parseBackends :: String -> Either AppError [Backend]
parseBackends raw =
    let pieces = splitCommas raw
        parsed = traverse parseBackend pieces
     in case parsed of
            Just [] -> Left (ParseError "backend list is empty")
            Just values -> Right values
            Nothing -> Left (ParseError ("bad backend list: " <> raw))

parseWorkload :: String -> Maybe Workload
parseWorkload value =
    case value of
        "rollouts" -> Just Rollouts
        "selfplay" -> Just Selfplay
        _ -> Nothing

parsePlanOptions :: [String] -> PlanOptions
parsePlanOptions rest =
    PlanOptions
        { planDryRun = "--dry-run" `elem` rest
        , planFile = flagValue "--plan-file" rest
        }

requiredFlag :: String -> [String] -> Either AppError String
requiredFlag key args =
    case flagValue key args of
        Just value -> Right value
        Nothing -> Left (ParseError ("missing " <> key))

flagValue :: String -> [String] -> Maybe String
flagValue key args =
    case args of
        [] -> Nothing
        x : y : rest
            | x == key -> Just y
            | (key <> "=") `isPrefixOf` x -> Just (drop (length key + 1) x)
            | otherwise -> flagValue key (y : rest)
        [x]
            | (key <> "=") `isPrefixOf` x -> Just (drop (length key + 1) x)
            | otherwise -> Nothing

intFlag :: String -> Int -> [String] -> Int
intFlag key fallback args =
    maybe fallback (readDigits fallback) (flagValue key args)

integerFlag :: String -> Integer -> [String] -> Integer
integerFlag key fallback args =
    maybe fallback (readInteger fallback) (flagValue key args)

integerFlagMaybe :: String -> [String] -> Maybe Integer
integerFlagMaybe key args = readInteger 0 <$> flagValue key args

readDigits :: Int -> String -> Int
readDigits fallback value
    | not (null value) && all isDigit value = read value
    | otherwise = fallback

readInteger :: Integer -> String -> Integer
readInteger fallback value
    | not (null value) && all isDigit value = read value
    | otherwise = fallback

splitCommas :: String -> [String]
splitCommas raw =
    case break (== ',') raw of
        (one, "") -> [one | not (null one)]
        (one, _ : rest) -> [one | not (null one)] <> splitCommas rest
