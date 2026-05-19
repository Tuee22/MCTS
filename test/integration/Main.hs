{-# LANGUAGE RankNTypes #-}

module Main where

import Control.Monad (filterM)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isInfixOf, isSuffixOf, sort, stripPrefix)
import Data.Word (Word32, Word8)
import MCTS.CLI.Test (buildMeasuredReportCardWith)
import MCTS.Crypto.SHA256 (sha256Hex)
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
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
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
            , testCase "legacy goldens decode and respect no-draw semantics" legacyGoldenCheck
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
        capture
            ( Subprocess
                "mcts"
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
                Nothing
                Nothing
            )
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
                            , envelopeBuildId = "rust-logical"
                            }
                    foreignStream =
                        (equityStreamForTranscript hashValue transcript)
                            { eqBackend = Rust
                            , eqBuildId = "rust-logical"
                            }
                foreignEntry <- writeEquitySidecarStreamWithEnvelope (Just cacheRoot) foreignEnvelope foreignStream
                listed <- listEquitySidecars (Just cacheRoot)
                length listed @?= 2
                assertBool "origin sidecar is marked as originator" (sidecarIsOriginator transcript originEntry)
                assertBool
                    "foreign sidecar is not marked as originator"
                    (not (sidecarIsOriginator transcript foreignEntry))

reportCardDivergenceIntegration :: IO ()
reportCardDivergenceIntegration = do
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
                            capture
                                ( Subprocess
                                    "mcts"
                                    [ "inspect"
                                    , "divergence"
                                    , take 8 hashValue
                                    , "--cache-dir"
                                    , cacheRoot
                                    , "--format"
                                    , "json"
                                    ]
                                    Nothing
                                    Nothing
                                )
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
                    -- ELF section that `mcts build rust` patches post-
                    -- link. A fresh `cargo build --release` leaves the
                    -- section all-zero; the integration test accepts
                    -- either state so it remains robust to whichever
                    -- build was last run.
                    case backend of
                        CppLegacy ->
                            assertBool
                                "cpp-legacy engine_build_id is patched"
                                (engineEnvBuildId envelope /= replicate 64 '0')
                        Rust ->
                            -- Either zero (smoke cargo build) or
                            -- patched (post `mcts build rust` install).
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

-- | Sprint 4.5 Q6 golden check. Iterates `test/golden/legacy/transcripts/<arch>/`
-- and asserts every fixture decodes via the Phase 2 wire format with the
-- legacy parity envelope: backend = cpp-legacy, rng = cpp, no Draw winners.
-- The check is intentionally cross-architecture: committed fixtures for any
-- `<arch>` directory are decode-validated on every host so an amd64 run still
-- covers the currently committed arm64 Q6 anchor.
legacyGoldenCheck :: IO ()
legacyGoldenCheck = do
    let root = "test/golden/legacy/transcripts"
        retiredThroughput = "test/golden/cpp-legacy/throughput.json"
        retiredImperativeRoot = "test/golden/cpp-imperative/transcripts"
        retiredImperativeThroughput = "test/golden/cpp-imperative/throughput.json"
        retiredFunctionalRoot = "test/golden/cpp-functional/transcripts"
        retiredFunctionalThroughput = "test/golden/cpp-functional/throughput.json"
    present <- doesDirectoryExist root
    if not present
        then assertFailure ("legacy fixture root missing: " <> root)
        else do
            entries <- sort <$> listDirectory root
            archDirs <- filterM (doesDirectoryExist . (root </>)) entries
            assertBool ("legacy fixture arch directories present in " <> root) (not (null archDirs))
            counts <- mapM (validateLegacyFixtureDir root) archDirs
            assertBool
                ("legacy fixtures present below " <> root)
                (sum counts > 0)
    throughputPresent <- doesFileExist retiredThroughput
    assertBool
        ("cpp-legacy retirement throughput anchor missing: " <> retiredThroughput)
        throughputPresent
    throughput <- BS.readFile retiredThroughput
    assertBool
        "cpp-legacy retirement throughput anchor names backend"
        ("\"backend\": \"cpp-legacy\"" `isInfixOf` BSC.unpack throughput)
    imperativeThroughputPresent <- doesFileExist retiredImperativeThroughput
    assertBool
        ("cpp-imperative retirement throughput anchor missing: " <> retiredImperativeThroughput)
        imperativeThroughputPresent
    imperativeThroughput <- BS.readFile retiredImperativeThroughput
    assertBool
        "cpp-imperative retirement throughput anchor names retiring backend"
        ("\"retiring\": \"cpp-imperative\"" `isInfixOf` BSC.unpack imperativeThroughput)
    imperativeRootPresent <- doesDirectoryExist retiredImperativeRoot
    assertBool
        ("cpp-imperative retirement transcript root missing: " <> retiredImperativeRoot)
        imperativeRootPresent
    imperativeEntries <- sort <$> listDirectory retiredImperativeRoot
    imperativeArchDirs <- filterM (doesDirectoryExist . (retiredImperativeRoot </>)) imperativeEntries
    assertBool
        ("cpp-imperative retirement transcript arch directories present in " <> retiredImperativeRoot)
        (not (null imperativeArchDirs))
    imperativeCounts <-
        mapM (validateRetiredBackendDir retiredImperativeRoot CppImperative) imperativeArchDirs
    assertBool
        ("cpp-imperative retirement transcripts present below " <> retiredImperativeRoot)
        (sum imperativeCounts > 0)
    functionalThroughputPresent <- doesFileExist retiredFunctionalThroughput
    assertBool
        ("cpp-functional retirement throughput anchor missing: " <> retiredFunctionalThroughput)
        functionalThroughputPresent
    functionalThroughput <- BS.readFile retiredFunctionalThroughput
    assertBool
        "cpp-functional retirement throughput anchor names retiring backend"
        ("\"retiring\": \"cpp-functional\"" `isInfixOf` BSC.unpack functionalThroughput)
    functionalRootPresent <- doesDirectoryExist retiredFunctionalRoot
    assertBool
        ("cpp-functional retirement transcript root missing: " <> retiredFunctionalRoot)
        functionalRootPresent
    functionalEntries <- sort <$> listDirectory retiredFunctionalRoot
    functionalArchDirs <- filterM (doesDirectoryExist . (retiredFunctionalRoot </>)) functionalEntries
    assertBool
        ("cpp-functional retirement transcript arch directories present in " <> retiredFunctionalRoot)
        (not (null functionalArchDirs))
    functionalCounts <-
        mapM (validateRetiredBackendDir retiredFunctionalRoot CppFunctional) functionalArchDirs
    assertBool
        ("cpp-functional retirement transcripts present below " <> retiredFunctionalRoot)
        (sum functionalCounts > 0)

validateLegacyFixtureDir :: FilePath -> FilePath -> IO Int
validateLegacyFixtureDir root arch = do
    let dir = root </> arch
    files <- sort . filter (".tr" `isSuffixOf`) <$> listDirectory dir
    assertBool ("legacy fixtures present in " <> dir) (not (null files))
    length files @?= 10
    mapM_ (validateLegacyFixture dir) files
    pure (length files)

validateRetiredBackendDir :: FilePath -> Backend -> FilePath -> IO Int
validateRetiredBackendDir root backend arch = do
    let dir = root </> arch
    files <- sort . filter (".tr" `isSuffixOf`) <$> listDirectory dir
    assertBool ("retired backend transcripts present in " <> dir) (not (null files))
    mapM_ (validateRetiredBackendTranscript dir backend) files
    pure (length files)

validateRetiredBackendTranscript :: FilePath -> Backend -> FilePath -> IO ()
validateRetiredBackendTranscript dir backend file = do
    bytes <- BS.readFile (dir </> file)
    let actualHash = sha256Hex bytes
    takeBaseName file @?= actualHash
    case decodeTranscript bytes of
        Left err ->
            assertFailure ("retired backend transcript failed to decode: " <> file <> " " <> show err)
        Right transcript ->
            runBackend (transcriptConfig transcript) @?= backend

validateLegacyFixture :: FilePath -> FilePath -> IO ()
validateLegacyFixture dir file = do
    bytes <- BS.readFile (dir </> file)
    takeBaseName file @?= sha256Hex bytes
    case decodeTranscript bytes of
        Left err ->
            assertFailure ("legacy fixture " <> file <> " failed to decode: " <> show err)
        Right transcript -> do
            let config = transcriptConfig transcript
            runBackend config @?= CppLegacy
            runWorkload config @?= Selfplay
            runThreading config @?= SingleThreaded
            runRngSource config @?= CppRng
            runMasterSeed config @?= 42
            runInitialSims config @?= 10000
            runPerMoveSims config @?= 10000
            runMaxPlies config @?= 10000
            runGames config @?= 1
            assertBool
                ("legacy fixture " <> file <> " must not record Draw winners")
                (all ((/= Draw) . gameWinner) (transcriptGames transcript))
            assertBool
                ("legacy fixture " <> file <> " must contain at least one game")
                (not (null (transcriptGames transcript)))

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
        else do
            let inputs =
                    defaultRunInputs
                        { inputBackend = backend
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputThreading = SingleThreaded
                        , inputGames = 1
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 6
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
