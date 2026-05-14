# Phase 1: Haskell CLI Surface, `CommandSpec`, Lint Stack

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

> **Purpose**: Stand up the Haskell CLI binary, the `CommandSpec` registry that
> generates every parser-and-doc artefact, the typed effect boundary
> (`Subprocess` / `Plan` / `prerequisiteRegistry` / `Env` / `AppError`), the output
> discipline, the lint stack, and the `mcts-haskell-style` test stanza, so every later
> phase plugs new subcommands into a stable typed scaffold.

## Phase Status

📋 Planned. No Haskell source exists on the supported path at Phase `0` closure.

## Phase Summary

Phase `1` establishes the Haskell CLI surface as the single execution surface for the
project. The `mcts` binary is the only operator-facing entry point; the parser is
generated from a separate `CommandSpec` registry that also feeds the markdown command
reference, the manpages, the shell completion scripts, the JSON command schema, and the
command tree rendering. The phase adopts every in-scope doctrine surface — `CommandSpec`
+ Generated Artifacts, Progressive Introspection, `Subprocess` as typed values,
`Plan / Apply`, `prerequisiteRegistry`, `ReaderT Env IO`, the single `AppError` ADT with
`renderError` boundary, Output Rules, Library-first layout, Toolchain pinning — and
declares the `mcts-haskell-style` test stanza that locks the formatter, hlint, and
`cabal format` round-trip in place. No backend logic, no engine, no transcript codec
lands in this phase; those phases plug into the scaffold built here.

## Sprint 1.1: Cabal Project, Toolchain Pin, Library-First Layout 📋

**Status**: Planned
**Implementation**: `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/App.hs`,
`docker/Dockerfile`, `docker/compose.yaml`
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/engineering/cli_command_surface.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Create the Cabal package, the pinned toolchain manifest, the library-first layout, and
the reproducible Docker development environment that every later sprint builds on.

### Deliverables

- `mcts.cabal` declares `tested-with: ghc ==9.14.1` per
  [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md). The
  `build-depends` set includes the doctrine's standardized stack:
  `optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter`,
  `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`, `path-io`, `typed-process`,
  `safe-exceptions`, `tasty`, `tasty-hunit`, `tasty-quickcheck`, `tasty-golden`,
  `temporary`. The two recorded deviations from doctrine are `brick` + `vty` (gated
  to the TUI command modules only) and the absence of `dhall` per
  [00-overview.md → Doctrine Scope → Stack deviations from doctrine](00-overview.md):
  the doctrine prescribes `dhall` for daemon configuration, daemon configuration
  is itself out of scope (the CLI is short-running only), so the dependency does
  not enter the stack.
- `cabal.project` declares `with-compiler: ghc-9.14.1` and `Cabal 3.16.1.0` per
  [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md), plus the
  report-card knobs (`G_R`, `G_S`, `G_V`, `G_LP`, `S_BENCH`, `S_VERIFY`, `S_LP_SIMS`,
  `S_LP`) as `program-default-options` or equivalent so Phase `7` can consume them.
- `app/Main.hs` is the thin entrypoint per
  [../HASKELL_CLI_TOOL.md → Project Structure](../HASKELL_CLI_TOOL.md):

  ```haskell
  module Main where
  import MCTS.App qualified as App
  main :: IO ()
  main = App.main
  ```

- `src/MCTS/App.hs` owns the `App.main` entrypoint; subsequent sprints add modules
  under `src/MCTS/`.
- `docker/Dockerfile` is single-stage `ubuntu:24.04`, installs `ghcup` in-image, pins
  GHC `9.14.1` and Cabal `3.16.1.0`, pins one LLVM version shared by GHC's `-fllvm`
  backend and BOLT post-link, pins GCC (latest stable on 24.04), installs `rustup`
  with a pinned Rust minor version, installs `mimalloc`, and avoids symlinked
  Haskell tool shims. `docker/compose.yaml` exposes the canonical
  `docker compose up -d` + `docker compose exec mcts bash` entrypoint declared in
  the project [README](../README.md).
- `cabal build all` succeeds inside the container with no warnings under the pinned
  toolchain.

### Validation

1. `cabal build all` succeeds inside the container, producing the placeholder `mcts`
   binary that prints a stub help message.
2. `cabal --version` reports `Cabal 3.16.1.0`; `ghc --version` reports `9.14.1`.
3. `app/Main.hs` is ≤ 5 lines of business logic; `src/MCTS/App.hs` carries
   `App.main`.
4. A static check of `mcts.cabal` confirms `tested-with: ghc ==9.14.1` and the
   doctrine's standardized library set (deviations explicitly annotated as the
   `brick`/`vty` TUI exception).

### Remaining Work

Not started.

## Sprint 1.2: `CommandSpec` Registry and Parser Generation 📋

**Status**: Planned
**Implementation**: `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`,
`src/MCTS/CLI/Command.hs`, `src/MCTS/CLI/Tree.hs`, `src/MCTS/CLI/Json.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Make the `CommandSpec` registry the source of truth and reduce the parser to a renderer
of it. Add progressive introspection (`mcts commands`, `mcts help`).

### Deliverables

- `src/MCTS/CLI/Spec.hs` defines `CommandSpec` and `OptionSpec` with the doctrine-named
  record fields per
  [../HASKELL_CLI_TOOL.md → Automatically Generated Documentation](../HASKELL_CLI_TOOL.md):
  `name`, `summary`, `description`, `children`, `options`, `examples` for
  `CommandSpec`; `longName`, `shortName`, `metavar`, `description`, `required` for
  `OptionSpec`. Every leaf `CommandSpec` carries at least one `Example` entry.
- `src/MCTS/CLI/Command.hs` declares the full ADT cascade verbatim per
  [../README.md → CLI command topology](../README.md) (lines 301–454). The
  declarations below are authoritative for every later phase that adds a new
  subcommand. Each constructor is given its concrete shape — no "mirroring the
  shape" delegation; later phases extend by adding constructors or fields, not by
  re-deriving the shape from the README.

  Top-level command:

  ```haskell
  data Command
    = Bench     BenchCommand
    | Verify    VerifyCommand
    | Play      PlayOptions
    | Inspect   InspectCommand
    | Test      TestCommand          -- inner constructors owned by Sprint 7.3
    | Lint      LintCommand
    | Docs      DocsCommand
    | Commands  CommandsOptions
    | Help      HelpOptions
    | CheckCode                      -- inner dispatcher owned by Sprint 1.4
    | Build     BuildCommand         -- inner constructors owned by Phases 4–6 (per-backend sprints)
    deriving stock (Show, Eq)
  ```

  > **Ownership note.** `CheckCode` lands in Sprint 1.4 alongside the
  > `src/MCTS/CheckCode.hs` dispatcher. The `Build BuildCommand` family is
  > filled in by the per-backend sprints: `BuildCppLegacy` in Phase 4
  > Sprint 4.1 (legacy-flags subset; no PGO/BOLT/mimalloc),
  > `BuildCppImperative` in Phase 5 Sprint 5.3, `BuildCppFunctional` and
  > `BuildRust` in Phase 6 Sprints 6.2 and 6.4. Sprint 1.2's obligation is
  > the eleven top-level constructors above; the `BuildCommand` family is
  > extended incrementally by the owning sprints.

  Subcommand families:

  ```haskell
  data BenchCommand
    = BenchRollouts BenchOptions
    | BenchSelfplay BenchOptions
    deriving stock (Show, Eq)

  data VerifyCommand
    = VerifyRollouts     VerifyOptions          -- cross-backend determinism, rollouts
    | VerifySelfplay     VerifyOptions          -- cross-backend determinism, self-play
    | VerifyLegacyParity LegacyParityOptions    -- 5-backend legacy-parity envelope
    deriving stock (Show, Eq)

  data InspectCommand
    = InspectList                    -- enumerate the local transcript cache
    | InspectShow   ShowOptions      -- dump one transcript, legacy notation
    | InspectReplay ReplayOptions    -- interactive TUI replay (Sprint 7.4)
    deriving stock (Show, Eq)

  data LintCommand
    = LintFiles   { lintWrite :: Bool }  -- whitespace, final newline, forbidden paths
    | LintDocs    { lintWrite :: Bool }  -- governed docs, generated sections
    | LintHaskell { lintWrite :: Bool }  -- fourmolu + hlint + cabal format
    | LintAll                            -- runs every lint above
    deriving stock (Show, Eq)

  data DocsCommand
    = DocsCheck                      -- compare rendered output against on-disk markers
    | DocsGenerate                   -- splice rendered output into markers (idempotent)
    deriving stock (Show, Eq)

  data BuildCommand
    = BuildCppLegacy                 -- legacy-flags subset (no PGO/BOLT/mimalloc); Phase 4 Sprint 4.1
    | BuildCppImperative             -- steelman: two-stage PGO + BOLT + mimalloc; Phase 5 Sprint 5.3
    | BuildCppFunctional             -- functional-style; same stack as cpp-imperative; Phase 6 Sprint 6.2
    | BuildRust                      -- cdylib; rustc PGO + BOLT + mimalloc; Phase 6 Sprint 6.4
    deriving stock (Show, Eq)

  data CommandsOptions = CommandsOptions
    { commandsTree :: Bool           -- --tree
    , commandsJson :: Bool           -- --json
    } deriving stock (Show, Eq)

  newtype HelpOptions = HelpOptions { helpTarget :: [Text] }
                        deriving stock (Show, Eq)
  ```

  Backend, workload, and axis enums:

  ```haskell
  data Backend    = CppLegacy | CppImperative | CppFunctional | Rust | Haskell
                    deriving stock (Show, Eq)

  data VerifyBackend = VCppImperative | VCppFunctional | VRust | VHaskell
                       deriving stock (Show, Eq)
                       -- (i) excluded at the type level per
                       -- [../README.md → Cross-backend verification](../README.md)
                       -- and [00-overview.md → Hard Constraints item 7](00-overview.md).

  data LegacyParityBackend = LpCppLegacy | LpCppImperative | LpCppFunctional
                           | LpRust | LpHaskell
                             deriving stock (Show, Eq)
                             -- LpCppLegacy required at parse time per
                             -- [00-overview.md → Hard Constraints item 8](00-overview.md);
                             -- cohorts without it fail with AppError VerifyCohortTooSmall.

  data LegacyParityWorkload = LpRollouts | LpSelfplay
                              deriving stock (Show, Eq)

  data RngSource  = NativeRng | CppRng
                    deriving stock (Show, Eq)

  data Threading  = SingleThreaded | MultiThreaded { workers :: Int }
                    deriving stock (Show, Eq)

  data Side       = Hero | Villain
                    deriving stock (Show, Eq)

  data SimBudget  = FixedSims Int                    -- same budget every move
                  | RampedSims Int Int               -- initial, then per-move
                    deriving stock (Show, Eq)
  -- CLI syntax: `--sims N` parses as `FixedSims N`; `--sims N0:N1` parses as
  -- `RampedSims N0 N1` (initial-move budget N0, per-move budget N1 thereafter).

  newtype TranscriptRef = TranscriptRef Text          -- sha256 prefix, git-style
                          deriving stock (Show, Eq)
  ```

  Options records, with the README-pinned defaults and parse-time invariants
  documented inline:

  ```haskell
  data BenchOptions = BenchOptions
    { benchBackends  :: NonEmpty Backend
    , benchRng       :: RngSource
    , benchThreading :: Threading       -- default: MultiThreaded { workers = 8 }
    , benchGames     :: Int
    , benchSeed      :: Word64
    , benchMaxPlies  :: Word16          -- default: 200; ignored for backend (i)
    , benchSims      :: SimBudget       -- default: FixedSims 10_000; ignored by bench rollouts
    } deriving stock (Show, Eq)

  data VerifyOptions = VerifyOptions
    { verifyBackends  :: NonEmpty VerifyBackend  -- (i) cannot appear (see VerifyBackend)
    , verifyThreading :: Threading              -- default: SingleThreaded
    , verifyGames     :: Int
    , verifySeed      :: Word64
    , verifyMaxPlies  :: Word16                 -- default: 200; pinned across the cohort
    , verifySims      :: SimBudget              -- default: FixedSims 10_000; ignored by verify rollouts
    -- RngSource pinned to CppRng on the verify subtree (no verifyRng field);
    -- attempting --rng native is rejected at parse time per Sprint 2.5.
    -- "must include >= 2 backends" is parse-time, surfaced as AppError VerifyCohortTooSmall.
    } deriving stock (Show, Eq)

  data LegacyParityOptions = LegacyParityOptions
    { lpBackends :: NonEmpty LegacyParityBackend  -- must include LpCppLegacy (parse-time check)
    , lpWorkload :: LegacyParityWorkload          -- rollouts or self-play
    , lpGames    :: Int
    , lpSeed     :: Word64                        -- fixture seed; default S_LP = 42
    , lpSims     :: SimBudget                     -- default: FixedSims 10_000; ignored for LpRollouts
    -- max_plies pinned to MAX_ROLLOUT_ITERS = 10000 (not user-overridable).
    -- RngSource pinned to CppRng. Threading pinned to SingleThreaded.
    -- (i) throwing or its longest rollout reaching the cap → AppError
    -- LegacyParityRolloutOverflow (seed, game_index, move_index).
    } deriving stock (Show, Eq)

  data PlayOptions = PlayOptions
    { playBackend  :: Backend
    , playSide     :: Side
    , playVs       :: Maybe Backend         -- Just b → AI-vs-AI; Nothing → human plays
    , playRng      :: RngSource
    , playSeed     :: Maybe Word64          -- Nothing → fresh random, recorded in transcript
    , playSims     :: SimBudget
    , playMaxPlies :: Word16                -- default: 200; ignored if playBackend is (i)
    -- no threading field: a single game is always single-threaded internally
    } deriving stock (Show, Eq)

  data ShowOptions = ShowOptions
    { showRef        :: TranscriptRef
    , showTopN       :: Int                -- default 10; 0 = all
    , showWithEquity :: Bool               -- default False; True re-runs search
    } deriving stock (Show, Eq)

  data ReplayOptions = ReplayOptions
    { replayRef         :: TranscriptRef
    , replayTopN        :: Int             -- default 10; 0 = all; live-adjustable in-app
    , replayCacheStates :: Int             -- default 20; in-memory MCTS state cache size
    } deriving stock (Show, Eq)
  ```

  `TestCommand = TestAll | TestStanza Text` is declared by
  [phase-7-cross-backend-verify-and-report-card.md → Sprint 7.3](phase-7-cross-backend-verify-and-report-card.md)
  alongside the `mcts test all` runner; the top-level `Command` constructor
  `Test TestCommand` above is the only Phase 1 obligation.

- `src/MCTS/CLI/Parser.hs` generates the `optparse-applicative` `Parser` from the
  `CommandSpec` registry. The parser is **not** the source of truth.
- `mcts commands` (flat), `mcts commands --tree`, `mcts commands --json`, and
  `mcts help <subcommand>` are wired per
  [../HASKELL_CLI_TOOL.md → Progressive Introspection](../HASKELL_CLI_TOOL.md). The
  `--json` form is the externally-stable schema for downstream tooling.
- `src/MCTS/CLI/Tree.hs` and `src/MCTS/CLI/Json.hs` carry the renderers; both share
  the same `CommandSpec` value as input.
- The twelve worked invocations in
  [../README.md → CLI command topology → Concrete invocations](../README.md)
  (lines 460–495) are bound to the registry as seed `Example` entries on the
  corresponding `CommandSpec` leaves so the `mcts <subcommand> --help` text, the
  `documents/cli/commands.md` rendering, and the `mcts commands --json` schema
  all carry them. Sprint 7.1's `mcts-unit` golden over `mcts commands --json`
  pins the invocations into the externally-stable schema. The invocations are:
  `bench rollouts` (5-backend, ST, native RNG, 100k games);
  `bench selfplay --backend haskell` (default 8 workers);
  `bench selfplay --workers 32`;
  `verify selfplay --backend cpp-imperative,rust,haskell` (cross-backend);
  `play --backend haskell --side hero --sims 10000` (human vs AI);
  `play --backend haskell --side villain --vs cpp-imperative --sims 10000`
  (Haskell-vs-(ii) spectate);
  `inspect list`;
  `inspect show 7a2f --top 10 --with-equity`;
  `inspect replay 7a2f --top 15`;
  `check-code` (the canonical doctrine-alignment gate);
  `build cpp-imperative --dry-run` (Plan/Apply prints the typed Subprocess
  sequence and exits 0);
  `build cpp-imperative` (Plan/Apply executes the plan and produces
  `cpp-imperative/libmcts_cpp_imperative.so`).

### Validation

1. `mcts commands` lists every subcommand; `mcts commands --tree` renders the tree
   per the README example; `mcts commands --json` emits valid JSON that schema-checks
   against an enumerated set of expected keys.
2. Parser tests via `execParserPure` cover leaf happy paths and unhappy paths
   (Sprint 7.1 owns the `mcts-unit` stanza placement; this sprint provides the
   `execParserPure`-friendly parser shape).
3. Every leaf `CommandSpec` node has at least one `Example` entry — a property
   test in Sprint 7.1 enforces this; this sprint's deliverable provides the
   examples.

### Remaining Work

Not started.

## Sprint 1.3: Generated Artefacts Registry and Docs Pipeline 📋

**Status**: Planned
**Implementation**: `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Sections.hs`,
`src/MCTS/Generated/Paths.hs`, `documents/cli/commands.md`,
`share/man/man1/mcts.1`, `share/man/man1/mcts-*.1`, `share/completion/bash/mcts`,
`share/completion/zsh/_mcts`, `share/completion/fish/mcts.fish`
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/documentation_standards.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Implement the paired `mcts docs check` and `mcts docs generate` commands plus the
`GeneratedSectionRule` and `trackingGeneratedPaths` registries that drive every
text-artefact derived from the `CommandSpec` registry.

### Deliverables

- `src/MCTS/Generated/Sections.hs` declares the `GeneratedSectionRule` registry per
  [../HASKELL_CLI_TOOL.md → Generated Artifacts → The generated-section
  registry](../HASKELL_CLI_TOOL.md). Each rule names a target file, a marker key, a
  pure renderer, and a source-module owner.
- `src/MCTS/Generated/Paths.hs` declares the `trackingGeneratedPaths` registry for
  fully-generated files: `documents/cli/commands.md`, `share/man/man1/mcts.1`,
  `share/man/man1/mcts-*.1`, `share/completion/bash/mcts`,
  `share/completion/zsh/_mcts`, `share/completion/fish/mcts.fish`. Hand edits to
  these paths fail `mcts lint files`.
- `src/MCTS/CLI/Docs.hs` owns `mcts docs check` (compare rendered output against
  on-disk markers and tracked paths, fail on drift with the doctrine's
  three-element error message: file path, marker key, literal remedy
  `` `mcts docs generate` ``) and `mcts docs generate` (splice the renderer output
  between the marker pair, idempotent).
- `mcts docs generate` is a Plan/Apply command per
  [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md): the plan
  enumerates the marker substitutions to splice and the `trackingGeneratedPaths`
  writes that will be applied. `--dry-run` renders the plan to stdout and exits
  0 without touching the worktree; `--plan-file <path>` writes the rendered
  plan to disk for out-of-band review per
  [00-overview.md → Hard Constraints item 24](00-overview.md). Both flags are
  required on every Plan/Apply command.
- Marker conventions follow
  [../HASKELL_CLI_TOOL.md → Generated Artifacts → Marker conventions](../HASKELL_CLI_TOOL.md):
  `<!-- mcts:<key>:start -->` / `<!-- mcts:<key>:end -->` for Markdown,
  `// mcts:<key>:start` / `// mcts:<key>:end` for Haskell, `# mcts:<key>:start` /
  `# mcts:<key>:end` for YAML.
- The renderer is deterministic: no timestamps, no random IDs, no locale-dependent
  ordering, no terminal-width-dependent wrapping, no environment-dependent paths.

### Validation

1. `mcts docs check` exits 0 on a freshly-generated worktree.
2. `mcts docs generate` is idempotent: running it twice produces no diff.
3. Hand-editing a marker region produces a `mcts docs check` failure with the
   three-element error message.
4. Hand-editing a `trackingGeneratedPaths` entry produces an `mcts lint files`
   failure.

### Remaining Work

Not started.

## Sprint 1.4: Lint Stack, `fourmolu.yaml`, `mcts-haskell-style` Stanza 📋

**Status**: Planned
**Implementation**: `fourmolu.yaml`, `.hlint.yaml`, `src/MCTS/Lint.hs`,
`src/MCTS/CheckCode.hs`, `test/haskell-style/Main.hs`, `mcts.cabal`
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Lock the formatter, linter, `cabal format` round-trip, forbidden-path registry, and
forbidden-symbol HLint rules behind the `mcts-haskell-style` test stanza plus the
`mcts lint` family.

### Deliverables

- `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings per
  [../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality Stack → Pinned
  fourmolu.yaml](../HASKELL_CLI_TOOL.md): `indentation`, `column-limit`,
  `function-arrows`, `comma-style`, `import-export-style`, `indent-wheres`,
  `record-brace-space`, `newlines-between-decls`, `haddock-style`, `let-style`,
  `in-style`, `unicode`. `respectful: true` follows.
- `.hlint.yaml` at repo root carries the doctrine's nested-case warnings plus
  negative-space rules: `print`, `exitFailure`, `Text.IO.putStrLn`, direct terminal
  formatting forbidden outside `src/MCTS/CLI/Output.hs`; `callProcess`,
  `readCreateProcess`, `System.Process.createProcess`, `System.Process.proc`,
  `System.Process.shell` forbidden outside `src/MCTS/Subprocess.hs`.
- `src/MCTS/Lint.hs` owns the `mcts lint files|docs|haskell|all` runners.
  `mcts lint files` enforces the `forbiddenPathRegistry` (`.github/workflows/`,
  `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, `pre-commit-*.yaml`, root
  `Makefile`, root `justfile`, root `Taskfile.yml`) plus the
  `trackingGeneratedPaths` no-hand-edit check, per
  [../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../HASKELL_CLI_TOOL.md).
- `src/MCTS/CheckCode.hs` owns `mcts check-code`, which dispatches lint, formatter,
  hlint, warning-clean `cabal build all`, and the `mcts docs check` gate in one
  command per
  [../HASKELL_CLI_TOOL.md → CLI surface](../HASKELL_CLI_TOOL.md).
- `src/MCTS/CLI/Command.hs` gains the `CheckCode` constructor on the top-level
  `Command` ADT and a matching `CommandSpec` leaf in the registry per
  [Sprint 1.2 ownership note](#sprint-12-commandspec-registry-and-parser-generation-).
  The leaf carries a single `Example` (literal `mcts check-code`) so the
  `mcts <subcommand> --help`, `documents/cli/commands.md`, and `mcts commands --json`
  outputs all reflect the new surface.
- `mcts.cabal` declares the `mcts-haskell-style` test-suite with
  `type: exitcode-stdio-1.0`, `main-is: Main.hs`, `hs-source-dirs: test/haskell-style`.
  The suite asserts `fourmolu --mode check` succeeds, `hlint --with-group=default
  --with-group=extra` (with `.hlint.yaml` picked up from the repo root) succeeds,
  and `cabal format` round-trips byte-equally via a temp file. The exact `hlint`
  flag pair is pinned per
  [../README.md → `mcts test all` → Test-suite stanzas](../README.md) and
  [system-components.md → Test Stanzas](system-components.md).

### Validation

1. `cabal test mcts-haskell-style` passes.
2. `mcts lint haskell` exits 0; `mcts lint files` exits 0; `mcts lint all` exits 0.
3. `mcts check-code` exits 0 on a clean worktree.
4. A synthetic violation (e.g. a `print` call in `src/MCTS/App.hs`) is rejected by
   `mcts lint haskell` with a clear hlint error.

### Remaining Work

Not started.

## Sprint 1.5: `Plan / Apply` Boundary 📋

**Status**: Planned
**Implementation**: `src/MCTS/Plan.hs`, `src/MCTS/CLI/Command.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Implement the doctrine's `Plan / apply` shape so `mcts test all`, the PGO+BOLT build
harness, and any later state-mutating command get `--dry-run` and `--plan-file <path>`
for free.

### Deliverables

- `src/MCTS/Plan.hs` defines the generic `Plan a` ADT and the
  `build :: inputs -> Either AppError (Plan a)` /
  `apply :: Env -> Plan a -> IO ExitCode` pair per
  [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md).
- Every Plan/Apply subcommand in the `CommandSpec` registry carries `--dry-run`
  (renders the plan and exits 0) and `--plan-file <path>` (writes the rendered plan
  for out-of-band review) as `OptionSpec` entries.
- The rendered plan is deterministic: golden-testable, no timestamps, no
  environment-dependent paths.

### Validation

1. A trivial Plan/Apply command (e.g. a stub Sprint-1.7 `mcts toolchain check`)
   supports `--dry-run` and `--plan-file <path>` and round-trips through golden
   tests.
2. A property test (Sprint 7.1) asserts `render is deterministic` over the `Plan`
   renderer.

### Remaining Work

Not started.

## Sprint 1.6: `Subprocess` ADT and Interpreter 📋

**Status**: Planned
**Implementation**: `src/MCTS/Subprocess.hs`, `.hlint.yaml`
**Docs to update**: `documents/engineering/haskell_code_guide.md`,
`documents/engineering/code_quality.md`

### Objective

Implement the typed `Subprocess` boundary so the PGO+BOLT build harness, the FFI
shared-library builds, and every subprocess call site go through one IO boundary.

### Deliverables

- `src/MCTS/Subprocess.hs` declares the `Subprocess` record per
  [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../HASKELL_CLI_TOOL.md):

  ```haskell
  data Subprocess = Subprocess
    { subprocessPath             :: FilePath
    , subprocessArguments        :: [Text]
    , subprocessEnvironment      :: Maybe [(Text, Text)]
    , subprocessWorkingDirectory :: Maybe FilePath
    }
    deriving stock (Eq, Show)
  ```

- Pure `renderSubprocess :: Subprocess -> Text` for logs, `--dry-run`, golden tests.
- Interpreter API: `runStreaming :: Subprocess -> IO (Either AppError ExitCode)` and
  `capture :: Subprocess -> IO (Either AppError ProcessOutput)`. These are the **only**
  IO boundary for subprocess execution.
- `.hlint.yaml` rules refuse `callProcess`, `readCreateProcess`,
  `System.Process.createProcess`, `System.Process.proc`, `System.Process.shell`, and
  `typed-process` smart constructors outside `src/MCTS/Subprocess.hs` per
  [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values
  → Forbidden patterns](../HASKELL_CLI_TOOL.md).

### Validation

1. `cabal build all` succeeds with the `Subprocess` module compiled.
2. A synthetic violation (e.g. a `callProcess` call in `src/MCTS/Lint.hs`) is
   rejected by `mcts lint haskell`.
3. A golden test of `renderSubprocess` over a sample value passes.

### Remaining Work

Not started.

## Sprint 1.7: `prerequisiteRegistry` 📋

**Status**: Planned
**Implementation**: `src/MCTS/Prerequisite.hs`, `mcts.cabal` (consumer modules)
**Docs to update**: `documents/engineering/haskell_code_guide.md`,
`documents/engineering/code_quality.md`

### Objective

Implement the typed-DAG prerequisite registry so every toolchain check (GCC, LLVM,
BOLT, `rustc`, `mimalloc`, `ghcup`, the PGO profile directories) runs through one
typed boundary and emits structured remedy hints on failure.

### Deliverables

- `src/MCTS/Prerequisite.hs` defines `PrerequisiteNode` with `nodeId`,
  `nodeDescription`, dependencies, and a remedy hint per
  [../HASKELL_CLI_TOOL.md → Prerequisites as Typed Effects](../HASKELL_CLI_TOOL.md).
- The Phase `1` registry has stub nodes for the future toolchain prereqs; Phases
  `3`–`6` populate the concrete nodes (`ghc-9.14.1`, `cabal-3.16.1.0`, `g++-23`,
  `rustc-stable`, `mimalloc-static`, `bolt`, `pgo-profile-dirs`).
- The transitive closure runs before `apply`; a single unmet node emits
  `AppError PrerequisiteUnmet` carrying the failing `nodeId`, `nodeDescription`, and
  remedy hint.

### Validation

1. A unit test exercises the transitive-closure pass with a synthetic unmet node and
   asserts the `AppError PrerequisiteUnmet` payload.
2. A property test asserts the registry has no cycles.

### Remaining Work

Not started.

## Sprint 1.8: `Env` Record and `ReaderT App` 📋

**Status**: Planned
**Implementation**: `src/MCTS/App.hs`, `src/MCTS/Env.hs`, every CLI runner
**Docs to update**: `documents/engineering/haskell_code_guide.md`

### Objective

Thread one shared `Env` record through every command runner via `ReaderT Env IO` per
[../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md).

### Deliverables

- `src/MCTS/Env.hs` declares `data Env = Env { ... }` with fields for the
  log handle, the cache root, the parsed CLI options, the `CommandSpec` registry, the
  `GeneratedSectionRule` registry, the `trackingGeneratedPaths` registry, and the
  `prerequisiteRegistry` per
  [../HASKELL_CLI_TOOL.md → Application Environment](../HASKELL_CLI_TOOL.md).
  Optional test-hook fields with no-op production defaults are admitted from
  [../HASKELL_CLI_TOOL.md → Test hooks in Env](../HASKELL_CLI_TOOL.md) — that
  subsection lives inside the otherwise-out-of-scope daemon section
  ([00-overview.md → Out of scope](00-overview.md)), but the test-hook pattern
  itself is portable to short-running CLIs and is required for the Phase 3
  Sprint 3.5 monotonic-clock bracket assertion. No other daemon discipline
  (lifecycle, `BootConfig`/`LiveConfig` split, hot reload, signal handling,
  `/healthz` endpoints) is admitted.
- `newtype App a = App { runApp :: ReaderT Env IO a }` plus the standard typeclass
  instances.
- Every command runner under `src/MCTS/CLI/` has type `... -> App ()` or
  `... -> App ExitCode`; no command runner takes an `Env` explicitly.

### Validation

1. `cabal build all` succeeds.
2. Every command runner module imports `MCTS.Env` and uses `App`.

### Remaining Work

Not started.

## Sprint 1.9: `AppError`, `renderError`, Output Discipline 📋

**Status**: Planned
**Implementation**: `src/MCTS/Error.hs`, `src/MCTS/CLI/Output.hs`, `.hlint.yaml`
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Implement the single `AppError` ADT, the `renderError` boundary, and the `--format` /
`--color` output discipline.

### Deliverables

- `src/MCTS/Error.hs` declares the single `AppError` ADT covering the canonical
  15-variant set:
  `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
  `VerifyMismatch`, `VerifyCohortTooSmall`, `RecomputeMismatch`,
  `LegacyParityRolloutOverflow`,
  `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidMove`, plus the generic catchalls per
  [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md). The set
  matches [../README.md → Output and error discipline](../README.md) exactly;
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, and
  `EngineEnvelopeMismatch` are the MCTS-specific failure surfaces enumerated
  alongside the user-facing variants.
  Semantic distinctions:
  - `SubprocessFailed` is reserved for the typed `Subprocess` boundary
    (`runStreaming` / `capture` non-zero exit).
  - `FFIFailure` is reserved for C ABI exceptions surfaced through the FFI bridge
    (Phase 4 Sprint 4.2 owns the constructor's payload shape).
  - `TranscriptFormatUnsupported` is raised by `MCTS.Transcript.Codec.decode`
    when a transcript carries a non-zero `flags u32` (reserved for future format
    extensions); see
    [phase-2-transcript-codec-and-determinism.md → Sprint 2.1](phase-2-transcript-codec-and-determinism.md).
  - `ArchEnvelopeMismatch` is raised when a verify cohort or `inspect` comparison
    spans more than one `host_arch` per
    [../README.md → Architecture envelope](../README.md); see
    [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md).
  - `EngineEnvelopeMismatch` is raised by `mcts verify` when the layered
    engine-envelope check finds a disagreement: either a cohort-invariant
    field (`host_arch`, `rng_source`, `shared_rng_build_id`,
    `run_config_hash`) disagrees across the cohort, or a per-backend-slot
    field (`engine_build_id`, `compiler_id`, `compiler_version`,
    `fp_flags`, `libm_id`, `cpu_features`, `fp_env`) disagrees between
    a cached transcript and the live binary for the same backend slot.
    Payload carries an `EnvelopeMismatchScope` discriminator
    (`CohortLevel | BackendSlot Backend`) plus the field, expected,
    and got values. Cohort-level mismatches are unconditionally hard
    fails; per-backend-slot mismatches are downgradeable to a warning
    via `mcts verify --allow-stale`. See
    [../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md).
  - `DocsCheckDrift` is raised by `mcts docs check` when a marker region's
    on-disk slice differs from the renderer's output.
  - `RecomputeMismatch` is raised by `src/MCTS/Engine/Recompute.hs` when a
    `mcts inspect show` / `inspect replay` recompute under `--rng cpp`
    disagrees with the transcript's recorded visits at a move; payload is
    `(Backend, GameId, MoveIndex, recomputed_record, recorded_record)`.
    Distinct from `VerifyMismatch` (cross-backend) because the live backend
    has become non-deterministic against its own prior recording — a bug
    bell, not an expected outcome. See
    [../documents/engineering/determinism_contract.md → Recompute Mismatch Output](../documents/engineering/determinism_contract.md).
- `src/MCTS/CLI/Output.hs` defines `renderError :: AppError -> Text` plus the
  `--format json|table|plain` and `--color auto|always|never` / `--no-color`
  renderers per
  [../HASKELL_CLI_TOOL.md → Output Rules](../HASKELL_CLI_TOOL.md). Default format is
  `table` on a TTY, `plain` otherwise. The TUI commands (`mcts play`,
  `mcts inspect replay`) own their own rendering and ignore both flag families.
- `.hlint.yaml` rules refuse `print`, `exitFailure`, `Text.IO.putStrLn`,
  `Text.IO.hPutStrLn` (other than to `stderr` inside `Output.hs`), and direct
  terminal-formatting calls outside `src/MCTS/CLI/Output.hs`.

### Validation

1. Golden tests over `renderError` for each `AppError` variant.
2. A synthetic violation (e.g. a `print` outside `Output.hs`) is rejected by
   `mcts lint haskell`.
3. `mcts <subcommand> --format json` emits valid JSON; `mcts <subcommand> --format
   table` emits a TTY-friendly table; `mcts <subcommand> --format plain` emits
   newline-delimited output suitable for piping.

### Remaining Work

Not started.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — fill in the MCTS-specific command
  matrix derived from `CommandSpec`; defer to the doctrine on Command Topology and
  Progressive Introspection.
- `documents/engineering/code_quality.md` — describe `mcts check-code` /
  `mcts lint *` / `mcts docs check`; defer to the doctrine on Lint, Format,
  Code-Quality Stack, Generated Artifacts, and Forbidden Surfaces.
- `documents/engineering/unit_testing_policy.md` — describe the `mcts-haskell-style`
  stanza and the lint-first ordering of `mcts test all`; defer to the doctrine on
  Test Organization.
- `documents/engineering/haskell_code_guide.md` — describe how the project uses
  `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `Env`, and `AppError`; defer
  to the doctrine on each pattern.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `documents/cli/commands.md` (generated by Sprint `1.3`) is reachable from the
  `documents/engineering/README.md` index.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
