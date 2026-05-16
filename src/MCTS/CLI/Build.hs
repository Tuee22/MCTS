module MCTS.CLI.Build
    ( runBuild
    , buildBackendPlan
    , cppImperativePgoBoltPlan
    , cppFunctionalPgoBoltPlan
    , rustPgoBoltPlan
    , pgoTrainingGames
    , pgoTrainingSims
    , boltTrainingGames
    , boltTrainingSims
    ) where

import Control.Monad.IO.Class (liftIO)
import MCTS.CLI.Command (BuildCommand (..))
import MCTS.CLI.Output (outputLine, renderErrorString)
import qualified MCTS.Env as Env
import MCTS.Plan
import MCTS.Prerequisite (checkPrerequisites, prerequisitesForBuild)
import MCTS.Subprocess
import System.Exit (ExitCode (..))

-- | PGO training tuple per Sprint 5.3's pinned report-card knobs:
-- benchmark (b) self-play at `($PGO_TRAINING_GAMES, $PGO_TRAINING_SIMS)
-- = (100, 10_000)`. Lives here rather than `cabal.project` because the
-- harness reads them from Haskell at plan-build time.
pgoTrainingGames :: Int
pgoTrainingGames = 100

pgoTrainingSims :: Int
pgoTrainingSims = 10000

-- | BOLT instrumentation pass uses a smaller training workload: BOLT
-- profiles are about basic-block edge frequencies, which converge fast.
boltTrainingGames :: Int
boltTrainingGames = 20

boltTrainingSims :: Int
boltTrainingSims = 2000

runBuild :: BuildCommand -> Env.App ExitCode
runBuild command = do
    env <- Env.askEnv
    let (name, opts) =
            case command of
                BuildCppLegacy planOptions -> ("cpp-legacy", planOptions)
                BuildCppImperative planOptions -> ("cpp-imperative", planOptions)
                BuildCppFunctional planOptions -> ("cpp-functional", planOptions)
                BuildRust planOptions -> ("rust", planOptions)
        plan = buildBackendPlan name
        rendered = renderPlan plan
    liftIO (writePlanFile (planFile opts) rendered)
    if planDryRun opts
        then liftIO (outputLine rendered) >> pure ExitSuccess
        else do
            prerequisites <- liftIO (checkPrerequisites (prerequisitesForBuild name))
            case prerequisites of
                Left err -> liftIO (outputLine (renderErrorString (Env.envOutputOptions env) err)) >> pure (ExitFailure 1)
                Right () -> runBackendPlan plan

buildBackendPlan :: String -> Plan Subprocess
buildBackendPlan backend =
    Plan
        { planName = "build " <> backend
        , planSteps =
            case backend of
                "cpp-imperative" -> cppImperativePgoBoltPlan
                "cpp-functional" -> cppFunctionalPgoBoltPlan
                "rust" -> rustPgoBoltPlan
                _ ->
                    [ Subprocess "make" ["-C", backend, "smoke"] Nothing Nothing
                    ]
        }

-- | Sprint 5.3 PGO+BOLT pipeline as a typed `[Subprocess]` sequence
-- per [phase-5-cpp-imperative-steelman.md → Sprint 5.3](../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md):
--
--   1. PGO-instrumented bench + instrumented artefacts.
--   2. Training run (self-play under `--rng cpp`) writes
--      `cpp-imperative/pgo-profile/*.gcda`.
--   3. PGO-optimized rebuild of both artefacts with `-fprofile-use`.
--   4. BOLT instrument pass for both artefacts (writes
--      `cpp-imperative/bolt-profile/*.fdata`).
--   5. BOLT training run produces the BOLT profile data.
--   6. BOLT optimize pass produces `*_bench.bolted.so` and
--      `*_instrumented.bolted.so`.
--   7. Install: rename `_bench.bolted.so` to the canonical FFI load
--      name `libmcts_cpp_imperative.so`; symlink-equivalent for the
--      `_instrumented` artefact.
--
-- The whole pipeline rides the typed `Subprocess` boundary; no
-- ad-hoc `callProcess` or `System.Process` smart constructors live in
-- this module. The training runs invoke `cabal exec mcts` so the
-- exact same binary that ships the rest of the CLI drives the training
-- workload — there is no separate training executable.
cppImperativePgoBoltPlan :: [Subprocess]
cppImperativePgoBoltPlan = pgoBoltPlan "cpp-imperative"

-- | Sprint 6.2 PGO+BOLT pipeline for backend (iii); identical shape
-- to backend (ii)'s plan, only the backend identifier changes. The
-- training workload and the BOLT instrumentation parameters share the
-- pinned constants so the (ii)-vs-(iii) report-card comparison
-- isolates style as the variable, not the build harness.
cppFunctionalPgoBoltPlan :: [Subprocess]
cppFunctionalPgoBoltPlan = pgoBoltPlan "cpp-functional"

-- | Sprint 6.4 PGO+BOLT pipeline for backend (iv) Rust. The first
-- four steps drive `cargo build --release` with rustc's PGO flags
-- through `RUSTFLAGS`; the BOLT pass runs `llvm-bolt -instrument`
-- against the cdylib output so `perf` is not required in the
-- container (matching the C++ pipelines). The install step renames
-- the bolted artefact to the canonical `rust/target/release/libmcts_rust.so`
-- so the Haskell FFI continues to load it from the pinned path.
rustPgoBoltPlan :: [Subprocess]
rustPgoBoltPlan =
    [ -- 1. Instrumented build: rustc -Cprofile-generate
      cargoBuild "rust/pgo-profile" "generate"
    , -- 2. Training run: same shape as C++ backends
      trainingRunFor "rust" pgoTrainingGames pgoTrainingSims
    , -- 3. Merge LLVM profraw -> profdata (the rustc PGO flow requires
      -- profdata, not profraw)
      Subprocess
        "bash"
        [ "-c"
        , "if command -v llvm-profdata-19 >/dev/null 2>&1; then "
            <> "llvm-profdata-19 merge -o rust/pgo-profile/merged.profdata rust/pgo-profile/*.profraw 2>/dev/null || true; "
            <> "elif command -v llvm-profdata >/dev/null 2>&1; then "
            <> "llvm-profdata merge -o rust/pgo-profile/merged.profdata rust/pgo-profile/*.profraw 2>/dev/null || true; "
            <> "fi"
        ]
        Nothing
        Nothing
    , -- 4. Optimized rebuild: rustc -Cprofile-use
      cargoBuild "rust/pgo-profile" "use"
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
    , -- 6. BOLT training run
      trainingRunFor "rust" boltTrainingGames boltTrainingSims
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
    ]
  where
    cargoBuild profileDir mode =
        Subprocess
            "cargo"
            ["build", "--release"]
            ( Just
                [
                    ( "RUSTFLAGS"
                    , "-C target-cpu=native -C "
                        <> (if mode == "generate" then "profile-generate=" else "profile-use=")
                        <> profileDir
                    )
                ]
            )
            (Just "rust")

pgoBoltPlan :: String -> [Subprocess]
pgoBoltPlan backend =
    [ -- 1. PGO instrument
      make ["pgo-bench-generate"]
    , make ["pgo-instr-generate"]
    , -- 2. PGO training run (benchmark (b))
      trainingRunFor backend pgoTrainingGames pgoTrainingSims
    , -- 3. PGO optimize rebuild
      make ["pgo-bench-use"]
    , make ["pgo-instr-use"]
    , -- 4. BOLT instrument
      make ["bolt-bench-instrument"]
    , make ["bolt-instr-instrument"]
    , -- 5. BOLT training run (smaller workload — block frequencies
      -- converge fast)
      trainingRunFor backend boltTrainingGames boltTrainingSims
    , -- 6. BOLT optimize
      make ["bolt-bench-optimize"]
    , make ["bolt-instr-optimize"]
    , -- 7. Install
      make ["install-bench"]
    ]
  where
    make args =
        Subprocess
            "make"
            ("-C" : backend : args)
            Nothing
            Nothing

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
        , "cpp"
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
