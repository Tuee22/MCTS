module MCTS.CLI.Build
    ( runBuild
    , buildBackendPlan
    , legacyFixturePlan
    , cppPgoBoltPlan
    , rustPgoBoltPlan
    , TrainingRun (..)
    , pgoTrainingRuns
    , boltTrainingRuns
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Word (Word64)
import MCTS.CLI.Command (BuildCommand (..), LegacyFixtureOptions (..))
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForBuild)
import MCTS.Subprocess
import MCTS.Types (Threading (..), Workload (..), threadingWorkers, workloadName)
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))

data TrainingRun = TrainingRun
    { trainingWorkload :: !Workload
    , trainingThreading :: !Threading
    , trainingGames :: !Int
    , trainingSeed :: !Word64
    , trainingSims :: !Int
    }
    deriving (Eq, Show)

trainingMaxPlies :: Int
trainingMaxPlies = 1

trainingMultiWorkers :: Int
trainingMultiWorkers = 8

pgoTrainingSeeds :: [Word64]
pgoTrainingSeeds = [42, 424242]

boltTrainingSeeds :: [Word64]
boltTrainingSeeds = [42, 424242]

-- | Dockerfile-time PGO training mirrors the Q1/Q2 report-card shape:
-- random rollouts and self-play, ST and MT8, backend-native RNG, and
-- multiple deterministic seeds. The training subprocess environment
-- forces foreign dispatch for this bounded one-move ply cap so profile
-- training cannot silently fall back to the in-process Haskell engine.
-- Self-play uses S_BENCH's 500-sim per-move budget to profile the hot
-- search path while keeping the image build usable.
pgoTrainingRuns :: [TrainingRun]
pgoTrainingRuns =
    trainingRuns
        pgoTrainingSeeds
        2
        2
        1
        1
        500

-- | BOLT training keeps the same workload/threading/seed shape with a
-- shorter self-play budget. BOLT needs block-edge coverage, not the
-- full report-card duration.
boltTrainingRuns :: [TrainingRun]
boltTrainingRuns =
    trainingRuns
        boltTrainingSeeds
        1
        1
        1
        1
        100

trainingRuns :: [Word64] -> Int -> Int -> Int -> Int -> Int -> [TrainingRun]
trainingRuns seeds rolloutSingleGames rolloutMultiGames selfplaySingleGames selfplayMultiGames selfplaySims =
    concatMap runsForSeed seeds
  where
    runsForSeed seed =
        [ TrainingRun Rollouts SingleThreaded rolloutSingleGames seed 1
        , TrainingRun Rollouts (MultiThreaded trainingMultiWorkers) rolloutMultiGames seed 1
        , TrainingRun Selfplay SingleThreaded selfplaySingleGames seed selfplaySims
        , TrainingRun Selfplay (MultiThreaded trainingMultiWorkers) selfplayMultiGames seed selfplaySims
        ]

runBuild :: BuildCommand -> Env.App ExitCode
runBuild command = do
    env <- Env.askEnv
    case command of
        BuildLegacyFixtures fixtureOptions ->
            runBuildPlan
                env
                "legacy-fixtures"
                (legacyFixturePlanOptions fixtureOptions)
                (legacyFixturePlan fixtureOptions)
        BuildCppLegacy planOptions -> runBackendBuild env "cpp-legacy" planOptions
        BuildCppImperative planOptions -> runBackendBuild env "cpp-imperative" planOptions
        BuildCppFunctional planOptions -> runBackendBuild env "cpp-functional" planOptions
        BuildRust planOptions -> runBackendBuild env "rust" planOptions

runBackendBuild :: Env.Env -> String -> PlanOptions -> Env.App ExitCode
runBackendBuild env name opts =
    runBuildPlan env name opts (buildBackendPlan name)

runBuildPlan :: Env.Env -> String -> PlanOptions -> Plan Subprocess -> Env.App ExitCode
runBuildPlan env name opts plan = do
    let rendered = renderPlan plan
    liftIO (writePlanFile (planFile opts) rendered)
    if planDryRun opts
        then liftIO (outputLine rendered) >> pure ExitSuccess
        else do
            liftIO (ensureProfileDirectories name)
            prerequisites <- liftIO (checkPrerequisites (prerequisitesForBuild name))
            case prerequisites of
                Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)
                Right () -> runBackendPlan plan

ensureProfileDirectories :: String -> IO ()
ensureProfileDirectories backend =
    case backend of
        "cpp-imperative" -> ensure ["cpp-imperative/pgo-profile", "cpp-imperative/bolt-profile"]
        "cpp-functional" -> ensure ["cpp-functional/pgo-profile", "cpp-functional/bolt-profile"]
        "rust" -> ensure ["rust/pgo-profile", "rust/bolt-profile"]
        _ -> pure ()
  where
    ensure paths = do
        mapM_ (createDirectoryIfMissing True) paths

buildBackendPlan :: String -> Plan Subprocess
buildBackendPlan backend =
    Plan
        { planName = "build " <> backend
        , planSteps =
            case backend of
                "cpp-imperative" -> cppPgoBoltPlan "cpp-imperative"
                "cpp-functional" -> cppPgoBoltPlan "cpp-functional"
                "rust" -> rustPgoBoltPlan
                _ ->
                    [ Subprocess "make" ["-C", backend, "smoke"] Nothing Nothing
                    ]
        }

legacyFixturePlan :: LegacyFixtureOptions -> Plan Subprocess
legacyFixturePlan options =
    Plan
        { planName = "build legacy-fixtures"
        , planSteps =
            [ Subprocess "make" ["-C", "cpp-legacy", "legacy-to-wire"] Nothing Nothing
            , Subprocess
                "cpp-legacy/build/legacy-to-wire"
                [ "--output-dir"
                , legacyFixtureOutputDir options
                , "--seed"
                , show (legacyFixtureSeed options)
                , "--games"
                , show (legacyFixtureGames options)
                , "--sims"
                , show (legacyFixtureSims options)
                , "--max-plies"
                , "10000"
                ]
                Nothing
                Nothing
            ]
        }

-- | Shared C++ PGO+BOLT pipeline as a typed `[Subprocess]` sequence
-- per the backend (ii)/(iii) steelman build sprints:
--
--   1. PGO-instrumented bench + instrumented artefacts.
--   2. Blended PGO training suite under `--rng native` writes
--      `<backend>/pgo-profile/*.gcda`.
--   3. PGO-optimized rebuild of both artefacts with `-fprofile-use`.
--   4. BOLT instrument pass for both artefacts (writes
--      `<backend>/bolt-profile/*.fdata`).
--   5. Short blended BOLT training suite produces the BOLT profile data.
--   6. BOLT optimize pass produces `*_bench.bolted.so` and
--      `*_instrumented.bolted.so`.
--   7. Install: rename `_bench.bolted.so` to the canonical FFI load
--      name `libmcts_cpp_functional.so`; symlink-equivalent for the
--      `_instrumented` artefact.
--   8. Smoke the installed canonical artefact so a crashing BOLT output
--      fails the Dockerfile build instead of reaching runtime.
--
-- The whole pipeline rides the typed `Subprocess` boundary; no
-- ad-hoc `callProcess` or `System.Process` smart constructors live in
-- this module. The training runs invoke `cabal exec mcts` so the
-- exact same binary that ships the rest of the CLI drives the training
-- workload — there is no separate training executable.
cppPgoBoltPlan :: String -> [Subprocess]
cppPgoBoltPlan backend =
    [ resetCppProfileDirectories
    , makeTarget "pgo-bench-generate"
    , installCppTrainingArtifact "_bench.so"
    ]
        <> trainingRunsFor backend pgoTrainingRuns
        <> [ makeTarget "pgo-instr-generate"
           , installCppTrainingArtifact "_instrumented.so"
           ]
        <> trainingRunsFor backend pgoTrainingRuns
        <> [ requireCppGcdaProfiles
           , makeTarget "pgo-bench-use"
           , makeTarget "pgo-instr-use"
           , makeTarget "bolt-bench-instrument"
           , installCppBoltTrainingArtifact "_bench.inst.so"
           ]
        <> trainingRunsFor backend boltTrainingRuns
        <> [ makeTarget "bolt-instr-instrument"
           , installCppBoltTrainingArtifact "_instrumented.inst.so"
           ]
        <> trainingRunsFor backend boltTrainingRuns
        <> [ makeTarget "bolt-bench-optimize"
           , makeTarget "bolt-instr-optimize"
           , makeTarget "install-bench"
           , smokeRunFor backend
           ]
  where
    libraryBase = cppLibraryBase backend
    canonicalLibrary = cppBuildPath (libraryBase <> ".so")

    makeTarget target =
        Subprocess "make" ["-C", backend, target] Nothing Nothing

    resetCppProfileDirectories =
        Subprocess
            "bash"
            [ "-c"
            , "rm -rf "
                <> backend
                <> "/pgo-profile "
                <> backend
                <> "/bolt-profile && mkdir -p "
                <> backend
                <> "/pgo-profile "
                <> backend
                <> "/bolt-profile"
            ]
            Nothing
            Nothing

    installCppTrainingArtifact suffix =
        Subprocess
            "cp"
            [cppBuildPath (libraryBase <> suffix), canonicalLibrary]
            Nothing
            Nothing

    installCppBoltTrainingArtifact instSuffix =
        Subprocess
            "bash"
            [ "-c"
            , "if [ ! -s "
                <> cppBuildPath (libraryBase <> instSuffix)
                <> " ]; then echo \"[bolt] missing instrumented C++ artefact: "
                <> cppBuildPath (libraryBase <> instSuffix)
                <> "\" >&2; exit 1; fi; cp "
                <> cppBuildPath (libraryBase <> instSuffix)
                <> " "
                <> canonicalLibrary
            ]
            Nothing
            Nothing

    requireCppGcdaProfiles =
        Subprocess
            "bash"
            [ "-c"
            , "if ! find "
                <> backend
                <> "/pgo-profile -type f -name '*.gcda' -size +0c -print -quit | grep -q .; then "
                <> "find "
                <> backend
                <> " -type f \\( -name '*.gcda' -o -name '*.gcno' -o -name '*gcov*' \\) -print | sort | head -100 >&2; "
                <> "echo \"[pgo] no non-empty C++ .gcda files under "
                <> backend
                <> "/pgo-profile\" >&2; exit 1; fi"
            ]
            Nothing
            Nothing

    cppBuildPath file =
        backend <> "/build/" <> file

cppLibraryBase :: String -> String
cppLibraryBase backend =
    case backend of
        "cpp-functional" -> "libmcts_cpp_functional"
        _ -> "libmcts_cpp_imperative"

-- | Sprint 6.4 PGO+BOLT pipeline for backend (iv) Rust. The first
-- four steps drive `cargo build --release` with rustc's PGO flags
-- through `RUSTFLAGS`; the BOLT pass runs `llvm-bolt -instrument`
-- against the cdylib output so `perf` is not required in the
-- container (matching the C++ pipelines). The install step renames
-- the bolted artefact to the canonical `rust/target/release/libmcts_rust.so`
-- so the Haskell FFI continues to load it from the pinned path.
rustPgoBoltPlan :: [Subprocess]
rustPgoBoltPlan =
    [ Subprocess
        "bash"
        [ "-c"
        , "rm -rf rust/pgo-profile rust/bolt-profile && mkdir -p rust/pgo-profile rust/bolt-profile"
        ]
        Nothing
        Nothing
    , -- 1. Instrumented build: rustc -Cprofile-generate. The profile
      -- directory is absolute inside the pinned Compose workspace so
      -- the loaded cdylib writes `.profraw` beside the Rust backend
      -- even though the training `mcts` process runs from the repo root.
      cargoBuild "pgo-profile" "generate"
    ]
        <> trainingRunsFor "rust" pgoTrainingRuns
        <> [ -- 3. Merge LLVM profraw -> profdata (the rustc PGO flow requires
             -- profdata, not profraw)
             Subprocess
                "bash"
                [ "-c"
                , "profraw_files=$(find rust/pgo-profile -type f -name '*.profraw' -size +0c -print | sort); "
                    <> "if [ -z \"$profraw_files\" ]; then "
                    <> "echo \"[pgo] no non-empty Rust profraw files under rust/pgo-profile\" >&2; exit 1; "
                    <> "elif command -v llvm-profdata-19 >/dev/null 2>&1; then "
                    <> "profdata_tool=llvm-profdata-19; "
                    <> "elif command -v llvm-profdata >/dev/null 2>&1; then "
                    <> "profdata_tool=llvm-profdata; "
                    <> "else echo \"[pgo] llvm-profdata not found\" >&2; exit 1; fi; "
                    <> "$profdata_tool merge -o rust/pgo-profile/merged.profdata $profraw_files; "
                    <> "test -s rust/pgo-profile/merged.profdata"
                ]
                Nothing
                Nothing
           , -- 4. Optimized rebuild: rustc -Cprofile-use against the
             -- absolute merged profile path produced above.
             cargoBuild "pgo-profile/merged.profdata" "use"
           , Subprocess
                "cp"
                ["rust/target/release/libmcts_rust.so", "rust/target/release/libmcts_rust.pgo.so"]
                Nothing
                Nothing
           , -- 5. BOLT instrument (writes profile via -instrument)
             Subprocess
                "bash"
                [ "-c"
                , "mkdir -p rust/bolt-profile && "
                    <> "llvm-bolt rust/target/release/libmcts_rust.so -instrument "
                    <> "-o rust/target/release/libmcts_rust.inst.so "
                    <> "--instrumentation-file=$(pwd)/rust/bolt-profile/rust.fdata "
                    <> "--instrumentation-file-append-pid && "
                    <> "test -s rust/target/release/libmcts_rust.inst.so"
                ]
                Nothing
                Nothing
           , Subprocess
                "bash"
                [ "-c"
                , "if [ ! -s rust/target/release/libmcts_rust.inst.so ]; then "
                    <> "echo \"[bolt] missing instrumented Rust artefact: rust/target/release/libmcts_rust.inst.so\" >&2; "
                    <> "exit 1; fi; "
                    <> "cp rust/target/release/libmcts_rust.inst.so rust/target/release/libmcts_rust.so"
                ]
                Nothing
                Nothing
           ]
        <> trainingRunsFor "rust" boltTrainingRuns
        <> [ Subprocess
                "bash"
                [ "-c"
                , "if [ ! -s rust/target/release/libmcts_rust.pgo.so ]; then "
                    <> "echo \"[pgo] missing optimized Rust artefact: rust/target/release/libmcts_rust.pgo.so\" >&2; "
                    <> "exit 1; fi; "
                    <> "cp rust/target/release/libmcts_rust.pgo.so rust/target/release/libmcts_rust.so"
                ]
                Nothing
                Nothing
           , -- 7. BOLT optimize (reorder blocks via ext-tsp)
             Subprocess
                "bash"
                [ "-c"
                , "fdata=\"\"; "
                    <> "for candidate in $(ls -t rust/bolt-profile/rust.fdata* 2>/dev/null); do "
                    <> "if [ -s \"$candidate\" ]; then fdata=\"$candidate\"; break; fi; "
                    <> "done; "
                    <> "if [ -z \"$fdata\" ]; then "
                    <> "echo \"[bolt] no usable Rust .fdata under rust/bolt-profile\" >&2; exit 1; fi; "
                    <> "llvm-bolt rust/target/release/libmcts_rust.so "
                    <> "-o rust/target/release/libmcts_rust.bolted.so "
                    <> "-data \"$fdata\" -reorder-blocks=ext-tsp && "
                    <> "test -s rust/target/release/libmcts_rust.bolted.so"
                ]
                Nothing
                Nothing
           , -- 8. Install: rename bolted -> canonical FFI load name
             Subprocess
                "bash"
                [ "-c"
                , "if [ ! -s rust/target/release/libmcts_rust.bolted.so ]; then "
                    <> "echo \"[bolt] missing optimized Rust artefact: rust/target/release/libmcts_rust.bolted.so\" >&2; "
                    <> "exit 1; fi; "
                    <> "cp rust/target/release/libmcts_rust.bolted.so rust/target/release/libmcts_rust.so"
                ]
                Nothing
                Nothing
           , -- 9. Post-link engine_build_id patch: hash the installed cdylib
             -- and overwrite the `.envelope_build_id` section with the
             -- 32-byte digest so `mcts_rust_get_envelope()` reports a
             -- non-zero engine_build_id. Mirrors the C++ backend
             -- `envelope-build-id` Makefile target. Prefer LLVM objcopy
             -- because GNU objcopy can rewrite BOLT-produced shared objects
             -- into crashing artefacts. Uses `python3` to decode the hex
             -- digest because `xxd` is not in the pinned container's base
             -- image.
             Subprocess
                "bash"
                [ "-c"
                , "lib=rust/target/release/libmcts_rust.so; "
                    <> "objcopy_tool=$(command -v llvm-objcopy-19 || command -v llvm-objcopy || command -v objcopy || true); "
                    <> "if [ -n \"$objcopy_tool\" ] && command -v python3 >/dev/null 2>&1; then "
                    <> "tmpbin=$(mktemp); "
                    <> "digest=$(sha256sum \"$lib\" | awk '{print $1}'); "
                    <> "python3 -c \"import sys, binascii; sys.stdout.buffer.write(binascii.unhexlify(sys.argv[1]))\" \"$digest\" > \"$tmpbin\"; "
                    <> "\"$objcopy_tool\" --update-section .envelope_build_id=\"$tmpbin\" \"$lib\"; "
                    <> "rm -f \"$tmpbin\"; "
                    <> "fi"
                ]
                Nothing
                Nothing
           , -- 10. Smoke the installed canonical artefact so a crashing
             -- BOLT output fails during the Docker image build.
             smokeRunFor "rust"
           ]
  where
    cargoBuild profileDir mode =
        Subprocess
            "cargo"
            ["build", "--release"]
            ( Just
                [
                    ( "RUSTFLAGS"
                    , rustPgoFlags mode profileDir
                    )
                ]
            )
            (Just "rust")

    rustPgoFlags mode profileDir =
        unwords
            [ "-C target-cpu=native"
            , "-C link-arg=-fuse-ld=lld"
            , "-C link-arg=-Wl,--emit-relocs"
            , "-C "
                <> (if mode == "generate" then "profile-generate=" else "profile-use=")
                <> absoluteRustProfilePath profileDir
            ]

    absoluteRustProfilePath profileDir =
        "/workspace/MCTS/rust/" <> profileDir

trainingRunsFor :: String -> [TrainingRun] -> [Subprocess]
trainingRunsFor backend = map (trainingRunFor backend)

trainingRunFor :: String -> TrainingRun -> Subprocess
trainingRunFor backend run =
    Subprocess
        "cabal"
        ( [ "exec"
          , "mcts"
          , "--"
          , "bench"
          , workloadName (trainingWorkload run)
          , "--backend"
          , backend
          ]
            <> threadingArgs (trainingThreading run)
            <> [ "--rng"
               , "native"
               , "--games"
               , show (trainingGames run)
               , "--seed"
               , show (trainingSeed run)
               , "--max-plies"
               , show trainingMaxPlies
               , "--sims"
               , show (trainingSims run)
               , "--cache-dir"
               , trainingCacheDir backend run
               ]
        )
        (Just (profileTrainingEnv backend))
        Nothing
  where
    threadingArgs threading =
        case threading of
            SingleThreaded -> ["--threading", "single"]
            MultiThreaded workers -> ["--threading", "multi", "--workers", show (threadingWorkers (MultiThreaded workers))]

profileTrainingEnv :: String -> [(String, String)]
profileTrainingEnv backend =
    [ ("MCTS_FORCE_FOREIGN_SEARCH", "1")
    ]
        <> [ ("MCTS_SCOPED_DYNAMIC_LIBRARY", "1")
           | backend /= "rust"
           ]

trainingCacheDir :: String -> TrainingRun -> FilePath
trainingCacheDir backend run =
    "/tmp/mcts-profile-training/"
        <> backend
        <> "/"
        <> workloadName (trainingWorkload run)
        <> "-"
        <> threadingCacheLabel (trainingThreading run)
        <> "-"
        <> show (trainingSeed run)
        <> "-"
        <> show (trainingSims run)

threadingCacheLabel :: Threading -> String
threadingCacheLabel threading =
    case threading of
        SingleThreaded -> "single"
        MultiThreaded workers -> "multi" <> show (threadingWorkers (MultiThreaded workers))

smokeRunFor :: String -> Subprocess
smokeRunFor backend =
    trainingRunFor
        backend
        TrainingRun
            { trainingWorkload = Selfplay
            , trainingThreading = SingleThreaded
            , trainingGames = 1
            , trainingSeed = 42
            , trainingSims = 4
            }

-- | Run a backend build plan through the doctrine `apply :: Env -> Plan
-- a -> IO ExitCode` shape. `Env.defaultEnv` is the production-default
-- environment; future runners can pass a custom env via `Env.runAppIO`.
runBackendPlan :: Plan Subprocess -> Env.App ExitCode
runBackendPlan = applySubprocessWithEnv
