# Haskell Code Guide

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../documentation_standards.md, ./README.md
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

The Phase 5/6 PGO+BOLT build harness and the FFI shared-library link path go
through `runStreaming` / `capture`. There is no other IO surface for subprocess
execution. The `.hlint.yaml` rules from
[code_quality.md → HLint Rules](./code_quality.md#hlint-rules) enforce the
forbidden-primitives list.

### `Plan / Apply`

The MCTS commands that consume the `Plan / Apply` pattern are:

- `mcts test all` — Plan/Apply over the five Cabal stanzas plus the report-card
  workload (Phase 7 Sprint 7.3).
- `mcts build {cpp-legacy|cpp-imperative|cpp-functional|rust}` — Plan/Apply over
  the per-backend two-stage PGO + BOLT post-link + `mimalloc` link pipeline
  (Phase 5 Sprint 5.3, Phase 6 Sprint 6.2, Phase 6 Sprint 6.4).
- `mcts docs generate` — internally Plan/Apply over the rendered marker
  substitutions and the `trackingGeneratedPaths` writes (Phase 1 Sprint 1.3).

`mcts bench` and `mcts verify` are not Plan/Apply commands — they do not mutate
external state (only the transcript cache, which they own), so the
`--dry-run` flag does not apply. They do, however, consume the
`prerequisiteRegistry`.

### `prerequisiteRegistry`

The `prerequisiteRegistry` (Phase 1 Sprint 1.7) covers every toolchain dependency
across the five backends. The remedy hints point at concrete operator actions —
`docker compose up -d` for missing container tooling, `make -C cpp-imperative
smoke` for a missing `libmcts_cpp_imperative.so`, `mcts build rust` for a missing
`libmcts_rust.so`, and so on.

### `Env`

The `Env` record (Phase 1 Sprint 1.8) carries the log handle, the cache root, the
parsed CLI options, the `CommandSpec` registry, the generated-section registries,
the `prerequisiteRegistry`, and test-hook fields. The `newtype App = App
{ runApp :: ReaderT Env IO a }` is the only application monad.

### `AppError` and `renderError`

The single `AppError` ADT (Phase 1 Sprint 1.9) declares the canonical 15-variant
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
- `VerifyMismatch`, `VerifyCohortTooSmall` — cross-backend verify failures.
- `RecomputeMismatch` — `mcts inspect` recompute of an existing transcript
  under `--rng cpp` disagrees with the recorded visits. Carries
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
- `EngineEnvelopeMismatch` — `mcts verify` detects a layered engine-envelope
  disagreement: either a cohort-invariant field
  (`host_arch`, `rng_source`, `shared_rng_build_id`, `cohort_config_hash`)
  disagrees across the cohort, or a per-backend-slot field
  (`engine_build_id`, `compiler_id`, `compiler_version`, `fp_flags`,
  `libm_id`, `cpu_features`, `fp_env`) disagrees between a cached
  transcript and the live binary for the same backend slot. Carries
  an `EnvelopeMismatchScope` discriminator (`CohortLevel | BackendSlot
  Backend`) plus `(field, expected, got)`. Cohort-level mismatches are
  unconditionally hard fails; per-backend-slot mismatches are
  downgradeable to a warning via `mcts verify --allow-stale`. See
  [determinism_contract.md → Engine Envelope](./determinism_contract.md).
- `PrerequisiteUnmet` — `prerequisiteRegistry` failure carrying the failing
  `nodeId`, `nodeDescription`, and remedy hint.
- `SubprocessFailed` — `runStreaming` / `capture` returns a non-zero exit code
  through the typed `Subprocess` boundary (the PGO+BOLT build harness, the
  `cabal test` invocation, etc.). Reserved for the subprocess boundary only.
- `FFIFailure` — a C ABI call through the Haskell FFI raised. Carries the
  backend identity (`Backend`), the C ABI symbol that raised, and the decoded
  error message. Reserved for the FFI bridge only; distinct from
  `SubprocessFailed` because the failure surface is in-process rather than a
  spawned child. See
  [backend_ffi_contract.md → Error rendering](./backend_ffi_contract.md).
- `DocsCheckDrift` — `mcts docs check` detects a marker drift.
- `UnknownCommand`, `InvalidMove` — `mcts play` in-app input errors.

`renderError :: AppError -> Text` lives in `src/MCTS/CLI/Output.hs`. It is the
only Text-rendering path at the CLI boundary; the `.hlint.yaml` rules enforce
this.

### GADT-Indexed State Machines

Two project state machines use phantom-type indices per the doctrine's "more
than two states ⇒ GADT-indexed" rule, with backend cohort membership encoded
at the type level:

- `VerifyBackend` — type-level exclusion of backend (i) from the default
  `verify` cohort. Constructors: `VCppImperative | VCppFunctional | VRust |
  VHaskell`. See
  [determinism_contract.md → Cross-Backend Determinism (Q3)](./determinism_contract.md).
- `LegacyParityBackend` — type-level requirement of backend (i) for the
  legacy-parity cohort. Constructors: `LpCppLegacy | LpCppImperative |
  LpCppFunctional | LpRust | LpHaskell` with `LpCppLegacy` mandated at parse
  time. See
  [determinism_contract.md → Legacy Parity Envelope](./determinism_contract.md).

Phase 7 Sprint 7.2 owns the GADT shapes per
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
they surface as cross-backend `verify` mismatches, golden-test diffs, or
silent disagreement between two implementations of the same engine. The
project therefore bans partial functions outright on the supported path.
`Prelude.head`, `Prelude.tail`, `Prelude.init`, `Prelude.last`,
`Prelude.read`, `Data.List.(!!)`, `Data.Maybe.fromJust`,
`Data.Either.fromLeft`, and `Data.Either.fromRight` are forbidden;
[code_quality.md → HLint Rules](./code_quality.md) carries the enforcement.
Use `Data.List.NonEmpty` when the call site genuinely owns a non-empty
list, `readMaybe` from `Text.Read` for parses, the `safe` package's
`headMay` / `lastMay` when a `Maybe` is appropriate, or pattern-match with
an explicit `AppError` branch. The hot inner loops of the Haskell engine
(see [../../README.md → Backend (v) — Haskell](../../README.md)) use
unboxed mutable arrays inside `ST s`, so the partial-function set on lists
rarely shows up in the engine itself — but it bites in the CLI, transcript,
and FFI marshalling layers, which is exactly where determinism damage
would propagate the furthest.

### Smart Constructors for Bounded Domain Types

The transcript wire format and the determinism contract pin two
range-bounded domains the type system can make unrepresentable when
violated:

- **Action enumeration** (single-byte action IDs). Valid: `0..208`
  (`0..80` pawn moves, `81..144` horizontal walls, `145..208` vertical
  walls). Reserved-for-extensions: `209..254`. Sentinel: `255`. See
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
  modules under `src/MCTS/CLI/Tui/`, `src/MCTS/CLI/Play.hs`, and
  `src/MCTS/CLI/Replay.hs`. Phase 7 Sprint 7.4 owns the gate. The `mcts lint
  haskell` pass enforces the gate via an `.hlint.yaml` rule.
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

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — lint rules that enforce the patterns
- [cli_command_surface.md](./cli_command_surface.md) — the user-facing surface
  these patterns underpin
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how `Subprocess`
  underpins the FFI build harness
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
