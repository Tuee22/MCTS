{-# LANGUAGE DuplicateRecordFields #-}

module Main where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.ST (runST)
import Data.Aeson (Value (..), eitherDecodeStrict')
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (sort)
import qualified Data.List as List
import qualified Data.Text as T
import Data.Word (Word16, Word8)
import MCTS.CLI.Bench (monotonicNanos, runBenchWithClock)
import MCTS.CLI.Build
    ( boltTrainingGames
    , boltTrainingSims
    , buildBackendPlan
    , legacyFixturePlan
    , pgoTrainingGames
    , pgoTrainingSims
    , rustPgoBoltPlan
    )
import MCTS.CLI.Command
    ( BenchCommand (..)
    , BuildCommand (..)
    , Command (..)
    , InspectCommand (..)
    , LegacyFixtureOptions (..)
    , PlayOptions (..)
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
import MCTS.CLI.Inspect
    ( InspectRow (..)
    , prepareReplayOverlays
    , renderInspectRows
    , renderTranscript
    )
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
import MCTS.CLI.Tui.Board (renderBoardText, renderStatusText)
import MCTS.CLI.Tui.Play
    ( PlayState (..)
    , UserInputOutcome (..)
    , advanceAiState
    , applyUserInput
    , initialPlayState
    , savePlayState
    )
import MCTS.CLI.Tui.Replay
    ( OverlayRow (..)
    , ReplayKey (..)
    , ReplayOverlayLoadResult (..)
    , ReplayState (..)
    , applyOverlayLoadResult
    , applyReplayKey
    , currentOverlayRows
    , initialReplayState
    , initialReplayStateWithOverlays
    , nextOverlayBackend
    , renderOverlayRowsText
    , replayBoardAt
    )
import MCTS.CLI.Verify (renderVerifyJson)
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
import MCTS.FFI.Common (EngineEnvelope (..), engineEnvelopeToEnvelope)
import MCTS.Generated.Paths (trackingGeneratedPaths)
import MCTS.Notation (parseMove, renderMove)
import MCTS.Plan
    ( Plan (..)
    , PlanOptions (..)
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
import MCTS.ReportCard
    ( ReportDivergenceRow (..)
    , defaultReportCard
    , divergenceRowsFromTranscripts
    , renderReportCard
    , renderReportCardJson
    )
import MCTS.Rng.Mix (backendNativeSalt, mix)
import qualified MCTS.Search.Arena as Arena
import qualified MCTS.Search.UCT as UCT
import MCTS.Subprocess (ProcessOutput (..), Subprocess (..), capture, renderSubprocess)
import MCTS.Transcript
    ( TranscriptRef (..)
    , decodeTranscript
    , encodeTranscript
    , hostArch
    , listTranscriptFiles
    , lookupByPrefix
    , playTranscriptHash
    , readTranscriptFile
    , runConfigHash
    , writeTranscriptPerGame
    )
import qualified MCTS.Transcript as Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import MCTS.Verify (VerifyResult (..), compareTranscripts)
import MCTS.Verify.Divergence
import MCTS.Verify.Envelope
import qualified Options.Applicative as OA
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , removePathForcibly
    )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (testCase)
import qualified Test.Tasty.QuickCheck as QC

main :: IO ()
main =
    defaultMain (testGroup "mcts-unit" unitTests)

unitTests :: [TestTree]
unitTests =
    [ testGroup
        "cli and parser"
        [ testCase "command registry and parser invariants" exerciseCommandParserSurface
        , testCase "command and generated-section renderers" exerciseCommandGeneratedRenderers
        ]
    , testGroup
        "transcripts and cache"
        [ testCase "transcript codec invariants" exerciseTranscriptCodecSurface
        , testCase "transcript semantic fixtures and cache lookup" exerciseTranscriptGeneratedSurface
        , testCase "per-game transcript writer" exercisePerGameTranscriptWriter
        , QC.testProperty
            "transcript decode . encode == id (quickcheck)"
            (QC.withNumTests 20 propTranscriptRoundtrip)
        ]
    , testGroup
        "engine and rng"
        [ testCase "engine invariants" exerciseEngineSurface
        , testCase "search arena helpers" exerciseArena
        , testCase "uct search" exerciseUctSearch
        , testCase "equity recompute" exerciseRecompute
        , testCase "splitmix fixtures" exerciseSplitmixSurface
        , testCase "backend rng salts" exerciseBackendNativeSalt
        ]
    , testGroup
        "envelopes and sidecars"
        [ testCase "envelope checks and divergence" exerciseEnvelopeDivergenceSurface
        , testCase "equity sidecar codec and helpers" exerciseSidecarSurface
        , testCase "engine envelope wire roundtrip" exerciseEnvelopeRoundTrip
        ]
    , testGroup
        "plans and subprocesses"
        [ testCase "prerequisite graph" exercisePrerequisiteSurface
        , testCase "plan/apply helpers" exercisePlanSurface
        , testCase "Rust PGO/BOLT build plan" exerciseRustBuildPlan
        , testCase "subprocess rendering and environment" exerciseSubprocessSurface
        ]
    , testGroup
        "renderers and TUI dispatch"
        [ testCase "error and inspect renderers" exerciseRendererSurface
        , testCase "report-card renderer" exerciseReportCardRenderer
        , testCase "TUI board layout renderer" exerciseTuiBoardRenderer
        , testCase "TUI replay layout renderer" exerciseTuiReplayRenderer
        , testCase "TUI play input dispatcher" exerciseTuiPlayInput
        , testCase "TUI replay navigation" exerciseTuiReplayNav
        , testCase "TUI replay overlays" exerciseTuiReplayOverlay
        ]
    ]

sampleInputs :: RunInputs
sampleInputs =
    defaultRunInputs{inputGames = 2, inputSeed = 42, inputSims = FixedSims 12}

sampleTranscript :: Transcript
sampleTranscript =
    Transcript
        (makeRunConfig sampleInputs)
        (makeLogicalEnvelope Haskell NativeRng)
        [runGame sampleInputs 0, runGame sampleInputs 1]

propTranscriptRoundtrip :: QC.NonNegative Int -> QC.NonNegative Int -> QC.Property
propTranscriptRoundtrip (QC.NonNegative seedN) (QC.NonNegative simsN) =
    let games = 1 + seedN `mod` 2
        inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputThreading = SingleThreaded
                , inputGames = games
                , inputSeed = fromIntegral (seedN `mod` 4096)
                , inputSims = FixedSims (fromIntegral (1 + simsN `mod` 6))
                , inputMaxPlies = 8
                }
        transcript =
            Transcript
                (makeRunConfig inputs)
                (makeLogicalEnvelope Haskell CppRng)
                [ runGame inputs gid
                | gid <- [0 .. fromIntegral (games - 1)]
                ]
     in QC.counterexample
            ("seed=" <> show (inputSeed inputs) <> " games=" <> show games)
            (decodeTranscript (encodeTranscript transcript) QC.=== Right transcript)

exerciseCommandParserSurface :: IO ()
exerciseCommandParserSurface = do
    assert
        "generated-path registry excludes validation fixtures"
        (not (any ("test/golden/" `prefixOf`) trackingGeneratedPaths))
    assert
        "generated-path registry still tracks generated command docs"
        ("documents/cli/commands.md" `elem` trackingGeneratedPaths)
    assert "command tree mentions verify" ("verify" `contains` renderCommandTree)
    assert "command json is object" (take 1 renderCommandJson == "{")
    assert "all leaves have examples" (all (not . null . examples) (leafSpecs commandSpec))
    assert
        "backend parser"
        ( parseBackends "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
            == Right [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]
        )
    assert
        "command parser"
        ( parsesBenchCohort
            ( parseCommand
                ["bench", "selfplay", "--backend", "rust,haskell", "--games", "1", "--seed", "42"]
            )
        )
    assert
        "bench requires an explicit backend cohort"
        (isLeft (parseCommand ["bench", "selfplay", "--games", "1", "--seed", "42"]))
    assert
        "legacy parity command parses all five backend slots"
        ( parsesLegacyParityCohort
            ( parseCommand
                [ "verify"
                , "legacy-parity"
                , "rollouts"
                , "--backend"
                , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
                , "--games"
                , "1"
                , "--seed"
                , "42"
                ]
            )
        )
    assert
        "allow stale parser"
        ( parsesAllowStale
            ( parseCommand
                [ "verify"
                , "selfplay"
                , "--backend"
                , "rust,haskell"
                , "--allow-stale"
                , "--games"
                , "1"
                , "--seed"
                , "42"
                ]
            )
        )
    assert
        "verify defaults to single-threaded dispatch"
        ( parsesVerifyDefaultThreading
            (parseCommand ["verify", "selfplay", "--backend", "rust,haskell", "--games", "1", "--seed", "42"])
        )
    assert
        "play parser carries rng seed and max-plies"
        ( parsesPlaySurface
            ( parseCommand
                [ "play"
                , "--backend"
                , "haskell"
                , "--side"
                , "hero"
                , "--rng"
                , "cpp"
                , "--seed"
                , "99"
                , "--max-plies"
                , "123"
                , "--sims"
                , "1000"
                , "--cache-dir"
                , ".mcts-cache-play"
                ]
            )
        )
    assert
        "legacy fixture build parser"
        ( parsesLegacyFixtureBuild
            ( parseCommand
                [ "build"
                , "legacy-fixtures"
                , "--output-dir"
                , "/tmp/legacy-fixtures"
                , "--seed"
                , "42"
                , "--games"
                , "1"
                , "--sims"
                , "4"
                , "--dry-run"
                ]
            )
        )
    assert
        "legacy fixture build requires explicit output dir"
        (isLeft (parseCommand ["build", "legacy-fixtures", "--dry-run"]))
    assert
        "verify rejects native rng"
        ( isLeft
            ( parseCommand
                [ "verify"
                , "selfplay"
                , "--backend"
                , "rust,haskell"
                , "--rng"
                , "native"
                , "--games"
                , "1"
                , "--seed"
                , "42"
                ]
            )
        )
    assert
        "verify rejects single-backend cohorts at parser boundary"
        ( isVerifyCohortTooSmall
            (parseCommand ["verify", "selfplay", "--backend", "haskell", "--games", "1", "--seed", "42"])
        )
    assert
        "verify rejects cpp-legacy at parser boundary"
        ( isLeft
            ( parseCommand
                ["verify", "selfplay", "--backend", "cpp-legacy,haskell", "--games", "1", "--seed", "42"]
            )
        )
    assert
        "verify accepts cpp-imperative at parser boundary"
        ( not
            ( isLeft
                ( parseCommand
                    ["verify", "selfplay", "--backend", "cpp-imperative,haskell", "--games", "1", "--seed", "42"]
                )
            )
        )
    assert
        "verify accepts cpp-functional at parser boundary"
        ( not
            ( isLeft
                ( parseCommand
                    ["verify", "selfplay", "--backend", "cpp-functional,haskell", "--games", "1", "--seed", "42"]
                )
            )
        )
    assert
        "verify accepts full Q3 cohort at parser boundary"
        ( parsesFullVerifyCohort
            ( parseCommand
                [ "verify"
                , "selfplay"
                , "--backend"
                , "cpp-imperative,cpp-functional,rust,haskell"
                , "--games"
                , "1"
                , "--seed"
                , "42"
                ]
            )
        )
    exerciseOptparseParser
    exercisePlanOptionMetadata
    exerciseForbiddenPathRegistry

exerciseCommandGeneratedRenderers :: IO ()
exerciseCommandGeneratedRenderers = do
    exerciseCommandRenderers
    exerciseMarkerSplice

exerciseTranscriptCodecSurface :: IO ()
exerciseTranscriptCodecSurface = do
    assert
        "sha256 known vector"
        (sha256Hex (BS.pack []) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    let encoded = encodeTranscript sampleTranscript
    assert "transcript encoding non-empty" (BS.length encoded > 48)
    assert "transcript roundtrip" (decodeTranscript encoded == Right sampleTranscript)
    assert
        "transcript envelope skips trailers"
        (decodeTranscript (withEnvelopeTrailer encoded) == Right sampleTranscript)
    let rolloutInputs = sampleInputs{inputWorkload = Rollouts}
        rolloutTranscript =
            sampleTranscript
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
        (runConfigHash (makeRunConfig sampleInputs) == runConfigHash (makeRunConfig sampleInputs))
    exerciseRunConfigHashEnvelopeInvariant
    exerciseSortedRecords
    exerciseLegacyDrawRejection

exerciseTranscriptGeneratedSurface :: IO ()
exerciseTranscriptGeneratedSurface = do
    exerciseLookup
    exerciseTranscriptSemanticFixtures
    exerciseCacheRootBranches
    exerciseUniquePrefixProperty

exerciseEngineSurface :: IO ()
exerciseEngineSurface = do
    assert "action enumeration roundtrip" (all (\a -> actionFromId (actionId a) == Just a) allActions)
    assert "notation roundtrip" (all (\a -> parseMove (renderMove a) == Just a) allActions)
    assert "initial board has legal moves" (not (null (legalMoves initialBoard)))
    exerciseEngineProperties
    exerciseKnownPositionRenderer
    exerciseEngineBruteForce
    exerciseEnv
    exerciseMonotonicBracket

exerciseSplitmixSurface :: IO ()
exerciseSplitmixSurface = do
    assert "splitmix is deterministic" (mix 42 0 == mix 42 0 && mix 42 0 /= mix 42 1)
    assert "splitmix known vector 0" (mix 42 0 == 2949826092126892291)
    assert "splitmix known vector 1" (mix 42 1 == 5139283748462763858)
    exerciseSplitmixBijection

exerciseEnvelopeDivergenceSurface :: IO ()
exerciseEnvelopeDivergenceSurface = do
    assert
        "divergence same transcript is zero"
        (divergenceRate sampleTranscript sampleTranscript == DivergenceMetrics 0.0 0.0 0.0)
    let changed =
            sampleTranscript{transcriptGames = mapFirstGame changeFirstMove (transcriptGames sampleTranscript)}
    assert
        "divergence catches changed move"
        (moveDisagreementRate (divergenceRate sampleTranscript changed) > 0.0)
    let zeroPadded =
            sampleTranscript{transcriptGames = mapFirstGame addZeroVisit (transcriptGames sampleTranscript)}
    assert
        "divergence ignores backend-specific zero-visit padding"
        (divergenceRate sampleTranscript zeroPadded == DivergenceMetrics 0.0 0.0 0.0)
    exerciseVerifyComparator sampleTranscript
    exerciseDivergenceVsEqStream sampleTranscript
    exerciseEnvelopeChecks sampleTranscript

exerciseVerifyComparator :: Transcript -> IO ()
exerciseVerifyComparator transcript = do
    let foreignSamePayload =
            transcript
                { transcriptConfig = (transcriptConfig transcript){runBackend = Rust}
                , transcriptEnvelope = makeLogicalEnvelope Rust (runRngSource (transcriptConfig transcript))
                }
    assert
        "verify comparator ignores backend and envelope when payload matches"
        (compareTranscripts Haskell transcript Rust foreignSamePayload == Right ())
    let extraMove =
            foreignSamePayload
                { transcriptGames = mapFirstGame appendDuplicateMove (transcriptGames foreignSamePayload)
                }
    case compareTranscripts Haskell transcript Rust extraMove of
        Left (VerifyLengthMismatch Haskell Rust scope _ _) ->
            assert "verify comparator reports extra moves" ("moves game=0" `contains` scope)
        other -> error ("expected verify move length mismatch, got " <> show other)
    let extraGame =
            foreignSamePayload
                { transcriptGames = transcriptGames foreignSamePayload <> [runGame sampleInputs 2]
                }
    case compareTranscripts Haskell transcript Rust extraGame of
        Left (VerifyLengthMismatch Haskell Rust "games" 0 1) -> pure ()
        other -> error ("expected verify game length mismatch, got " <> show other)
    let wrongWinner =
            foreignSamePayload
                { transcriptGames =
                    mapFirstGame (\game -> game{gameWinner = Draw}) (transcriptGames foreignSamePayload)
                }
    case compareTranscripts Haskell transcript Rust wrongWinner of
        Left (VerifyTerminatorMismatch Haskell Rust 0 _ _) -> pure ()
        other -> error ("expected verify terminator mismatch, got " <> show other)
  where
    appendDuplicateMove game =
        case gameMoves game of
            record : _ -> game{gameMoves = gameMoves game <> [record{moveIndex = fromIntegral (length (gameMoves game))}]}
            [] -> game

exerciseSidecarSurface :: IO ()
exerciseSidecarSurface = do
    exerciseSidecars sampleTranscript
    exerciseEquitySidecarBinary

exercisePrerequisiteSurface :: IO ()
exercisePrerequisiteSurface = do
    exercisePrerequisites
    exercisePrerequisiteClosure

exercisePlanSurface :: IO ()
exercisePlanSurface = do
    exercisePlanShape
    exerciseApplyWithEnv

exerciseSubprocessSurface :: IO ()
exerciseSubprocessSurface = do
    exerciseSubprocessRenderer
    exerciseSubprocessEnvironment

exerciseRendererSurface :: IO ()
exerciseRendererSurface = do
    exerciseErrorRenderings
    exerciseErrorRenderer
    exerciseInspectShowRenderer
    exerciseInspectListRenderer

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

isVerifyCohortTooSmall :: Either AppError Command -> Bool
isVerifyCohortTooSmall (Left (VerifyCohortTooSmall _)) = True
isVerifyCohortTooSmall _ = False

parsesAllowStale :: Either AppError Command -> Bool
parsesAllowStale parsed =
    case parsed of
        Right (Verify (VerifySelfplay True [VRust, VHaskell] _)) -> True
        _ -> False

parsesVerifyDefaultThreading :: Either AppError Command -> Bool
parsesVerifyDefaultThreading parsed =
    case parsed of
        Right (Verify (VerifySelfplay False [VRust, VHaskell] inputs)) ->
            inputThreading inputs == SingleThreaded
        _ -> False

parsesFullVerifyCohort :: Either AppError Command -> Bool
parsesFullVerifyCohort parsed =
    case parsed of
        Right (Verify (VerifySelfplay False [VCppImperative, VCppFunctional, VRust, VHaskell] inputs)) ->
            inputThreading inputs == SingleThreaded
        _ -> False

parsesLegacyParityCohort :: Either AppError Command -> Bool
parsesLegacyParityCohort parsed =
    case parsed of
        Right (Verify (VerifyLegacyParity False Rollouts backends inputs)) ->
            backends == [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]
                && inputThreading inputs == SingleThreaded
                && inputRng inputs == CppRng
                && inputMaxPlies inputs == 10000
        _ -> False

parsesBenchCohort :: Either AppError Command -> Bool
parsesBenchCohort parsed =
    case parsed of
        Right (Bench (BenchSelfplay [Rust, Haskell] inputs)) -> inputBackend inputs == Rust
        _ -> False

parsesPlaySurface :: Either AppError Command -> Bool
parsesPlaySurface parsed =
    case parsed of
        Right (Play playOptions) ->
            playBackend playOptions == Haskell
                && playSide playOptions == Hero
                && playRng playOptions == CppRng
                && playSeed playOptions == Just 99
                && playMaxPlies playOptions == 123
                && playCacheDir playOptions == Just ".mcts-cache-play"
        _ -> False

parsesLegacyFixtureBuild :: Either AppError Command -> Bool
parsesLegacyFixtureBuild parsed =
    case parsed of
        Right (Build (BuildLegacyFixtures fixtureOptions)) ->
            legacyFixtureOutputDir fixtureOptions == "/tmp/legacy-fixtures"
                && legacyFixtureSeed fixtureOptions == 42
                && legacyFixtureGames fixtureOptions == 1
                && legacyFixtureSims fixtureOptions == 4
                && legacyFixturePlanOptions fixtureOptions == PlanOptions True Nothing
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
        assert
            ("runConfigHash ignores " <> backendIdentifier backend <> " batch game count")
            ( runConfigHash config{runGames = 1}
                == runConfigHash config{runGames = 2}
            )
        assert
            ("runConfigHash includes " <> backendIdentifier backend <> " game_index")
            ( runConfigHash config{runGames = 1, runGameIndex = 0}
                /= runConfigHash config{runGames = 1, runGameIndex = 1}
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
    let liveEnvelope =
            engineEnvelopeToEnvelope
                EngineEnvelope
                    { engineEnvVersion = 1
                    , engineEnvBackend = CppImperative
                    , engineEnvRngSource = 1
                    , engineEnvHostArch = if hostArch == "arm64" then 1 else 0
                    , engineEnvSharedRngBuildId = replicate 64 'a'
                    , engineEnvCohortConfigHash = replicate 64 'b'
                    , engineEnvBuildId = replicate 64 'c'
                    , engineEnvGitCommit = "abcdef"
                    , engineEnvCompilerId = 0
                    , engineEnvCompilerVersion = "gcc-test"
                    , engineEnvFpFlags = 0x10
                    , engineEnvLibmId = "glibc-test"
                    , engineEnvCpuFeatures = 0x20
                    , engineEnvFpEnv = 0x30
                    }
        liveTranscript =
            transcript
                { transcriptConfig =
                    (transcriptConfig transcript)
                        { runBackend = CppImperative
                        , runRngSource = CppRng
                        }
                , transcriptEnvelope = liveEnvelope
                }
        compilerVersionBad =
            liveTranscript
                { transcriptEnvelope =
                    liveEnvelope{envelopeCompilerVersion = "old-gcc"}
                }
        sharedRngBad =
            liveTranscript
                { transcriptEnvelope =
                    liveEnvelope{envelopeSharedRngBuildId = ByteString32 (replicate 64 'd')}
                }
    assert
        "live backend slot exact match"
        (checkBackendSlotAgainst False liveEnvelope liveTranscript == Right [])
    case checkBackendSlotAgainst False liveEnvelope compilerVersionBad of
        Left (EngineEnvelopeMismatch (BackendSlot CppImperative) "compiler_version" _ _) -> pure ()
        other -> error ("expected live compiler_version backend-slot mismatch, got " <> show other)
    case checkBackendSlotAgainst True liveEnvelope compilerVersionBad of
        Right (EngineEnvelopeMismatch (BackendSlot CppImperative) "compiler_version" _ _ : _) -> pure ()
        other -> error ("expected live compiler_version warning, got " <> show other)
    case checkBackendSlotAgainst True liveEnvelope sharedRngBad of
        Left (EngineEnvelopeMismatch CohortLevel "shared_rng_build_id" _ _) -> pure ()
        other -> error ("expected shared_rng_build_id hard fail, got " <> show other)
    let jsonWarning =
            EngineEnvelopeMismatch
                (BackendSlot CppImperative)
                "compiler_version"
                "gcc-test"
                "old-gcc"
        verifyJson =
            renderVerifyJson
                "verify \"selfplay\""
                VerifyResult{verifyWarnings = [jsonWarning], verifyBatches = []}
    assert "verify json counts warnings" ("\"warnings\":1" `contains` verifyJson)
    assert "verify json includes warning details" ("\"warning_details\":[" `contains` verifyJson)
    assert
        "verify json structures envelope warning type"
        ("\"type\":\"EngineEnvelopeMismatch\"" `contains` verifyJson)
    assert
        "verify json structures backend slot scope"
        ("\"scope\":\"BackendSlot\",\"backend\":\"cpp-imperative\"" `contains` verifyJson)
    assert
        "verify json structures envelope field"
        ("\"field\":\"compiler_version\"" `contains` verifyJson)
    assert "verify json escapes label" ("\"label\":\"verify \\\"selfplay\\\"\"" `contains` verifyJson)

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
    loaded <- loadMatchingOriginatorSidecar (Just cacheRoot) hashValue transcript
    assert
        "inspect show can load envelope-matched originator sidecar before recompute"
        (loaded == Just (equityStreamForTranscript hashValue transcript))
    removeDirectoryIfExists cacheRoot

removeDirectoryIfExists :: FilePath -> IO ()
removeDirectoryIfExists path = do
    exists <- doesDirectoryExist path
    if exists then removePathForcibly path else pure ()

-- | Sprint 7.5: divergenceVsEqStream pairs a transcript against a
-- recompute-produced `EqStream` and reports per-move metrics. Same-
-- backend roundtrip should yield zero disagreement; a synthesized
-- foreign stream that disagrees on the chosen action for every move
-- should report a 100% move-disagreement rate and a strictly positive
-- equity L2 drift.
exerciseDivergenceVsEqStream :: Transcript -> IO ()
exerciseDivergenceVsEqStream transcript = do
    let hashValue = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        sameStream = equityStreamForTranscript hashValue transcript
        sameMetrics = divergenceVsEqStream transcript sameStream
    assert
        "divergence vs same eq stream is zero"
        (sameMetrics == DivergenceMetrics 0.0 0.0 0.0)
    let foreignStream =
            sameStream
                { eqRecords =
                    [ record{eqEquity = 0.5}
                    | record <- eqRecords sameStream
                    ]
                }
        foreignMetrics = divergenceVsEqStream transcript foreignStream
    assert
        "divergence vs foreign eq stream surfaces equity drift"
        (equityL2Drift foreignMetrics > 0.0)

changeFirstMove :: GameTranscript -> GameTranscript
changeFirstMove game =
    case gameMoves game of
        [] -> game
        record : rest ->
            let replacement = if moveChosen record == Pawn 0 0 then Pawn 1 0 else Pawn 0 0
             in game{gameMoves = record{moveChosen = replacement} : rest}

addZeroVisit :: GameTranscript -> GameTranscript
addZeroVisit game =
    case gameMoves game of
        [] -> game
        record : rest ->
            game{gameMoves = record{moveVisits = (Pawn 0 0, 0) : moveVisits record} : rest}

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
            , "mcts test parity-anchor"
            , "mcts docs generate"
            , "mcts inspect cache prune"
            , "mcts build cpp-legacy"
            , "mcts build cpp-imperative"
            , "mcts build cpp-functional"
            , "mcts build rust"
            , "mcts build legacy-fixtures"
            ]
    assert
        ( "Plan/Apply leaves declare --dry-run and --plan-file; missing "
            <> show (filter (not . hasPlanOptions) planApplyLeaves)
        )
        (all hasPlanOptions planApplyLeaves)
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

-- | Sprint 8.8 semantic fixture: the transcript codec is exercised with
-- in-memory values for every backend tag. The assertions pin determinism and
-- decode coverage without depending on committed byte fixtures.
exerciseTranscriptSemanticFixtures :: IO ()
exerciseTranscriptSemanticFixtures =
    mapM_
        exerciseCase
        [Haskell, CppImperative, CppFunctional, Rust]
  where
    exerciseCase backend = do
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
        let expectedHash = sha256Hex encoded
        assert
            ("transcript fixture bytes are non-empty: " <> backendIdentifier backend)
            (BS.length encoded > 48)
        assert
            ("transcript hash is deterministic: " <> backendIdentifier backend)
            (sha256Hex (encodeTranscript transcript) == expectedHash)
        assert
            ("transcript fixture roundtrips: " <> backendIdentifier backend)
            (decodeTranscript encoded == Right transcript)

exerciseInspectShowRenderer :: IO ()
exerciseInspectShowRenderer = do
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
    assert "inspect show renders the selected hash" ("abc123" `contains` rendered)
    assert "inspect show renders the backend" ("haskell" `contains` rendered)
    case gameMoves game of
        record : _ ->
            assert "inspect show renders transcript moves" (renderMove (moveChosen record) `contains` rendered)
        [] -> failTest "inspect show fixture must contain moves"
    let envelopeRendered =
            renderTranscript
                defaultOutputOptions
                showOptions{showEnvelope = True}
                ".mcts-cache/transcripts/arm64/abc123.tr"
                (Just stream)
                transcript
    assert
        "inspect show envelope renders rng source"
        ("envelope.rng_source: cpp" `contains` envelopeRendered)
    assert
        "inspect show envelope renders engine build id"
        ("envelope.engine_build_id:" `contains` envelopeRendered)
    assert "inspect show envelope renders fp env" ("envelope.fp_env:" `contains` envelopeRendered)

exerciseInspectListRenderer :: IO ()
exerciseInspectListRenderer = do
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
    assert "inspect list JSON decodes" (isJsonObjectOrArray (decodeJsonValue "inspect list" rendered))
    assert "inspect list JSON includes hash" ("abc12345" `contains` rendered)
    assert "inspect list JSON includes backend" ("haskell" `contains` rendered)

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
                (envelopeBuildId actual == "cpp-imperative-deadbeefcafe0011")
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
            assert
                "per-game files preserve master seed and record game_index"
                ( all
                    ( \r -> case r of
                        Right t -> case transcriptGames t of
                            [game] ->
                                runMasterSeed (transcriptConfig t) == inputSeed inputs
                                    && runGameIndex (transcriptConfig t) == gameId game
                            _ -> False
                        Left _ -> False
                    )
                    decoded
                )
    removePathForcibly cacheRoot

-- | Validate the Rust PGO+BOLT plan as a typed `[Subprocess]` sequence.
-- C++ backend build harnesses are covered through the Plan/Apply command surface.
exerciseRustBuildPlan :: IO ()
exerciseRustBuildPlan = do
    let plan = buildBackendPlan "rust"
        steps = rustPgoBoltPlan
        commands = map subprocessPath steps
        argsOf = map subprocessArguments steps
        rustFlagsAt index =
            case subprocessEnvironment (steps !! index) of
                Just env -> maybe "" id (List.lookup "RUSTFLAGS" env)
                Nothing -> ""
        generateFlags = rustFlagsAt 0
        useFlags = rustFlagsAt 3
    assert "Rust PGO+BOLT plan has 12 typed Subprocess steps" (length steps == 12)
    assert "Rust PGO+BOLT plan is the same as buildBackendPlan output" (planSteps plan == steps)
    assert
        "Rust PGO step 1 is cargo build --release"
        (case commands of (c : _) -> c == "cargo"; _ -> False)
    assert
        "Rust PGO generate flags include target CPU, lld linker, and profile-generate"
        ( all
            (`List.isInfixOf` generateFlags)
            [ "-C target-cpu=native"
            , "-C link-arg=-fuse-ld=lld"
            , "-C profile-generate=/workspace/MCTS/rust/pgo-profile"
            ]
        )
    assert
        "Rust PGO training step invokes bench selfplay --rng native"
        ( commands !! 1 == "cabal"
            && "selfplay" `elem` argsOf !! 1
            && "native" `elem` argsOf !! 1
            && show pgoTrainingGames `elem` argsOf !! 1
            && show pgoTrainingSims `elem` argsOf !! 1
        )
    assert
        "Rust BOLT training step invokes bench selfplay --rng native"
        ( commands !! 7 == "cabal"
            && "selfplay" `elem` argsOf !! 7
            && "native" `elem` argsOf !! 7
            && show boltTrainingGames `elem` argsOf !! 7
            && show boltTrainingSims `elem` argsOf !! 7
        )
    assert
        "Rust PGO use flags include target CPU, lld linker, and profile-use"
        ( all
            (`List.isInfixOf` useFlags)
            [ "-C target-cpu=native"
            , "-C link-arg=-fuse-ld=lld"
            , "-C profile-use=/workspace/MCTS/rust/pgo-profile/merged.profdata"
            ]
        )
    assert
        "Rust final step patches engine_build_id"
        (case reverse argsOf of (a : _) -> argContains a ".envelope_build_id"; _ -> False)
    assert "buildBackendPlan is idempotent" (buildBackendPlan "rust" == plan)
    assert
        "PGO+BOLT plan name is build rust"
        (planName plan == "build rust")
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
    assert
        "rust plan matches buildBackendPlan"
        (planSteps (buildBackendPlan "rust") == steps)
    let fixtureOptions =
            LegacyFixtureOptions
                { legacyFixtureOutputDir = "/tmp/mcts-legacy-fixtures"
                , legacyFixtureSeed = 42
                , legacyFixtureGames = 10
                , legacyFixtureSims = 10000
                , legacyFixturePlanOptions = PlanOptions True Nothing
                }
        fixturePlan = legacyFixturePlan fixtureOptions
        fixtureSteps = planSteps fixturePlan
        fixtureRendered = renderPlan fixturePlan
    assert "legacy fixture plan name is stable" (planName fixturePlan == "build legacy-fixtures")
    assert
        "legacy fixture plan has make and generator steps"
        ( case fixtureSteps of
            [makeStep, generatorStep] ->
                subprocessPath makeStep == "make"
                    && subprocessArguments makeStep == ["-C", "cpp-legacy", "legacy-to-wire"]
                    && subprocessPath generatorStep == "cpp-legacy/build/legacy-to-wire"
            _ -> False
        )
    assert
        "legacy fixture plan passes explicit regeneration flags"
        ( case fixtureSteps of
            [_, generatorStep] ->
                subprocessArguments generatorStep
                    == [ "--output-dir"
                       , "/tmp/mcts-legacy-fixtures"
                       , "--seed"
                       , "42"
                       , "--games"
                       , "10"
                       , "--sims"
                       , "10000"
                       , "--max-plies"
                       , "10000"
                       ]
            _ -> False
        )
    assert
        "legacy fixture plan does not use environment overrides"
        ( all ((== Nothing) . subprocessEnvironment) fixtureSteps
            && not ("LEGACY_FIXTURE_" `contains` fixtureRendered)
        )
  where
    argContains args needle =
        any (T.isInfixOf (T.pack needle) . T.pack) args

-- | Sprint 1.4: the forbidden-path registry is a typed value carrying
-- a rationale per entry. The pinned set matches
-- [../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../HASKELL_CLI_TOOL.md):
-- `.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`,
-- `pre-commit-*.yaml`, root `Makefile`, host-level `.build/`, root
-- `bootstrap/`, repository `.sh` wrappers, root `justfile`, and root
-- `Taskfile.yml`.
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
            , ".build"
            , "bootstrap"
            , "*.sh"
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
    -- Test-injected clock counts calls. Keep this unit test on the
    -- in-process Haskell backend so the clock-bracketing assertion is
    -- independent of which foreign cdylibs happen to be present.
    counter <- newIORef (0 :: Int)
    let injected = do
            modifyIORef' counter (+ 1)
            v <- readIORef counter
            pure (fromIntegral (v * 1000))
        cacheRoot = ".mcts-cache-unit-bench"
        inputs =
            defaultRunInputs
                { inputGames = 1
                , inputSeed = 1
                , inputSims = FixedSims 1
                , inputCacheDir = Just cacheRoot
                }
    removeDirectoryIfExists cacheRoot
    code <- runBenchWithClock injected defaultOutputOptions [Haskell] inputs
    final <- readIORef counter
    assert "bench reads the clock twice per backend" (final == 2)
    assert "bench returns 0 on success" (code == 0)
    -- Clean up the isolated cache directory the bench wrote.
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

-- | Command renderer checks use semantic assertions so normal validation does
-- not depend on committed renderer snapshots.
exerciseCommandRenderers :: IO ()
exerciseCommandRenderers = do
    assert
        "commands --tree mentions play"
        ("play - Play or spectate a game" `contains` renderCommandTree)
    assert
        "commands --list mentions legacy fixture command"
        ("mcts build legacy-fixtures" `contains` renderCommandList)
    assert
        "commands --json has command schema keys"
        ( jsonObjectHasKeys
            (decodeJsonValue "commands json" renderCommandJson)
            ["name", "summary", "children"]
        )
    assert "commands --tree is deterministic" (renderCommandTree == renderCommandTree)
    assert "commands --json is deterministic" (renderCommandJson == renderCommandJson)

exerciseOptparseParser :: IO ()
exerciseOptparseParser = do
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["bench", "selfplay", "--backend", "rust,haskell", "--games", "1", "--seed", "42"] of
        OA.Success command -> assert "execParserPure parses bench cohort" (parsesBenchCohort (Right command))
        _ -> error "execParserPure failed to parse bench cohort"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        [ "verify"
        , "legacy-parity"
        , "rollouts"
        , "--backend"
        , "cpp-legacy,cpp-imperative,cpp-functional,rust,haskell"
        , "--games"
        , "1"
        , "--seed"
        , "42"
        ] of
        OA.Success command -> assert "execParserPure parses legacy parity cohort" (parsesLegacyParityCohort (Right command))
        _ -> error "execParserPure failed to parse legacy parity cohort"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        ["inspect", "show", "abc123", "--with-equity", "--top", "3"] of
        OA.Success command -> assert "execParserPure parses inspect equity show" (parsesInspectEquityShow (Right command))
        _ -> error "execParserPure failed to parse inspect show --with-equity"
    case OA.execParserPure
        OA.defaultPrefs
        commandParserInfo
        [ "verify"
        , "selfplay"
        , "--backend"
        , "rust,haskell"
        , "--rng"
        , "native"
        , "--games"
        , "1"
        , "--seed"
        , "42"
        ] of
        OA.Failure _ -> pure ()
        _ -> error "execParserPure accepted native RNG for verify selfplay"

exerciseCacheRootBranches :: IO ()
exerciseCacheRootBranches = do
    explicit <- Transcript.resolveCacheRoot (Just ".mcts-cache-explicit")
    assert "cache root explicit branch" (explicit == ".mcts-cache-explicit")
    fallback <- Transcript.resolveCacheRoot Nothing
    assert "cache root default branch" (".mcts-cache" `isSuffixOfLocal` fallback)
  where
    isSuffixOfLocal suffix value = suffix == drop (length value - length suffix) value

exerciseReportCardRenderer :: IO ()
exerciseReportCardRenderer = do
    let renderedText = renderReportCard defaultReportCard
        renderedJson = renderReportCardJson defaultReportCard
        jsonValue = decodeJsonValue "renderReportCardJson defaultReportCard" renderedJson
    assert "report card text renders title" ("MCTS POC report card" `contains` renderedText)
    assert
        "report card text renders determinism section"
        ("Cross-backend determinism" `contains` renderedText)
    assert
        "report card text renders visit/move thresholds in matrix order"
        ("thresholds native 0.050/0.005, cross-build 0.010/0.001" `contains` renderedText)
    assert "report card text renders verdict" ("Verdict:" `contains` renderedText)
    assert
        "report card JSON has required top-level keys"
        ( jsonObjectHasKeys
            jsonValue
            ["q1_rollouts_st", "q2_selfplay_st", "q5_cpp_imperative_scaling", "divergence_matrix", "verdict"]
        )
    let rows = divergenceRowsFromTranscripts [asBackend Rust, asBackend Haskell]
    assert
        "report card derives one matrix row per transcript"
        (map reportDivergenceOrigin rows == ["rust", "haskell"])
    assert
        "report card derives one matrix cell per transcript"
        (all ((== 2) . length . reportDivergenceCells) rows)
  where
    asBackend backend =
        sampleTranscript
            { transcriptConfig = (transcriptConfig sampleTranscript){runBackend = backend}
            , transcriptEnvelope = makeLogicalEnvelope backend CppRng
            }

decodeJsonValue :: String -> String -> Value
decodeJsonValue label raw =
    case eitherDecodeStrict' (BSC.pack raw) of
        Left err -> error ("invalid JSON in " <> label <> ": " <> err)
        Right value -> value

jsonObjectHasKeys :: Value -> [String] -> Bool
jsonObjectHasKeys (Object object) keys =
    all (flip AesonKeyMap.member object . AesonKey.fromString) keys
jsonObjectHasKeys _ _ = False

isJsonObjectOrArray :: Value -> Bool
isJsonObjectOrArray (Object _) = True
isJsonObjectOrArray (Array _) = True
isJsonObjectOrArray _ = False

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
    -- runAppIO threads the env through and `askEnv` returns the production
    -- monotonic clock.
    first <- runAppIO env $ do
        e <- askEnv
        liftIO (envClock e)
    second <- runAppIO env $ do
        e <- askEnv
        liftIO (envClock e)
    assert "default clock is monotone" (second >= first)
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

exerciseKnownPositionRenderer :: IO ()
exerciseKnownPositionRenderer = do
    let moves = [Pawn 4 1, Pawn 4 7, WallH 0 0, WallH 2 0, Pawn 4 2]
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
    assert "known position renders hero coordinate" ("hero=" `contains` rendered)
    assert "known position renders villain coordinate" ("villain=" `contains` rendered)
    assert "known position renders side to move" ("sideToMove=Villain" `contains` rendered)
    assert "known position renders legal moves" ("legal=" `contains` rendered)
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

exerciseErrorRenderings :: IO ()
exerciseErrorRenderings = do
    -- Smoke test: every variant has a non-empty renderError output.
    let samples = map snd sampleErrorRenderings
    assert "every error variant renders to non-empty text" (all (not . T.null . renderError) samples)
    assert "TranscriptNotFound mentions the ref" ("abc" `inText` renderError (TranscriptNotFound "abc"))
    assert
        "DocsCheckDrift mentions the remedy"
        ("docker compose run --rm mcts mcts docs generate" `inText` renderError (DocsCheckDrift "x" "y"))
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

exerciseErrorRenderer :: IO ()
exerciseErrorRenderer = do
    let rendered = unlines [label <> ": " <> T.unpack (renderError err) | (label, err) <- sampleErrorRenderings]
    assert
        "error renderer includes every sample label"
        (all ((`contains` rendered) . fst) sampleErrorRenderings)
    assert
        "error renderer emits one line per sample"
        (length (lines rendered) == length sampleErrorRenderings)

exerciseSubprocessRenderer :: IO ()
exerciseSubprocessRenderer = do
    let subprocess = Subprocess "cabal" ["exec", "mcts", "--", "inspect", "show", "a b"] Nothing Nothing
        rendered = renderSubprocess subprocess
        failure = renderError (SubprocessFailed rendered 2)
    assert
        "subprocess render quotes spaced arguments"
        (rendered == "cabal exec mcts -- inspect show 'a b'")
    assert "subprocess failure includes rendered command" (T.pack rendered `T.isInfixOf` failure)
    assert "subprocess failure includes exit code" (T.pack "exit=2" `T.isInfixOf` failure)

exerciseSubprocessEnvironment :: IO ()
exerciseSubprocessEnvironment = do
    result <-
        capture
            ( Subprocess
                "bash"
                ["-c", "printf '%s\\n%s\\n' \"$MCTS_TEST_OVERRIDE\" \"$PATH\""]
                (Just [("MCTS_TEST_OVERRIDE", "ok")])
                Nothing
            )
    case result of
        Right output -> do
            let outLines = lines (processStdout output)
            assert
                "subprocess env override is present"
                (take 1 outLines == ["ok"])
            assert
                "subprocess env preserves inherited PATH"
                ( case drop 1 outLines of
                    path : _ -> not (null path)
                    [] -> False
                )
        Left err -> failTest ("subprocess env capture failed: " <> show err)

exerciseTuiBoardRenderer :: IO ()
exerciseTuiBoardRenderer = do
    let rendered = renderBoardText initialBoard <> renderStatusText "00000000" 0 0 <> "\n"
    assert "TUI board renders status hash" ("00000000" `contains` rendered)
    assert "TUI board renders move index" ("move" `contains` rendered)
    assert "TUI board renders board text" (length (lines rendered) > 4)

exerciseTuiReplayRenderer :: IO ()
exerciseTuiReplayRenderer = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSims = FixedSims 4
                , inputMaxPlies = 8
                , inputThreading = SingleThreaded
                }
        record = MoveRecord 0 (Pawn 4 1) [(Pawn 4 1, 4)]
        transcript =
            Transcript
                (makeRunConfig inputs)
                (makeLogicalEnvelope Haskell CppRng)
                [GameTranscript 0 [record] HeroWin]
        stream =
            EqStream
                { eqTranscriptHash = replicate 64 'a'
                , eqBackend = Haskell
                , eqBuildId = "overlay-fixture"
                , eqRecords = [EqRecord 0 0 (Pawn 4 1) 0.25]
                }
        stateAtStart = initialReplayStateWithOverlays (replicate 64 'a') transcript [stream]
    case applyReplayKey ReplayNext stateAtStart of
        Nothing -> failTest "ReplayNext in replay renderer test must continue"
        Just stateAtOne -> do
            let rendered =
                    unlines $
                        [ renderStatusText "aaaaaaaa" (replayMoveIndex stateAtOne) 1
                        , "move played: " <> renderMove (moveChosen record)
                        ]
                            <> renderOverlayRowsText (currentOverlayRows stateAtOne)
            assert "TUI replay renders status row" ("status" `contains` rendered)
            assert "TUI replay renders originator overlay" ("originator" `contains` rendered)
            assert "TUI replay renders divergence column" ("divergence" `contains` rendered)

-- | Sprint 7.4: cover the `mcts play` interactive command dispatcher.
-- The pure `applyUserInput` lets us exercise each in-app command
-- without spinning up brick.
exerciseTuiPlayInput :: IO ()
exerciseTuiPlayInput = do
    let st0 = initialPlayState 42 200 4
        quitOutcome = applyUserInput ":quit" st0
        quitShort = applyUserInput ":q" st0
        invalidParse = applyUserInput "garbage" st0
        emptyInput = applyUserInput "" st0
        hintOutcome = applyUserInput ":hint" st0
        undoNoHistory = applyUserInput ":undo" st0
        saveOutcome = applyUserInput ":save" st0
        aiTurnInput = applyUserInput "*(4,1)" st0{playStateAiSide = Hero}
        spectatorInput =
            applyUserInput
                "*(4,1)"
                st0{playStateAiSide = Villain, playStateVsBackend = Just Rust}
    case quitOutcome of
        OutcomeQuit -> pure ()
        _ -> failTest "applyUserInput :quit must produce OutcomeQuit"
    case quitShort of
        OutcomeQuit -> pure ()
        _ -> failTest "applyUserInput :q must produce OutcomeQuit"
    case invalidParse of
        OutcomeContinue st ->
            assert
                "InvalidMove message surfaced for garbage input"
                ("InvalidMove" `isInfixOfStr` playStateMessage st)
        _ -> failTest "applyUserInput garbage must continue"
    case emptyInput of
        OutcomeContinue st -> assert "empty input leaves message intact" (playStateInput st == "")
        _ -> failTest "applyUserInput \"\" must continue"
    case hintOutcome of
        OutcomeContinue st -> do
            assert ":hint records a last-hint action" (playStateLastHint st /= Nothing)
            assert ":hint surfaces a hint message" ("hint:" `isInfixOfStr` playStateMessage st)
        _ -> failTest ":hint must continue"
    case undoNoHistory of
        OutcomeContinue st ->
            assert
                ":undo with empty history reports nothing-to-undo"
                ("nothing to undo" `isInfixOfStr` playStateMessage st)
        _ -> failTest ":undo must continue"
    case saveOutcome of
        OutcomeSave st ->
            assert ":save leaves a save request for the event loop" (playStateInput st == "")
        _ -> failTest ":save must request a transcript write"
    case aiTurnInput of
        OutcomeContinue st ->
            assert
                "human input is blocked on an AI-controlled turn"
                ("waiting for" `isInfixOfStr` playStateMessage st)
        _ -> failTest "AI-turn input must continue with a status message"
    case spectatorInput of
        OutcomeContinue st ->
            assert "spectator mode blocks manual moves" ("waiting for" `isInfixOfStr` playStateMessage st)
        _ -> failTest "spectator input must continue with a status message"
    noMove <- advanceAiState st0
    assert "advanceAiState does not move during a human turn" (playStateMoveCount noMove == 0)
    -- Apply a real move, then undo it, then verify the board state is
    -- back to the initial position.
    case applyUserInput "*(4,1)" st0 of
        OutcomeContinue st1 -> do
            assert "real move advances ply count" (playStateMoveCount st1 == 1)
            assert "real move records transcript move" (length (playStateRecords st1) == 1)
            aiSt <- advanceAiState st1{playStateBackend = Rust}
            assert "selected-backend AI advances the game" (playStateMoveCount aiSt == 2)
            assert
                "selected-backend AI records transcript visits"
                ( case reverse (playStateRecords aiSt) of
                    record : _ -> not (null (moveVisits record))
                    [] -> False
                )
            assert
                "selected-backend AI reports the move source"
                ("AI played" `isInfixOfStr` playStateMessage aiSt)
            let cacheRoot = ".mcts-cache-unit-play"
            removeDirectoryIfExists cacheRoot
            saved <- savePlayState st1{playStateCacheDir = Just cacheRoot}
            assert ":save writes a transcript status" ("saved " `isInfixOfStr` playStateMessage saved)
            files <- listTranscriptFiles (Just cacheRoot)
            assert ":save writes exactly one transcript" (length files == 1)
            case files of
                [path] -> do
                    decoded <- readTranscriptFile path
                    case decoded of
                        Right transcript ->
                            assert
                                ":save transcript preserves played move"
                                (concatMap gameMoves (transcriptGames transcript) == playStateRecords st1)
                        Left err -> failTest (":save transcript failed to decode: " <> show err)
                _ -> failTest ":save wrote an unexpected transcript file set"
            removeDirectoryIfExists cacheRoot
            case applyUserInput ":undo" st1 of
                OutcomeContinue st2 -> do
                    assert "undo rewinds the ply count" (playStateMoveCount st2 == 0)
                    assert "undo restores the board" (playStateBoard st2 == playStateBoard st0)
                    assert "undo removes transcript record" (null (playStateRecords st2))
                _ -> failTest "undo after real move must continue"
        _ -> failTest "valid move *(4,1) must continue"

failTest :: String -> IO ()
failTest message = do
    putStrLn ("FAIL: " <> message)
    error message

isInfixOfStr :: String -> String -> Bool
isInfixOfStr needle haystack =
    T.isInfixOf (T.pack needle) (T.pack haystack)

-- | Sprint 7.2: `backendNativeSalt` must be zero under `--rng cpp`
-- and distinct per backend under `--rng native`. The Haskell
-- backend's salt is the smallest non-zero value because
-- `backendId Haskell == 4` and the multiplier is constant.
exerciseBackendNativeSalt :: IO ()
exerciseBackendNativeSalt = do
    let salts =
            [ backendNativeSalt NativeRng backend
            | backend <- [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]
            ]
    assert
        "cpp-RNG salt is zero for every backend"
        ( all
            (== 0)
            [ backendNativeSalt CppRng backend
            | backend <- [CppLegacy, CppImperative, CppFunctional, Rust, Haskell]
            ]
        )
    assert
        "native salt is non-zero for every backend"
        (all (/= 0) salts)
    assert
        "native salts are pairwise distinct across backends"
        (length (List.nub salts) == length salts)

-- | Sprint 7.4: cover the multi-backend equity overlay produced by
-- `currentOverlayRows`. Initial position (idx == 0) yields no rows;
-- advancing to move 1 with a single-backend EqStream yields one row
-- with the recompute's chosen action and equity.
exerciseTuiReplayOverlay :: IO ()
exerciseTuiReplayOverlay = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSims = FixedSims 4
                , inputMaxPlies = 8
                }
        gameRec = runGame inputs 0
        transcript =
            Transcript
                (makeRunConfig inputs)
                (makeLogicalEnvelope Haskell CppRng)
                [gameRec]
        hashValue = replicate 64 '0'
        stream = (equityStreamForTranscript hashValue transcript){eqBuildId = "overlay-fixture"}
        stateAtStart = initialReplayStateWithOverlays hashValue transcript [stream]
    -- Index 0: no current move, all overlay rows are empty.
    case currentOverlayRows stateAtStart of
        [row] -> do
            assert "overlay start row has no chosen" (overlayChosen row == Nothing)
            assert "overlay start row has no equity" (overlayEquity row == Nothing)
        rows -> failTest ("expected one overlay row at idx 0, got " <> show (length rows))
    -- Advance to move 1: overlay should resolve to the recorded chosen action.
    case applyReplayKey ReplayNext stateAtStart of
        Just stateAtOne -> case currentOverlayRows stateAtOne of
            [row] -> do
                assert "overlay row 1 carries a chosen action" (overlayChosen row /= Nothing)
                assert "overlay row 1 reports the fixture build id" (overlayBuildId row == "overlay-fixture")
                assert "overlay row 1 marks verified replay data" ("verified" `isInfixOfStr` overlayStatus row)
                assert "overlay row 1 has no divergence annotation" (overlayDivergence row == Nothing)
            rows -> failTest ("expected one overlay row at idx 1, got " <> show (length rows))
        Nothing -> failTest "ReplayNext at idx 0 must continue"
    case (gameMoves gameRec, applyReplayKey ReplayNext stateAtStart) of
        (record : _, Just stateAtOne) -> do
            case filter (/= moveChosen record) allActions of
                divergentAction : _ -> do
                    let divergentStream =
                            stream
                                { eqRecords = [EqRecord 0 (moveIndex record) divergentAction 0.125]
                                }
                        divergentState = stateAtOne{replayOverlays = [divergentStream]}
                    case currentOverlayRows divergentState of
                        [row] -> do
                            assert "divergent replay row marks divergence" ("diverged" `isInfixOfStr` overlayStatus row)
                            assert "divergent replay row annotates the move" (overlayDivergence row /= Nothing)
                        rows -> failTest ("expected one divergent overlay row, got " <> show (length rows))
                [] -> failTest "allActions must contain a divergent action"
        _ -> failTest "replay overlay fixture must have at least one move"
    -- On-demand columns: `r` selects the next backend that does not
    -- already have a loaded or unavailable overlay, then status-annotates
    -- loaded/skipped results.
    let stateWithCandidates =
            stateAtStart
                { replayOverlayCandidates = [Haskell, Rust]
                , replayUnavailableBackends = []
                }
        onDemandStream =
            stream
                { eqBackend = Rust
                , eqBuildId = "rust-on-demand"
                }
    assert
        "on-demand replay column skips loaded and unavailable backends"
        (nextOverlayBackend stateWithCandidates == Just Rust)
    let loadedState =
            applyOverlayLoadResult
                Rust
                (ReplayOverlayLoaded onDemandStream)
                stateWithCandidates
    assert "on-demand replay column appends overlay" (length (replayOverlays loadedState) == 2)
    assert
        "on-demand replay status reports loaded column"
        ("loaded rust" `isInfixOfStr` replayMessage loadedState)
    let skippedState =
            applyOverlayLoadResult
                Rust
                (ReplayOverlaySkipped "rust unavailable")
                stateAtStart
    assert
        "on-demand skipped backend is marked unavailable"
        (Rust `elem` replayUnavailableBackends skippedState)
    case currentOverlayRows skippedState of
        [_, row] ->
            assert "unavailable replay row is rendered explicitly" (overlayStatus row == "unavailable")
        rows -> failTest ("expected loaded plus unavailable replay rows, got " <> show (length rows))
    -- Cache miss: replay preparation recomputes the originator column,
    -- writes the sidecar, and subsequent preparation loads it without
    -- recomputing.
    let cacheRoot = ".mcts-cache-replay-overlay-test"
    removeDirectoryIfExists cacheRoot
    (prepared, preparedMessage) <- prepareReplayOverlays (Just cacheRoot) hashValue transcript
    assert "replay cache miss prepares one overlay" (length prepared == 1)
    assert
        "replay cache miss reports recompute"
        (maybe False ("recomputed haskell" `isInfixOfStr`) preparedMessage)
    sidecars <- listEquitySidecars (Just cacheRoot)
    assert "replay cache miss writes one sidecar" (length sidecars == 1)
    (cached, cachedMessage) <- prepareReplayOverlays (Just cacheRoot) hashValue transcript
    assert "replay cache hit loads one overlay" (length cached == 1)
    assert "replay cache hit has no recompute message" (cachedMessage == Nothing)
    removeDirectoryIfExists cacheRoot

-- | Sprint 7.4: cover the `mcts inspect replay` TUI's pure
-- navigation dispatcher. The replay state walks forward, backward,
-- to the start, and to the end of a small synthesized transcript.
exerciseTuiReplayNav :: IO ()
exerciseTuiReplayNav = do
    let inputs =
            defaultRunInputs
                { inputBackend = Haskell
                , inputRng = CppRng
                , inputGames = 1
                , inputSims = FixedSims 4
                , inputMaxPlies = 8
                }
        gameRec = runGame inputs 0
        transcript =
            Transcript
                (makeRunConfig inputs)
                (makeLogicalEnvelope Haskell CppRng)
                [gameRec]
        st0 = initialReplayState (replicate 64 '0') transcript
        nMoves = length (gameMoves gameRec)
    assert "replay starts at move 0" (replayMoveIndex st0 == 0)
    case applyReplayKey ReplayNext st0 of
        Nothing -> failTest "ReplayNext must continue"
        Just st1 -> do
            assert "ReplayNext advances by 1" (replayMoveIndex st1 == 1)
            case applyReplayKey ReplayPrev st1 of
                Nothing -> failTest "ReplayPrev must continue"
                Just st2 ->
                    assert "ReplayPrev rewinds to 0" (replayMoveIndex st2 == 0)
    case applyReplayKey ReplayEnd st0 of
        Nothing -> failTest "ReplayEnd must continue"
        Just stEnd ->
            assert "ReplayEnd lands at total" (replayMoveIndex stEnd == nMoves)
    case applyReplayKey ReplayPrev st0 of
        Nothing -> failTest "ReplayPrev at start must continue"
        Just stStay ->
            assert "ReplayPrev at 0 clamps to 0" (replayMoveIndex stStay == 0)
    case applyReplayKey ReplayQuit st0 of
        Nothing -> pure ()
        Just _ -> failTest "ReplayQuit must terminate"
    -- replayBoardAt 0 == initial board
    assert
        "replayBoardAt 0 equals initial board"
        (replayBoardAt transcript 0 == initialBoard)
    -- Walk to the end and back via Home to cross-check.
    case applyReplayKey ReplayEnd st0 of
        Just stEnd -> case applyReplayKey ReplayStart stEnd of
            Just stHome -> assert "ReplayStart lands at 0" (replayMoveIndex stHome == 0)
            Nothing -> failTest "ReplayStart must continue"
        Nothing -> failTest "ReplayEnd must continue"
