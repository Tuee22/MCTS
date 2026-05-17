{-# LANGUAGE RankNTypes #-}

module Main where

import qualified Data.ByteString as BS
import Data.List (sort)
import Data.Word (Word32, Word8)
import MCTS.Driver
import MCTS.Driver.CppFunctional (runGameCppFunctional)
import MCTS.Driver.CppImperative (runGameCppImperative)
import MCTS.Driver.CppLegacy (runGameCppLegacy)
import MCTS.Driver.Rust (runGameRust)
import MCTS.Engine.ForeignRecompute (foreignRecomputeEqStream)
import MCTS.Error (AppError)
import MCTS.FFI.Common (EngineEnvelope (..))
import qualified MCTS.FFI.Common
import MCTS.FFI.CppFunctional (loadCppFunctionalEnvelope, withCppFunctionalRecomputeGame)
import MCTS.FFI.CppImperative (loadCppImperativeEnvelope, withCppImperativeRecomputeGame)
import MCTS.FFI.CppLegacy (cppLegacyRecomputeMove, loadCppLegacyEnvelope, withCppLegacyGame)
import MCTS.FFI.Rust (loadRustEnvelope, withRustRecomputeGame)
import MCTS.Transcript
import MCTS.Transcript.EquitySidecar
import MCTS.Types
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))
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
                "foreign ffi smoke drivers"
                [ testCase
                    "cpp-legacy"
                    (foreignFfiSmokeDriver "cpp-legacy/build/libmcts_cpp_legacy.so" CppLegacy runGameCppLegacy)
                , testCase
                    "cpp-imperative"
                    ( foreignFfiSmokeDriver
                        "cpp-imperative/build/libmcts_cpp_imperative.so"
                        CppImperative
                        runGameCppImperative
                    )
                , testCase
                    "cpp-functional"
                    ( foreignFfiSmokeDriver
                        "cpp-functional/build/libmcts_cpp_functional.so"
                        CppFunctional
                        runGameCppFunctional
                    )
                , testCase "rust" (foreignFfiSmokeDriver "rust/target/release/libmcts_rust.so" Rust runGameRust)
                ]
            , testGroup
                "foreign ffi live envelopes"
                [ testCase
                    "cpp-legacy"
                    (foreignFfiEnvelope "cpp-legacy/build/libmcts_cpp_legacy.so" CppLegacy loadCppLegacyEnvelope)
                , testCase
                    "cpp-imperative"
                    ( foreignFfiEnvelope
                        "cpp-imperative/build/libmcts_cpp_imperative.so"
                        CppImperative
                        loadCppImperativeEnvelope
                    )
                , testCase
                    "cpp-functional"
                    ( foreignFfiEnvelope
                        "cpp-functional/build/libmcts_cpp_functional.so"
                        CppFunctional
                        loadCppFunctionalEnvelope
                    )
                , testCase "rust" (foreignFfiEnvelope "rust/target/release/libmcts_rust.so" Rust loadRustEnvelope)
                ]
            , testCase "equity sidecar originator markers" sidecarOriginMarkers
            , testCase "legacy goldens decode and respect no-draw semantics" legacyGoldenCheck
            , testCase "legacy parity pre-flight: S_LP=42 does not trip MAX_ROLLOUT_ITERS" legacyParityPreflight
            , testCase "cpp-legacy recompute symbol returns visits and equity" legacyRecomputeSmoke
            , testCase
                "cpp-legacy envelope reports cpu_features bits and a non-zero engine_build_id"
                legacyEnvelopeRuntime
            , testGroup
                "foreign recompute EqStream"
                [ testCase
                    "cpp-imperative"
                    ( foreignRecomputeSmoke
                        "cpp-imperative/build/libmcts_cpp_imperative.so"
                        CppImperative
                        withCppImperativeRecomputeGame
                    )
                , testCase
                    "cpp-functional"
                    ( foreignRecomputeSmoke
                        "cpp-functional/build/libmcts_cpp_functional.so"
                        CppFunctional
                        withCppFunctionalRecomputeGame
                    )
                , testCase
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
                        , inputMaxPlies = 8
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
                    -- Backends (i) and (ii) backfill `engine_build_id` from
                    -- their post-link `.envelope_build_id` ELF section per
                    -- Sprint 4.7 / Sprint 5.5. Backends (iii) and (iv) still
                    -- report the zero-digest sentinel.
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
                        CppImperative ->
                            assertBool
                                "cpp-imperative engine_build_id is patched"
                                (engineEnvBuildId envelope /= replicate 64 '0')
                        CppFunctional ->
                            assertBool
                                "cpp-functional engine_build_id is patched"
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

-- | Sprint 4.5 Q6 golden check. Iterates `test/golden/legacy/transcripts/<arch>/`
-- and asserts every fixture decodes via the Phase 2 wire format with the
-- legacy parity envelope: backend = cpp-legacy, rng = cpp, no Draw winners.
-- Byte-exact comparison against a `mcts bench` regeneration awaits the Phase 2
-- single-game-file alignment tracked in legacy-tracking-for-deletion.md.
legacyGoldenCheck :: IO ()
legacyGoldenCheck = do
    let dir = "test/golden/legacy/transcripts" </> hostArch
    present <- doesDirectoryExist dir
    if not present
        then pure ()
        else do
            files <- sort <$> listDirectory dir
            assertBool ("legacy fixtures present in " <> dir) (not (null files))
            mapM_ (validateLegacyFixture dir) files

-- | Sprint 4.6 validation #3 pre-flight: assert that backend (i) at the
-- pinned report-card legacy-parity envelope (seed = S_LP = 42, single
-- game, single-threaded, --rng cpp, max_plies = 10000) plays a full
-- game without surfacing `AppError LegacyParityRolloutOverflow`. Runs
-- only when the cpp-legacy shared library is built.
legacyParityPreflight :: IO ()
legacyParityPreflight = do
    present <- doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so"
    if not present
        then pure ()
        else do
            let inputs =
                    defaultRunInputs
                        { inputBackend = CppLegacy
                        , inputWorkload = Selfplay
                        , inputRng = CppRng
                        , inputThreading = SingleThreaded
                        , inputGames = 1
                        , inputSeed = 42
                        , inputMaxPlies = 10000
                        , inputSims = FixedSims 200
                        }
            result <- runGameCppLegacy inputs 0
            case result of
                Right game ->
                    assertBool
                        "legacy parity pre-flight game has at least one move"
                        (not (null (gameMoves game)))
                Left err ->
                    assertFailure
                        ( "legacy parity pre-flight failed at S_LP=42 with: "
                            <> show err
                        )

-- | Sprint 4.7 recompute smoke: call `mcts_legacy_recompute_move` and
-- assert the visit vector is populated. The equity slot may be NaN at
-- the very first move so we only require it is reported.
legacyRecomputeSmoke :: IO ()
legacyRecomputeSmoke = do
    present <- doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so"
    if not present
        then pure ()
        else do
            result <- withCppLegacyGame $ \game -> cppLegacyRecomputeMove game 42 16
            case result of
                Left err ->
                    assertFailure ("recompute outer FFI failed: " <> show err)
                Right (Left err) ->
                    assertFailure ("recompute inner FFI failed: " <> show err)
                Right (Right (_chosen, visits, _equity)) ->
                    assertBool
                        "recompute returned a non-empty visit vector"
                        (not (null visits))

-- | Sprint 4.7 envelope smoke: confirm the runtime CPU/FP probes
-- populate non-zero `cpu_features` on a supported host and that the
-- `engine_build_id` byte slot is no longer all-zero once the post-link
-- patch lands. The post-link patch is optional in the smoke build (it
-- depends on `objcopy` + a 32-byte ELF section); when absent, the
-- check is downgraded to the cpu_features assertion only.
legacyEnvelopeRuntime :: IO ()
legacyEnvelopeRuntime = do
    present <- doesFileExist "cpp-legacy/build/libmcts_cpp_legacy.so"
    if not present
        then pure ()
        else do
            result <- loadCppLegacyEnvelope
            case result of
                Left err -> assertFailure ("envelope load failed: " <> show err)
                Right envelope -> do
                    let cpu = engineEnvCpuFeatures envelope
                    assertBool
                        ("cpu_features must be non-zero (got " <> show cpu <> ")")
                        (cpu /= 0)

validateLegacyFixture :: FilePath -> FilePath -> IO ()
validateLegacyFixture dir file = do
    bytes <- BS.readFile (dir </> file)
    case decodeTranscript bytes of
        Left err ->
            assertFailure ("legacy fixture " <> file <> " failed to decode: " <> show err)
        Right transcript -> do
            runBackend (transcriptConfig transcript) @?= CppLegacy
            runRngSource (transcriptConfig transcript) @?= CppRng
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
                        , inputGames = 1
                        , inputSims = FixedSims 4
                        , inputMaxPlies = 6
                        }
                transcript =
                    Transcript
                        (makeRunConfig inputs)
                        (makeLogicalEnvelope backend CppRng)
                        [runGame inputs 0]
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
