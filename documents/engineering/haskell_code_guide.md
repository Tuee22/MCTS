# Haskell Code Guide

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md
**Generated sections**: none

> **Purpose**: Describe how the MCTS project uses the doctrine's Haskell patterns —
> `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `ReaderT Env IO`, `AppError`
> with `renderError`, GADT-indexed state machines — and record the project's
> stack deviations. Defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
> for each pattern's authoritative definition.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../../HASKELL_CLI_TOOL.md) — `Subprocess` ADT, pure `renderSubprocess`,
  `runStreaming` / `capture` as the only IO boundary, the forbidden-primitives
  list (`callProcess`, `readCreateProcess`, `System.Process` constructors,
  `typed-process` smart constructors).
- [../../HASKELL_CLI_TOOL.md → Plan / Apply](../../HASKELL_CLI_TOOL.md) — `build` /
  `apply` boundary, `--dry-run` and `--plan-file <path>` on every Plan/Apply
  command.
- [../../HASKELL_CLI_TOOL.md → Prerequisites as Typed
  Effects](../../HASKELL_CLI_TOOL.md) — `prerequisiteRegistry` with `nodeId`,
  `nodeDescription`, remedy hint, transitive closure, `AppError PrerequisiteUnmet`
  on failure.
- [../../HASKELL_CLI_TOOL.md → Application Environment](../../HASKELL_CLI_TOOL.md)
  — `ReaderT Env IO` with a single `Env` record, test-hook fields with no-op
  defaults in production.
- [../../HASKELL_CLI_TOOL.md → Error Handling](../../HASKELL_CLI_TOOL.md) — single
  `AppError` ADT, `renderError :: AppError -> Text` boundary, `print` /
  `exitFailure` / direct terminal formatting forbidden outside the dedicated
  output module.
- [../../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../../HASKELL_CLI_TOOL.md)
  — phantom-type indices, singleton witnesses, the existential-wrapping pattern
  for runtime discovery, the forbidden runtime-status-enum-with-manual-validation
  pattern.

## Project-Specific Elaborations

### `Subprocess`

The Rust and C++ PGO/BOLT build harnesses and the FFI shared-library link path go
through `runStreaming` / `capture`, which interpret `Subprocess` values with
`typed-process`. There is no other IO surface for subprocess execution. The
`.hlint.yaml` rules from
[code_quality.md → HLint Rules](./code_quality.md#hlint-rules) enforce the
forbidden-primitives list.

### `Plan / Apply`

The MCTS commands that consume the `Plan / Apply` pattern are:

- `mcts test all` — Plan/Apply over the five live Cabal stanzas plus the report-card
  workload, consuming Dockerfile-built backend artefacts (Phase 7 Sprint 7.3).
- `mcts build cpp-legacy`, `mcts build cpp-imperative`, and
  `mcts build cpp-functional` — Dockerfile-invoked Plan/Apply recipes for the C++
  backend build leaves. The steelman C++ leaves drive the shared PGO/BOLT target
  sequence and install the canonical shared libraries only after PGO and BOLT both
  produce their required profile data from the blended Q1/Q2 report-card training
  suite. Runtime validation does not rebuild them, and PGO-only/unoptimized fallback
  installs are forbidden.
- `mcts build rust` — Plan/Apply over
  the Dockerfile-invoked foreign backend two-stage PGO + BOLT post-link +
  system `mimalloc` link pipeline, including the final installed-cdylib smoke and
  the same blended training workload as the steelman C++ backends.
- `mcts build legacy-fixtures` — Plan/Apply over the backend (i) optional external
  evidence generator. Its outputs belong in ignored/external artifact roots, not in
  normal test inputs.
- `mcts docs generate` — internally Plan/Apply over the rendered marker
  substitutions and the `trackingGeneratedPaths` writes (Phase 1 Sprint 1.3).

Host invocations wrap these logical commands as
`docker compose run --rm mcts mcts <command>`.

`mcts bench` and `mcts verify` are not Plan/Apply commands — they do not mutate
external state (only the transcript cache, which they own), so the
`--dry-run` flag does not apply. They do, however, consume the
`prerequisiteRegistry`.

### `prerequisiteRegistry`

The `prerequisiteRegistry` (Phase 1 Sprint 1.7) covers every toolchain dependency
across the five backends. The current baseline uses exact version probes for
`ghc-9.14.1 --numeric-version == 9.14.1` and
`cabal --numeric-version == 3.16.1.0`, LLVM/BOLT `19.x`, Rust `1.95.0`, LLD `19`,
`mimalloc` via library-path probes, executable/file probes for the remaining
build-command prerequisites (`c++`, Rust and C++ profile directories, and canonical
foreign shared-library nodes), and
emits `AppError PrerequisiteUnmet` with a remedy hint before applying backend build
plans or Cabal-backed test plans.

### `Env`

The `Env` record (Phase 1 Sprint 1.8) carries the active output options
(`envOutputOptions`), the `CommandSpec` registry (`envCommandSpec`), the
generated-section registry (`envGeneratedSectionRules`), tracked generated paths
(`envTrackingGeneratedPaths`), the prerequisite registry (`envPrerequisites`), the
explicit cache-dir override (`envCacheDir`), the process log handle
(`envLogHandle`), raw invocation arguments (`envRawArguments`), and a
monotonic-clock test-hook (`envClockMonotonic`).
`newtype App = App (ReaderT Env IO a)` (with `MonadIO` derived via
`DerivingStrategies + GeneralizedNewtypeDeriving`) is the application monad;
`runAppIO :: Env -> App a -> IO a` runs it. `askEnv` retrieves the env and
`withTestClock :: IO Word64 -> App a -> App a` overrides the clock locally
— the bench runner's monotonic-bracket assertion uses this to capture the
exact start/stop call sites.
`MCTS.App.runCommand` and the public `MCTS.CLI.*` command runners return
`App ExitCode`; `runWithArgs` is the IO adapter that parses global flags,
constructs `Env`, runs the command, and converts the final `ExitCode` for
`main`.

Sprint 1.5's apply boundary lives in `MCTS.Plan`:

- `applyWithEnv :: (Env -> step -> IO (Either AppError ExitCode)) -> Plan step -> App ExitCode`
- `applySubprocessWithEnv :: Plan Subprocess -> App ExitCode`

Existing per-command runners (`MCTS.CLI.Build`, `MCTS.CLI.Test`) call the
`applyWithEnv` family. `MCTS.CLI.Build` uses `applySubprocessWithEnv`; `MCTS.CLI.Test`
uses `applyWithEnv` with a custom step interpreter so subprocess failures still render
through `renderError`.

### `AppError` and `renderError`

The single `AppError` ADT (Phase 1 Sprint 1.9) declares the canonical 19-variant
set. The set matches
[../../README.md → Output and error discipline](../../README.md) exactly;
`SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, and
`EngineEnvelopeMismatch` are the MCTS-specific failure surfaces named
alongside the user-facing variants:

- `TranscriptNotFound`, `TranscriptAmbiguous` — hash-prefix lookup failures.
- `TranscriptFormatUnsupported` — `MCTS.Transcript.Codec.decode` rejects a
  transcript carrying a non-zero `flags u32` (reserved for future format
  extensions); see
  [transcript_format.md → Header](./transcript_format.md).
- `VerifyMismatch`, `VerifyLengthMismatch`, `VerifyTerminatorMismatch`,
  `VerifyCohortTooSmall` — cross-backend verify failures. The length and
  terminator variants prevent zip-truncation from hiding extra games, extra
  moves, or winner/total-move disagreement after digest mismatch.
- `RecomputeMismatch` — same-backend originator recompute of an existing
  transcript under `--rng cpp` disagrees with the recorded chosen actions or
  visits. Carries
  `(Backend, GameId, MoveIndex, recomputed_record, recorded_record)`.
  Distinct from `VerifyMismatch` because it indicates a single backend's
  own determinism has broken against its prior recording (a bug bell), not
  the expected cross-backend disagreement `verify` exists to surface. See
  [determinism_contract.md → Recompute Mismatch Output](./determinism_contract.md).
- `LegacyParityRolloutOverflow` — backend (i) throws or hits
  `MAX_ROLLOUT_ITERS`.
- `ArchEnvelopeMismatch` — a transcript cohort or verify cohort spans more than
  one `host_arch`; see
  [determinism_contract.md → Architecture Envelope](./determinism_contract.md).
- `EngineEnvelopeMismatch` — logical `mcts verify` or the live integration
  verifier detects a layered engine-envelope
  disagreement: either a cohort-invariant field
  (`host_arch`, `rng_source`, `shared_rng_build_id`, `cohort_config_hash`)
  disagrees across the cohort, or, in the live integration verifier, a per-backend-slot field
  (`engine_build_id`, `compiler_id`, `compiler_version`, `fp_flags`,
  `libm_id`, `cpu_features`, `fp_env`) disagrees between a cached
  transcript and the live binary for the same backend slot. Foreign transcripts
  produced through `MCTS.Driver.Dispatch` carry the live C ABI envelope when the
  cdylib is present; absent cdylibs use the in-process fallback. Carries
  an `EnvelopeMismatchScope` discriminator (`CohortLevel | BackendSlot
  Backend`) plus `(field, expected, got)`. Cohort-level mismatches are
  unconditionally hard fails; per-backend-slot mismatches are
  downgradeable to a warning via `mcts verify --allow-stale`. See
  [determinism_contract.md → Engine Envelope](./determinism_contract.md).
- `PrerequisiteUnmet` — `prerequisiteRegistry` failure carrying the failing
  `nodeId`, `nodeDescription`, and remedy hint.
- `SubprocessFailed` — `runStreaming` / `capture` returns a non-zero exit code
  through the typed `Subprocess` boundary (the Rust PGO/BOLT build harness, C++
  smoke builds, the `cabal test` invocation, etc.). Reserved for the subprocess
  boundary only.
- `FFIFailure` — a C ABI call through the Haskell FFI raised. Carries the
  backend identity (`Backend`), the C ABI symbol that raised, and the decoded
  error message. Reserved for the FFI bridge only; distinct from
  `SubprocessFailed` because the failure surface is in-process rather than a
  spawned child. See
  [backend_ffi_contract.md → Error rendering](./backend_ffi_contract.md).
- `DocsCheckDrift` — `mcts docs check` detects a marker drift.
- `UnknownCommand`, `InvalidMove` — `mcts play` in-app input errors.
- `ParseError` — parser and option validation failures that need to render
  through the same `AppError` boundary as runtime errors.
- `IOErrorText` — textual IO failures surfaced at command boundaries where the
  lower-level exception cannot be kept as a typed project error.

`renderError :: AppError -> Text` lives in `src/MCTS/Error.hs` as the canonical
boundary. `src/MCTS/CLI/Output.hs` re-exports that Text boundary and owns
`renderErrorString :: OutputOptions -> AppError -> String` for final
stdout/stderr emission, including `--color always|never` handling. The `.hlint.yaml`
rules enforce this boundary by keeping direct terminal output out of command modules.

### GADT-Indexed State Machines

The Q3 backend cohort uses a phantom-indexed shape per the doctrine's "more
than two states ⇒ GADT-indexed" rule:

- `VerifyBackend` — type-level Q3 cohort `(ii)..(v)`. Constructors:
  `VCppImperative | VCppFunctional | VRust | VHaskell`. See
  [determinism_contract.md → Cross-Backend Determinism (Q3)](./determinism_contract.md).
- `mcts verify legacy-parity` — Q7 validates the complete backend list `(i)..(v)`
  under the legacy envelope. The runtime parser rejects incomplete cohorts and pins
  `max_plies = 10000`, `--rng cpp`, and single-threaded execution. See
  [determinism_contract.md → Legacy Parity Envelope](./determinism_contract.md).

Phase 7 Sprint 7.2 implements these GADT-shaped parser surfaces per
[../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md →
Sprint 7.2](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md).

`SimBudget`, `Threading`, and `Side` remain plain ADTs per
[../../DEVELOPMENT_PLAN/00-overview.md → Doctrine Scope](../../DEVELOPMENT_PLAN/00-overview.md):
each has a two-conceptual-state state space (fixed vs ramped budget; single vs
multi threading; hero vs villain) and the doctrine's GADT mandate applies only
to state machines with more than two conceptual states.

### Total Functions on the Supported Path

MCTS is a determinism-critical project: bottoms in transcript decoding, RNG
state derivation, or move generation do not surface as graceful failures —
they surface as cross-backend `verify` mismatches, semantic renderer-test
failures, or
silent disagreement between two implementations of the same engine. The
project therefore bans ambient data partials on the supported path.
`Prelude.head`, `Prelude.tail`, `Prelude.init`, `Prelude.last`,
`Prelude.read`, `Data.List.(!!)`, `Data.Maybe.fromJust`,
`Data.Either.fromLeft`, and `Data.Either.fromRight` are forbidden;
[code_quality.md → HLint Rules](./code_quality.md) carries the enforcement
through the `mcts-haskell-style` source walker.
Use `Data.List.NonEmpty` when the call site genuinely owns a non-empty
list, `readMaybe` from `Text.Read` for parses, a local total helper returning
`Maybe`, or pattern-match with an explicit `AppError` branch. Narrow `error`
calls are permitted only for impossible hot-path invariants in the Haskell
engine, where changing the inner-loop type to carry `AppError` would alter the
measured surface. The hot inner loops of the Haskell engine (see
[../../README.md → Backend (v) — Haskell](../../README.md)) use unboxed mutable
arrays inside `ST s`, so the forbidden partial-function set on lists rarely
shows up in the engine itself — but it bites in the CLI, transcript, and FFI
marshalling layers, which is exactly where determinism damage would propagate
the furthest.

### Smart Constructors for Bounded Domain Types

The transcript wire format and the determinism contract pin two
range-bounded domains the type system can make unrepresentable when
violated:

- **Action enumeration** (single-byte action IDs). Valid: `0..208`
  (`0..80` pawn moves, `81..144` horizontal walls, `145..208` vertical
  walls). Reserved-for-extensions: `209..254`. Sentinel/invalid byte: `255`,
  not admitted by the `Action` domain. See
  [transcript_format.md → Action Enumeration](./transcript_format.md) for
  the layout the wire format pins and
  [../../README.md → Cross-backend verification](../../README.md) for the
  contract.
- **Ply counter** (`Word16` per board state). Valid: `0..max_plies`
  (default `200`; pinned at `MAX_ROLLOUT_ITERS = 10000` for the
  legacy-parity envelope). See
  [../../README.md → Draw rule](../../README.md) and
  [determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md).

The canonical pattern is a newtype with a smart constructor that returns
`Either AppError`, the data constructor hidden from the module's exports,
and a paired raw accessor for the inverse direction:

```haskell
-- Example: newtype + smart-constructor + raw-accessor pattern
-- | Single-byte action identifier per the transcript wire format.
--   Valid: 0..208 ∪ {255}.  209..254 reserved (must be rejected on decode).
newtype ActionId = ActionId Word8
  deriving stock (Eq, Ord, Show)
  -- ^ Data constructor NOT exported from MCTS.Action.

mkActionId :: Word8 -> Either AppError ActionId
mkActionId w
  | w <= 208 || w == 255 = Right (ActionId w)
  | otherwise            = Left (TranscriptFormatUnsupported ...)

unActionId :: ActionId -> Word8
unActionId (ActionId w) = w

-- | Game-state ply counter bounded by the run configuration's max_plies.
newtype Ply = Ply Word16
  deriving stock (Eq, Ord, Show)

mkPly :: Word16 -> Word16 -> Either AppError Ply
mkPly maxPlies w
  | w <= maxPlies = Right (Ply w)
  | otherwise     = Left (LegacyParityRolloutOverflow ...)
```

Two consequences worth pinning:

1. **Phase 2's `decode . encode == id` property holds vacuously on the
   valid-range subset.** Decoding constructs `ActionId` via the smart
   constructor; the only `Word8` values the decoder will accept are exactly
   the ones the encoder emits, so the QuickCheck generator over
   `Word8 \ {209..254}` round-trips without further axioms.
2. **The reserved range and the sentinel are encoded once.** Every reader
   of the format reuses the smart constructor; there is no second copy of
   the predicate to drift.

The same pattern applies to other bounded scalars introduced later (sim
budgets enforced positive, worker counts enforced `>= 1`, etc.). New
bounded domains land alongside their smart constructor — adding the raw
type without the constructor and validating ad-hoc at call sites is
forbidden by review.

## Stack Deviations from Doctrine

Two recorded deviations from
[../../HASKELL_CLI_TOOL.md → Overview](../../HASKELL_CLI_TOOL.md):

- **`brick` + `vty` for TUIs only.** Required by the interactive `mcts play` and
  `mcts inspect replay` commands. Gated: `brick` and `vty` are imported only by
  modules under `src/MCTS/CLI/Tui/`. Phase 7 Sprint 7.4 owns the gate. The `mcts lint
  haskell` pass enforces the gate via an `.hlint.yaml` rule.
- TUI side effects still route through ordinary project boundaries. For example,
  `mcts play :save` records move state in `MCTS.CLI.Tui.Play` but writes through
  `MCTS.Transcript.writePlayTranscript`; AI turns call
  `MCTS.Driver.ForeignSearch.foreignSearchMove` when a selected foreign backend's
  shared library is present and use the in-process fallback otherwise; `mcts inspect
  replay` prepares originator cache-miss overlays and on-demand backend-column
  loaders in `MCTS.CLI.Inspect` before passing pure `EqStream`s and loader callbacks
  into `MCTS.CLI.Tui.Replay`; terminal output stays inside the `brick` renderer.
- **`dhall` unused.** The doctrine prescribes `dhall` for daemon configuration;
  daemon configuration is out of scope for this CLI per
  [../../DEVELOPMENT_PLAN/00-overview.md → Doctrine
  Scope](../../DEVELOPMENT_PLAN/00-overview.md), so the dependency does not
  enter the stack.

## Doctrine Out of Scope

[../../README.md → Doctrine scope](../../README.md) marks the following
sections of `HASKELL_CLI_TOOL.md` as informational only — not binding on this
project. Each is read as background context; none imposes obligations on the
code:

- **Long-Running Daemons in the Same Binary** (the CLI is short-running only;
  this also covers the daemon-internal "Configuration: Dhall file with
  mandatory hot reload" subsection).
- **Capability Classes and Service Errors** (no external subsystems).
- **Retry Policy as First-Class Values** (no external subsystems).
- **At-Least-Once Event Processing** (no event stream).
- **Reconcilers: Idempotent Mutation as a Single Command** (no managed state
  in the world).
- **Smart Constructors for Paired Resources** (no paired resources).
- **Pulumi-Orchestrated Infrastructure Tests** (no cloud surface).

Adding new code that invokes any of these patterns is a doctrine-scope change
and requires updating
[../../README.md → Doctrine scope](../../README.md) first.

## Editor / IDE Setup

The project's build doctrine routes all supported builds, tests, lints, and
codegen through `docker compose run --rm mcts mcts <command>`. Host editor
integration is personal convenience only; it is not a supported validation,
build, formatting, linting, documentation-generation, test, benchmark, or
backend-build workflow.

- **Haskell Language Server may run on the host.** The VS Code / code-server
  Haskell extension launches `haskell-language-server-wrapper` as a host
  subprocess of the editor, so it cannot see anything that lives only inside
  the Compose service.
- **The host's `~/.cabal/store/<ghc-ver>/` and the project's `dist-newstyle/`
  are treated as IDE-only caches.** They are never consumed by CI, release
  artifacts, or any `mcts <command>` workflow. Both are already gitignored or
  outside the repo.
- **No host command is part of repository validation.** If an editor requires
  host-side package metadata, that setup is outside the supported project
  workflow and must not be cited as evidence that the repo builds or tests.
- **GHC version bumps** require updating the pinned project toolchain and any
  personal editor configuration that references it, including
  `haskell.toolchain.ghc` in the editor's
  settings (vscode-server: `~/.vscode-server/data/Machine/settings.json`;
  code-server: `~/.local/share/code-server/User/settings.json`). Expected
  cadence: rare.

Adding any other host-side build pathway is a doctrine change and requires
updating the root operator/agent guidance and
[../../README.md → Build and run](../../README.md).

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — lint rules that enforce the patterns
- [cli_command_surface.md](./cli_command_surface.md) — the user-facing surface
  these patterns underpin
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how `Subprocess`
  underpins the FFI build harness
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
