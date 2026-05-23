{-# LANGUAGE RankNTypes #-}

module Main where

import qualified Data.ByteString as BS
import Data.List (isInfixOf, stripPrefix)
import Data.Word (Word32, Word8)
import MCTS.CLI.Test (buildMeasuredReportCardWith)
import MCTS.Driver
import MCTS.Driver.Dispatch (runBatchDispatch)
import MCTS.Driver.Rust (runGameRust)
import MCTS.Engine.ForeignRecompute (foreignRecomputeEqStream)
import qualified MCTS.Engine.Recompute as Recompute
import MCTS.Error (AppError (..), EnvelopeMismatchScope (..))
import MCTS.FFI.Common (EngineEnvelope (..))
import qualified MCTS.FFI.Common
import MCTS.FFI.Rust (loadRustEnvelope, withRustRecomputeGame)
import MCTS.ReportCard (ReportCard (..), ReportDivergenceRow (..), renderReportCardJson)
import MCTS.Subprocess (ProcessOutput (..), Subprocess (..), capture)
import MCTS.Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import MCTS.Verify.Envelope (checkTranscriptEnvelopesLive)
import System.Directory (doesFileExist, findExecutable)
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

main :: IO ()
main =
    defaultMain $
        testGroup
            "mcts-integration"
            [ testGroup "same-backend determinism" (map sameBackend allBackends)
            , testGroup
                "real mcts binary determinism"
                [ testCase "haskell" (binaryBenchDeterminism Nothing Haskell)
                , testCase
                    "rust"
                    (binaryBenchDeterminism (Just "rust/target/release/libmcts_rust.so") Rust)
                , testCase "integration subprocess boundary guard" integrationSubprocessBoundaryGuard
                ]
            , testGroup
                "foreign ffi smoke drivers"
                [ testCase "rust" (foreignFfiSmokeDriver "rust/target/release/libmcts_rust.so" Rust runGameRust)
                ]
            , testGroup
                "foreign ffi live envelopes"
                [ testCase "rust" (foreignFfiEnvelope "rust/target/release/libmcts_rust.so" Rust loadRustEnvelope)
                ]
            , testGroup
                "foreign ffi live envelope stamping"
                [ testCase
                    "rust"
                    (foreignDispatchLiveEnvelope "rust/target/release/libmcts_rust.so" Rust loadRustEnvelope)
                ]
            , testCase "equity sidecar originator markers" sidecarOriginMarkers
            , testCase
                "report-card divergence and inspect sidecar integration"
                reportCardDivergenceIntegration
            , testCase "generated C++ parity evidence is synthetic and no-draw" cppParityEvidenceCheck
            , testGroup
                "foreign recompute EqStream"
                [ testCase
                    "rust"
                    ( foreignRecomputeSmoke
                        "rust/target/release/libmcts_rust.so"
                        Rust
                        withRustRecomputeGame
                    )
                ]
            ]

sameBackend :: Backend -> TestTree
sameBackend backend =
    testGroup
        (backendIdentifier backend)
        [ testCase ("seed " <> show seedValue) (sameBackendSeed baseInputs seedValue)
        | seedValue <- [42, 43, 44 :: Integer]
        ]
  where
    baseInputs =
        defaultRunInputs
            { inputBackend = backend
            , inputRng = CppRng
            , inputGames = 1
            , inputSims = FixedSims 4
            , inputMaxPlies = 20
            }

sameBackendSeed :: RunInputs -> Integer -> IO ()
sameBackendSeed baseInputs seedValue = do
    let inputs = baseInputs{inputSeed = fromIntegral seedValue}
        first = runGame inputs 0
        second = runGame inputs 0
    first @?= second

binaryBenchDeterminism :: Maybe FilePath -> Backend -> IO ()
binaryBenchDeterminism maybeLibraryPath backend = do
    present <-
        case maybeLibraryPath of
            Nothing -> pure True
            Just libraryPath -> doesFileExist libraryPath
    if not present
        then pure ()
        else withSystemTempDirectory "mcts-bin-a" $ \cacheA ->
            withSystemTempDirectory "mcts-bin-b" $ \cacheB -> do
                first <- runBinaryBench cacheA backend
                second <- runBinaryBench cacheB backend
                firstHash <- requireBinaryBenchHash first
                secondHash <- requireBinaryBenchHash second
                firstHash @?= secondHash
                assertBinaryBenchTranscriptDeterminism cacheA cacheB firstHash secondHash

runBinaryBench :: FilePath -> Backend -> IO ProcessOutput
runBinaryBench cacheRoot backend = do
    result <-
        captureMcts
            [ "bench"
            , "selfplay"
            , "--backend"
            , backendIdentifier backend
            , "--threading"
            , "single"
            , "--rng"
            , "cpp"
            , "--games"
            , "1"
            , "--seed"
            , "42"
            , "--sims"
            , "4"
            , "--max-plies"
            , "8"
            , "--cache-dir"
            , cacheRoot
            , "--format"
            , "json"
            ]
    case result of
        Left err ->
            assertFailure
                ("real mcts binary bench failed for " <> backendIdentifier backend <> ": " <> show err)
        Right output -> do
            assertBool
                (backendIdentifier backend <> " binary JSON names backend")
                (("\"backend\":\"" <> backendIdentifier backend <> "\"") `isInfixOf` processStdout output)
            assertBool
                (backendIdentifier backend <> " binary JSON names workload")
                ("\"workload\":\"selfplay\"" `isInfixOf` processStdout output)
            assertBool
                (backendIdentifier backend <> " binary JSON names one game")
                ("\"games\":1" `isInfixOf` processStdout output)
            pure output

captureMcts :: [String] -> IO (Either AppError ProcessOutput)
captureMcts args = do
    maybeMcts <- findExecutable "mcts"
    case maybeMcts of
        Just mctsPath ->
            capture (Subprocess mctsPath args Nothing Nothing)
        Nothing -> do
            maybeBuildDir <- lookupEnv "MCTS_CABAL_BUILDDIR"
            let buildDirArgs =
                    case maybeBuildDir of
                        Nothing -> []
                        Just buildDir -> ["--builddir=" <> buildDir]
            capture (Subprocess "cabal" (buildDirArgs <> ["exec", "mcts", "--"] <> args) Nothing Nothing)

requireBinaryBenchHash :: ProcessOutput -> IO String
requireBinaryBenchHash output =
    case jsonStringField "hash" (processStdout output) of
        Nothing -> assertFailure ("real mcts binary JSON missing hash: " <> processStdout output)
        Just value -> pure value

assertBinaryBenchTranscriptDeterminism :: FilePath -> FilePath -> String -> String -> IO ()
assertBinaryBenchTranscriptDeterminism cacheA cacheB firstHash secondHash = do
    first <- readTranscriptFile (benchTranscriptPath cacheA firstHash)
    second <- readTranscriptFile (benchTranscriptPath cacheB secondHash)
    case (first, second) of
        (Right firstTranscript, Right secondTranscript) ->
            firstTranscript @?= secondTranscript
        (Left err, _) ->
            assertFailure ("first real-binary transcript failed to decode: " <> show err)
        (_, Left err) ->
            assertFailure ("second real-binary transcript failed to decode: " <> show err)

benchTranscriptPath :: FilePath -> String -> FilePath
benchTranscriptPath cacheRoot hashValue =
    cacheRoot </> "transcripts" </> hostArch </> (hashValue <> ".tr")

jsonStringField :: String -> String -> Maybe String
jsonStringField key text =
    takeWhile (/= '"') <$> findAfter ("\"" <> key <> "\":\"") text

findAfter :: String -> String -> Maybe String
findAfter needle text =
    case stripPrefix needle text of
        Just rest -> Just rest
        Nothing ->
            case text of
                [] -> Nothing
                _ : rest -> findAfter needle rest

integrationSubprocessBoundaryGuard :: IO ()
integrationSubprocessBoundaryGuard = do
    source <- readFile "test/integration/Main.hs"
    let typedProcessModule = "System.Process" <> ".Typed"
        typedProcessProc = "Process" <> ".proc"
    assertBool
        "integration test must use MCTS.Subprocess rather than direct process constructors"
        ( typedProcessModule `notElem` words source
            && typedProcessProc `notElem` words source
        )

sidecarOriginMarkers :: IO ()
sidecarOriginMarkers =
    withSystemTempDirectory "mcts-sidecars" $ \cacheRoot -> do
        let inputs =
                defaultRunInputs
                    { inputBackend = Haskell
                    , inputRng = CppRng
                    , inputGames = 1
                    , inputSims = FixedSims 4
                    , inputMaxPlies = 12
                    }
            transcript =
                Transcript
                    (makeRunConfig inputs)
                    (makeLogicalEnvelope Haskell CppRng)
                    [runGame inputs 0]
        written <- writeTranscript (Just cacheRoot) transcript
        case written of
            Left err -> assertFailure ("transcript write failed: " <> show err)
            Right (hashValue, _) -> do
                originEntry <- writeEquitySidecar (Just cacheRoot) hashValue transcript
                let foreignEnvelope =
                        (transcriptEnvelope transcript)
                            { envelopeBackend = Rust
                            , envelopeBuildId = "logical"
                            }
                    foreignStream =
                        (equityStreamForTranscript hashValue transcript)
                            { eqBackend = Rust
                            , eqBuildId = "logical"
                            }
                foreignEntry <- writeEquitySidecarStreamWithEnvelope (Just cacheRoot) foreignEnvelope foreignStream
                listed <- listEquitySidecars (Just cacheRoot)
                length listed @?= 2
                assertBool "origin sidecar is marked as originator" (sidecarIsOriginator transcript originEntry)
                assertBool
                    "foreign sidecar is not marked as originator"
                    (not (sidecarIsOriginator transcript foreignEntry))

reportCardDivergenceIntegration :: IO ()
reportCardDivergenceIntegration =
    withSystemTempDirectory "mcts-report-card" $ \reportCache -> do
        reportResult <-
            buildMeasuredReportCardWith
                [Rust, Haskell]
                defaultRunInputs
                    { inputWorkload = Selfplay
                    , inputRng = CppRng
                    , inputThreading = SingleThreaded
                    , inputGames = 1
                    , inputSeed = 42
                    , inputSims = FixedSims 16
                    , inputMaxPlies = 60
                    , inputCacheDir = Just reportCache
                    }
        case reportResult of
            Left err ->
                assertFailure ("measured report-card builder failed: " <> show err)
            Right card -> do
                map reportDivergenceOrigin (reportDivergenceRows card)
                    @?= map backendIdentifier [Rust, Haskell]
                assertBool
                    "each measured divergence row has a two-backend cell set"
                    (all ((== 2) . length . reportDivergenceCells) (reportDivergenceRows card))
                assertBool
                    "measured report-card JSON exposes divergence_matrix"
                    ("\"divergence_matrix\"" `isInfixOf` renderReportCardJson card)
                assertBool
                    "measured report-card JSON exposes Q1 evidence fields"
                    ("\"q1_rollouts_st\"" `isInfixOf` renderReportCardJson card)
                assertBool
                    "measured report-card JSON exposes Q5 evidence fields"
                    ("\"q5_cpp_imperative_scaling\"" `isInfixOf` renderReportCardJson card)

        withSystemTempDirectory "mcts-divergence-sidecar" $ \cacheRoot -> do
            let inputs =
                    defaultRunInputs
                        { inputBackend = Haskell
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputThreading = SingleThreaded
                        , inputGames = 1
                        , inputSeed = 42
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 8
                        , inputCacheDir = Just cacheRoot
                        }
                transcript =
                    Transcript
                        (makeRunConfig inputs)
                        (makeLogicalEnvelope Haskell CppRng)
                        [runGame inputs 0]
            written <- writeTranscript (Just cacheRoot) transcript
            case written of
                Left err ->
                    assertFailure ("report-card sidecar transcript write failed: " <> show err)
                Right (hashValue, _) -> do
                    case Recompute.recomputeEqStream hashValue (envelopeBuildId (transcriptEnvelope transcript)) transcript of
                        Left err ->
                            assertFailure ("report-card sidecar recompute failed: " <> show err)
                        Right stream -> do
                            _ <- writeEquitySidecarStream (Just cacheRoot) transcript stream
                            divergence <-
                                captureMcts
                                    [ "inspect"
                                    , "divergence"
                                    , take 8 hashValue
                                    , "--cache-dir"
                                    , cacheRoot
                                    , "--format"
                                    , "json"
                                    ]
                            case divergence of
                                Left err ->
                                    assertFailure ("inspect divergence sidecar path failed: " <> show err)
                                Right output -> do
                                    assertBool
                                        "inspect divergence reports the cached sidecar"
                                        ("\"cached_sidecars\":1" `isInfixOf` processStdout output)
                                    assertBool
                                        "inspect divergence includes the originator sidecar row"
                                        ("\"backend_pair\":\"haskell/haskell\"" `isInfixOf` processStdout output)
                                    assertBool
                                        "originator sidecar has zero visit disagreement"
                                        ("\"visit_disagreement_rate\":0.0" `isInfixOf` processStdout output)

foreignFfiSmokeDriver
    :: FilePath
    -> Backend
    -> (RunInputs -> Word32 -> IO (Either AppError GameTranscript))
    -> IO ()
foreignFfiSmokeDriver libraryPath backend runner = do
    present <- doesFileExist libraryPath
    if not present
        then pure ()
        else do
            result <-
                runner
                    defaultRunInputs
                        { inputBackend = backend
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputGames = 1
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 60
                        }
                    0
            case result of
                Left err -> assertFailure (backendIdentifier backend <> " FFI smoke driver failed: " <> show err)
                Right game -> do
                    assertBool (backendIdentifier backend <> " FFI smoke produced moves") (not (null (gameMoves game)))
                    assertBool
                        (backendIdentifier backend <> " FFI smoke records chosen visits")
                        (all (\record -> moveChosen record `elem` map fst (moveVisits record)) (gameMoves game))

foreignFfiEnvelope :: FilePath -> Backend -> IO (Either AppError EngineEnvelope) -> IO ()
foreignFfiEnvelope libraryPath backend loader = do
    present <- doesFileExist libraryPath
    if not present
        then pure ()
        else do
            result <- loader
            case result of
                Left err -> assertFailure (backendIdentifier backend <> " FFI envelope failed: " <> show err)
                Right envelope -> do
                    engineEnvVersion envelope @?= 1
                    engineEnvBackend envelope @?= backend
                    engineEnvRngSource envelope @?= 1
                    engineEnvHostArch envelope @?= expectedHostArch
                    -- The surviving foreign backend backfills
                    -- `engine_build_id` from their post-link
                    -- `.envelope_build_id` section where the build harness
                    -- patches it.
                    -- Sprint 6.5: Rust now exposes a `.envelope_build_id`
                    -- ELF section that the Dockerfile-invoked Rust build
                    -- recipe patches post-link. Fresh cargo release builds
                    -- leave the section all-zero; the integration test
                    -- accepts either state so it remains robust to whichever
                    -- build was last run.
                    case backend of
                        CppLegacy ->
                            assertBool
                                "cpp-legacy engine_build_id is patched"
                                (engineEnvBuildId envelope /= replicate 64 '0')
                        Rust ->
                            -- Either zero (smoke cargo build) or patched
                            -- by the Dockerfile-owned Rust install path.
                            pure ()
                        _ -> engineEnvBuildId envelope @?= replicate 64 '0'
                    engineEnvCompilerId envelope @?= expectedCompilerId backend
                    case backend of
                        Rust ->
                            assertBool
                                "rust envelope carries rustc compiler version"
                                ("rustc " `prefixOf` engineEnvCompilerVersion envelope)
                        _ -> pure ()
                    -- Sprint 6.5: every foreign backend now populates a
                    -- compile-time `libm_id` slot. The pinned container
                    -- ships glibc; macOS dev shells report `libsystem`;
                    -- musl containers report `musl`. The integration
                    -- test accepts the known string set.
                    assertBool
                        ( backendIdentifier backend
                            <> " envelope carries a known libm_id (got `"
                            <> engineEnvLibmId envelope
                            <> "`)"
                        )
                        (engineEnvLibmId envelope `elem` ["glibc", "musl", "libsystem"])

foreignDispatchLiveEnvelope :: FilePath -> Backend -> IO (Either AppError EngineEnvelope) -> IO ()
foreignDispatchLiveEnvelope libraryPath backend loader = do
    present <- doesFileExist libraryPath
    if not present
        then pure ()
        else withSystemTempDirectory "mcts-live-envelope" $ \cacheRoot -> do
            loaded <- loader
            expected <-
                case loaded of
                    Left err -> assertFailure (backendIdentifier backend <> " FFI envelope failed: " <> show err)
                    Right envelope -> pure (MCTS.FFI.Common.engineEnvelopeToEnvelope envelope)
            batchResult <-
                runBatchDispatch
                    defaultRunInputs
                        { inputBackend = backend
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputThreading = SingleThreaded
                        , inputGames = 1
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 60
                        , inputCacheDir = Just cacheRoot
                        }
            case batchResult of
                Left err ->
                    assertFailure (backendIdentifier backend <> " dispatch failed: " <> err)
                Right batch -> do
                    let transcript = batchTranscript batch
                    transcriptEnvelope transcript @?= expected
                    assertStaleCompilerVersion backend transcript

expectedHostArch :: Word8
expectedHostArch =
    case hostArch of
        "arm64" -> 1
        _ -> 0

expectedCompilerId :: Backend -> Word8
expectedCompilerId backend =
    case backend of
        Rust -> 2
        Haskell -> 3
        _ -> 0

prefixOf :: String -> String -> Bool
prefixOf [] _ = True
prefixOf _ [] = False
prefixOf (x : xs) (y : ys) = x == y && prefixOf xs ys

assertStaleCompilerVersion :: Backend -> Transcript -> IO ()
assertStaleCompilerVersion backend transcript = do
    let staleVersion = envelopeCompilerVersion (transcriptEnvelope transcript) <> "-stale-test"
        staleTranscript =
            transcript
                { transcriptEnvelope =
                    (transcriptEnvelope transcript)
                        { envelopeCompilerVersion = staleVersion
                        }
                }
    hardResult <- checkTranscriptEnvelopesLive False [staleTranscript]
    case hardResult of
        Left (EngineEnvelopeMismatch (BackendSlot gotBackend) "compiler_version" _ got) -> do
            gotBackend @?= backend
            got @?= staleVersion
        other -> assertFailure ("expected hard stale compiler_version mismatch, got " <> show other)
    allowedResult <- checkTranscriptEnvelopesLive True [staleTranscript]
    case allowedResult of
        Right [EngineEnvelopeMismatch (BackendSlot gotBackend) "compiler_version" _ got] -> do
            gotBackend @?= backend
            got @?= staleVersion
        other -> assertFailure ("expected allow-stale compiler_version warning, got " <> show other)

-- | Sprint 8.8 replacement for committed C++ fixture files. The integration
-- gate validates the Phase 2 wire shape with in-memory transcripts so a clean
-- clone has no `test/golden/` prerequisite.
cppParityEvidenceCheck :: IO ()
cppParityEvidenceCheck =
    withSystemTempDirectory "mcts-cpp-parity-evidence" $ \cacheRoot ->
        mapM_ (validateCppParityTranscript cacheRoot) [CppLegacy, CppImperative, CppFunctional]

validateCppParityTranscript :: FilePath -> Backend -> IO ()
validateCppParityTranscript cacheRoot backend = do
    let transcript = syntheticCppParityTranscript cacheRoot backend
        bytes = encodeTranscript transcript
    assertBool (backendIdentifier backend <> " transcript bytes are non-empty") (BS.length bytes > 48)
    case decodeTranscript bytes of
        Left err ->
            assertFailure (backendIdentifier backend <> " synthetic transcript failed to decode: " <> show err)
        Right decoded -> do
            runBackend (transcriptConfig decoded) @?= backend
            runWorkload (transcriptConfig decoded) @?= Selfplay
            runThreading (transcriptConfig decoded) @?= SingleThreaded
            runRngSource (transcriptConfig decoded) @?= CppRng
            assertBool
                (backendIdentifier backend <> " synthetic transcript contains games")
                (not (null (transcriptGames decoded)))
            assertBool
                (backendIdentifier backend <> " synthetic transcript records no Draw winners")
                (all ((/= Draw) . gameWinner) (transcriptGames decoded))
    writes <- writeTranscriptPerGame (Just cacheRoot) transcript
    case writes of
        Left err -> assertFailure (backendIdentifier backend <> " temporary transcript write failed: " <> show err)
        Right [(writtenHash, writtenPath)] -> do
            writtenBytes <- BS.readFile writtenPath
            takeBaseName writtenPath @?= writtenHash
            case decodeTranscript writtenBytes of
                Left err ->
                    assertFailure
                        (backendIdentifier backend <> " temporary transcript failed to decode: " <> show err)
                Right decoded -> do
                    runBackend (transcriptConfig decoded) @?= backend
                    runGames (transcriptConfig decoded) @?= 1
                    writtenHash @?= runConfigHash (transcriptConfig decoded)
        Right other ->
            assertFailure
                (backendIdentifier backend <> " expected one temporary transcript write, got " <> show (length other))

syntheticCppParityTranscript :: FilePath -> Backend -> Transcript
syntheticCppParityTranscript cacheRoot backend =
    let inputs =
            defaultRunInputs
                { inputBackend = backend
                , inputWorkload = Selfplay
                , inputRng = CppRng
                , inputThreading = SingleThreaded
                , inputGames = 1
                , inputSeed = 42
                , inputSims = FixedSims 10000
                , inputMaxPlies = 10000
                , inputCacheDir = Just cacheRoot
                }
        record = MoveRecord 0 (Pawn 4 1) [(Pawn 4 1, 10000)]
     in Transcript
            (makeRunConfig inputs)
            (makeLogicalEnvelope backend CppRng)
            [GameTranscript 0 [record] HeroWin]

-- | Sprint 6.5 / 7.5: drive `foreignRecomputeEqStream` against a real
-- foreign backend cdylib through `MCTS.Engine.ForeignRecompute` and
-- assert the emitted `EqStream` carries one record per move with a
-- finite or NaN equity slot. Skip when the cdylib is not built.
foreignRecomputeSmoke
    :: FilePath
    -> Backend
    -> (forall a. (MCTS.FFI.Common.DynamicRecomputeGame -> IO a) -> IO (Either AppError a))
    -> IO ()
foreignRecomputeSmoke libraryPath backend opener = do
    present <- doesFileExist libraryPath
    if not present
        then pure ()
        else withSystemTempDirectory "mcts-foreign-recompute" $ \cacheRoot -> do
            let inputs =
                    defaultRunInputs
                        { inputBackend = backend
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputThreading = SingleThreaded
                        , inputGames = 1
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 6
                        , inputCacheDir = Just cacheRoot
                        }
            batch <- runBatchDispatch inputs
            case batch of
                Left err ->
                    assertFailure
                        (backendIdentifier backend <> " foreign transcript generation failed: " <> err)
                Right batchResult -> do
                    let transcript = batchTranscript batchResult
                        moveCount = sum (map (length . gameMoves) (transcriptGames transcript))
                    result <-
                        foreignRecomputeEqStream
                            backend
                            (replicate 64 '0')
                            "smoke-build"
                            opener
                            transcript
                    case result of
                        Left err ->
                            assertFailure
                                ( backendIdentifier backend
                                    <> " foreign recompute failed: "
                                    <> show err
                                )
                        Right stream -> do
                            eqBackend stream @?= backend
                            eqBuildId stream @?= "smoke-build"
                            assertBool
                                (backendIdentifier backend <> " foreign recompute emitted records")
                                (length (eqRecords stream) == moveCount)
