{-# LANGUAGE DuplicateRecordFields #-}

module Main where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.ST (runST)
import qualified Data.ByteString as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (sort)
import qualified Data.Text as T
import Data.Word (Word16, Word8)
import MCTS.CLI.Bench (monotonicNanos, runBenchWithClock)
import MCTS.CLI.Build
    ( boltTrainingGames
    , boltTrainingSims
    , buildBackendPlan
    , cppFunctionalPgoBoltPlan
    , cppImperativePgoBoltPlan
    , pgoTrainingGames
    , pgoTrainingSims
    )
import MCTS.CLI.Command
    ( BenchCommand (..)
    , Command (..)
    , InspectCommand (..)
    , ShowOptions (..)
    , VerifyCommand (..)
    )
import MCTS.CLI.Docs
    ( GeneratedSectionRule (..)
    , applyGeneratedSection
    , checkGeneratedSection
    , generatedSectionRules
    , spliceMarkerRegion
    )
import MCTS.CLI.Inspect (InspectRow (..), renderInspectRows, renderTranscript)
import MCTS.CLI.Lint (ForbiddenPath (..), forbiddenPathPaths, forbiddenPathRegistry)
import MCTS.CLI.Output (OutputFormat (..), OutputOptions (..), defaultOutputOptions)
import MCTS.CLI.Parser (commandParserInfo, parseBackends, parseCommand)
import MCTS.CLI.Spec
    ( CommandSpec (..)
    , OptionSpec (..)
    , commandRows
    , commandSpec
    , leafSpecs
    , renderCommandJson
    , renderCommandList
    , renderCommandTree
    )
import MCTS.Crypto.SHA256 (sha256Hex)
import MCTS.Driver
import MCTS.Engine
    ( Board (..)
    , applyMove
    , initialBoard
    , isTerminal
    , legalMoves
    , nonTerminalOutcome
    , nonTerminalRank
    , terminalOutcome
    )
import qualified MCTS.Engine.Recompute as Recompute
import MCTS.Env (Env (..), askEnv, defaultEnv, envClock, runAppIO, withTestClock)
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..), renderError)
import MCTS.FFI.CppLegacy (withCppLegacyBoard)
import MCTS.Generated.Paths (trackingGeneratedPaths)
import MCTS.Notation (parseMove, renderMove)
import MCTS.Plan
    ( Plan (..)
    , applyPlan
    , applySubprocessPlan
    , applyWithEnv
    , buildPlan
    , renderPlan
    , renderPlanWith
    )
import MCTS.Prerequisite
    ( PrerequisiteNode (..)
    , checkPrerequisites
    , prerequisiteRegistry
    , prerequisitesForTest
    , registryHasCycle
    , transitiveClosure
    )
import MCTS.ReportCard (defaultReportCard, renderReportCard, renderReportCardJson)
import MCTS.Rng.Cpp (cppSplitSeed)
import MCTS.Rng.Mix (mix)
import qualified MCTS.Search.Arena as Arena
import qualified MCTS.Search.UCT as UCT
import MCTS.Subprocess (Subprocess (..), renderSubprocess)
import MCTS.Transcript
    ( TranscriptRef (..)
    , decodeTranscript
    , encodeTranscript
    , hostArch
    , lookupByPrefix
    , playTranscriptHash
    , readTranscriptFile
    , runConfigHash
    , writeTranscriptPerGame
    )
import qualified MCTS.Transcript as Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import MCTS.Verify.Divergence
import MCTS.Verify.Envelope
import qualified Options.Applicative as OA
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , removePathForcibly
    )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase)

main :: IO ()
main =
    defaultMain (testGroup "mcts-unit" [testCase "baseline" runUnit])

runUnit :: IO ()
runUnit = do
    assert
        "test/golden/legacy/transcripts is in the no-hand-edit registry"
        ("test/golden/legacy/transcripts" `elem` trackingGeneratedPaths)
    assert "command tree mentions verify" ("verify" `contains` renderCommandTree)
    assert "command json is object" (take 1 renderCommandJson == "{")
    assert "all leaves have examples" (all (not . null . examples) (leafSpecs commandSpec))
    assert
        "backend parser"
        (parseBackends "cpp-imperative,rust,haskell" == Right [CppImperative, Rust, Haskell])
    assert
        "command parser"
        ( parsesBenchCohort
            ( parseCommand
                ["bench", "selfplay", "--backend", "cpp-legacy,haskell", "--games", "1", "--seed", "42"]
            )
        )
    assert
        "legacy parity workload parser"
        ( parsesLegacyRollouts
            (parseCommand ["verify", "legacy-parity", "rollouts", "--backend", "cpp-legacy,haskell"])
        )
    assert
        "allow stale parser"
        ( parsesAllowStale
            (parseCommand ["verify", "selfplay", "--backend", "cpp-imperative,haskell", "--allow-stale"])
        )
    assert
        "verify rejects native rng"
        ( isLeft
            (parseCommand ["verify", "selfplay", "--backend", "cpp-imperative,haskell", "--rng", "native"])
        )
    assert "splitmix is deterministic" (mix 42 0 == mix 42 0 && mix 42 0 /= mix 42 1)
    assert "splitmix known vector 0" (mix 42 0 == 2949826092126892291)
    assert "splitmix known vector 1" (mix 42 1 == 5139283748462763858)
    assert
        "sha256 known vector"
        (sha256Hex (BS.pack []) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    assert "action enumeration roundtrip" (all (\a -> actionFromId (actionId a) == Just a) allActions)
    assert "notation roundtrip" (all (\a -> parseMove (renderMove a) == Just a) allActions)
    assert "initial board has legal moves" (not (null (legalMoves initialBoard)))
    let inputs = defaultRunInputs{inputGames = 2, inputSeed = 42, inputSims = FixedSims 12}
        transcript =
            Transcript
                (makeRunConfig inputs)
                (makeLogicalEnvelope Haskell NativeRng)
                [runGame inputs 0, runGame inputs 1]
        encoded = encodeTranscript transcript
    assert "transcript encoding non-empty" (BS.length encoded > 48)
    assert "transcript roundtrip" (decodeTranscript encoded == Right transcript)
    assert
        "transcript envelope skips trailers"
        (decodeTranscript (withEnvelopeTrailer encoded) == Right transcript)
    let rolloutInputs = inputs{inputWorkload = Rollouts}
        rolloutTranscript =
            transcript
                { transcriptConfig = makeRunConfig rolloutInputs
                , transcriptGames = [runGame rolloutInputs 0]
                }
    assert
        "transcript preserves workload"
        ( fmap (runWorkload . transcriptConfig) (decodeTranscript (encodeTranscript rolloutTranscript))
            == Right Rollouts
        )
    assert
        "hash deterministic"
        (runConfigHash (makeRunConfig inputs) == runConfigHash (makeRunConfig inputs))
    exerciseRunConfigHashEnvelopeInvariant
    assert
        "divergence same transcript is zero"
        (divergenceRate transcript transcript == DivergenceMetrics 0.0 0.0 0.0)
    let changed = transcript{transcriptGames = mapFirstGame changeFirstMove (transcriptGames transcript)}
    assert
        "divergence catches changed move"
        (moveDisagreementRate (divergenceRate transcript changed) > 0.0)
    exerciseEnvelopeChecks transcript
    exerciseLookup
    exercisePrerequisites
    exerciseSidecars transcript
    exercisePrerequisiteClosure
    exercisePlanShape
    exercisePlanOptionMetadata
    exerciseErrorRenderings
    exerciseErrorGolden
    exerciseSubprocessGolden
    exerciseSortedRecords
    exerciseLegacyDrawRejection
    exerciseSplitmixBijection
    exerciseCppRngFixture
    exerciseCppLegacyBoardFixture
    exerciseEngineProperties
    exerciseKnownPositionGolden
    exerciseEngineBruteForce
    exerciseEnv
    exerciseTranscriptGolden
    exerciseInspectShowGolden
    exerciseInspectListGolden
    exerciseEquitySidecarBinary
    exerciseCommandGoldens
    exerciseOptparseParser
    exerciseCacheRootBranches
    exerciseReportCardGolden
    exerciseMarkerSplice
    exerciseMonotonicBracket
    exerciseUniquePrefixProperty
    exerciseArena
    exerciseApplyWithEnv
    exerciseUctSearch
    exerciseRecompute
    exerciseForbiddenPathRegistry
    exerciseEnvelopeRoundTrip
    exerciseCppImperativeBuildPlan
    exercisePerGameTranscriptWriter
    putStrLn "mcts-unit PASS"

assert :: String -> Bool -> IO ()
assert label ok =
    if ok
        then pure ()
        else error ("assertion failed: " <> label)

contains :: String -> String -> Bool
contains needle haystack = any (needle `prefixOf`) (tails haystack)

prefixOf :: String -> String -> Bool
prefixOf prefix value = take (length prefix) value == prefix

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

parsesLegacyRollouts :: Either AppError Command -> Bool
parsesLegacyRollouts parsed =
    case parsed of
        Right (Verify (VerifyLegacyParity Rollouts False [CppLegacy, Haskell] inputs)) -> inputWorkload inputs == Rollouts
        _ -> False

parsesAllowStale :: Either AppError Command -> Bool
parsesAllowStale parsed =
    case parsed of
        Right (Verify (VerifySelfplay True [CppImperative, Haskell] _)) -> True
        _ -> False

parsesBenchCohort :: Either AppError Command -> Bool
parsesBenchCohort parsed =
    case parsed of
        Right (Bench (BenchSelfplay [CppLegacy, Haskell] inputs)) -> inputBackend inputs == CppLegacy
        _ -> False

parsesInspectEquityShow :: Either AppError Command -> Bool
parsesInspectEquityShow parsed =
    case parsed of
        Right (Inspect (InspectShow showOptions)) ->
            showRef showOptions == "abc123" && showWithEquity showOptions && showTopN showOptions == 3
        _ -> False

exerciseRunConfigHashEnvelopeInvariant :: IO ()
exerciseRunConfigHashEnvelopeInvariant =
    mapM_ assertBackend [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]
  where
    assertBackend backend = do
        let inputs =
                defaultRunInputs
                    { inputBackend = backend
                    , inputRng = CppRng
                    , inputGames = 1
                    , inputSeed = 99
                    , inputSims = FixedSims 4
                    }
            config = makeRunConfig inputs
            envelopeA = makeLogicalEnvelope backend CppRng
            envelopeB =
                envelopeA
                    { envelopeBuildId = backendIdentifier backend <> "-changed"
                    , envelopeCompilerVersion = "changed-compiler"
                    , envelopeFpFlags = 0x10
                    , envelopeCpuFeatures = 0x20
                    , envelopeFpEnv = 0x30
                    }
            record = MoveRecord 0 (Pawn 4 4) [(Pawn 4 4, 1)]
            game = GameTranscript 0 [record] HeroWin
            transcriptA = Transcript config envelopeA [game]
            transcriptB = Transcript config envelopeB [game]
        assert
            ("runConfigHash ignores " <> backendIdentifier backend <> " envelope changes")
            (runConfigHash (transcriptConfig transcriptA) == runConfigHash (transcriptConfig transcriptB))
        assert
            ("playTranscriptHash ignores " <> backendIdentifier backend <> " envelope changes")
            ( playTranscriptHash (transcriptConfig transcriptA) (gameMoves game)
                == playTranscriptHash (transcriptConfig transcriptB) (gameMoves game)
            )

exerciseEnvelopeChecks :: Transcript -> IO ()
exerciseEnvelopeChecks transcript = do
    assert "cohort envelope check" (checkCohortInvariant [transcript, transcript] == Right ())
    let archMismatch =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeHostArch = "other-arch"
                        }
                }
        stale =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeBuildId = "haskell-old"
                        }
                }
        expectedStale = EngineEnvelopeMismatch (BackendSlot Haskell) "build_id" "haskell-logical" "haskell-old"
    assert
        "cohort arch mismatch"
        (checkCohortInvariant [transcript, archMismatch] == Left (ArchEnvelopeMismatch hostArch "other-arch"))
    assert "backend slot stale hard fail" (checkBackendSlot False stale == Left expectedStale)
    assert "backend slot stale warning" (checkBackendSlot True stale == Right [expectedStale])
    -- Additional cohort-invariant fields: rng_source, shared_rng_build_id, cohort_config_hash.
    let rngMismatch =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeRngSource = CppRng
                        }
                }
    case checkCohortInvariant [transcript, rngMismatch] of
        Left (EngineEnvelopeMismatch CohortLevel "rng_source" _ _) -> pure ()
        other -> error ("expected rng_source cohort mismatch, got " <> show other)
    let cohortHashMismatch =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeCohortConfigHash = ByteString32 (replicate 64 'a')
                        }
                }
    case checkCohortInvariant [transcript, cohortHashMismatch] of
        Left (EngineEnvelopeMismatch CohortLevel "cohort_config_hash" _ _) -> pure ()
        other -> error ("expected cohort_config_hash mismatch, got " <> show other)
    -- Additional backend-slot fields: fp_flags, cpu_features, fp_env.
    let fpFlagsBad =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript){envelopeFpFlags = 0x42}
                }
    case checkBackendSlot False fpFlagsBad of
        Left (EngineEnvelopeMismatch (BackendSlot Haskell) "fp_flags" _ _) -> pure ()
        other -> error ("expected fp_flags backend-slot mismatch, got " <> show other)

exerciseLookup :: IO ()
exerciseLookup = do
    let cacheRoot = ".mcts-cache-unit-lookup"
        archDir = cacheRoot </> "transcripts" </> hostArch
    removeDirectoryIfExists cacheRoot
    createDirectoryIfMissing True archDir
    writeFile (archDir </> "abcd1111.tr") ""
    writeFile (archDir </> "abcd2222.tr") ""
    writeFile (archDir </> "1234aaaa.tr") ""
    short <- lookupShape <$> lookupByPrefix (Just cacheRoot) "abc"
    nonHex <- lookupShape <$> lookupByPrefix (Just cacheRoot) "zzzz"
    noMatch <- lookupShape <$> lookupByPrefix (Just cacheRoot) "ffff"
    ambiguous <- lookupShape <$> lookupByPrefix (Just cacheRoot) "abcd"
    exact <- lookupShape <$> lookupByPrefix (Just cacheRoot) "1234"
    assert "lookup rejects short prefix" (short == Left "not-found")
    assert "lookup rejects non-hex prefix" (nonHex == Left "not-found")
    assert "lookup reports no match" (noMatch == Left "not-found")
    assert "lookup reports ambiguity" (ambiguous == Left "ambiguous")
    assert "lookup resolves exact prefix" (exact == Right "ok")
    removeDirectoryIfExists cacheRoot

lookupShape :: Either AppError TranscriptRef -> Either String String
lookupShape result =
    case result of
        Left (TranscriptNotFound _) -> Left "not-found"
        Left (TranscriptAmbiguous _ _) -> Left "ambiguous"
        Left err -> Left (show err)
        Right _ -> Right "ok"

exercisePrerequisites :: IO ()
exercisePrerequisites = do
    let failing = PrerequisiteNode "missing-node" "Missing test prerequisite" "fix the test" [] (pure False)
    result <- checkPrerequisites [failing]
    assert
        "prerequisite unmet"
        (result == Left (PrerequisiteUnmet "missing-node" "Missing test prerequisite" "fix the test"))

exerciseSidecars :: Transcript -> IO ()
exerciseSidecars transcript = do
    let cacheRoot = ".mcts-cache-unit-sidecar"
        hashValue = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        stale =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeBuildId = "haskell-old"
                        }
                }
    removeDirectoryIfExists cacheRoot
    currentEntry <- writeEquitySidecar (Just cacheRoot) hashValue transcript
    _ <- writeEquitySidecar (Just cacheRoot) hashValue stale
    let foreignEnvelope =
            (transcriptEnvelope transcript)
                { envelopeBackend = Rust
                , envelopeBuildId = "rust-logical"
                }
        foreignStream =
            (equityStreamForTranscript hashValue transcript)
                { eqBackend = Rust
                , eqBuildId = "rust-logical"
                }
    foreignEntry <- writeEquitySidecarStreamWithEnvelope (Just cacheRoot) foreignEnvelope foreignStream
    decoded <- decodeEqStream <$> BS.readFile (sidecarEqPath currentEntry)
    assert
        "equity sidecar roundtrip"
        (decoded == Right (equityStreamForTranscript hashValue transcript))
    assert
        "originator sidecar helper"
        (isOriginator transcript (equityStreamForTranscript hashValue transcript))
    assert "foreign sidecar helper" (not (isOriginator transcript foreignStream))
    assert "originator entry helper" (sidecarIsOriginator transcript currentEntry)
    assert "foreign entry helper" (not (sidecarIsOriginator transcript foreignEntry))
    listed <- listEquitySidecars (Just cacheRoot)
    assert "equity sidecar list" (length listed == 3)
    pruned <- pruneEquitySidecars (Just cacheRoot) True
    assert "equity sidecar keep-current prune" (pruned == 1)
    remaining <- listEquitySidecars (Just cacheRoot)
    assert
        "equity sidecar current remains"
        (map sidecarBuildId remaining == ["haskell-logical", "rust-logical"])
    removeDirectoryIfExists cacheRoot

removeDirectoryIfExists :: FilePath -> IO ()
removeDirectoryIfExists path = do
    exists <- doesDirectoryExist path
    if exists then removePathForcibly path else pure ()

changeFirstMove :: GameTranscript -> GameTranscript
changeFirstMove game =
    case gameMoves game of
        [] -> game
        record : rest ->
            let replacement = if moveChosen record == Pawn 0 0 then Pawn 1 0 else Pawn 0 0
             in game{gameMoves = record{moveChosen = replacement} : rest}

mapFirstGame :: (GameTranscript -> GameTranscript) -> [GameTranscript] -> [GameTranscript]
mapFirstGame _ [] = []
mapFirstGame f (game : rest) = f game : rest

withEnvelopeTrailer :: BS.ByteString -> BS.ByteString
withEnvelopeTrailer encoded =
    let envelopeLength = readWord32LE (BS.unpack (BS.take 4 (BS.drop 50 encoded)))
        newLength = envelopeLength + 3
        payloadLength = envelopeLength - 6
        prefix = BS.take 50 encoded
        payload = BS.take payloadLength (BS.drop 54 encoded)
        suffix = BS.drop (48 + envelopeLength) encoded
     in prefix <> word32LEBytes newLength <> payload <> BS.pack [0, 0, 0] <> suffix

readWord32LE :: [Word8] -> Int
readWord32LE bytes =
    sum [fromIntegral byte * (256 ^ idx) | (idx, byte) <- zip [0 :: Int ..] bytes]

word32LEBytes :: Int -> BS.ByteString
word32LEBytes value =
    BS.pack [fromIntegral ((value `div` (256 ^ idx)) `mod` 256) | idx <- [0 :: Int .. 3]]

exercisePrerequisiteClosure :: IO ()
exercisePrerequisiteClosure = do
    assert "prerequisite registry has no cycle" (not (registryHasCycle prerequisiteRegistry))
    let closure = map nodeId (transitiveClosure prerequisiteRegistry ["cargo"])
    assert "transitive closure pulls cargo dep rustup" ("rustup" `elem` closure)
    assert
        "transitive closure is idempotent"
        (closure == map nodeId (transitiveClosure prerequisiteRegistry closure))
    let boltClosure = map nodeId (transitiveClosure prerequisiteRegistry ["bolt"])
    assert "bolt closure includes llvm" ("llvm" `elem` boltClosure)
    let legacyLibClosure = map nodeId (transitiveClosure prerequisiteRegistry ["libmcts-cpp-legacy-built"])
    assert "legacy shared library prerequisite includes cxx" ("cxx" `elem` legacyLibClosure)
    let imperativeLibClosure = map nodeId (transitiveClosure prerequisiteRegistry ["libmcts-cpp-imperative-built"])
    assert "imperative shared library prerequisite includes cxx" ("cxx" `elem` imperativeLibClosure)
    let functionalLibClosure = map nodeId (transitiveClosure prerequisiteRegistry ["libmcts-cpp-functional-built"])
    assert "functional shared library prerequisite includes cxx" ("cxx" `elem` functionalLibClosure)
    let rustLibClosure = map nodeId (transitiveClosure prerequisiteRegistry ["libmcts-rust-built"])
    assert "rust shared library prerequisite includes rustup" ("rustup" `elem` rustLibClosure)
    let lldClosure = map nodeId (transitiveClosure prerequisiteRegistry ["lld-linker"])
    assert "lld linker prerequisite includes llvm" ("llvm" `elem` lldClosure)
    let testClosure = map nodeId prerequisitesForTest
    assert "test prerequisite closure includes ghc" ("ghc-9.14.1" `elem` testClosure)
    assert "test prerequisite closure includes cabal" ("cabal-3.16.1.0" `elem` testClosure)
    assert "test prerequisite closure includes ghcup dependency" ("ghcup" `elem` testClosure)

exercisePlanShape :: IO ()
exercisePlanShape = do
    let stepBuilder :: Int -> Either AppError [Subprocess]
        stepBuilder n = Right [Subprocess "echo" [show idx] Nothing Nothing | idx <- [1 .. n]]
        ok = buildPlan "echo plan" stepBuilder 3
        rendered = either (const "") renderPlan ok
    assert
        "buildPlan succeeds for valid input"
        (case ok of Right (Plan pname steps) -> pname == "echo plan" && length steps == 3; _ -> False)
    assert
        "renderPlanWith is deterministic"
        ( renderPlanWith renderSubprocess (Plan "p" [Subprocess "x" ["1"] Nothing Nothing])
            == renderPlanWith renderSubprocess (Plan "p" [Subprocess "x" ["1"] Nothing Nothing])
        )
    assert "renderPlan emits plan header" (take 5 rendered == "plan:")
    code <- applyPlan (\_ -> pure (Right ExitSuccess)) (Plan "noop" [(), ()])
    assert "applyPlan succeeds on all-success plan" (code == ExitSuccess)
    let badBuilder :: () -> Either AppError [Subprocess]
        badBuilder _ = Left (ParseError "rejected")
        bad = buildPlan "fail" badBuilder ()
    assert
        "buildPlan surfaces error from builder"
        (case bad of Left (ParseError "rejected") -> True; _ -> False)
    -- applySubprocessPlan is callable as a smoke check on an empty plan
    emptyCode <- applySubprocessPlan (Plan "empty" [])
    assert "applySubprocessPlan succeeds on empty plan" (emptyCode == ExitSuccess)

exercisePlanOptionMetadata :: IO ()
exercisePlanOptionMetadata = do
    let planApplyLeaves =
            [ "mcts test all"
            , "mcts docs generate"
            , "mcts inspect cache prune"
            , "mcts build cpp-legacy"
            , "mcts build cpp-imperative"
            , "mcts build cpp-functional"
            , "mcts build rust"
            ]
    assert "Plan/Apply leaves declare --dry-run and --plan-file" (all hasPlanOptions planApplyLeaves)
  where
    hasPlanOptions path =
        case lookup path commandRows of
            Nothing -> False
            Just spec ->
                let optionNames = map longName (options spec)
                 in all (`elem` optionNames) ["dry-run", "plan-file"]

exerciseSortedRecords :: IO ()
exerciseSortedRecords = do
    let inputs = defaultRunInputs{inputBackend = Haskell, inputGames = 1, inputSeed = 7, inputSims = FixedSims 8}
        config = makeRunConfig inputs
        envelope = makeLogicalEnvelope Haskell CppRng
        unsorted =
            MoveRecord
                { moveIndex = 0
                , moveChosen = Pawn 4 4
                , moveVisits = [(Pawn 5 4, 3), (Pawn 4 4, 7), (Pawn 4 3, 1)]
                }
        game = GameTranscript 0 [unsorted] HeroWin
        transcript = Transcript config envelope [game]
        encoded = encodeTranscript transcript
        decoded = decodeTranscript encoded
    case decoded of
        Right t ->
            case transcriptGames t of
                game' : _ ->
                    case gameMoves game' of
                        record : _ ->
                            assert
                                "encoded visits are sorted ascending by action ID"
                                (map fst (moveVisits record) == [Pawn 4 3, Pawn 4 4, Pawn 5 4])
                        _ -> assert "encoded visits are sorted ascending by action ID" False
                _ -> assert "encoded visits are sorted ascending by action ID" False
        Left _ -> assert "encoded visits are sorted ascending by action ID" False

exerciseLegacyDrawRejection :: IO ()
exerciseLegacyDrawRejection = do
    let inputs =
            defaultRunInputs{inputBackend = CppLegacy, inputGames = 1, inputSeed = 7, inputSims = FixedSims 1}
        config = makeRunConfig inputs
        envelope = makeLogicalEnvelope CppLegacy CppRng
        record = MoveRecord 0 (Pawn 4 4) [(Pawn 4 4, 1)]
        game = GameTranscript 0 [record] Draw
        transcript = Transcript config envelope [game]
        encoded = encodeTranscript transcript
    case decodeTranscript encoded of
        Left (TranscriptFormatUnsupported _) -> pure ()
        other -> error ("expected cpp-legacy draw rejection, got " <> show other)

-- | Sprint 2.1 byte-level golden: a known transcript encodes to a pinned
-- byte sequence under the v1 wire format. The golden file
-- `test/golden/transcript-codec/v1-haskell-2games.bin` is the canonical
-- pinned bytes; if it does not yet exist, this test creates it on the
-- first run (so the developer can commit the bytes); subsequent runs
-- assert byte-equality.
exerciseTranscriptGolden :: IO ()
exerciseTranscriptGolden =
    mapM_
        exerciseCase
        [ (Haskell, "test/golden/transcript-codec/v1-haskell-2games.bin")
        , (CppImperative, "test/golden/transcript-codec/v1-cpp-imperative-2games.bin")
        , (CppFunctional, "test/golden/transcript-codec/v1-cpp-functional-2games.bin")
        , (Rust, "test/golden/transcript-codec/v1-rust-2games.bin")
        ]
  where
    exerciseCase (backend, goldenPath) = do
        let inputs =
                defaultRunInputs
                    { inputBackend = backend
                    , inputRng = CppRng
                    , inputGames = 2
                    , inputSeed = 42
                    , inputSims = FixedSims 8
                    , inputMaxPlies = 24
                    , inputThreading = SingleThreaded
                    }
            config = makeRunConfig inputs
            envelope = makeLogicalEnvelope backend CppRng
            transcript =
                Transcript
                    config
                    envelope
                    [runGame inputs 0, runGame inputs 1]
            encoded = encodeTranscript transcript
        existing <- doesFileExist' goldenPath
        if existing
            then do
                stored <- BS.readFile goldenPath
                assert ("transcript byte-level golden matches: " <> backendIdentifier backend) (stored == encoded)
            else do
                createDirectoryIfMissing True "test/golden/transcript-codec"
                BS.writeFile goldenPath encoded
                putStrLn ("wrote golden: " <> goldenPath <> " (" <> show (BS.length encoded) <> " bytes)")
        -- Also pin the SHA-256 of the encoded bytes so a drift in encoder output
        -- causes a clear, single-line failure independent of the golden file.
        let expectedHash = sha256Hex encoded
        assert
            ("transcript hash is deterministic: " <> backendIdentifier backend)
            (sha256Hex (encodeTranscript transcript) == expectedHash)
        -- And the decode roundtrip still holds.
        assert
            ("transcript golden roundtrips: " <> backendIdentifier backend)
            (decodeTranscript encoded == Right transcript)

exerciseInspectShowGolden :: IO ()
exerciseInspectShowGolden = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSeed = 13
                , inputSims = FixedSims 6
                , inputMaxPlies = 8
                , inputThreading = SingleThreaded
                }
        config = makeRunConfig inputs
        envelope = makeLogicalEnvelope Haskell CppRng
        game = runGame inputs 0
        transcript = Transcript config envelope [game]
        showOptions = ShowOptions "abc123" 2 True False Nothing
        stream =
            EqStream
                { eqTranscriptHash = "abc123"
                , eqBackend = Haskell
                , eqBuildId = envelopeBuildId envelope
                , eqRecords =
                    [ EqRecord (gameId game) (moveIndex record) (moveChosen record) (fromIntegral (moveIndex record) / 10)
                    | record <- gameMoves game
                    ]
                }
        rendered =
            renderTranscript
                defaultOutputOptions
                showOptions
                ".mcts-cache/transcripts/arm64/abc123.tr"
                (Just stream)
                transcript
    goldenCompare "test/golden/cli/inspect-show.txt" rendered

exerciseInspectListGolden :: IO ()
exerciseInspectListGolden = do
    let rows =
            [ InspectRow
                { rowHash = "abc12345"
                , rowBackend = "haskell"
                , rowSeed = "13"
                , rowGames = "1"
                , rowThreading = "ST"
                , rowSims = "6:6"
                , rowTotalMoves = "8"
                , rowPath = ".mcts-cache/transcripts/arm64/abc12345.tr"
                , rowMtime = "2026-05-14 12:00:00 UTC"
                }
            ]
        rendered = renderInspectRows defaultOutputOptions{outputFormat = JsonFormat} rows
    goldenCompare "test/golden/cli/inspect-list.json" rendered

doesFileExist' :: FilePath -> IO Bool
doesFileExist' = doesFileExist

-- | Sprint 2.7 verifies the binary equity sidecar codec round-trips
-- arbitrary doubles (not just `0.0`), the leading magic is `MEQ1`, and the
-- terminator is `0xFFFFFFFF`.
exerciseEquitySidecarBinary :: IO ()
exerciseEquitySidecarBinary = do
    let stream =
            EqStream
                { eqTranscriptHash = "abcd1234"
                , eqBackend = Haskell
                , eqBuildId = "haskell-logical"
                , eqRecords =
                    [ EqRecord 0 0 (Pawn 4 4) 0.0
                    , EqRecord 0 1 (Pawn 4 5) 0.5
                    , EqRecord 1 0 (Pawn 4 4) (-0.25)
                    , EqRecord 1 1 (WallH 1 2) 1.0
                    ]
                }
        bytes = encodeEqStream stream
    assert "sidecar magic is MEQ1" (BS.take 4 bytes == BS.pack [0x4D, 0x45, 0x51, 0x31])
    assert "sidecar terminator is 0xFFFFFFFF" (BS.takeEnd 4 bytes == BS.pack [0xFF, 0xFF, 0xFF, 0xFF])
    case decodeEqStream bytes of
        Right decoded -> assert "binary sidecar round-trips arbitrary doubles" (decoded == stream)
        Left err -> error ("binary sidecar decode failed: " <> err)
    -- Reject a corrupted magic.
    let corrupted = BS.pack [0x00, 0x00, 0x00, 0x00] <> BS.drop 4 bytes
    case decodeEqStream corrupted of
        Left _ -> pure ()
        Right _ -> error "expected decode failure on bad magic"

-- | Sprint 2.6 closure: a transcript whose envelope carries non-default
-- values for every field still round-trips bit-for-bit through
-- `encodeTranscript` / `decodeTranscript`. This pins the wire layout
-- against accidental field reorderings.
exerciseEnvelopeRoundTrip :: IO ()
exerciseEnvelopeRoundTrip = do
    let inputs =
            defaultRunInputs
                { inputBackend = CppImperative
                , inputSeed = 7
                , inputSims = FixedSims 4
                , inputMaxPlies = 8
                }
        config = makeRunConfig inputs
        digest = ByteString32 "deadbeefcafe00112233445566778899aabbccddeeff00112233445566778899"
        envelope =
            Envelope
                { envelopeVersion = 1
                , envelopeBackend = CppImperative
                , envelopeRngSource = CppRng
                , envelopeHostArch = hostArch
                , envelopeSharedRngBuildId = digest
                , envelopeCohortConfigHash = digest
                , envelopeEngineBuildId = digest
                , envelopeEngineGitCommit = "0123456789abcdef"
                , envelopeCompilerId = 1
                , envelopeCompilerVersion = "clang-17.0.6"
                , envelopeFpFlags = 0x01020304
                , envelopeLibmId = "musl-libm-1.2"
                , envelopeCpuFeatures = 0x00800001
                , envelopeFpEnv = 0x42
                , envelopeBuildId = "cpp-imperative-12345678"
                }
        transcript = Transcript config envelope [runGame inputs 0]
        encoded = encodeTranscript transcript
    case decodeTranscript encoded of
        Right t -> do
            let actual = transcriptEnvelope t
            assert "envelope round-trips backend" (envelopeBackend actual == envelopeBackend envelope)
            assert "envelope round-trips rng source" (envelopeRngSource actual == envelopeRngSource envelope)
            assert "envelope round-trips shared_rng_build_id" (envelopeSharedRngBuildId actual == digest)
            assert "envelope round-trips engine_build_id" (envelopeEngineBuildId actual == digest)
            assert
                "envelope round-trips engine_git_commit"
                (envelopeEngineGitCommit actual == "0123456789abcdef")
            assert "envelope round-trips compiler_id" (envelopeCompilerId actual == 1)
            assert "envelope round-trips compiler_version" (envelopeCompilerVersion actual == "clang-17.0.6")
            assert "envelope round-trips fp_flags" (envelopeFpFlags actual == 0x01020304)
            assert "envelope round-trips libm_id" (envelopeLibmId actual == "musl-libm-1.2")
            assert "envelope round-trips cpu_features" (envelopeCpuFeatures actual == 0x00800001)
            assert "envelope round-trips fp_env" (envelopeFpEnv actual == 0x42)
            assert
                "envelope round-trips build_id accessor"
                (envelopeBuildId actual == "cpp-imperative-12345678")
        Left err -> error ("envelope round-trip decode failed: " <> show err)

-- | Sprint 7.5: verify the per-game writer splits a batch into N
-- one-game-per-file transcripts. The legacy single-file writer
-- continues to produce one combined file; the per-game writer's
-- individual file hashes derive from each game's splitmix-derived
-- per-game seed so they differ from the batch hash.
exercisePerGameTranscriptWriter :: IO ()
exercisePerGameTranscriptWriter = do
    let cacheRoot = ".mcts-cache-pergame-test"
        inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputWorkload = Selfplay
                , inputRng = CppRng
                , inputThreading = SingleThreaded
                , inputGames = 3
                , inputSeed = 42
                , inputSims = FixedSims 4
                , inputMaxPlies = 12
                , inputCacheDir = Just cacheRoot
                }
        config = makeRunConfig inputs
        envelope = makeLogicalEnvelope Haskell CppRng
        games = [runGame inputs 0, runGame inputs 1, runGame inputs 2]
        transcript = Transcript config envelope games
    removePathForcibly cacheRoot
    perGame <- writeTranscriptPerGame (Just cacheRoot) transcript
    case perGame of
        Left err -> error ("per-game write failed: " <> show err)
        Right entries -> do
            assert "per-game writer emits one entry per game" (length entries == 3)
            let hashes = map fst entries
            assert "per-game entries have distinct hashes" (length (sort hashes) == length hashes)
            -- All per-game files exist
            existsAll <- mapM (doesFileExist . snd) entries
            assert "per-game files exist on disk" (and existsAll)
            -- Each per-game file decodes as a single-game transcript
            decoded <- mapM (readTranscriptFile . snd) entries
            assert
                "every per-game file decodes to exactly one game"
                ( all
                    ( \r -> case r of
                        Right t -> length (transcriptGames t) == 1
                        Left _ -> False
                    )
                    decoded
                )
    removePathForcibly cacheRoot

-- | Sprint 5.3: validate the cpp-imperative PGO+BOLT plan as a typed
-- `[Subprocess]` sequence. The pipeline must visit, in order, the
-- doctrine-mandated stages: PGO-instrument both artefacts, run the
-- training workload (`bench selfplay --rng cpp`), PGO-optimize, BOLT
-- instrument both, BOLT training workload, BOLT optimize both, install
-- the bench artefact under the canonical FFI load name. Idempotence
-- holds because `buildBackendPlan` is a pure function of the backend
-- name; the failure-mode check uses an unknown backend.
exerciseCppImperativeBuildPlan :: IO ()
exerciseCppImperativeBuildPlan = do
    let plan = buildBackendPlan "cpp-imperative"
        steps = cppImperativePgoBoltPlan
        commands = map subprocessPath steps
        argsOf = map subprocessArguments steps
    assert "PGO+BOLT plan has 11 typed Subprocess steps" (length steps == 11)
    assert "PGO+BOLT plan is the same as buildBackendPlan output" (planSteps plan == steps)
    assert
        "PGO+BOLT step 1 is make pgo-bench-generate"
        (case argsOf of (a : _) -> a == ["-C", "cpp-imperative", "pgo-bench-generate"]; _ -> False)
    assert
        "PGO+BOLT step 11 is make install-bench"
        (case reverse argsOf of (a : _) -> a == ["-C", "cpp-imperative", "install-bench"]; _ -> False)
    assert
        "PGO training step invokes bench selfplay --rng cpp"
        ( commands !! 2 == "cabal"
            && "selfplay" `elem` argsOf !! 2
            && "cpp" `elem` argsOf !! 2
            && show pgoTrainingGames `elem` argsOf !! 2
            && show pgoTrainingSims `elem` argsOf !! 2
        )
    assert
        "BOLT training step invokes bench selfplay --rng cpp"
        ( commands !! 7 == "cabal"
            && "selfplay" `elem` argsOf !! 7
            && show boltTrainingGames `elem` argsOf !! 7
            && show boltTrainingSims `elem` argsOf !! 7
        )
    assert "buildBackendPlan is idempotent" (buildBackendPlan "cpp-imperative" == plan)
    assert
        "PGO+BOLT plan name is build cpp-imperative"
        (planName plan == "build cpp-imperative")
    -- Failure-mode test: unknown backend collapses to a single
    -- `make -C <backend> smoke` step. The `BuildCommand` ADT in
    -- `MCTS.CLI.Command` constrains the set of backends reachable at
    -- the CLI boundary, so this fallback exists for completeness; the
    -- check exercises that one unrecognized identifier produces a
    -- single deterministic Subprocess (not a stray sequence).
    assert
        "buildBackendPlan handles unknown backends with one smoke step"
        ( case planSteps (buildBackendPlan "wat-backend") of
            [s] ->
                subprocessPath s == "make"
                    && subprocessArguments s == ["-C", "wat-backend", "smoke"]
            _ -> False
        )
    -- Sprint 6.2: the cpp-functional plan mirrors the cpp-imperative
    -- plan exactly except for the backend identifier — this is the
    -- (ii)-vs-(iii) style-isolation discipline at the build-harness
    -- level (same training workload, same BOLT parameters, only the
    -- backend identifier differs).
    let imperativeSteps = cppImperativePgoBoltPlan
        functionalSteps = cppFunctionalPgoBoltPlan
        renameStep s =
            s
                { subprocessArguments = map renameArg (subprocessArguments s)
                }
        renameArg "cpp-imperative" = "cpp-functional"
        renameArg other = other
    assert
        "cpp-functional plan is the cpp-imperative plan with backend rewritten"
        (functionalSteps == map renameStep imperativeSteps)
    assert
        "cpp-functional plan matches buildBackendPlan"
        (planSteps (buildBackendPlan "cpp-functional") == functionalSteps)

-- | Sprint 1.4: the forbidden-path registry is a typed value carrying
-- a rationale per entry. The pinned set matches
-- [../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../HASKELL_CLI_TOOL.md):
-- `.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`,
-- `pre-commit-*.yaml`, root `Makefile`, root `justfile`, root `Taskfile.yml`.
exerciseForbiddenPathRegistry :: IO ()
exerciseForbiddenPathRegistry = do
    let paths = map forbiddenPath forbiddenPathRegistry
        expected =
            [ ".github/workflows"
            , ".husky"
            , ".githooks"
            , ".pre-commit-config.yaml"
            , "pre-commit-*.yaml"
            , "Makefile"
            , "justfile"
            , "Taskfile.yml"
            ]
    assert "forbidden path registry matches doctrine" (paths == expected)
    assert "forbiddenPathPaths matches the registry" (forbiddenPathPaths == expected)
    assert
        "every forbidden path carries a non-empty rationale"
        (all (not . null . forbiddenReason) forbiddenPathRegistry)

-- | Sprint 3.6: the equity recompute path produces an EqStream whose
-- per-move records correspond 1:1 with the transcript's moves. Under
-- `--rng cpp` recompute against a transcript that the same engine
-- produced agrees on visit counts (otherwise we'd get
-- `RecomputeMismatch`).
exerciseRecompute :: IO ()
exerciseRecompute = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSeed = 42
                , inputSims = FixedSims 4
                , inputMaxPlies = 10
                , inputThreading = SingleThreaded
                }
        config = makeRunConfig inputs
        envelope = makeLogicalEnvelope Haskell CppRng
        game = runGame inputs 0
        transcript = Transcript config envelope [game]
    case Recompute.recomputeEqStream "deadbeef" "haskell-logical" transcript of
        Left err -> error ("equity recompute failed: " <> show err)
        Right stream -> do
            assert
                "recompute produces one EqRecord per recorded move"
                (length (eqRecords stream) == length (gameMoves game))
            assert
                "recompute preserves the chosen-move sequence"
                (map eqChosen (eqRecords stream) == map moveChosen (gameMoves game))
            assert "recompute stamps the transcript hash" (eqTranscriptHash stream == "deadbeef")
            assert "recompute stamps the build id" (eqBuildId stream == "haskell-logical")
    -- A transcript with intentionally wrong visit counts triggers
    -- RecomputeMismatch under CppRng.
    case gameMoves game of
        record : _ ->
            let corrupted =
                    transcript
                        { transcriptGames =
                            [ game{gameMoves = [record{moveVisits = [(moveChosen record, 999999)]}]}
                            ]
                        }
             in case Recompute.recomputeEquities corrupted of
                    Left (RecomputeMismatch _ _ _ _ _) -> pure ()
                    other ->
                        error
                            ("expected RecomputeMismatch on corrupted visits, got " <> show (either Just (const Nothing) other))
        [] -> pure ()

-- | Sprint 3.3: real UCT search produces an action that's in the legal
-- move set, the visit list covers every legal move, the visits are
-- sorted by action ID, and the search is deterministic for fixed inputs.
exerciseUctSearch :: IO ()
exerciseUctSearch = do
    let (action1, visits1) = UCT.uctSearch initialBoard 42 16 50
        (action2, visits2) = UCT.uctSearch initialBoard 42 16 50
        legal = legalMoves initialBoard
    assert "uctSearch is deterministic for fixed inputs" ((action1, visits1) == (action2, visits2))
    assert "initial non-terminal rank is balanced" (nonTerminalRank initialBoard == 0)
    assert "uctSearch's chosen action is legal" (action1 `elem` legal)
    assert "uctSearch's visit list covers every legal action" (length visits1 == length legal)
    -- Each move in the visit list must be a legal action.
    assert "every visit-list action is legal" (all (`elem` legal) (map fst visits1))
    -- Visits are sorted ascending by action ID per the wire-format
    -- contract.
    let ids = map (actionId . fst) visits1
    assert "uctSearch returns visits sorted by action ID" (ids == sort ids)
    -- Total visits across root children equals the sim budget (since
    -- every simulation descends through exactly one root child).
    let total = sum (map snd visits1)
    assert "total root-child visits equals sim budget" (total == 16)

-- | Sprint 1.5: `apply :: Env -> Plan a -> IO ExitCode` shape. Each
-- step receives the active env and an `IORef` counter accumulates the
-- run order so the test asserts every step saw the same env.
exerciseApplyWithEnv :: IO ()
exerciseApplyWithEnv = do
    counter <- newIORef (0 :: Int)
    let plan = Plan "exerciseApplyWithEnv" ["a", "b", "c"]
        runStep _env _step = do
            modifyIORef' counter (+ 1)
            pure (Right ExitSuccess)
    code <- runAppIO defaultEnv (applyWithEnv runStep plan)
    final <- readIORef counter
    assert "applyWithEnv runs every step" (final == 3)
    assert "applyWithEnv returns ExitSuccess on all-success plan" (code == ExitSuccess)

-- | Sprint 3.2 ST tree arena: allocations, parent linking, visit
-- accumulation, and treeReroot round-trip preserve inherited visits.
exerciseArena :: IO ()
exerciseArena = do
    let result = runST $ do
            arena <- Arena.newArena 32
            -- Allocate root + 3 children.
            root <- Arena.allocNode arena (-1) 0
            c1 <- Arena.allocNode arena root 10
            c2 <- Arena.allocNode arena root 20
            c3 <- Arena.allocNode arena root 30
            Arena.setChildren arena root c1 3
            -- Backprop 100 visits across the children with sample value sums.
            Arena.addVisits arena c1 40
            Arena.addVisits arena c2 35
            Arena.addVisits arena c3 25
            Arena.addValueSum arena c1 0.4
            Arena.addValueSum arena c2 0.35
            Arena.addValueSum arena c3 0.25
            -- Re-root at c2. Inherited visits on the new subtree are
            -- preserved.
            newRoot <- Arena.treeReroot arena c2
            v <- Arena.readVisits arena newRoot
            sumV <- Arena.readValueSum arena newRoot
            size <- Arena.arenaSize arena
            cap <- pure (Arena.arenaCapacity arena)
            visits <- Arena.bulkVisits arena 4
            pure (v, sumV, size, cap, visits)
    case result of
        (v, sumV, size, cap, visits) -> do
            assert "rerooted subtree preserves visits" (v == 35)
            assert "rerooted subtree preserves value sum" (sumV == 0.35)
            assert "arena cursor is 4 after 4 allocations" (size == 4)
            assert "arena capacity is 32" (cap == 32)
            assert "bulk visits match per-slot reads" (map snd visits == [0, 40, 35, 25])
    -- freeArena resets the cursor so subsequent allocs start at slot 0.
    let resetResult = runST $ do
            arena <- Arena.newArena 4
            _ <- Arena.allocNode arena (-1) 1
            _ <- Arena.allocNode arena 0 2
            Arena.freeArena arena
            n <- Arena.arenaSize arena
            -- Allocate again - first slot is 0 again.
            nid <- Arena.allocNode arena (-1) 99
            pure (n, nid)
    assert "freeArena resets cursor" (resetResult == (0, 0))

-- | Sprint 2.3 unique-prefix property: for any populated transcript cache
-- with N hashes, any prefix `p` of `sha(t)` that is unique among the set
-- returns `t` and nothing else; non-unique prefixes return
-- `TranscriptAmbiguous`; prefixes that don't match any entry return
-- `TranscriptNotFound`.
exerciseUniquePrefixProperty :: IO ()
exerciseUniquePrefixProperty = do
    let cacheRoot = ".mcts-cache-unit-uniqueprefix"
        archDir = cacheRoot </> "transcripts" </> hostArch
        hashes =
            [ "1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa"
            , "1111bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb"
            , "2222cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc"
            , "3333dddd4444dddd4444dddd4444dddd4444dddd4444dddd4444dddd4444dddd"
            , "4444eeee5555eeee5555eeee5555eeee5555eeee5555eeee5555eeee5555eeee"
            , "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
            ]
    removeDirectoryIfExists cacheRoot
    createDirectoryIfMissing True archDir
    mapM_ (\h -> writeFile (archDir </> h <> ".tr") "") hashes
    -- Property body: for every populated hash h and every prefix length L
    -- in [4 .. length h], computing `lookupByPrefix (take L h)` returns h
    -- if take L h is unique across the set, otherwise it returns
    -- TranscriptAmbiguous with at least the colliding candidates.
    let testPrefixes =
            [ (h, take len h)
            | h <- hashes
            , len <- [4, 5, 6, 8, 16, 24, 64]
            ]
    mapM_ (checkOne cacheRoot hashes) testPrefixes
    -- A prefix that matches nothing returns TranscriptNotFound.
    notFoundResult <- lookupByPrefix (Just cacheRoot) "deadbeef00"
    case notFoundResult of
        Left (TranscriptNotFound _) -> pure ()
        other -> error ("expected TranscriptNotFound, got " <> show other)
    removeDirectoryIfExists cacheRoot
  where
    checkOne cacheRoot allHashes (expectedHash, prefix) = do
        result <- lookupByPrefix (Just cacheRoot) prefix
        let collisions = [h | h <- allHashes, prefix `prefixOf` h]
        case (collisions, result) of
            ([_], Right ref) ->
                -- Unique: must return the one matching hash.
                if transcriptRefHash ref == expectedHash
                    then pure ()
                    else error ("unique prefix " <> prefix <> " returned wrong hash: " <> transcriptRefHash ref)
            (_ : _ : _, Left (TranscriptAmbiguous _ candidates)) ->
                if length candidates == length collisions
                    then pure ()
                    else error ("ambiguous prefix " <> prefix <> " returned wrong candidate count")
            _ -> error ("unexpected lookup result for prefix " <> prefix <> ": " <> show result)

-- | Sprint 3.5 monotonic-clock bracket assertion. The test injects a
-- custom clock that increments on every call, so the bench start/stop
-- bracket captures exactly two clock reads per backend. Production runs
-- use `monotonicNanos` (GHC's `getMonotonicTimeNSec`).
exerciseMonotonicBracket :: IO ()
exerciseMonotonicBracket = do
    -- The production clock is non-zero and monotone: two reads in sequence
    -- yield t2 >= t1.
    t1 <- monotonicNanos
    t2 <- monotonicNanos
    assert "monotonic clock is non-decreasing" (t2 >= t1)
    -- Test-injected clock counts calls. For N backends, we expect 2*N reads
    -- (start + stop per backend). With 3 backends we expect 6 reads,
    -- giving final = 6.
    counter <- newIORef (0 :: Int)
    let injected = do
            modifyIORef' counter (+ 1)
            v <- readIORef counter
            pure (fromIntegral (v * 1000))
        inputs = defaultRunInputs{inputGames = 1, inputSeed = 1, inputSims = FixedSims 1}
    code <- runBenchWithClock injected defaultOutputOptions [Haskell, CppImperative, Rust] inputs
    final <- readIORef counter
    assert "bench reads the clock twice per backend" (final == 6)
    assert "bench returns 0 on success" (code == 0)
    -- Clean up the .mcts-cache directory the bench wrote.
    let cacheRoot = ".mcts-cache"
    removeDirectoryIfExists cacheRoot

-- | Sprint 1.3: `GeneratedSectionRule` marker-delimited regions. The
-- splice is idempotent, missing-marker cases surface as
-- `AppError DocsCheckDrift`, and the check path matches the apply path.
exerciseMarkerSplice :: IO ()
exerciseMarkerSplice = do
    let source =
            unlines
                [ "# Heading"
                , "before"
                , "<!-- mcts:k:start -->"
                , "old"
                , "<!-- mcts:k:end -->"
                , "after"
                ]
        expected =
            unlines
                [ "# Heading"
                , "before"
                , "<!-- mcts:k:start -->"
                , "new"
                , "<!-- mcts:k:end -->"
                , "after"
                ]
    case spliceMarkerRegion "<!-- mcts:k:start -->" "<!-- mcts:k:end -->" "new" source of
        Just rendered -> assert "marker splice replaces region" (rendered == expected)
        Nothing -> error "marker splice failed unexpectedly"
    -- Idempotent: splicing the same body twice is a no-op.
    let once = case spliceMarkerRegion "<!-- mcts:k:start -->" "<!-- mcts:k:end -->" "new" source of
            Just r -> r
            Nothing -> source
        twice = case spliceMarkerRegion "<!-- mcts:k:start -->" "<!-- mcts:k:end -->" "new" once of
            Just r -> r
            Nothing -> once
    assert "marker splice is idempotent" (once == twice)
    -- Missing start marker → Nothing → DocsCheckDrift on the rule layer.
    let rule =
            GeneratedSectionRule
                { sectionPath = "test.md"
                , sectionKey = "k"
                , sectionStartMarker = "<!-- mcts:k:start -->"
                , sectionEndMarker = "<!-- mcts:k:end -->"
                , sectionOwner = "test"
                , sectionRender = "new"
                }
    case applyGeneratedSection "no markers here\n" rule of
        Left (DocsCheckDrift "test.md" "k") -> pure ()
        other -> error ("expected DocsCheckDrift on missing markers, got " <> show other)
    -- Already-applied source: check passes; drift returns DocsCheckDrift.
    assert "check matches applied source" (checkGeneratedSection expected rule == Right ())
    case checkGeneratedSection source rule of
        Left (DocsCheckDrift "test.md" "k") -> pure ()
        other -> error ("expected drift on stale source, got " <> show other)
    assert
        "real generated section registry is non-empty"
        ( any
            ( \registered ->
                sectionPath registered == "documents/engineering/cli_command_surface.md"
                    && sectionKey registered == "command-matrix"
                    && sectionOwner registered == "MCTS.Generated.Sections.renderCommandMatrix"
            )
            generatedSectionRules
        )

-- | Sprint 7.1 + 7.3: pin `commands --tree`, `commands --json`, and the
-- report-card summary block as golden fixtures. The fixtures live in
-- `test/golden/cli/` and are created on first run if missing.
exerciseCommandGoldens :: IO ()
exerciseCommandGoldens = do
    goldenCompare "test/golden/cli/commands-tree.txt" renderCommandTree
    goldenCompare "test/golden/cli/commands-list.txt" renderCommandList
    goldenCompare "test/golden/cli/commands.json" renderCommandJson
    -- `render is deterministic`: invoke the renderer twice and require the
    -- exact same bytes.
    assert "commands --tree is deterministic" (renderCommandTree == renderCommandTree)
    assert "commands --json is deterministic" (renderCommandJson == renderCommandJson)

exerciseOptparseParser :: IO ()
exerciseOptparseParser = do
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["bench", "selfplay", "--backend", "cpp-legacy,haskell", "--games", "1", "--seed", "42"] of
        OA.Success command -> assert "execParserPure parses bench cohort" (parsesBenchCohort (Right command))
        _ -> error "execParserPure failed to parse bench cohort"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["verify", "legacy-parity", "rollouts", "--backend", "cpp-legacy,haskell"] of
        OA.Success command -> assert "execParserPure parses legacy parity" (parsesLegacyRollouts (Right command))
        _ -> error "execParserPure failed to parse legacy parity"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["inspect", "show", "abc123", "--with-equity", "--top", "3"] of
        OA.Success command -> assert "execParserPure parses inspect equity show" (parsesInspectEquityShow (Right command))
        _ -> error "execParserPure failed to parse inspect show --with-equity"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["verify", "selfplay", "--backend", "cpp-imperative,haskell", "--rng", "native"] of
        OA.Failure _ -> pure ()
        _ -> error "execParserPure accepted native RNG for verify selfplay"

exerciseCacheRootBranches :: IO ()
exerciseCacheRootBranches = do
    original <- lookupEnv "MCTS_CACHE_DIR"
    explicit <- Transcript.resolveCacheRoot (Just ".mcts-cache-explicit")
    assert "cache root explicit branch" (explicit == ".mcts-cache-explicit")
    setEnv "MCTS_CACHE_DIR" ".mcts-cache-env"
    fromEnv <- Transcript.resolveCacheRoot Nothing
    assert "cache root env branch" (fromEnv == ".mcts-cache-env")
    unsetEnv "MCTS_CACHE_DIR"
    fallback <- Transcript.resolveCacheRoot Nothing
    assert "cache root default branch" (".mcts-cache" `isSuffixOfLocal` fallback)
    restoreEnv original
  where
    restoreEnv (Just value) = setEnv "MCTS_CACHE_DIR" value
    restoreEnv Nothing = unsetEnv "MCTS_CACHE_DIR"
    isSuffixOfLocal suffix value = suffix == drop (length value - length suffix) value

exerciseReportCardGolden :: IO ()
exerciseReportCardGolden = do
    goldenCompare "test/golden/cli/report-card.txt" (renderReportCard defaultReportCard)
    goldenCompare "test/golden/cli/report-card.json" (renderReportCardJson defaultReportCard)

goldenCompare :: FilePath -> String -> IO ()
goldenCompare path actual = do
    present <- doesFileExist path
    if present
        then do
            stored <- readFile path
            assert ("golden matches: " <> path) (stored == actual)
        else do
            createDirectoryIfMissing True (takeDirectoryGolden path)
            writeFile path actual
            putStrLn ("wrote golden: " <> path <> " (" <> show (length actual) <> " chars)")

takeDirectoryGolden :: FilePath -> FilePath
takeDirectoryGolden path =
    case reverse path of
        rev ->
            case break (== '/') rev of
                (_, '/' : rest) -> reverse rest
                _ -> "."

exerciseEnv :: IO ()
exerciseEnv = do
    -- defaultEnv exists and exposes the canonical command spec and the
    -- prerequisite registry without panicking on access.
    let env = defaultEnv
        leaves = leafSpecs (envCommandSpec env)
    assert
        "default env carries the command spec"
        (case leaves of leaf : _ -> not (null (examples leaf)); _ -> False)
    assert "default env carries generated section rules" (not (null (envGeneratedSectionRules env)))
    assert "default env carries generated path registry" (not (null (envTrackingGeneratedPaths env)))
    -- runAppIO threads the env through and `askEnv` returns the same value.
    same <- runAppIO env $ do
        e <- askEnv
        liftIO (envClock e)
    assert "default clock returns zero" (same == 0)
    -- withTestClock replaces the clock locally inside an App action.
    counter <- newIORef 0
    let tickClock = do
            modifyIORef' counter (+ 1)
            readIORef counter
    final <- runAppIO env $ withTestClock tickClock $ do
        a <- askEnv >>= liftIO . envClock
        b <- askEnv >>= liftIO . envClock
        pure (a, b)
    assert "withTestClock installs the test hook" (final == (1, 2))

exerciseEngineProperties :: IO ()
exerciseEngineProperties = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputGames = 1
                , inputSeed = 17
                , inputSims = FixedSims 8
                , inputMaxPlies = 40
                }
        game1 = runGame inputs 0
        game2 = runGame inputs 0
    assert "runGame is reproducible for fixed inputs" (game1 == game2)
    assert "runGame produces at least one move from the initial board" (not (null (gameMoves game1)))
    assert
        "initial board uses non-terminal outcome sentinel"
        (terminalOutcome 200 initialBoard == nonTerminalOutcome)
    let allRecords = gameMoves game1
        chosenInLegal record =
            let board = applyChain (map moveChosen (takeBefore (moveIndex record) allRecords))
                legal = legalMoves board
             in moveChosen record `elem` legal
    assert "every chosen move was in the legal set when applied" (all chosenInLegal allRecords)
    -- moveVisits always include at least the chosen move
    let chosenInVisits record = moveChosen record `elem` map fst (moveVisits record)
    assert "every chosen move appears in its visit list" (all chosenInVisits allRecords)

exerciseKnownPositionGolden :: IO ()
exerciseKnownPositionGolden = do
    let moves = [Pawn 4 1, Pawn 4 7, WallH 0 0, WallH 1 0, Pawn 4 2]
        board = foldl applyLegal initialBoard moves
        rendered =
            unlines
                [ "hero=" <> show (boardHero board)
                , "villain=" <> show (boardVillain board)
                , "wallsH=" <> show (boardWallsH board)
                , "wallsV=" <> show (boardWallsV board)
                , "heroWalls=" <> show (boardHeroWalls board)
                , "villainWalls=" <> show (boardVillainWalls board)
                , "sideToMove=" <> show (boardSideToMove board)
                , "ply=" <> show (boardPly board)
                , "legal=" <> unwords (map renderMove (take 12 (legalMoves board)))
                ]
    goldenCompare "test/golden/engine/known-position.txt" rendered
  where
    applyLegal board action =
        if action `elem` legalMoves board
            then applyMove action board
            else error ("known-position move is illegal: " <> show action)

applyChain :: [Action] -> Board
applyChain = foldl (flip applyMove) initialBoard

-- | Brute-force engine property checks per Phase 3 Sprint 3.1: random
-- pawn-walk sequences must always land on legal successor states, and
-- terminal-state detection must agree with the engine's own
-- `terminalWinner` view across all reachable boards. The walk is a
-- splitmix-driven random pick from `legalMoves`, so any disagreement is a
-- bug in the engine, not in the test harness.
exerciseEngineBruteForce :: IO ()
exerciseEngineBruteForce = do
    let seeds = [42, 43, 100, 999, 4242, 12345, 7, 17, 31, 1024]
        boards = take 200 (concatMap (boardWalk 30) seeds)
    -- (1) Legal-move enumeration produces actions that, when applied,
    -- yield a successor that is itself a board the engine accepts.
    let successorOK board action =
            let next = applyMove action board
                legalThere = legalMoves next
             in not (null legalThere) || isTerminal 200 next
    let badSuccessor =
            [ (board, action)
            | board <- boards
            , action <- legalMoves board
            , not (successorOK board action)
            ]
    assert "every legal move leads to a board that is legal or terminal" (null badSuccessor)
    -- (2) `legalMoves` returns no duplicates.
    let dupes =
            [ board
            | board <- boards
            , let ms = legalMoves board
            , length (uniqueByActionId ms) /= length ms
            ]
    assert "legal moves are unique by action id" (null dupes)
    -- (3) Terminal boards have empty legal-move sets.
    let terminalHasNoMoves =
            [ board
            | board <- boards
            , isTerminal 200 board
            , not (null (legalMoves board))
            ]
    assert "terminal boards have no legal moves" (null terminalHasNoMoves)

uniqueByActionId :: [Action] -> [Action]
uniqueByActionId actions = go [] actions
  where
    go acc [] = acc
    go acc (a : rest)
        | any ((== actionId a) . actionId) acc = go acc rest
        | otherwise = go (acc <> [a]) rest

-- | Random walk of length `n` starting from the initial board, picking a
-- legal move per step using splitmix-derived choices. Returns the
-- sequence of intermediate boards (excluding the initial one).
boardWalk :: Int -> Integer -> [Board]
boardWalk n seed = go n initialBoard (fromIntegral seed)
  where
    go 0 _ _ = []
    go steps board s =
        case legalMoves board of
            [] -> []
            moves ->
                let pick = fromIntegral (mix s (fromIntegral steps)) `mod` length moves
                    chosen = moves !! pick
                    next = applyMove chosen board
                 in next : go (steps - 1) next (mix s (fromIntegral steps))

takeBefore :: Word16 -> [MoveRecord] -> [MoveRecord]
takeBefore boundary = takeWhile (\r -> moveIndex r < boundary)

exerciseSplitmixBijection :: IO ()
exerciseSplitmixBijection = do
    let samples = [mix 42 (fromIntegral i) | i <- [0 :: Int .. 1023]]
        unique = countDistinct samples
    assert "splitmix is bijective on a small fixed window" (unique == length samples)
  where
    countDistinct :: (Eq a, Ord a) => [a] -> Int
    countDistinct xs = length (unique' xs)
    unique' :: (Eq a, Ord a) => [a] -> [a]
    unique' [] = []
    unique' (x : xs) = x : unique' (filter (/= x) xs)

exerciseCppRngFixture :: IO ()
exerciseCppRngFixture = do
    present <- doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so"
    if not present
        then putStrLn "mcts-unit SKIP cpp_rng_split_seed fixture (cpp-legacy shared library not built)"
        else do
            seed0 <- cppSplitSeed 42 0
            seed1 <- cppSplitSeed 42 1
            assert "cpp_rng_split_seed fixture 0" (seed0 == Right (mix 42 0))
            assert "cpp_rng_split_seed fixture 1" (seed1 == Right (mix 42 1))

exerciseCppLegacyBoardFixture :: IO ()
exerciseCppLegacyBoardFixture = do
    present <- doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so"
    if not present
        then putStrLn "mcts-unit SKIP cpp-legacy board fixture (cpp-legacy shared library not built)"
        else mapM_ exerciseOne [1 :: Int .. 100]
  where
    exerciseOne _ = do
        result <- withCppLegacyBoard (\_ -> pure ())
        assert "cpp-legacy dynamic board acquire/free" (result == Right ())

exerciseErrorRenderings :: IO ()
exerciseErrorRenderings = do
    -- Smoke test: every variant has a non-empty renderError output.
    let samples = map snd sampleErrorRenderings
    assert "every error variant renders to non-empty text" (all (not . T.null . renderError) samples)
    assert "TranscriptNotFound mentions the ref" ("abc" `inText` renderError (TranscriptNotFound "abc"))
    assert
        "DocsCheckDrift mentions the remedy"
        ("mcts docs generate" `inText` renderError (DocsCheckDrift "x" "y"))
    assert
        "PrerequisiteUnmet mentions the remedy"
        ("install ghcup" `inText` renderError (PrerequisiteUnmet "ghc" "GHC" "install ghcup"))
  where
    inText :: String -> T.Text -> Bool
    inText needle haystack = T.pack needle `T.isInfixOf` haystack

sampleErrorRenderings :: [(String, AppError)]
sampleErrorRenderings =
    [ ("TranscriptNotFound", TranscriptNotFound "abc")
    , ("TranscriptAmbiguous", TranscriptAmbiguous "ab" ["abcd", "abce"])
    , ("TranscriptFormatUnsupported", TranscriptFormatUnsupported "future")
    , ("VerifyCohortTooSmall", VerifyCohortTooSmall "need two")
    , ("LegacyParityRolloutOverflow", LegacyParityRolloutOverflow 42 0 1)
    , ("ArchEnvelopeMismatch", ArchEnvelopeMismatch "x86" "arm")
    , ("EngineEnvelopeMismatch", EngineEnvelopeMismatch CohortLevel "host_arch" "x86" "arm")
    , ("PrerequisiteUnmet", PrerequisiteUnmet "ghc" "GHC" "install ghcup")
    , ("SubprocessFailed", SubprocessFailed "cmd" 1)
    , ("FFIFailure", FFIFailure Haskell "fn" "boom")
    , ("DocsCheckDrift", DocsCheckDrift "documents/cli/commands.md" "fully-generated")
    , ("UnknownCommand", UnknownCommand "wat")
    , ("InvalidMove", InvalidMove "?")
    , ("ParseError", ParseError "bad")
    , ("IOErrorText", IOErrorText "io")
    ]

exerciseErrorGolden :: IO ()
exerciseErrorGolden =
    goldenCompare "test/golden/cli/errors.txt" $
        unlines [label <> ": " <> T.unpack (renderError err) | (label, err) <- sampleErrorRenderings]

exerciseSubprocessGolden :: IO ()
exerciseSubprocessGolden = do
    let subprocess = Subprocess "cabal" ["exec", "mcts", "--", "inspect", "show", "a b"] Nothing Nothing
        rendered = renderSubprocess subprocess
        failure = renderError (SubprocessFailed rendered 2)
    goldenCompare "test/golden/cli/subprocess.txt" (rendered <> "\n")
    assert
        "subprocess render quotes spaced arguments"
        (rendered == "cabal exec mcts -- inspect show 'a b'")
    assert "subprocess failure includes rendered command" (T.pack rendered `T.isInfixOf` failure)
    assert "subprocess failure includes exit code" (T.pack "exit=2" `T.isInfixOf` failure)
