module MCTS.CLI.Build
    ( runBuild
    , buildBackendPlan
    , legacyFixturePlan
    , rustPgoBoltPlan
    , pgoTrainingGames
    , pgoTrainingSims
    , boltTrainingGames
    , boltTrainingSims
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (BuildCommand (..), LegacyFixtureOptions (..))
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForBuild)
import MCTS.Subprocess
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))

-- | Build-scoped PGO training tuple. This is deliberately smaller
-- than the report-card workloads: `mcts build <backend>` must be a
-- bounded install command that emits representative profile data,
-- while Phase 7/8 report-card commands own the full comparison runs.
pgoTrainingGames :: Int
pgoTrainingGames = 1

pgoTrainingSims :: Int
pgoTrainingSims = 100

-- | BOLT instrumentation pass uses a smaller training workload: BOLT
-- profiles are about basic-block edge frequencies, which converge fast.
boltTrainingGames :: Int
boltTrainingGames = 1

boltTrainingSims :: Int
boltTrainingSims = 50

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
        "rust" -> ensure ["rust/pgo-profile", "rust/bolt-profile"]
        _ -> pure ()
  where
    ensure paths = do
        createDirectoryIfMissing True ".build/profiles"
        mapM_ (createDirectoryIfMissing True) paths

buildBackendPlan :: String -> Plan Subprocess
buildBackendPlan backend =
    Plan
        { planName = "build " <> backend
        , planSteps =
            case backend of
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
--   2. Training run (self-play under `--rng native`) writes
--      `<backend>/pgo-profile/*.gcda`.
--   3. PGO-optimized rebuild of both artefacts with `-fprofile-use`.
--   4. BOLT instrument pass for both artefacts (writes
--      `<backend>/bolt-profile/*.fdata`).
--   5. BOLT training run produces the BOLT profile data.
--   6. BOLT optimize pass produces `*_bench.bolted.so` and
--      `*_instrumented.bolted.so`.
--   7. Install: rename `_bench.bolted.so` to the canonical FFI load
--      name `libmcts_cpp_functional.so`; symlink-equivalent for the
--      `_instrumented` artefact.
--
-- The whole pipeline rides the typed `Subprocess` boundary; no
-- ad-hoc `callProcess` or `System.Process` smart constructors live in
-- this module. The training runs invoke `cabal exec mcts` so the
-- exact same binary that ships the rest of the CLI drives the training
-- workload — there is no separate training executable.
-- | Sprint 6.4 PGO+BOLT pipeline for backend (iv) Rust. The first
-- four steps drive `cargo build --release` with rustc's PGO flags
-- through `RUSTFLAGS`; the BOLT pass runs `llvm-bolt -instrument`
-- against the cdylib output so `perf` is not required in the
-- container (matching the C++ pipelines). The install step renames
-- the bolted artefact to the canonical `rust/target/release/libmcts_rust.so`
-- so the Haskell FFI continues to load it from the pinned path.
rustPgoBoltPlan :: [Subprocess]
rustPgoBoltPlan =
    [ -- 1. Instrumented build: rustc -Cprofile-generate. The profile
      -- directory is absolute inside the pinned Compose workspace so
      -- the loaded cdylib writes `.profraw` beside the Rust backend
      -- even though the training `mcts` process runs from the repo root.
      cargoBuild "pgo-profile" "generate"
    , -- 2. Training run: same shape as C++ backends
      trainingRunFor "rust" pgoTrainingGames pgoTrainingSims
    , -- 3. Merge LLVM profraw -> profdata (the rustc PGO flow requires
      -- profdata, not profraw)
      Subprocess
        "bash"
        [ "-c"
        , "if ! ls rust/pgo-profile/*.profraw >/dev/null 2>&1; then "
            <> "echo \"[pgo] no Rust profraw files under rust/pgo-profile\" >&2; exit 1; "
            <> "elif command -v llvm-profdata-19 >/dev/null 2>&1; then "
            <> "llvm-profdata-19 merge -o rust/pgo-profile/merged.profdata rust/pgo-profile/*.profraw; "
            <> "elif command -v llvm-profdata >/dev/null 2>&1; then "
            <> "llvm-profdata merge -o rust/pgo-profile/merged.profdata rust/pgo-profile/*.profraw; "
            <> "else echo \"[pgo] llvm-profdata not found\" >&2; exit 1; fi"
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
            <> "--instrumentation-file-append-pid 2>/dev/null || true"
        ]
        Nothing
        Nothing
    , Subprocess
        "bash"
        [ "-c"
        , "if [ -f rust/target/release/libmcts_rust.inst.so ]; then "
            <> "cp rust/target/release/libmcts_rust.inst.so rust/target/release/libmcts_rust.so; "
            <> "else cp rust/target/release/libmcts_rust.pgo.so rust/target/release/libmcts_rust.so; fi"
        ]
        Nothing
        Nothing
    , -- 6. BOLT training run
      trainingRunFor "rust" boltTrainingGames boltTrainingSims
    , Subprocess
        "cp"
        ["rust/target/release/libmcts_rust.pgo.so", "rust/target/release/libmcts_rust.so"]
        Nothing
        Nothing
    , -- 7. BOLT optimize (reorder blocks via ext-tsp)
      Subprocess
        "bash"
        [ "-c"
        , "fdata=$(ls -t rust/bolt-profile/rust.fdata* 2>/dev/null | head -1); "
            <> "if [ -n \"$fdata\" ]; then "
            <> "llvm-bolt rust/target/release/libmcts_rust.so "
            <> "-o rust/target/release/libmcts_rust.bolted.so "
            <> "-data $fdata -reorder-blocks=ext-tsp 2>/dev/null || "
            <> "cp rust/target/release/libmcts_rust.so rust/target/release/libmcts_rust.bolted.so; "
            <> "else cp rust/target/release/libmcts_rust.so rust/target/release/libmcts_rust.bolted.so; fi"
        ]
        Nothing
        Nothing
    , -- 8. Install: rename bolted -> canonical FFI load name
      Subprocess
        "bash"
        [ "-c"
        , "cp rust/target/release/libmcts_rust.bolted.so rust/target/release/libmcts_rust.so"
        ]
        Nothing
        Nothing
    , -- 9. Post-link engine_build_id patch: hash the installed cdylib
      -- and overwrite the `.envelope_build_id` section with the
      -- 32-byte digest so `mcts_rust_get_envelope()` reports a
      -- non-zero engine_build_id. Mirrors the C++ backend
      -- `envelope-build-id` Makefile target. Uses `python3` to
      -- decode the hex digest because `xxd` is not in the pinned
      -- container's base image.
      Subprocess
        "bash"
        [ "-c"
        , "lib=rust/target/release/libmcts_rust.so; "
            <> "if command -v objcopy >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then "
            <> "tmpbin=$(mktemp); "
            <> "digest=$(sha256sum \"$lib\" | awk '{print $1}'); "
            <> "python3 -c \"import sys, binascii; sys.stdout.buffer.write(binascii.unhexlify(sys.argv[1]))\" \"$digest\" > \"$tmpbin\"; "
            <> "objcopy --update-section .envelope_build_id=\"$tmpbin\" \"$lib\" 2>/dev/null || true; "
            <> "rm -f \"$tmpbin\"; "
            <> "fi"
        ]
        Nothing
        Nothing
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
            , "-C "
                <> (if mode == "generate" then "profile-generate=" else "profile-use=")
                <> absoluteRustProfilePath profileDir
            ]

    absoluteRustProfilePath profileDir =
        "/workspace/MCTS/rust/" <> profileDir

trainingRunFor :: String -> Int -> Int -> Subprocess
trainingRunFor backend games sims =
    Subprocess
        "cabal"
        [ "exec"
        , "mcts"
        , "--"
        , "bench"
        , "selfplay"
        , "--backend"
        , backend
        , "--threading"
        , "single"
        , "--rng"
        , "native"
        , "--games"
        , show games
        , "--seed"
        , "42"
        , "--sims"
        , show sims
        ]
        Nothing
        Nothing

-- | Run a backend build plan through the doctrine `apply :: Env -> Plan
-- a -> IO ExitCode` shape. `Env.defaultEnv` is the production-default
-- environment; future runners can pass a custom env via `Env.runAppIO`.
runBackendPlan :: Plan Subprocess -> Env.App ExitCode
runBackendPlan = applySubprocessWithEnv
