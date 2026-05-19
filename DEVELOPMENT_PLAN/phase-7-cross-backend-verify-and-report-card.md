# Phase 7: Cross-Backend Verify, Test Stanzas, POC Report Card

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land the four remaining Cabal test stanzas (`mcts-unit`,
> `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`), the `mcts test all`
> Plan/Apply command, the pinned report-card workload, the tidy summary block, and
> the `mcts play` plus `mcts inspect replay` interactive TUIs.

## Phase Status

🔄 **Active**. `docker compose run --rm mcts mcts test all` is the phase validation
gate under the pinned toolchain; when the foreign cdylibs are present, the
integration paths exercise the real FFI-backed engines for backends
(i)/(ii)/(iii)/(iv), while Q3/Q7 `verify` uses the logical in-process cohort.
The latest completed focused validations are `docker compose run --rm --volume
/home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-unit`, which passes 26
named `tasty` / `tasty-hunit` cases across parser, transcript/cache,
engine/RNG, envelope, plan/subprocess, renderer, and TUI-dispatch groups
including the foreign-selected play AI advance assertion; `docker compose run
--rm mcts mcts lint all`;
`docker compose run --rm mcts mcts check-code`; the four backend build commands
`docker compose run --rm mcts mcts build cpp-legacy`,
`docker compose run --rm mcts mcts build cpp-imperative`,
`docker compose run --rm mcts mcts build cpp-functional`, and
`docker compose run --rm mcts mcts build rust`; and
`docker compose run --rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-integration`, which passes
42 cases including real `mcts` binary same-backend determinism for Haskell and
each built foreign backend plus conditional live-envelope stamping/stale-cache
checks for every present foreign cdylib plus the report-card divergence builder
and cached recompute-sidecar `inspect divergence` path; `docker compose run
--rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-cross-backend`,
which passes 6 logical-cohort cases; and `docker compose run --rm --volume
/home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-legacy-parity`, which
passes 3 logical-cohort cases. The 2026-05-18 full lifecycle gate
`docker compose run --rm --build mcts mcts test all` passed through the
canonical entrypoint and recorded the bounded report-card evidence.
Same-backend determinism
(Q4), the legacy-parity preflight, cross-host Q6 golden decode, and the
per-backend live envelope checks all pass. Sprint 7.5 ships
`divergenceVsEqStream` + foreign-FFI driver paths, live-envelope stamping for
FFI-produced transcripts, `checkTranscriptEnvelopesLive` comparison against
`mcts_<backend>_get_envelope()` in integration when the matching cdylib is
present, and envelope-mismatch tests covering host-arch + `shared_rng_build_id`
cohort-level hard-fails plus the `--allow-stale` downgrade for `BackendSlot`
mismatches; `mcts-integration` now exercises the same backend-slot stale path
against transcripts stamped by live FFI backends when those shared libraries are
present. `MCTS.ReportCard` also carries the report-card divergence
matrix through table and JSON renderers, pinned by the report-card golden in
`mcts-unit`, and `mcts-integration` now checks a bounded measured report-card
cohort plus cached sidecar consumption through the real `mcts inspect
divergence` subprocess. Sprint 7.4
ships the move-input parser, the in-app commands
`:hint`/`:undo`/`:quit`/`:q`, the `:save` play-transcript writer, the
`runPlay → runInteractivePlay` TTY hookup, and `MCTS.CLI.Tui.Replay`
with forward/back/home/end navigation, cached board snapshots, cached sidecar
overlays, originator cache-miss recompute/visit-checking before TUI start, and
an `r` key that materialises the next non-originator backend equity column on
demand (pure dispatchers unit-tested). The shared board
widget renders the 9×9 pawn grid with horizontal and vertical wall overlays.
Sprint 7.2 now carries GADT-shaped `VerifyBackend` /
`LegacyParityBackend` parser surfaces in `MCTS.Types` and `MCTS.CLI.Command`;
`mcts-unit`, `mcts-cross-backend`, and `mcts-legacy-parity` validate the typed
parser boundary and cohort guards. The cross-backend and legacy-parity stanzas now
hard-fail `VerifyMismatch` on their focused logical rollout and self-play smoke
cohorts; the live FFI cohort determinism gap is tracked in
`legacy-tracking-for-deletion.md` until those compiled engines are deliberately
promoted back into Q3/Q7 verify.
The bounded canonical report card records Q1 ST 2.88×, Q1 MT8 18.93×,
Q2 ST 3.65×, Q2 MT8 10.18×, Q5 Haskell 1.00×, Q5 cpp-imperative 2.80×,
zero `(ii)..(v)` divergence, and verdict `Shortfall 17.925246987694774`;
the earlier non-PGO smoke snapshots remain in
`documents/engineering/compiler_runtime_tuning.md` as tuning history.

## Phase Summary

Phase `7` is where the logical determinism contract becomes enforceable
end-to-end while live FFI paths are kept under integration and divergence
coverage. The `mcts-cross-backend` stanza runs the four-backend `(ii)..(v)`
logical round-robin under `--rng cpp` and fails the stanza on any
`VerifyMismatch` in the focused rollout/self-play cohorts. The
`mcts-legacy-parity` stanza runs the 5-backend logical round-robin under the
legacy parity envelope (`max_plies = 10000`, fixture seed `S_LP = 42`) with the
same hard-fail mismatch discipline. The `mcts-integration`
stanza covers same-backend determinism (Q4) across all five backends at three seeds
each, plus the Q6 golden-fixture comparison for backend (i) against
`test/golden/legacy/`. The `mcts-unit` stanza covers pure logic, parser tests via
`execParserPure`, property tests, golden tests, transcript codec roundtrips, and RNG
mixer properties. `mcts test all` is the Plan/Apply command that builds canonical
foreign backend artefacts, runs every cabal stanza in order, runs the pinned
no-write report-card measurements plus verify cohorts, and emits the tidy
summary block answering Q1–Q7. The
`mcts play` and `mcts inspect replay` interactive TUIs land here, completing the
user-facing CLI surface.

## Sprint 7.1: `mcts-unit` and `mcts-integration` Stanzas 🔄

**Status**: Active
**Implementation**: `mcts.cabal` (`mcts-unit`, `mcts-integration` stanzas),
`test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the unit and integration stanzas. Unit covers pure logic; integration covers
the real `mcts` binary across the FFI to every backend.

### Deliverables

- `mcts.cabal` declares the `mcts-unit` and `mcts-integration` stanzas with
  `type: exitcode-stdio-1.0` and `tasty` as the in-stanza runner per
  [../HASKELL_CLI_TOOL.md → Test Organization](../HASKELL_CLI_TOOL.md). A single
  `tasty` tree spanning multiple stanzas is forbidden.
- `test/unit/` covers:
  - **Parser tests via `execParserPure`** per
    [../HASKELL_CLI_TOOL.md → Test Categories → Parser
    Tests](../HASKELL_CLI_TOOL.md): leaf happy paths, unhappy paths
    (missing required option, unknown subcommand, malformed flag value).
  - **Canonical property invariants** per
    [../HASKELL_CLI_TOOL.md → Test Categories → Property Tests](../HASKELL_CLI_TOOL.md):
    `decode . encode == id` on transcript header / record / file; `render is
    deterministic` on every renderer (the report-card summary block, the
    `inspect show` output, the `commands --tree` and `commands --json`
    outputs, the `Subprocess` `renderSubprocess`, the `AppError` `renderError`);
    `parser roundtrips` on every leaf `CommandSpec` (`render (parse argv) ==
    argv`).
  - **Golden tests** per
    [../HASKELL_CLI_TOOL.md → Test Categories → Golden Tests](../HASKELL_CLI_TOOL.md)
    for `commands --tree`, `commands --json`, `inspect show` on a fixed
    transcript, the report-card summary block (with wall-clock throughputs
    replaced by sentinel placeholders), and `renderError` for each `AppError`
    variant.
  - **Engine invariants**: legal-move agreement with the brute-force reference;
    terminal-state agreement; tree-persistence inherited-visit-count
    preservation.
  - **RNG mixer properties**: `splitmix64(master_seed, n)` bijective in `n` for
    fixed `master_seed` over the first 1M values; pinned `(seed, n)` values
    match the canonical splitmix spec.
  - **Per-leaf `Example` presence**: every leaf `CommandSpec` node has at least
    one `Example` entry.
- `test/integration/` covers:
  - **Same-backend determinism (Q4).** For each backend in `{cpp-legacy,
    cpp-imperative, cpp-functional, rust, haskell}`, run `mcts bench selfplay
    --backend <B> --threading single --rng cpp --games 4 --seed <S> --sims 100`
    at three pinned seeds `(42, 43, 44)` and assert two consecutive runs
    produce identical determinism payload sets.
  - **Q6 legacy golden comparison.** For backend (i), run `mcts bench selfplay
    --backend cpp-legacy --rng cpp --max-plies 10000 --seed <S> --games 1
    --sims <S_LP_SIMS>` at the seeds covered by `test/golden/legacy/`
    (Phase 4 Sprint 4.5) and assert byte-equal transcripts.
  - **`typed-process` regression guard.** A static check that the
    integration runners go through `Subprocess`, not `typed-process` smart
    constructors.

### Validation

1. `docker compose run --rm mcts mcts test mcts-unit` passes.
2. `docker compose run --rm mcts mcts test mcts-integration` passes with all five backends built (this
   sprint requires all of Phases 3–6 closure to be meaningful; a partial-backend
   smoke is acceptable interim but Q4/Q6 closure waits for full cohort).
3. Each test category produces a golden file or a property-test stanza
   citing the doctrine section it implements.

### Remaining Work

- Baseline landed: `mcts-unit` and `mcts-integration` Cabal stanzas exist and are
  wired through in-stanza `tasty` runners. `docker compose run --rm --build mcts
  mcts test mcts-integration` validates the logical five-backend same-backend
  determinism baseline at three seeds per backend; real `mcts` binary
  same-backend determinism for Haskell and each built foreign backend through
  `MCTS.Subprocess.capture`; bounded FFI smoke drivers for all four foreign
  backends when their container-built shared libraries are present; live
  `mcts_<backend>_get_envelope` loading for those same foreign libraries; and the
  equity-sidecar originator marker integration check. The `mcts-unit` stanza now
  covers the doctrine's required property-test categories at fixture scale: transcript
  `decode . encode == id`, sorted-record contract, cpp-legacy draw rejection,
  splitmix bounded bijection (`mix 42 i` unique for `i ∈ [0, 1023]`), every
  `AppError` variant renders to non-empty text, the prerequisite registry is
  acyclic and its transitive closure pulls dependency edges (`cargo → rustup`,
  `bolt → llvm`), `buildPlan` / `applyPlan` / `applySubprocessPlan` shapes,
  same-seed `runGame` reproducibility, and every chosen move appears in its
  visit list and was legal on the matching reconstructed board. The full v1
  engine envelope round-trips through the unit stanza (cohort-invariant
  fields plus per-backend-slot fields). Golden fixtures under
  `test/golden/cli/` pin `commands --tree`, `commands --json`,
  `commands --list`, `inspect show`, `inspect list --format json`, and the
  report-card summary block (table + JSON), and `renderError` output for every
  current `AppError` variant as byte-stable strings;
  `test/golden/cli/subprocess.txt` pins `renderSubprocess` shell quoting.
  Parser coverage now exercises `commandParserInfo` directly through
  `execParserPure` for happy leaves and the `verify --rng native` failure path.
  A byte-level transcript golden under
  `test/golden/transcript-codec/` pins the v1 wire output for known
  2-game Haskell, C++ imperative, C++ functional, and Rust-tagged transcripts.
  `test/golden/engine/known-position.txt` pins a legal-move board snapshot.
  The binary equity sidecar codec (`MEQ1`
  magic + 15-byte fixed-width records + `0xFFFFFFFF` terminator) round-
  trips arbitrary equity values through `castWord64ToDouble`. The `Env`
  scaffold (`MCTS.Env`) and `App` monad (`ReaderT Env IO`) exist and the
  `withTestClock` test-hook installs custom clocks for the Sprint 3.5
  monotonic-clock bracket assertion.
- The `mcts-unit` runner now uses a fine-grained `tasty` / `tasty-hunit` tree
  with 26 named cases grouped by `cli and parser`, `transcripts and cache`,
  `engine and rng`, `envelopes and sidecars`, `plans and subprocesses`, and
  `renderers and TUI dispatch`; this split is validated by
  `docker compose run --rm --build mcts mcts test mcts-unit`. Remaining unit
  work is to promote the hand-rolled fixture-scale properties and byte-golden
  assertions into dedicated `tasty-quickcheck` / `tasty-golden` providers where
  that adds coverage clarity.
- Remaining integration work is to expand the real-binary path from the current
  same-backend smoke/determinism checks into the full transcript-producing Q4
  closure. The committed external Q6 fixtures now decode on every host
  regardless of fixture architecture, verify their hash filenames, and assert
  the full `S_LP = 42`, `S_LP_SIMS = 10000`, `max_plies = 10000` legacy parity
  envelope generated through `mcts build legacy-fixtures`.

## Sprint 7.2: `mcts-cross-backend` and `mcts-legacy-parity` Stanzas 🔄

**Status**: Active
**Implementation**: `mcts.cabal` (`mcts-cross-backend`, `mcts-legacy-parity`
stanzas), `test/cross-backend/Main.hs`, `test/legacy-parity/Main.hs`,
`src/MCTS/CLI/Verify.hs` (extend with the four-backend cohort dispatch),
`src/MCTS/CLI/Spec.hs` (extend the `Verify` subtree)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the round-robin cross-backend `verify` cohort and the legacy-parity cohort as
their own Cabal stanzas, with the `VerifyBackend` GADT enforcing the (i)-excluded
constraint at the type level and `LegacyParityBackend` requiring (i) at parse time.

### Deliverables

- `mcts.cabal` declares the `mcts-cross-backend` stanza
  (`type: exitcode-stdio-1.0`, `tasty`). The stanza runs `mcts verify rollouts`
  and `mcts verify selfplay` across the full four-backend `(ii)..(v)` cohort
  under `--rng cpp` at the report-card knob `G_V = 4` and `S_VERIFY = 500`.
- `mcts.cabal` declares the `mcts-legacy-parity` stanza. The stanza runs `mcts
  verify legacy-parity selfplay` across all five backends with `max_plies =
  10000`, `--rng cpp`, `--threading single`, fixture seed `S_LP = 42`, and
  `G_LP = 2` games.
- `src/MCTS/CLI/Spec.hs` finalises the `Verify` subtree: `VerifyRollouts`,
  `VerifySelfplay`, `VerifyLegacyParity` carrying `VerifyOptions` /
  `LegacyParityOptions` per the project [README → CLI command
  topology](../README.md). `VerifyBackend` excludes `cpp-legacy` at the type
  level — its constructors are `VCppImperative | VCppFunctional | VRust |
  VHaskell` per
  [00-overview.md → Hard Constraints item 7](00-overview.md).
  `LegacyParityBackend` requires `LpCppLegacy` at parse time.
- `src/MCTS/CLI/Verify.hs` finalises the round-robin pairwise comparison as a
  two-phase protocol per
  [../README.md → Cross-backend verification → Typical transcript sizes](../README.md)
  and `documents/engineering/determinism_contract.md` → Verify Mismatch Output:
  1. **Determinism-payload digest first.** Decode each backend-specific transcript
     and compare the SHA-256 of the canonical determinism payload pairwise across
     the cohort. Cohorts whose payload digests all agree pass immediately.
  2. **Move-by-move scan on mismatch.** For each pair with disagreeing digests,
     decode both transcripts move-by-move until the first divergent record;
     emit `AppError VerifyMismatch` carrying
     `(left_backend, right_backend, game_id, move_index, left_record,
     right_record)` and stop the scan for that pair, per
     [../documents/engineering/determinism_contract.md → Verify Mismatch Output](../documents/engineering/determinism_contract.md).

  Cohorts of size 1 emit `AppError VerifyCohortTooSmall` at parse time (not at
  scan time).
- A pre-flight smoke run inside `mcts-legacy-parity` asserts backend (i)
  neither throws nor reaches `MAX_ROLLOUT_ITERS = 10000` at the fixture seed;
  if it does, the cohort emits `AppError LegacyParityRolloutOverflow` carrying
  `(seed, game_index, move_index)` so the fixture seed can be replaced.

### Validation

1. `docker compose run --rm mcts mcts test mcts-cross-backend` passes: the
   `(ii)..(v)` cohort agrees on visit counts at `G_V = 4`.
2. `docker compose run --rm mcts mcts test mcts-legacy-parity` passes: the
   5-backend cohort agrees on visit counts under the legacy parity envelope at
   `G_LP = 2`.
3. A synthetic injected mismatch in one backend produces `AppError
   VerifyMismatch` with the correct payload.
4. A synthetic `MAX_ROLLOUT_ITERS` overflow in backend (i) produces `AppError
   LegacyParityRolloutOverflow`.

### Remaining Work

- Baseline landed: `mcts-cross-backend` and `mcts-legacy-parity` Cabal stanzas exist
  and are wired through `MCTS.Verify`'s logical `Driver.runBatch` cohort so Q3/Q7
  remain stable even when foreign shared libraries are present. Live FFI engines
  remain exercised by `mcts-integration`, `mcts bench`, `mcts play`, and
  `mcts inspect divergence`; exact live-FFI cohort promotion is tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
  `docker compose run --rm mcts mcts test mcts-cross-backend` exercises the
  four-backend `(ii)..(v)` round-robin under `--rng cpp` (single-threaded),
  and additionally asserts the
  cohort-constraint surface rejects (a) a cohort containing `cpp-legacy` and (b) a
  single-backend cohort, both with `AppError VerifyCohortTooSmall`. Three Sprint
  7.5 envelope-mismatch tests cover `host_arch` + `shared_rng_build_id` cohort-
  level hard-fails and the `--allow-stale` downgrade for `BackendSlot` mismatches.
  `docker compose run --rm mcts mcts test mcts-legacy-parity` exercises the
  full-five-backend logical cohort under the legacy envelope and asserts a cohort
  missing `cpp-legacy` is rejected.
- Sprint 7.2 typed cohort closure: `src/MCTS/Types.hs` owns the GADT-shaped
  `VerifyBackend` constructors (`VCppImperative`, `VCppFunctional`, `VRust`,
  `VHaskell`) and the `LegacyParityBackend` constructors
  (`LpCppLegacy`, `LpCppImperative`, `LpCppFunctional`, `LpRust`,
  `LpHaskell`), with conversion helpers back to `Backend`. `VerifyCommand`
  stores typed `[VerifyBackend]` / `[LegacyParityBackend]` lists, and
  `src/MCTS/CLI/Parser.hs` uses typed backend-list readers so default
  `verify` rejects `cpp-legacy`, single-backend cohorts, and legacy-parity
  cohorts without `LpCppLegacy` at the parser boundary. Focused validation:
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-cross-backend`, and
  `docker compose run --rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-legacy-parity`.
- Sprint 7.2 RNG-salt refinement closure: `MCTS.Rng.Mix.backendNativeSalt` is
  the single source of truth for the per-backend `--rng native` salt; it is
  shared across `Driver.uctChooseMove`, `Engine.Recompute.recomputeGame`, and
  `Engine.ForeignRecompute.recomputeGameMoves`, and is asserted as zero under
  `--rng cpp` and pairwise distinct under `--rng native` in
  `mcts-unit::exerciseBackendNativeSalt`.
- Sprint 7.2 heuristic-drop closure, 2026-05-17: `src/MCTS/Search/UCT.hs::pickByUctIndex`
  no longer tiebreaks unvisited children by `nonTerminalRank`; the tiebreaker is now
  `(negate score, actionByte)` matching the C++/Rust first-unvisited-child policy.
  `finalChoiceKey` also drops the heuristic and equity components, leaving only
  `(negate visits, actionId)` consistent with `cpp-imperative/engine/search.cpp::run_search`'s
  `if (child.visit_count > best_visits) { ... }` discipline. `MCTS.Verify.comparable` sorts the
  visit list by `action_id` and filters zero-visit entries so per-backend
  child-enumeration shape does not block the visit-count contract. The
  `nonTerminalRank` function stays exported for standalone test coverage at
  `test/unit/Main.hs`. `docker compose run --rm mcts mcts test all` +
  `docker compose run --rm mcts mcts check-code` green for that closure point.
- Sprint 7.2 logical cohort-agreement closure, 2026-05-18: `cpp-imperative` and
  `cpp-functional` cap wall children at 12 to match Haskell's
  `take 12 (wallMoves board)` and Rust's `if count >= 12 { break; }` path. The
  `mcts-cross-backend` stanza now asserts equality for both logical rollout and
  self-play smoke cohorts across `(ii)..(v)` and fails on `VerifyMismatch`; the
  `mcts-legacy-parity` stanza does the same for logical rollout and self-play
  smoke cohorts across all five backend slots. Focused validation:
  `docker compose run --rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-cross-backend`,
  `docker compose run --rm --volume /home/matt/MCTS:/workspace/MCTS mcts mcts test mcts-legacy-parity`, and
  `docker compose run --rm --build mcts mcts lint all`.
- Sprint 7.1 external-fixture decode closure, 2026-05-18: the
  `mcts-integration` legacy-goldens test now walks every committed
  `test/golden/legacy/transcripts/<arch>/*.tr` fixture directory instead of
  only `transcripts/<host_arch>`, so committed Q6 anchors are decoded and
  envelope-checked on any validation host. Focused validation:
  `docker compose run --rm --build mcts mcts test mcts-integration`.
- Sprint 7.1 Q6 fixture byte-guard closure, 2026-05-18: the
  `test/golden/legacy/transcripts/amd64/` anchor was regenerated at
  `S_LP_SIMS = 10000` through `mcts build legacy-fixtures` against the
  `/home/matt/MCTS_legacy`-equivalent imported core. The integration test now
  requires ten fixtures per committed architecture directory, verifies each
  filename equals `sha256(file_bytes)`, and checks `cpp-legacy`, self-play,
  single-threaded, `--rng cpp`, `seed = 42`, `sims = 10000`, `max_plies =
  10000`, and `runGames = 1` on every decoded file.

## Sprint 7.3: `mcts test all` Plan/Apply and Report-Card Summary 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Test.hs`,
`src/MCTS/CLI/Spec.hs` (Test subtree),
`src/MCTS/ReportCard.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land `mcts test all` as the doctrine-mandatory canonical test command: a Plan/Apply
command that builds canonical backend artefacts, delegates to `cabal test`, runs the
pinned no-write report-card measurements plus verify cohorts, and emits the tidy
summary block answering Q1–Q7 in one screenful.

### Deliverables

- `src/MCTS/CLI/Spec.hs` declares `TestCommand = TestAll | TestStanza Text`. `mcts
  test <stanza>` runs the named Cabal stanza (e.g. `mcts test mcts-unit`).
- `src/MCTS/CLI/Test.hs` owns `mcts test all` as a Plan/Apply command. The plan is
  a typed `[Subprocess]` sequence per the project
  [README → mcts test all](../README.md), with the lint-first prelude required by
  [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack → Aggregate
  dispatch](../HASKELL_CLI_TOOL.md) (`tool test all` includes the full
  lint surface plus `cabal build all` as its first step before `cabal test`) —
  cited per standards rule L:
  1. Run `mcts lint files` (whitespace, final newline, `forbiddenPathRegistry`,
     `trackingGeneratedPaths` no-hand-edit) per
     [phase-1-haskell-cli-surface.md → Sprint 1.4](phase-1-haskell-cli-surface.md).
  2. Run `mcts lint docs` (generated-section drift on the `GeneratedSectionRule`
     registry) per
     [phase-1-haskell-cli-surface.md → Sprint 1.3](phase-1-haskell-cli-surface.md).
  3. Inside the container, run `cabal build all` warning-clean under the pinned
     toolchain. (`mcts lint haskell` is exercised inside the `mcts-haskell-style`
     Cabal stanza in step 4; it does not need its own plan step here.)
  4. Run the canonical foreign backend build harnesses: `mcts build cpp-legacy`,
     `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust`.
  5. Inside the container, run `cabal test mcts-haskell-style` (pinned style-tool
     `fourmolu --mode check` + `hlint --with-group=default --with-group=extra`
     with only `Error:` findings blocking + `cabal format` round-trip).
  6. Inside the container, run `cabal test mcts-unit`.
  7. Inside the container, run `cabal test mcts-integration`.
  8. Inside the container, run `cabal test mcts-cross-backend`.
  9. Inside the container, run `cabal test mcts-legacy-parity`.
  10. Run the pinned report-card workload. Q1/Q2/Q5 timing rows execute inside
     the report-card builder through `runBatchNoWriteDispatch`, using the
     `G_R`, `G_S`, and `S_BENCH` knobs without retaining or writing the large
     benchmark transcript batches. The rendered `--dry-run` plan therefore
     contains only the explicit deterministic verify subprocesses:
     1. `mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games $G_V --seed 42 --max-plies 200`
     2. `mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games $G_V --seed 42 --max-plies 200 --sims $S_VERIFY`
     3. `mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games $G_LP --seed $S_LP --sims $S_LP_SIMS`
     The README's standalone `mcts bench` examples remain operator-facing
     commands for comparable ad hoc wall-clock runs and cache-writing inspection
     workflows, not the canonical high-volume report-card implementation path.
  11. Render the tidy summary block from the collected `ReportCard` value.
- `--dry-run` renders the entire `[Subprocess]` plan and exits 0. `--plan-file
  <path>` writes the rendered plan to a file.
- `src/MCTS/ReportCard.hs` declares the typed `ReportCard` record carrying the
  Q1–Q7 results: per-backend wall-clock and games/sec / sims/sec for each
  workload-threading combination; PASS/FAIL plus failing-pair payload for each
  determinism cohort; the host `uname -m` and the GHC version string.
- The `ReportCard` carries a `backendBasisFootnotes :: [Text]` field. Whenever a
  Q1 / Q2 / Q5 row is computed for backend (i) under `max_plies != 10000`, the
  renderer appends the footnote "(i) throughput shown for reference only; not on
  the same basis as (ii)–(v) at this `max_plies`" per
  [../README.md → Benchmarks → Backend (i) throughput caveat](../README.md). The
  Haskell-vs-(ii) comparison is the load-bearing performance result; the (i)
  row is informational unless the legacy-parity envelope is in force.
- `src/MCTS/ReportCard/Render.hs` exposes a pure rendering function
  `renderReportCard :: ReportCard -> Text` (and the `Aeson` JSON encoding for
  `--format json`). The summary block matches the literal layout pinned at
  [../README.md → mcts test all → Tidy summary block](../README.md) (README
  lines 255–273), reproduced here as the rendering contract:

  ```
  MCTS POC report card — seed=42, max-plies=200, host=<uname -m>, ghc=9.14.1
  ──────────────────────────────────────────────────────────────────────────
  Q1  Haskell vs C++ (ii)  rollouts  ST          <ratio>×   (<hs> vs <ii> games/s)
  Q1  Haskell vs C++ (ii)  rollouts  MT8         <ratio>×   (<hs> vs <ii> games/s)
  Q2  Haskell vs C++ (ii)  self-play ST          <ratio>×   (<hs> vs <ii> games/s)
  Q2  Haskell vs C++ (ii)  self-play MT8         <ratio>×   (<hs> vs <ii> games/s)
  Q3  Cross-backend determinism  (cpp RNG)       <PASS|FAIL>    (4 backends × <G_V> games agree)
  Q4  Same-backend determinism   (per backend)   <PASS|FAIL>    (5/5 backends × 3 seeds)
  Q5  MT scaling  Haskell   1→8 workers          <ratio>×    (linear ideal: 8×)
  Q5  MT scaling  C++ (ii)  1→8 workers          <ratio>×
  Q6  Legacy port (i) vs MCTS_legacy             <PASS|FAIL>    (golden transcripts match)
  Q7  Legacy parity, 5-way round-robin           <PASS|FAIL>    (5 backends × <G_LP> games agree,
                                                              max_plies=10000, seed=<S_LP>)

  cabal test                                     <PASS|FAIL>    (mcts-unit, mcts-integration,
                                                              mcts-cross-backend, mcts-legacy-parity,
                                                              mcts-haskell-style)

  Verdict: <verdict text>
  ```

  Wall-clock numbers render to fixed precision (three significant figures for
  ratios, one decimal for throughputs in kilogames/s); no timestamps, no
  locale-dependent ordering, no terminal-width-dependent wrapping. The
  `<ratio>` / `<hs>` / `<ii>` / `<PASS|FAIL>` slots are filled from the typed
  `ReportCard`; everything else in the layout above is literal text the
  renderer must emit byte-for-byte.
- **Q5 two-anchor rule.** The text renderer emits only the Haskell and C++ (ii)
  anchor rows for Q5 scaling ("`1→8 workers <ratio>×`"). The full per-backend
  scaling matrix is included only in the `--format json` payload per
  [../README.md → mcts test all → POC headline questions Q5](../README.md):
  "The text summary block highlights Haskell and C++ (ii) as the two anchors;
  the full per-backend scaling table is available via `mcts test all --format
  json`." The asymmetry is enforced by `renderReportCard` returning only the
  anchor rows while the JSON encoder emits the full `[BackendScalingRow]`.
- A golden test in `mcts-unit` covers the rendering with sentinel placeholders
  replacing the live throughputs. The golden file pins the literal layout
  scraped from README lines 255–273 with sentinel placeholders substituted for
  the `<ratio>` / `<hs>` / `<ii>` / `<PASS|FAIL>` slots; any drift from the
  README layout fails the golden test.

#### Doctrine compliance

`mcts test all` honours three binding doctrine surfaces per
[../README.md → mcts test all → Doctrine compliance](../README.md) (lines
278–282); each is owned by a Sprint 7.3 deliverable above and cross-cited here
so the contract is reviewable in one place:

- **Plan / Apply.** `build :: TestInputs -> Either AppError TestPlan` produces
  the typed list of backend builds, Cabal stanzas, and verify subprocesses
  (modelled per
  [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../HASKELL_CLI_TOOL.md)); `apply :: Env -> TestPlan -> IO ExitCode`
  runs it before the no-write measured report-card builder populates Q1/Q2/Q5.
  `--dry-run` prints the rendered plan and exits 0; `--plan-file <path>` writes
  the rendered plan for out-of-band review per
  [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md).
- **Prerequisites as Typed Effects.** All five backend artefacts present,
  PGO+BOLT profiles populated, `mimalloc` linked, GHC/Cabal pinned versions on
  the container `PATH` are encoded as one `prerequisiteRegistry` per
  [../HASKELL_CLI_TOOL.md → Prerequisites as Typed
  Effects](../HASKELL_CLI_TOOL.md). The transitive closure runs before `apply`;
  a single unmet node aborts with `AppError PrerequisiteUnmet` carrying the
  failing `nodeId`, description, and remedy hint per
  [phase-1-haskell-cli-surface.md → Sprint 1.7](phase-1-haskell-cli-surface.md).
- **Determinism of the summary.** The block is rendered by a pure function over
  a typed `ReportCard` value. No timestamps, no locale-dependent ordering, no
  terminal-width-dependent wrapping. Wall-clock numbers are the only
  non-deterministic content and render to fixed precision (three significant
  figures for ratios, one decimal for throughputs in kilogames/s). The block is
  golden-testable; live throughputs are replaced by sentinel placeholders in
  the golden file.

### Validation

1. `mcts test all --dry-run` renders the full plan and exits 0. The plan
   carries fifteen typed-`Subprocess` steps: three lint/build prerequisites
   (`mcts lint files`, `mcts lint docs`, `cabal build all`); four canonical
   backend builds (`mcts build cpp-legacy`, `mcts build cpp-imperative`,
   `mcts build cpp-functional`, `mcts build rust`); five `cabal test` stanzas
   (`mcts-haskell-style`, `mcts-unit`, `mcts-integration`,
   `mcts-cross-backend`, `mcts-legacy-parity`); and the three pinned
   `mcts verify` report-card invocations enumerated above (rendering Q1/Q2/Q5
   timing rows and the summary block is an in-process final step, not a
   subprocess).
2. `mcts test all` runs end-to-end with all five backends and emits the tidy
   summary block.
3. `mcts test all --format json` emits valid JSON that schema-checks against a
   pinned schema in `test/golden/report-card-schema.json`.
4. Failure of any cabal stanza, any verify cohort, or any report-card measurement
   exits non-zero.

### Remaining Work

- Baseline landed and validated: `mcts test all --dry-run`, `mcts test <stanza>`, a
  Plan/Apply runner, report-card rendering, and the pinned command sequence exist.
  The dry-run now renders fifteen typed `Subprocess` steps in order, including the
  canonical backend builds before the Cabal stanzas and verify workload; recursive
  CLI steps route through `cabal exec mcts -- ...`, and the Q1/Q2/Q5 report-card
  measurements use the no-write batch runner instead of transcript-retaining
  benchmark subprocesses.
- The former logical Q1/Q2/Q5 summary placeholders now have typed measured fields in
  `src/MCTS/ReportCard.hs`. `MCTS.CLI.Test.buildMeasuredReportCard` requires canonical
  backend artefacts, measures Q1/Q2/Q5 through the production monotonic clock, derives
  `Within tolerance` / `Shortfall <ratio>` from `HASKELL_PARITY_TOLERANCE = 0.05`,
  and populates the Sprint 7.5 divergence matrix from the measured `G_V` verify cohort.
  The bounded canonical 2026-05-18 run recorded that evidence.
- Keep the bounded canonical workload practical enough for `mcts test all` while
  leaving larger standalone `mcts bench` runs as operator-facing diagnostics.
- JSON schema coverage now exists at `test/golden/report-card-schema.json`; the
  unit golden test validates the static evidence-pending Q1/Q2/Q5 fields and
  `divergence_matrix` baseline against it. The live measured values are recorded in
  the plan and tuning docs, while the static golden remains a renderer fixture.

## Sprint 7.4: `mcts play` and `mcts inspect replay` TUIs 🔄

**Status**: Active. The current TUI surface is:
`MCTS.CLI.Tui.Board` (9×9 board widget); `MCTS.CLI.Tui.Play` (brick
`App` with legacy-notation move input + `:hint`/`:undo`/`:quit`/
`:q` plus `:save` transcript writes and selected-backend AI dispatch
through dynamic FFI when the requested foreign cdylib is present);
`MCTS.CLI.Tui.Replay` (brick `App` with forward/
back/home/end navigation, multi-backend equity overlay column
populated from cached `.eq` sidecars via `currentOverlayRows`,
originator cache-miss recompute/visit-checking through
`MCTS.CLI.Inspect.prepareReplayOverlays`, and a bounded
`Map.Map Int Board` snapshot cache that warms the
nearest predecessor each navigation step so long-transcript
forward/back is amortised O(1) on the cache size; the
`--cache-states N` operator flag overrides the cache bound). The current
`MCTS.CLI.Tui.Board.renderBoard` draws the pawn grid, status line, and
horizontal/vertical wall overlays.
`MCTS.App.runPlay` dispatches to `runInteractivePlay` when stdin
is a TTY; `MCTS.CLI.Inspect.inspectReplay` dispatches to
`runReplayTuiFromState` on a TTY with the operator-configured
state including loaded cached sidecars and an on-demand overlay loader for the
`r` key. Pure dispatchers
(`applyUserInput`, `applyReplayKey`, `currentOverlayRows`,
`boardWithCache`, `nextOverlayBackend`, `applyOverlayLoadResult`) are unit-tested in `mcts-unit::exerciseTuiPlayInput`,
`mcts-unit::exerciseTuiReplayNav`, `mcts-unit::exerciseTuiReplayOverlay`.
Sprint-owned work remains for the final report-card/Q6 integration surface.
**Blocked by**: none (upstream `brick` / `config-ini` compatibility
landed under the `allow-newer` constraint)
**Implementation**: `src/MCTS/App.hs` (`runPlay` TTY/fallback dispatch),
`src/MCTS/CLI/Inspect.hs` (`inspectReplay` TTY/fallback dispatch),
`src/MCTS/CLI/Tui/{Board,Play,Replay}.hs`,
`src/MCTS/CLI/Spec.hs` (Play and Inspect.Replay subtrees)
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Land the two interactive `brick` + `vty` TUI commands: `mcts play` for human-vs-AI
or AI-vs-AI spectate, and `mcts inspect replay` for forward/back navigation through
a stored transcript with cached or recomputed equity overlays.

### Deliverables

- `mcts.cabal` declares `brick` and `vty` as `build-depends` for the two TUI
  modules only. The deviation is recorded once in
  [00-overview.md → Doctrine Scope → Stack deviations](00-overview.md); no other
  module imports either library. The dependency check in Sprint 1.1's
  standardized library audit accepts these two as the documented exception.
- `src/MCTS/CLI/Tui/Board.hs` renders the 9×9 Corridors board and pawn positions
  using `brick`/`vty` widgets; wall-segment overlays remain sprint-owned active
  work. `MCTS.CLI.Tui.Play` carries the input
  prompt and uses `MCTS.Notation.parseMove` for legacy move notation.
- `src/MCTS/CLI/Tui/Play.hs` owns the interactive `mcts play` TTY path per the project
  [README → Interactive modes](../README.md):
  - Left pane: Corridors board.
  - Right pane: whose turn, move count, last move, live simulation counter
    during AI turns.
  - In-app commands: `:hint` (top-N moves for the side to play), `:undo` (back
    up one ply via in-memory MCTS-state stack), `:save` (flush partial game as
    a transcript hashed by `sha256(run_config || move_history)`), `:quit`.
  - Move input: legacy notation `*(x,y)`, `H(x,y)`, `V(x,y)`.
  - `Ctrl-C` during AI turn cancels the in-progress search; `Ctrl-C` at the
    prompt is `:quit`.
  - Any other `:`-prefixed input renders `AppError UnknownCommand` to the
    status bar. Malformed move notation renders `AppError InvalidMove` the same
    way. Game state is left untouched in both cases; control returns to the
    prompt. All in-app error renderings route through the same `renderError`
    boundary the non-interactive commands use.
  - **Seed handling.** `playSeed :: Maybe Word64`. When `--seed` is not
    supplied, the driver draws a fresh `Word64` from system entropy (the
    standard splitmix seeder), records it in the transcript header's
    `master_seed` field, and uses it for the game. The recorded value is the
    actual seed, not a sentinel — replaying the transcript with
    `mcts inspect replay` reproduces the same game per
    [../README.md → CLI command topology](../README.md).
- `src/MCTS/CLI/Tui/Replay.hs` owns `mcts inspect replay <hash-prefix>` per the
  project README:
  - Layout: board on the left; on the right, current move index, move actually
    played, top-N legal-move list (visits, equity, action).
  - **Status line literal** per
    [../README.md → Interactive modes → `inspect replay <hash-prefix>`](../README.md)
    (README line 543). The bottom-of-screen status bar renders exactly:
    `<hash> | move M / total | press ? for help` (literal, byte-for-byte —
    `<hash>` is the short hash slot, `M` and `total` are the move-index and
    move-count slots, `press ? for help` is fixed text). A `mcts-unit` golden
    pins this layout; drift fails the golden.
  - Keybinds: `→`/`l` next, `←`/`h` prev, `Home`/`End` jump to start/end,
    `r` recompute the next missing backend equity column, and `q` quit.
  - **Equity recomputation on cache miss.** Opening the replay loads cached
    `.eq` overlays and, when the originator sidecar is absent, recomputes the
    originator's `EqStream` from the transcript before the TUI starts. The Haskell
    originator uses `MCTS.Engine.Recompute.recomputeEqStream`; foreign originators
    use `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` when the matching
    shared library is present. Under `--rng cpp`, the recompute compares the
    chosen action and visit table against the transcript records before writing
    the sidecar. Failures surface as a status-line message and do not block
    navigation through the stored transcript.
  - **Replay equity bit-equality contract.** When the navigator runs on the
    same compiled binary that wrote the transcript, equities are bit-identical
    to the values the original search computed (seed → RNG state → simulation
    order → identical float-accumulation order → identical bits on the same
    hardware). When the transcript was written by a different backend,
    equities agree to many digits but can differ at the last few ULPs. The
    replay UI does not assert equity bit-equality across backends; it asserts
    only visit-count bit-equality (which is the determinism contract).
    Authoritative spec:
    [../documents/engineering/determinism_contract.md → Replay Equity
    Guarantees](../documents/engineering/determinism_contract.md).
  - **State caching.** Last `replayCacheStates` MCTS states (default 20,
    `--cache-states N`) kept in memory; LRU eviction on the cached-state map.
- Both TUIs route errors through `AppError` and `renderError` (no `print`, no
  direct terminal output outside the `brick` rendering layer); `--format` and
  `--color` flags are ignored on these subcommands and the `CommandSpec`
  documents the asymmetry.

### Validation

1. `mcts play --backend haskell --side hero --sims 100` starts an interactive
   game and accepts move input.
2. `mcts inspect replay <prefix>` opens the navigator on a known transcript and
   the determinism check passes on every navigation.
3. A `docker compose run --rm mcts mcts test mcts-unit` golden covers the TUI
   board/status layout through the pure text rows that feed the `brick`
   renderer.
4. `mcts lint haskell` rejects any `print` / `exitFailure` / non-`brick` terminal
   output in either TUI module.

### Closure Notes (`:save`)

`MCTS.CLI.Tui.Play` records chronological `MoveRecord`s for human and AI moves,
writes hand-play transcripts through `MCTS.Transcript.writePlayTranscript`, and
addresses them with `sha256(run_config || move_history)` via `playTranscriptHash`.
The focused unit dispatcher test writes a saved game to a cache root, decodes it,
and asserts the saved move history matches the in-memory play state.

### Closure Notes (selected-backend AI)

`MCTS.CLI.Tui.Play.advanceAiState` dispatches AI turns through the selected backend.
For `haskell` it calls `MCTS.Driver.uctChooseMove` with the same per-move seed and
native-salt schedule as batch search. For foreign backends it first tries the matching
cdylib via `MCTS.Driver.ForeignSearch.foreignSearchMove`; that path rebuilds a fresh
foreign board by replaying the current move history through the backend's
`mcts_<backend>_apply_action` symbol, calls `mcts_<backend>_search_move`, and records
the returned visit vector in the play transcript. If the cdylib is absent, the TUI uses
the logical fallback with the selected backend's native salt and marks the status line
accordingly. `mcts-unit::exerciseTuiPlayInput` covers the selected-backend AI advance
and visit-vector recording path.

### Closure Notes (replay cache-miss recompute)

`MCTS.CLI.Inspect.prepareReplayOverlays` now loads cached sidecars and fills a
missing originator overlay before `MCTS.CLI.Tui.Replay` starts. The Haskell path
calls `MCTS.Engine.Recompute.recomputeEqStream`; foreign originators call
`MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` through the selected
backend's `with<Backend>RecomputeGame` opener when the shared library exists. Under
`--rng cpp`, `MCTS.Engine.ForeignRecompute.recomputeGameMoves` decodes flipped
action IDs back into the transcript perspective, compares the recomputed chosen
action and visit vector against the recorded move, and raises
`RecomputeMismatch backend game_id move_index recomputed recorded` on disagreement.
`mcts-unit::exerciseTuiReplayOverlay` covers the cache-miss sidecar write and the
cache-hit reuse path. Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-unit`,
`docker compose run --rm --build mcts mcts lint all`,
`docker compose run --rm mcts mcts check-code`, and `git diff --check`.

### Closure Notes (on-demand replay columns)

`MCTS.CLI.Tui.Replay` now binds `r` to `loadNextOverlay`, which asks the
`ReplayState.replayOverlayLoader` callback for the first backend not already loaded
or marked unavailable. `MCTS.CLI.Inspect.inspectReplay` installs that callback for
TTY replays; it recomputes the requested backend's `EqStream` through the Haskell
recompute path or the matching foreign `with<Backend>RecomputeGame` opener, writes
the sidecar, appends the new overlay column, and records loaded/skipped/error status
messages in the replay state. Pure candidate selection and status transitions are
covered by `mcts-unit::exerciseTuiReplayOverlay`. Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-unit` and
`docker compose run --rm --build mcts mcts lint all`.

### Remaining Work

- Stable board/status layout coverage exists via
  `test/golden/cli/tui-board.txt`; replay-buffer-specific layout coverage can
  be added when the final report-card/Q6 integration surface lands.
- Preserve the TUI exception to global `--format` / `--color` flags in command docs.

## Sprint 7.5: Layered Envelope Verify and Divergence Matrix 🔄

**Status**: Active
**Implementation**: `src/MCTS/Verify/Divergence.hs`, `src/MCTS/Verify/Envelope.hs`,
`src/MCTS/CLI/Inspect.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Enforce the layered engine-envelope rule in `mcts verify` per
[../documents/engineering/determinism_contract.md → Engine
Envelope](../documents/engineering/determinism_contract.md), add the
`--allow-stale` escape hatch for forensic comparisons, and extend the
`mcts test all` report-card workload with the cross-backend
divergence-rate matrix from
[../documents/engineering/determinism_contract.md → Divergence
Smell](../documents/engineering/determinism_contract.md).

### Current Validation State

`src/MCTS/Verify/Divergence.hs` exposes both the transcript-pair baseline metric and
`divergenceVsEqStream`, which scores a transcript against a recomputed or cached
`EqStream` for `visit_disagreement_rate`, `move_disagreement_rate`, and
`equity_l2_drift`. `mcts inspect divergence <hash-prefix>` resolves and decodes the
requested transcript, discovers cached sidecar columns for the transcript hash, and
adds one live foreign-recompute row per available cpp-imperative, cpp-functional, or
Rust cdylib. `mcts-unit` covers zero-divergence and changed-equity cases; the
integration stanza exercises the foreign recompute `EqStream` path when cdylibs are
present.

`src/MCTS/Verify/Envelope.hs` also enforces the full v1 layered envelope fields
that exist today: cohort-level `host_arch`, envelope-version, `rng_source`,
`shared_rng_build_id`, and `cohort_config_hash` checks; backend-slot `backend`,
`build_id`, `engine_build_id`, `engine_git_commit`, `compiler_id`,
`compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, and `fp_env` checks;
and `--allow-stale` downgrading of backend-slot mismatches to warnings.
`MCTS.Driver.Dispatch.runBatchDispatch` stamps FFI-produced transcripts with
the live `mcts_<backend>_get_envelope()` payload whenever the matching cdylib is
present, while `checkTranscriptEnvelopesLive` falls back to the logical
Haskell envelope when no cdylib exists so the Cabal stanzas remain
self-contained. The `mcts-integration` stanza conditionally runs a
live-stamping check for `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and
`rust`: it dispatches a small FFI self-play run, asserts the transcript envelope
equals the C ABI live envelope, then mutates `compiler_version` to prove the
live verifier hard-fails without `--allow-stale` and downgrades the same
backend-slot mismatch with `--allow-stale`. The parser now carries
`legacy-parity {rollouts|selfplay}` all the way to execution instead of
collapsing it to self-play.

`src/MCTS/ReportCard.hs` carries typed Q1/Q2 throughput comparisons, Q5 scaling
rows, and `reportDivergenceRows` as `ReportDivergenceRow` /
`ReportDivergenceCell` values. The text renderer emits the Q1/Q2 time ratios
with Haskell-vs-C++ games/sec evidence, Q5 ST-to-MT8 scaling rows, then a
fixed-width `visit/move` matrix after Q7; the JSON renderer emits the same data
under `q1_*`, `q2_*`, `q5_*`, and `divergence_matrix`. The current default report
card keeps explicit `Evidence pending` placeholders for golden-test determinism,
while `mcts test all` builds the final report card through
`MCTS.CLI.Test.buildMeasuredReportCard`: after the typed plan succeeds, it
requires the canonical backend artefacts built in that same container, measures
Q1/Q2/Q5 with the production monotonic clock, runs the pinned `G_V = 4`
self-play verify cohort for `(ii)..(v)`, and populates the matrix with
`divergenceRowsFromTranscripts`. `MCTS.CLI.Test.buildMeasuredReportCardWith`
exposes the bounded divergence builder for integration coverage, and
`mcts-integration` checks that path together with a cached recompute sidecar
consumed through the real `mcts inspect divergence` subprocess.

`MCTS.CLI.Verify.renderVerifyJson` emits `warning_details` for downgraded
`--allow-stale` backend-slot warnings. `EngineEnvelopeMismatch` warnings are
structured with `type`, `scope`, `backend`, `field`, `expected`, `got`, and
`message`, while the existing numeric `warnings` count remains for lightweight
consumers.

### Deliverables

- `src/MCTS/Verify/Envelope.hs` — `checkCohortInvariant ::
  NonEmpty Transcript -> Either AppError ()` and
  `checkBackendSlot :: LiveBinaries -> Transcript -> Either
  AppError ()`. The first reduces over the cohort and emits
  `EngineEnvelopeMismatch CohortLevel field expected got` on the
  first cohort-invariant disagreement; the second compares the
  cached transcript's per-backend-slot envelope against the live
  binary's `mcts_<backend>_get_envelope()` value and emits
  `EngineEnvelopeMismatch (BackendSlot b) field expected got` on the
  first disagreement.
- `VerifyOptions` gains `verifyAllowStale :: Bool` (CLI flag
  `--allow-stale`). When set, `BackendSlot` mismatches are downgraded
  to warnings rendered through `renderError` to stderr; verify
  continues on visits. JSON output also carries those warnings under
  `warning_details`. `CohortLevel` mismatches remain hard fails regardless.
- `src/MCTS/Verify/Divergence.hs` — `divergenceRate :: Transcript ->
  EqStream -> DivergenceMetrics` computes
  `visit_disagreement_rate`, `move_disagreement_rate`, and
  `equity_l2_drift` for a `(transcript, foreign-backend recompute)`
  pair. The full divergence matrix is `forM
  cohort_backends (recompute_then_score)`.
- `cabal.project` gains four pinned thresholds:
  `MOVE_DELTA_NATIVE_MAX = 0.005`, `VISIT_DELTA_NATIVE_MAX = 0.05`,
  `MOVE_DELTA_CROSS_BUILD_MAX = 0.001`, `VISIT_DELTA_CROSS_BUILD_MAX
  = 0.01`. Phase 7 calibration runs may relax these; commits must
  update both `cabal.project` and
  [../documents/engineering/determinism_contract.md → Divergence
  Smell → Thresholds](../documents/engineering/determinism_contract.md)
  in the same change.
- `mcts test all` report-card workload extension: the tidy summary
  block gains a per-backend-pair divergence matrix
  (`visit_disagreement_rate` / `move_disagreement_rate` over the
  recorded `G_V = 4` games). Under `--rng cpp` every off-diagonal
  element should read `0.0% / 0.0%`; anything else triggers a warn
  banner in the summary.
- `src/MCTS/CLI/Inspect/Divergence.hs` — `mcts inspect divergence
  <hash-prefix>` emits the divergence matrix for a single transcript
  across every cached `(backend, build)` slot, computed via the same
  `divergenceRate` helper. Forensic command; output renders through
  the same `--format json|table|plain` discipline as the rest of the
  non-TUI surface.

### Validation

- `mcts-cross-backend`: a cohort whose two transcripts disagree on
  `shared_rng_build_id` (synthesized via a build-harness flag for
  test purposes only) fails verify with `AppError
  EngineEnvelopeMismatch CohortLevel SharedRngBuildId`. The test
  also confirms `--allow-stale` does NOT rescue this case (cohort-
  level mismatches are hard-fail by contract).
- `mcts-integration`: live stale-cache test — write a transcript with
  the present foreign cdylib, mutate its `compiler_version` field to
  simulate a stale cache entry, re-run the live envelope verifier, assert
  `AppError EngineEnvelopeMismatch (BackendSlot backend)
  CompilerVersion expected got` without `--allow-stale`, and assert
  success-with-warning when `--allow-stale` is passed.
- `mcts-integration` REPL multi-backend overlay test: open a stored
  transcript in `inspect replay`, request the haskell column with
  `r`, assert the `.eq` sidecar is created and the recompute path
  matches visits; re-open the same transcript, assert the column
  populates instantly from cache (no FFI compute invoked, via a
  test-hook counter).
- `mcts-integration` report-card divergence matrix: the `mcts test
  all` summary contains a four-row matrix with `--rng cpp`
  diagonals at zero and a footnote on the empirically-pinned
  threshold values.

### Closure Notes (per-game writer)

- `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits a batch
  Transcript into N one-game-per-file transcripts, matching the
  doctrine's transcript wire format. Each per-game file carries
  `runGames = 1` and the splitmix-derived per-game seed; the per-game
  hashes differ from the batch hash. `MCTS.Driver.runBatchWithGame`
  populates the new `BatchResult.batchGameWrites` field; the bench
  renderer surfaces the N-file write set.
- `mcts-unit::exercisePerGameTranscriptWriter` covers the entry shape
  (one entry per game, distinct hashes, each file decodes as a
  single-game transcript).

### Closure Notes (live envelope integration verify)

- `MCTS.FFI.Common.engineEnvelopeToEnvelope` converts the live C ABI
  `EngineEnvelope` into the transcript `Envelope` record, preserving
  `compiler_version`, `libm_id`, `shared_rng_build_id`, `engine_build_id`,
  CPU/FP flags, and the project-local build-id stem.
- `MCTS.Driver.Dispatch.runBatchDispatch` loads the matching
  `mcts_<backend>_get_envelope()` value before running a present foreign
  cdylib and writes that payload into the transcript. If the cdylib is absent,
  the existing logical fallback remains the self-contained Cabal-test path.
- `MCTS.Verify.Envelope.checkTranscriptEnvelopesLive` compares each transcript
  with the live foreign envelope when available and otherwise with the logical
  fallback. This live check is exercised by `mcts-integration`; the Q3/Q7 CLI
  verify path uses the logical `checkTranscriptEnvelopes` baseline.
  Cohort-level fields remain hard failures; backend-slot mismatches are
  downgraded only by `--allow-stale`.
- Focused validation passed with
  `docker compose run --rm --build mcts mcts test mcts-integration`,
  `docker compose run --rm --build mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts test mcts-cross-backend`, and
  `docker compose run --rm mcts mcts test mcts-legacy-parity`.

### Closure Notes (real live-envelope integration coverage)

`test/integration/Main.hs` now has a `foreign ffi live envelope stamping` group
for `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and `rust`. Each case is
skipped when its shared library is absent and otherwise runs
`MCTS.Driver.Dispatch.runBatchDispatch` through the live FFI backend, asserts the
transcript envelope equals `mcts_<backend>_get_envelope()`, and checks the
stale-cache contract by mutating `compiler_version`: the live verifier returns a
hard `EngineEnvelopeMismatch (BackendSlot backend) CompilerVersion` without
`--allow-stale` and the same mismatch as a warning with `--allow-stale`.
Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-integration`.

### Closure Notes (report-card divergence matrix)

`MCTS.ReportCard.ReportCard` now owns a typed `reportDivergenceRows` field. The
table renderer prints the four-backend `(ii)..(v)` `visit/move` matrix in the
tidy summary block, and the JSON renderer emits the same rows under
`divergence_matrix`. `mcts-unit::exerciseReportCardGolden` pins
`test/golden/cli/report-card.txt`, `test/golden/cli/report-card.json`, and
`test/golden/report-card-schema.json`, so matrix layout/schema drift fails the
unit stanza. Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-unit`.

### Closure Notes (measured report-card divergence rows)

`MCTS.ReportCard.divergenceRowsFromTranscripts` builds the report-card matrix
from decoded verify transcripts using `MCTS.Verify.Divergence.divergenceRate`.
`mcts test all` now calls `buildMeasuredReportCard` after the Plan/Apply
subprocess sequence succeeds, reruns the pinned `(ii)..(v)` `G_V = 4`
self-play verify cohort under `--rng cpp`, and renders table/JSON output from
the measured transcript rows instead of the static default. `divergenceRate`
shares the verify comparator's zero-visit filtering so backend-specific
zero-count padding does not create false disagreement. Focused validation
passed with `docker compose run --rm --build mcts mcts test mcts-unit` and
`docker compose run --rm --build mcts mcts test all --dry-run`.

### Closure Notes (report-card integration coverage)

`MCTS.CLI.Test.buildMeasuredReportCardWith` exposes the same measured
report-card builder used by the live `mcts test all` path with injectable
backends and `RunInputs`, allowing the integration stanza to exercise the
report-card divergence matrix and measured-field JSON schema without running the
bounded canonical `G_V = 4`, `S_VERIFY = 500` workload.
`mcts-integration::report-card divergence and inspect sidecar integration` runs
the four-backend `(ii)..(v)` self-play smoke
cohort, asserts the JSON report-card contains `q1_rollouts_st`,
`q5_cpp_imperative_scaling`, and `divergence_matrix`, writes a Haskell transcript
plus recomputed `.eq` sidecar, and invokes the real
`mcts inspect divergence` subprocess to prove the cached sidecar row is
consumed. Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-integration`.

### Closure Notes (structured stale-warning JSON)

`MCTS.CLI.Verify.renderVerifyJson` now renders success payloads with both the
existing `warnings` count and a `warning_details` array. Downgraded
`EngineEnvelopeMismatch (BackendSlot b)` warnings include the backend identifier,
field name, expected value, actual value, and rendered message so JSON consumers
do not need to parse stderr. `mcts-unit::exerciseEnvelopeChecks` covers the
structured warning object and JSON string escaping. Focused validation passed with
`docker compose run --rm --build mcts mcts test mcts-unit`.

### Closure Notes (legacy fixture regeneration entrypoint)

`mcts build legacy-fixtures` is now the supported Plan/Apply entrypoint for Q6
fixture regeneration. `MCTS.CLI.Command.BuildLegacyFixtures`,
`MCTS.CLI.Parser.legacyFixtureParser`, and the `CommandSpec` build subtree expose
`--output-dir`, `--seed`, `--games`, `--sims`, `--dry-run`, and `--plan-file`.
`MCTS.CLI.Build.legacyFixturePlan` builds `cpp-legacy/build/legacy-to-wire` and
then invokes it with explicit flags plus `--max-plies 10000`; the C++ tool parses
those flags directly, rejects unknown options, rejects non-legacy `max_plies`, and
no longer accepts environment-variable fixture overrides as an operator path.
`mcts-unit::exerciseCommandParserSurface` and
`mcts-unit::exerciseCppImperativeBuildPlan` cover the parser and rendered plan,
and the generated command docs/goldens include the new leaf.

Focused validation passed with:
`docker compose run --rm --build mcts mcts build legacy-fixtures --output-dir
/tmp/mcts-legacy-fixtures --seed 42 --games 1 --sims 4 --dry-run`,
`docker compose run --rm --build mcts mcts build legacy-fixtures --output-dir
/tmp/mcts-legacy-fixtures --seed 42 --games 1 --sims 4`,
`docker compose run --rm --build mcts mcts test mcts-unit`,
`docker compose run --rm --build mcts mcts lint all`,
`docker compose run --rm --build mcts mcts check-code`, and `git diff --check`.

### Closure Notes (Q6 fixture refresh)

The external legacy checkout is available at `/home/matt/MCTS_legacy` with clean
status at commit `97dd6ed7908a20234e3857c1bb4f8af46b507e0a`. A
whitespace-insensitive diff between `cpp-legacy/legacy-core/` and
`/home/matt/MCTS_legacy/backend/core/` reports only external build/binding/test
files (`SConstruct`, `_corridors_mcts.cpp`, `conio.h`, `minimal_examples/`,
`test.cpp`) outside the imported core, so the repository generator is operating
on the same legacy engine logic.

`test/golden/legacy/transcripts/amd64/` now contains ten `S_LP = 42`,
`S_LP_SIMS = 10000`, one-game fixtures generated through:
`docker compose run --rm --build --volume
/home/matt/MCTS/test/golden/legacy/transcripts:/workspace/MCTS/test/golden/legacy/transcripts
mcts mcts build legacy-fixtures --output-dir test/golden/legacy/transcripts
--seed 42 --games 10 --sims 10000`. The one-shot output mount is needed because
the root Compose service intentionally does not bind-mount the workspace; the
project build/run still enters through the supported `mcts build
legacy-fixtures` command. The stale transitional `arm64` fixture set was removed.

### Remaining Work

- The bounded canonical 2026-05-18 report-card run passed against canonical backend
  artefacts. No threshold changes were required; live FFI cohort promotion remains
  tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/unit_testing_policy.md` — finalise the five-stanza
  model, the property-test invariant list, the parser-test
  `execParserPure` discipline, the golden-test sentinel-placeholder discipline,
  and the `mcts test all` ordering.
- `documents/engineering/cli_command_surface.md` — finalise the full `mcts`
  command matrix, including `mcts test all`, `mcts play`, `mcts inspect
  replay`, and the `--format`/`--color` asymmetry for the TUI commands.
- `documents/engineering/determinism_contract.md` — extend with the four- and
  five-backend cohort assertions, the `LegacyParityRolloutOverflow` pre-flight
  check, and the equity-recompute-as-determinism-check property of
  `inspect replay`.
- `documents/engineering/haskell_code_guide.md` — record the gated `brick` /
  `vty` deviation: usage allowed only in the named TUI modules; no other
  module may import either library.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Test Stanzas section updates each row from
  `📋 Planned` to `✅ Done` as each sprint lands.
- `legacy-tracking-for-deletion.md` Retirement Protocol Reference is consulted
  but not yet enqueued — Phase 8 owns the retirement.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md)
- [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
