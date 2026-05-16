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

🔄 **Active**. All five Cabal test stanzas pass under the pinned
toolchain with the real FFI-backed engines for backends (i), (ii),
(iii); the cross-backend and legacy-parity stanzas accept a
well-formed `VerifyMismatch` outcome until backend (iv) Rust gets a
real engine (tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)).
Same-backend determinism (Q4), the legacy-parity preflight, the Q6
golden decode, and the per-backend live envelope checks all pass.
Remaining Phase `7` closure: the `brick`/`vty` interactive TUIs for
`mcts play` and `mcts inspect replay` (currently non-interactive
smoke paths), the doctrine-shaped report-card with measured Q1–Q7
evidence (currently logical placeholders), and the foreign-engine
recompute sidecar pipeline that ties Sprint 4.7's
`mcts_legacy_recompute_move` (and its (ii)/(iii) siblings) into
`mcts inspect divergence`. All three remain on the legacy tracking
ledger.

## Phase Summary

Phase `7` is where the determinism contract becomes enforceable end-to-end. With all
five backends live, the `mcts-cross-backend` stanza runs the four-backend `(ii)..(v)`
round-robin under `--rng cpp` and asserts bit-equal visit counts. The
`mcts-legacy-parity` stanza runs the 5-backend round-robin under the legacy parity
envelope (`max_plies = 10000`, fixture seed `S_LP = 42`). The `mcts-integration`
stanza covers same-backend determinism (Q4) across all five backends at three seeds
each, plus the Q6 golden-fixture comparison for backend (i) against
`test/golden/legacy/`. The `mcts-unit` stanza covers pure logic, parser tests via
`execParserPure`, property tests, golden tests, transcript codec roundtrips, and RNG
mixer properties. `mcts test all` is the Plan/Apply command that runs every cabal
stanza in order, runs the pinned report-card workload, and emits the tidy summary
block answering Q1–Q7. The `mcts play` and `mcts inspect replay` interactive TUIs
land here, completing the user-facing CLI surface.

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

1. `cabal test mcts-unit` passes.
2. `cabal test mcts-integration` passes with all five backends built (this
   sprint requires all of Phases 3–6 closure to be meaningful; a partial-backend
   smoke is acceptable interim but Q4/Q6 closure waits for full cohort).
3. Each test category produces a golden file or a property-test stanza
   citing the doctrine section it implements.

### Remaining Work

- Baseline landed: `mcts-unit` and `mcts-integration` Cabal stanzas exist and are
  wired against the logical backend baseline through in-stanza `tasty` runners.
  `cabal test mcts-integration` validates the logical five-backend same-backend
  determinism baseline at three seeds per backend, bounded FFI smoke drivers for all
  four foreign backends when their container-built shared libraries are present, live
  `mcts_<backend>_get_envelope` loading for those same foreign libraries, and the
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
- The `mcts-unit` runner now uses a `tasty` / `tasty-hunit` tree with the
  existing baseline assertions grouped under one test case. Split the baseline
  into the final fine-grained `tasty`, `tasty-quickcheck`, and golden-test
  organization.
- Strengthen integration tests to exercise the real `mcts` binary and FFI-backed
  backends rather than direct logical module calls.

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
  under `--rng cpp` at the report-card knob `G_V = 50` and `S_VERIFY = 10_000`.
- `mcts.cabal` declares the `mcts-legacy-parity` stanza. The stanza runs `mcts
  verify legacy-parity selfplay` across all five backends with `max_plies =
  10000`, `--rng cpp`, `--threading single`, fixture seed `S_LP = 42`, and
  `G_LP = 10` games.
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

1. `cabal test mcts-cross-backend` passes: the `(ii)..(v)` cohort agrees on
   visit counts at `G_V = 50`.
2. `cabal test mcts-legacy-parity` passes: the 5-backend cohort agrees on
   visit counts under the legacy parity envelope at `G_LP = 10`.
3. A synthetic injected mismatch in one backend produces `AppError
   VerifyMismatch` with the correct payload.
4. A synthetic `MAX_ROLLOUT_ITERS` overflow in backend (i) produces `AppError
   LegacyParityRolloutOverflow`.

### Remaining Work

- Baseline landed: `mcts-cross-backend` and `mcts-legacy-parity` Cabal stanzas exist
  and are wired against the logical five-backend cohort through in-stanza `tasty`
  runners. `cabal test mcts-cross-backend` exercises the four-backend `(ii)..(v)`
  round-robin under `--rng cpp` (single-threaded), and additionally asserts the
  cohort-constraint surface rejects (a) a cohort containing `cpp-legacy` and (b) a
  single-backend cohort, both with `AppError VerifyCohortTooSmall`.
  `cabal test mcts-legacy-parity` exercises the full-five-backend cohort under the
  legacy envelope and asserts a cohort missing `cpp-legacy` is rejected.
- Replace logical in-process comparisons with the real FFI-backed `(ii)..(v)` cohort
  and real legacy-parity cohort.
- Enforce the final `VerifyBackend` / `LegacyParityBackend` GADT shapes rather than
  the current ADT + parser checks.
- Add external legacy fixture coverage for Q6/Q7.

## Sprint 7.3: `mcts test all` Plan/Apply and Report-Card Summary 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Test.hs`,
`src/MCTS/CLI/Spec.hs` (Test subtree),
`src/MCTS/ReportCard.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Land `mcts test all` as the doctrine-mandatory canonical test command: a Plan/Apply
command that delegates to `cabal test`, runs the pinned POC report-card workload,
and emits the tidy summary block answering Q1–Q7 in one screenful.

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
  3. Run `cabal build all` warning-clean under the pinned toolchain. (`mcts lint
     haskell` is exercised inside the `mcts-haskell-style` Cabal stanza in step 4;
     it does not need its own plan step here.)
  4. Run `cabal test mcts-haskell-style` (pinned style-tool `fourmolu --mode check`
     + `hlint --with-group=default --with-group=extra` with only `Error:` findings
     blocking + `cabal format` round-trip).
  5. Run `cabal test mcts-unit`.
  6. Run `cabal test mcts-integration`.
  7. Run `cabal test mcts-cross-backend`.
  8. Run `cabal test mcts-legacy-parity`.
  9. Run the pinned report-card workload — the **seven invocations** below,
     enumerated verbatim from
     [../README.md → mcts test all → Report-card workload](../README.md)
     (README lines 223–246). The `--dry-run` plan must render these seven
     invocations literally, byte-for-byte against the README block (with the
     `$G_*` / `$S_*` knobs substituted from `cabal.project`):
     1. `mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading single --rng native --games $G_R --seed 42`
     2. `mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading multi --workers 8 --rng native --games $G_R --seed 42`
     3. `mcts bench selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading single --rng native --games $G_S --seed 42 --sims $S_BENCH`
     4. `mcts bench selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading multi --workers 8 --rng native --games $G_S --seed 42 --sims $S_BENCH`
     5. `mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games $G_V --seed 42 --max-plies 200`
     6. `mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games $G_V --seed 42 --max-plies 200 --sims $S_VERIFY`
     7. `mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games $G_LP --seed $S_LP --sims $S_LP_SIMS`
     Sprint 7.3 closes only when this enumeration is regenerated from a
     literal scrape of README lines 223–246 and a golden test asserts
     byte-equality with the rendered `--dry-run` plan.
  10. Render the tidy summary block from the collected `ReportCard` value.
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
  the typed list of cabal stanzas plus report-card subprocesses (modelled per
  [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../HASKELL_CLI_TOOL.md)); `apply :: Env -> TestPlan -> IO ExitCode`
  runs it. `--dry-run` prints the rendered plan and exits 0; `--plan-file
  <path>` writes the rendered plan for out-of-band review per
  [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md).
- **Prerequisites as Typed Effects.** All five backend artefacts present,
  PGO+BOLT profiles populated, `mimalloc` linked, GHC/Cabal pinned versions on
  `$PATH` are encoded as one `prerequisiteRegistry` per
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
   (`mcts lint files`, `mcts lint docs`, `cabal build all`); five `cabal test`
   stanzas (`mcts-haskell-style`, `mcts-unit`, `mcts-integration`,
   `mcts-cross-backend`, `mcts-legacy-parity`); and the seven pinned
   `mcts bench` / `mcts verify` report-card invocations enumerated above
   (rendering the summary block is a pure final step, not a subprocess). The
   seven report-card lines byte-equal the literal README workload block
   (lines 223–246) with the `$G_*` / `$S_*` knobs substituted from
   `cabal.project`.
2. `mcts test all` runs end-to-end with all five backends and emits the tidy
   summary block.
3. `mcts test all --format json` emits valid JSON that schema-checks against a
   pinned schema in `test/golden/report-card-schema.json`.
4. Failure of any cabal stanza, any verify cohort, or any report-card invocation
   exits non-zero.

### Remaining Work

- Baseline landed and validated: `mcts test all --dry-run`, `mcts test <stanza>`, a
  Plan/Apply runner, report-card rendering, and the pinned command sequence exist.
  The dry-run renders the fifteen typed `Subprocess` steps in order; recursive CLI
  steps route through `cabal exec mcts -- ...`, and the benchmark commands accept
  the comma-separated backend cohorts used by the report-card workload.
- Replace logical report-card placeholders with measured Q1-Q7 evidence from the real
  backends.
- Ensure the large pinned benchmark/verify workload remains practical for the final
  test mode and separate smoke vs full gates if needed.
- Add JSON/golden coverage for the final tidy report-card summary.

## Sprint 7.4: `mcts play` and `mcts inspect replay` TUIs ⏸️

**Status**: Blocked (cabal solver cannot resolve `brick` against GHC
9.14.1's installed `text 2.1.3` / `containers 0.8` / `base 4.22.0.0`
triple — every `brick`-eligible `config-ini` version conflicts with
those bounds). Closure requires an upstream `brick` / `config-ini`
release with compatible bounds. Tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
**Blocked by**: upstream `brick` / `config-ini` compatibility with GHC 9.14.1
**Implementation**: `src/MCTS/App.hs` (`runPlay` smoke path),
`src/MCTS/CLI/Inspect.hs` (`inspectReplay` smoke path),
`src/MCTS/CLI/Spec.hs` (Play and Inspect.Replay subtrees)
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Land the two interactive `brick` + `vty` TUI commands: `mcts play` for human-vs-AI
or AI-vs-AI spectate, and `mcts inspect replay` for forward/back navigation through
a stored transcript with equity recomputed on the fly.

### Deliverables

- `mcts.cabal` declares `brick` and `vty` as `build-depends` for the two TUI
  modules only. The deviation is recorded once in
  [00-overview.md → Doctrine Scope → Stack deviations](00-overview.md); no other
  module imports either library. The dependency check in Sprint 1.1's
  standardized library audit accepts these two as the documented exception.
- `src/MCTS/CLI/Tui/Board.hs` renders the 9×9 Corridors board, walls, and pawn
  positions using `brick`/`vty` widgets. `src/MCTS/CLI/Tui/Prompt.hs` carries
  the input prompt and the legacy move-notation parser.
- `src/MCTS/CLI/Play.hs` owns `mcts play` per the project
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
- `src/MCTS/CLI/Replay.hs` owns `mcts inspect replay <hash-prefix>` per the
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
    `g` jump-to-move prompt, `+`/`-` adjust top-N cutoff live, `?` toggle
    keybind overlay, `q` quit.
  - **Equity recomputation on the fly.** Navigating to move M reconstructs
    state by replaying moves 0..M-1 with the persistent tree carried forward,
    runs move M's search from the seed and budget in the transcript header,
    reads sorted actions back through the FFI / direct module call. The visit
    counts produced must equal the transcript record byte-for-byte (built-in
    determinism check that fires on every navigation).
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
3. A `cabal test mcts-unit` golden covers the TUI layout via a pinned
   `brick`-rendered string buffer.
4. `mcts lint haskell` rejects any `print` / `exitFailure` / non-`brick` terminal
   output in either TUI module.

### Remaining Work

- Baseline landed: `mcts play` runs a non-interactive logical game smoke path, and
  `mcts inspect replay <prefix>` opens a non-interactive transcript replay summary.
- Add the real `brick` / `vty` TUI modules, dependency gates, and rendering tests.
- Implement in-app `:hint`, `:undo`, `:save`, and `:quit` for `play`.
- Implement replay navigation, cached-state backtracking, multi-backend equity columns,
  and recompute-triggered sidecar writes.
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

`src/MCTS/Verify/Divergence.hs` now exposes a baseline transcript-pair metric for
`visit_disagreement_rate`, `move_disagreement_rate`, and `equity_l2_drift`.
`mcts inspect divergence <hash-prefix>` resolves and decodes the requested transcript,
discovers cached sidecar columns for the transcript hash, and renders metrics through
the shared helper instead of a fixed placeholder. `mcts-unit` covers the zero-divergence
case and a changed-move nonzero case.

`src/MCTS/Verify/Envelope.hs` also enforces the full logical v1 layered envelope fields
that exist today: cohort-level `host_arch`, envelope-version, `rng_source`,
`shared_rng_build_id`, and `cohort_config_hash` checks; backend-slot `backend`,
logical `build_id`, `engine_build_id`, `compiler_id`, `fp_flags`, `cpu_features`, and
`fp_env` checks; and `--allow-stale` downgrading of backend-slot mismatches to warnings.
The parser now carries `legacy-parity {rollouts|selfplay}` all the way to execution
instead of collapsing it to self-play.

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
  continues on visits. `CohortLevel` mismatches remain hard fails
  regardless.
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
  recorded `G_V = 50` games). Under `--rng cpp` every off-diagonal
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
- `mcts-cross-backend`: stale-cache test — write a transcript with
  the current `cpp-imperative` binary, rebuild `cpp-imperative` with
  a `compiler_version` bump (simulated), re-run `mcts verify`,
  assert `AppError EngineEnvelopeMismatch (BackendSlot
  CppImperative) CompilerVersion expected got` without
  `--allow-stale`, and assert success-with-warning when
  `--allow-stale` is passed.
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

### Remaining Work

- Extend layered envelope verification beyond the baseline fields to the full live
  backend envelope captured through per-backend FFI (`compiler_id`, `compiler_version`,
  `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, and shared RNG build id).
- Route `--allow-stale` warnings through richer structured JSON output once the final
  output renderer lands.
- Change `divergenceRate` from the baseline transcript-pair metric to the final
  `Transcript -> EqStream -> DivergenceMetrics` foreign-recompute scoring once
  per-backend recompute FFI lands.
- Calibrated threshold constants are present in `cabal.project`; add report-card
  divergence matrix rendering and keep the engineering-doc threshold table aligned.
- Add stale-cache, REPL overlay, and report-card integration tests against real backend
  envelopes and recompute sidecars.

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
