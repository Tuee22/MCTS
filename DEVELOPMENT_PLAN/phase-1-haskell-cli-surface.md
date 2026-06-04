# Phase 1: Haskell CLI Surface, `CommandSpec`, Lint Stack

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Stand up the Haskell CLI binary, the `CommandSpec` registry that
> drives command topology and generated CLI artefacts, the typed effect boundary
> (`Subprocess` / `Plan` / `prerequisiteRegistry` / `Env` / `AppError`), the output
> discipline, the lint stack, and the `mcts-haskell-style` test stanza, so every later
> phase plugs new subcommands into a stable typed scaffold.

## Phase Status

✅ **Done after focused reclosures.** A Cabal package, thin `app/Main.hs`,
`src/MCTS/` library layout, manual `CommandSpec` registry, parser, output/error
boundary, typed `Subprocess` wrapper, Plan/Apply helpers, prerequisite skeleton,
lint/docs commands, and `mcts-haskell-style` stanza exist;
`hostbootstrap run test all` is the baseline host validation gate under the
pinned toolchain. Phase `1`
reopened on 2026-05-21 for Sprint `1.10` and reclosed the same day after
generated-document metadata enforcement, `check-code` dispatch ordering, and
style-policy wording matched the implemented lint stack exactly. Sprint `1.11`
reclosed README/lint-write contract alignment on 2026-05-24, and Sprint `1.12`
reclosed generated `bench rollouts` summary wording on 2026-05-27 so generated
command docs match the implemented legacy played-game workload. Phase `1`
reopened again on 2026-06-03 for Sprint `1.13` after operator use showed the CLI
was not fully self-describing. Sprint `1.13` reclosed the same day after adding
choice-aware registry metadata, focused `optparse-applicative` help, value-aware
parse errors, enriched command JSON, regenerated Markdown/manpage/completion artefacts,
and semantic parser/help/JSON/generated-doc tests. Backend logic and transcript
semantics remain owned by later phases; this reopening was limited to
parser/help/command-metadata introspection. Phase `1` reopened again on
2026-06-03 on three narrow sub-surfaces driven by the Phase 9 hostbootstrap
adoption (see [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md)):
Sprint `1.14` updated the toolchain pin doctrine and source surfaces from
GHC `9.14.1` + Cabal `3.16.1.0` to GHC `9.12.4` + Cabal `3.16.1.0`;
Sprint `1.15` replaced the canonical invocation shape
`docker compose run --rm mcts mcts <command>` with
`hostbootstrap run <mcts-args>` backed by `hostbootstrap.dhall` and
deleted `compose.yaml`; Sprint `1.16` collapsed the lint stack's
separate formatter-tools GHC into the project GHC. All three sprints
reclosed on 2026-06-04 after `hostbootstrap run test all` passed.
Phase `1` reopened again on 2026-06-04 for Sprint `1.17` after operator use
showed that the play substrate was still not fully self-describing in the
command-use sense: `BACKEND` metavars appeared without enough operational text,
`mcts play` did not clearly teach human-vs-AI versus AI-vs-AI spectator mode,
and generated command docs listed flags without enough command workflow
description. Sprint `1.17` reclosed the same day after adding action-oriented
leaf-command descriptions, play examples, notes, parser-help text, generated docs,
README guidance, and semantic renderer/help tests. Sprints `1.1` through `1.17`
remain closed on their owned CLI surface, `CommandSpec`, self-describing
introspection, command-use text, lint stack, and toolchain-baseline surfaces;
their closure narratives are preserved.

## Phase Summary

Phase `1` establishes the Haskell CLI surface as the single execution surface for the
project. The `mcts` binary is the only operator-facing entry point; `CommandSpec`
is the registry for command topology, command-tree rendering, examples, generated
markdown command reference, manpage command list, shell-completion metadata, and JSON
command schema. Sprint `1.13` extends that registry with typed choice/default/note
metadata and makes the explicit leaf option parsers consume the same value sets, so
`optparse-applicative` remains the parser implementation while the CLI becomes
fully introspectable through `--help`, `mcts help`, `mcts commands --json`,
generated docs, and completions. Sprint `1.17` makes the same surfaces
action-oriented: command descriptions explain how to use a command, not only which
flags exist, with the `mcts play` human/spectator substrate as the forcing case.
`Parser.hs` renders the top-level/subcommand topology from that registry while
retaining explicit semantic parsers for leaf options.
The phase adopts
every in-scope doctrine surface — `CommandSpec`
+ Generated Artifacts, Progressive Introspection, `Subprocess` as typed values,
`Plan / Apply`, `prerequisiteRegistry`, `ReaderT Env IO`, the single `AppError` ADT with
`renderError` boundary, Output Rules, Library-first layout, Toolchain pinning — and
declares the `mcts-haskell-style` test stanza that locks the formatter, hlint, and
`cabal format` round-trip in place. No backend logic, no engine, no transcript codec
lands in this phase; those phases plug into the scaffold built here.

## Sprint 1.1: Cabal Project, Toolchain Pin, Library-First Layout ✅

**Status**: Done
**Implementation**: `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/App.hs`,
`docker/Dockerfile`, `hostbootstrap.dhall` (Phase 9 Sprint `9.2` deleted the
prior `compose.yaml` per [Sprint 1.15](#sprint-115-canonical-command-shape--hostbootstrap-run-mcts-command))
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/engineering/cli_command_surface.md`, `DEVELOPMENT_PLAN/system-components.md`

### Objective

Create the Cabal package, the pinned toolchain manifest, the library-first layout, and
the reproducible Docker development environment that every later sprint builds on.

### Deliverables

- `mcts.cabal` declares `tested-with: ghc ==9.12.4` per
  [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md). The
  current `build-depends` set includes the doctrine's standardized non-TUI stack:
  `optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter`,
  `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`, `path-io`, `typed-process`,
  `safe-exceptions`, `tasty`, `tasty-hunit`, `tasty-quickcheck`, `temporary`,
  plus the documented `brick` + `vty` TUI deviation now used by
  `MCTS.CLI.Tui.{Board,Play,Replay}`. The other recorded deviation is the absence
  of `dhall` per
  [00-overview.md → Doctrine Scope → Stack deviations from doctrine](00-overview.md):
  the doctrine prescribes `dhall` for daemon configuration, daemon configuration
  is itself out of scope (the CLI is short-running only), so the dependency does
  not enter the stack.
- `cabal.project` declares `with-compiler: ghc-9.12.4` and `Cabal 3.16.1.0` per
  [../HASKELL_CLI_TOOL.md → Toolchain pinning](../HASKELL_CLI_TOOL.md). The current
  file mirrors the report-card constants (`G_R`, `G_S`, `G_V`, `G_LP`,
  `S_BENCH`, `S_VERIFY`, `S_LP_SIMS`, `S_LP`) as pinned comments. The current
  `MCTS.CLI.Test` baseline owns the executable constants directly; making the
  comments machine-readable is not part of the closed operator path.
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
- `docker/Dockerfile` inherits `FROM ${BASE_IMAGE}` per
  [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md) (the
  `hostbootstrap` CLI passes the arch-specific tag
  `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>`), which ships GHC
  `9.12.4` and Cabal `3.16.1.0`, one LLVM version shared by GHC's `-fllvm`
  backend and BOLT post-link (`19`), `clang-19`,
  `libclang-rt-19-dev`, Rust `1.95.0`, `mimalloc`, fourmolu `0.19.0.1`,
  hlint `3.10`, and the warm Cabal store. The project Dockerfile adds
  only what the base does not ship: the source copy, the seven Cabal exe
  builds, and the four `mcts build <backend>`
  invocations. The lint stack uses the single project GHC `9.12.4`. The
  Dockerfile prebuilds the executable with tests and benchmarks enabled,
  installs all Cabal test-suite executables plus the `mcts-criterion`
  benchmark executable, and leaves runtime commands consuming image-local
  artefacts instead of compiling on first use. Host-level fallback to ambient
  Fourmolu, HLint, Cabal, GHC, or backend toolchains is unsupported.
  Root-level `hostbootstrap.dhall` declares the project config the
  `hostbootstrap` CLI reads to dispatch the canonical invocation
  `hostbootstrap run <mcts-args>` per Sprint `1.15`; there is no
  long-running daemon container, bind mount, or `sleep infinity` command.
- `hostbootstrap run check-code` succeeds with no warnings under the
  pinned toolchain.

### Validation

1. `hostbootstrap run check-code` succeeds, proving the container
   image carries the installed `mcts` binary and the container-owned lint/style gate.
2. `cabal --version` reports `Cabal 3.16.1.0`; `ghc --version` reports `9.12.4`.
3. `app/Main.hs` is ≤ 5 lines of business logic; `src/MCTS/App.hs` carries
   `App.main`.
4. A static check of `mcts.cabal` confirms `tested-with: ghc ==9.12.4` and the
   doctrine's standardized library set (deviations explicitly annotated as the
   `brick`/`vty` TUI exception).

### Closure Notes

- Baseline landed: `mcts.cabal`, `cabal.project`, thin `app/Main.hs`,
  `src/MCTS/App.hs`, root formatter/lint files, and Docker scaffolding exist.
- The full project dependency set now appears in `mcts.cabal`
  (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter`,
  `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`, `path-io`,
  `typed-process`, `safe-exceptions`, `tasty`, `tasty-hunit`,
  `tasty-quickcheck`, `temporary`). The recorded `brick` /
  `vty` TUI exception is active and limited to `MCTS.CLI.Tui.Board`,
  `MCTS.CLI.Tui.Play`, and `MCTS.CLI.Tui.Replay`.
- Docker toolchain pinning is now encoded across the hostbootstrap base image
  (per [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md))
  and the slim project `docker/Dockerfile` overlay: GHC `9.12.4` and Cabal
  `3.16.1.0` (Sprint `1.14`) come from the base image's warm Cabal store;
  LLVM/BOLT `19`, `clang-19`, `libclang-rt-19-dev`, Rust `1.95.0`,
  `mimalloc`, and the pinned `fourmolu-0.19.0.1` + `hlint-3.10` at
  `/opt/hostbootstrap/haskell-style/bin/` come from the base image. The
  formatter tools share the single project
  GHC `9.12.4` (Sprint `1.16`).
  Root-level `hostbootstrap.dhall` is the canonical project config (Sprint
  `1.15` + [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md));
  `hostbootstrap run <mcts-args>` is the canonical invocation shape.
- Validated on 2026-05-15 through the root Compose entrypoint:
  `ghc --numeric-version == 9.14.1`, `cabal --numeric-version == 3.16.1.0`,
  and `docker compose run --rm mcts mcts check-code`. Warning-clean compilation is
  now owned by Dockerfile image construction.

### Remaining Work

None.

## Sprint 1.2: `CommandSpec` Registry and Parser Generation ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`,
`src/MCTS/CLI/Command.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Make the `CommandSpec` registry the source of truth for command topology, generated
command artefacts, and progressive introspection (`mcts commands`, `mcts help`) while
keeping leaf option parsing explicit in `Parser.hs`.

### Deliverables

- `src/MCTS/CLI/Spec.hs` defines `CommandSpec` and `OptionSpec` with the doctrine-named
  record fields per
  [../HASKELL_CLI_TOOL.md → Automatically Generated Documentation](../HASKELL_CLI_TOOL.md):
  `name`, `summary`, `description`, `children`, `options`, `examples` for
  `CommandSpec`; `longName`, `shortName`, `metavar`, `description`, `required` for
  `OptionSpec`. Every leaf `CommandSpec` carries at least one `Example` entry.
- `src/MCTS/CLI/Command.hs` declares the command ADTs consumed by the
  `CommandSpec` registry. The declarations below are the Sprint `1.2` baseline
  snapshot used to establish the pattern; the live source of truth after later
  phases is the implemented `src/MCTS/CLI/Command.hs` / `src/MCTS/CLI/Spec.hs`
  pair plus the generated command artefacts. Later phases extend the code-owned
  ADTs and registry together; this historical block is not a competing current
  CLI specification.

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
  > filled in by the per-backend sprints. The intended live build leaves are
  > `BuildCppLegacy`, `BuildCppImperative`, `BuildCppFunctional`, `BuildRust`, and
  > `BuildLegacyFixtures`. Sprint 1.2's obligation is the eleven top-level
  > constructors above; the per-backend phases and Phase `8` restoration own the
  > backend leaves.

  Subcommand families:

  ```haskell
  data BenchCommand
    = BenchRollouts [Backend] RunInputs
    | BenchSelfplay [Backend] RunInputs
    deriving stock (Show, Eq)

  data VerifyCommand
    = VerifyRollouts Bool [VerifyBackend] RunInputs -- allow-stale, cohort, run inputs
    | VerifySelfplay Bool [VerifyBackend] RunInputs
    deriving stock (Show, Eq)

  data InspectCommand
    = InspectList (Maybe FilePath)   -- enumerate the local transcript cache
    | InspectShow   ShowOptions      -- dump one transcript, legacy notation
    | InspectReplay ReplayOptions    -- interactive TUI replay (Sprint 7.4)
    | InspectCache  CacheCommand      -- sidecar cache list / prune
    | InspectDivergence DivergenceOptions
    deriving stock (Show, Eq)

  data LintCommand
    = LintFiles Bool     -- whitespace, final newline, forbidden paths
    | LintDocs Bool      -- governed docs, generated sections
    | LintHaskell Bool   -- fourmolu + hlint + cabal format
    | LintAll                            -- runs every lint above
    deriving stock (Show, Eq)

  data DocsCommand
    = DocsCheck                      -- compare rendered output against on-disk markers
    | DocsGenerate Bool (Maybe FilePath)
    deriving stock (Show, Eq)

  data BuildCommand
    = BuildRust PlanOptions          -- cdylib; rustc PGO + BOLT + mimalloc; Phase 6 Sprint 6.4
    | BuildLegacyFixtures LegacyFixtureOptions
                                      -- external legacy audit fixture generator
    deriving stock (Show, Eq)

  data CommandsOptions = CommandsOptions
    { commandsTree :: Bool           -- --tree
    , commandsJson :: Bool           -- --json
    } deriving stock (Show, Eq)

  newtype HelpOptions = HelpOptions { helpTarget :: [String] }
                        deriving stock (Show, Eq)
  ```

  Backend, workload, and axis enums:

  ```haskell
  data Backend    = CppLegacy | CppImperative | CppFunctional | Rust | Haskell
                    deriving stock (Show, Eq)
  -- All five constructors remain first-class. Q3 VerifyBackend covers
  -- cpp-imperative, cpp-functional, rust, and haskell; Q6 verifies all five
  -- through `mcts verify legacy-parity`.

  data VerifyBackend where
    VCppImperative :: VerifyBackend
    VCppFunctional :: VerifyBackend
    VRust          :: VerifyBackend
    VHaskell       :: VerifyBackend
    -- (i) excluded at the type level per
    -- [../documents/engineering/determinism_contract.md → Cross-Backend Determinism (Q3)](../documents/engineering/determinism_contract.md)
    -- and [00-overview.md → Hard Constraints item 7](00-overview.md).

  data RngSource  = NativeRng | CppRng
                    deriving stock (Show, Eq)

  data Threading  = SingleThreaded | MultiThreaded Int -- worker count
                    deriving stock (Show, Eq)

  data Side       = Hero | Villain
                    deriving stock (Show, Eq)

  data SimBudget  = FixedSims Int                    -- same budget every move
                  | RampedSims Int Int               -- initial, then per-move
                    deriving stock (Show, Eq)
  -- CLI syntax: `--sims N` parses as `FixedSims N`; `--sims N0:N1` parses as
  -- `RampedSims N0 N1` (initial-move budget N0, per-move budget N1 thereafter).

  -- Hash-prefix references are stored as `String` fields in the parsed option
  -- records and resolved by `MCTS.Transcript.Lookup`.
  ```

  Options records, with the README-pinned defaults and parse-time invariants
  documented inline:

  ```haskell
  -- Bench and verify both lower parsed options into the shared RunInputs record.
  -- Bench stores the parsed `[Backend]` cohort next to those inputs. Verify stores
  -- `allow-stale`, a `[VerifyBackend]` cohort, and the same `RunInputs`; parser
  -- validation requires `--rng cpp` and at least two Q3 verify backends.

  data PlayOptions = PlayOptions
    { playBackend  :: Backend
    , playSide     :: Side
    , playVs       :: Maybe Backend         -- Just b → AI-vs-AI; Nothing → human plays
    , playRng      :: RngSource
    , playSeed     :: Maybe Word64          -- Nothing → fresh random, recorded in transcript
    , playSims     :: SimBudget
    , playMaxPlies :: Word16                -- default: 200
    , playCacheDir :: Maybe FilePath        -- default cache root when omitted
    -- no threading field: a single game is always single-threaded internally
    } deriving stock (Show, Eq)

  data ShowOptions = ShowOptions
    { showRef        :: String
    , showTopN       :: Int                -- default 10; 0 = all
    , showWithEquity :: Bool               -- default False; True re-runs search
    , showEnvelope   :: Bool               -- default False; True dumps the engine envelope
    , showCacheDir   :: Maybe FilePath
    } deriving stock (Show, Eq)

  data ReplayOptions = ReplayOptions
    { replayRef         :: String
    , replayTopN        :: Int             -- default 10; 0 = all; live-adjustable in-app
    , replayCacheStates :: Int             -- default 20; in-memory MCTS state cache size
    , replayCacheDir    :: Maybe FilePath
    } deriving stock (Show, Eq)

  data CacheCommand
    = CacheList (Maybe FilePath)
    | CachePrune Bool (Maybe FilePath) PlanOptions
    deriving stock (Show, Eq)

  data DivergenceOptions = DivergenceOptions
    { divergenceRef      :: String
    , divergenceCacheDir :: Maybe FilePath
    } deriving stock (Show, Eq)
  ```

  `TestCommand = TestAll PlanOptions | TestParityAnchor ParityAnchorOptions |
  TestStanza String` is declared by
  [phase-7-cross-backend-verify-and-report-card.md → Sprint 7.3](phase-7-cross-backend-verify-and-report-card.md)
  alongside the `mcts test all` runner and report-card helper surfaces;
  the top-level `Command` constructor `Test TestCommand` above is the Phase 1
  registry/parser obligation.

- `src/MCTS/CLI/Parser.hs` renders the `optparse-applicative` command topology from
  the `CommandSpec` registry. The parser module keeps explicit leaf option parsers but
  does not own a competing command tree.
- `mcts commands` (flat), `mcts commands --tree`, `mcts commands --json`, and
  `mcts help <subcommand>` are wired per
  [../HASKELL_CLI_TOOL.md → Progressive Introspection](../HASKELL_CLI_TOOL.md). The
  `--json` form is the externally-stable schema for downstream tooling.
- `src/MCTS/CLI/Tree.hs` and `src/MCTS/CLI/Json.hs` carry the renderers; both share
  the same `CommandSpec` value as input.
- The worked invocations in the generated
  [../documents/cli/commands.md](../documents/cli/commands.md) reference are bound
  to the registry as seed `Example` entries on the
  corresponding `CommandSpec` leaves so the `mcts <subcommand> --help` text, the
  `documents/cli/commands.md` rendering, and the `mcts commands --json` schema
  all carry them. Sprint 7.1's `mcts-unit` semantic renderer assertions over
  `mcts commands --json` pin the invocations into the externally-stable schema.
  The benchmark metric refactor records the current `bench rollouts` spelling as a
  legacy command name for a played-game workload; see
  [../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).
  The invocations are:
  `bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell`
  (live cohort, ST, native RNG);
  `bench selfplay --backend haskell` (default 8 workers);
  `bench selfplay --workers 32`;
  `verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell`
  (cross-backend);
  `play --backend haskell --side hero --sims 10000` (human vs AI);
  `play --backend haskell --side villain --vs rust --sims 10000`
  (Haskell-vs-Rust spectate);
  `inspect list`;
  `inspect show 7a2f --top 10 --with-equity`;
  `inspect replay 7a2f --top 15`;
  `check-code` (the canonical doctrine-alignment gate);
  `build rust --dry-run` (Plan/Apply prints the typed Subprocess
  sequence and exits 0);
  `build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --dry-run`
  (Plan/Apply prints the optional external legacy audit fixture generator).

### Validation

1. `docker compose run --rm mcts mcts commands` lists every subcommand;
   `docker compose run --rm mcts mcts commands --tree` renders the tree per the
   README example; `docker compose run --rm mcts mcts commands --json` emits valid
   JSON that schema-checks against an enumerated set of expected keys.
2. Parser tests via `execParserPure` cover leaf happy paths and unhappy paths
   (Sprint 7.1 owns the `mcts-unit` stanza placement; this sprint provides the
   `execParserPure`-friendly parser shape).
3. Every leaf `CommandSpec` node has at least one `Example` entry — a property
   test in Sprint 7.1 enforces this; this sprint's deliverable provides the
   examples.

### Closure Notes

- Baseline landed: `CommandSpec`, `OptionSpec`, `Example`, `Command` ADTs,
  `mcts commands`, `mcts commands --tree`, `mcts commands --json`, and smoke
  `mcts help` exist. `src/MCTS/CLI/Parser.hs` now exposes an
  `optparse-applicative` `commandParserInfo`; `parseCommand` is implemented by
  `execParserPure`, and the parser topology is rendered from the `CommandSpec`
  tree with per-leaf semantic parsers.
- Renderer ownership is split into `src/MCTS/CLI/Json.hs` and
  `src/MCTS/CLI/Tree.hs`, with pure renderers delegated to the same
  `CommandSpec` registry value.
- Parser tests via the doctrine-required `execParserPure` path now cover the
  bench cohort, backend parser coverage, `inspect show
  --with-equity`, and the unhappy `verify --rng native` path; semantic
  renderer/schema coverage for `mcts commands --json` lives in `mcts-unit`.
- The 2026-05-19 alignment sweep made `bench` require an explicit backend
  cohort, made `bench` and `verify` require explicit `--games` and `--seed`,
  kept `bench` defaulting to `--threading multi --workers 8`, made `verify`
  default to `--threading single`, and wired `play` through `--rng`,
  `--max-plies`, and `--cache-dir` for both batch and interactive execution.
  `mcts-unit` pins these parser invariants and the updated `commands --json`
  structure with semantic assertions.
- Current implementation note: the concrete `VerifyCommand` constructors carry
  typed `[VerifyBackend]` lists for Q3, and `mcts verify legacy-parity` validates
  the complete all-five backend list for Q6. The current parser rejects
  `cpp-legacy` only at the default Q3 `verify` boundary; it remains valid for
  bench, build, play, inspect, and legacy-parity surfaces. The Phase 1
  registry/parser surface remains closed.
- The root README concrete invocation examples wrap the same leaf `Example` entries in
  the Compose entrypoint. Validated on 2026-05-15 through the root Compose entrypoint
  with `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts commands --tree`,
  `docker compose run --rm mcts mcts commands --json`,
  `docker compose run --rm mcts mcts help bench selfplay`, and
  `docker compose run --rm mcts mcts check-code`.

### Remaining Work

None.

## Sprint 1.3: Generated Artefacts Registry and Docs Pipeline ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Paths.hs`,
`src/MCTS/Generated/Sections.hs`, `documents/engineering/cli_command_surface.md`,
`documents/cli/commands.md`, `share/man/man1/mcts.1`,
`share/completion/bash/mcts`, `share/completion/zsh/_mcts`,
`share/completion/fish/mcts.fish`
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
  `` `docker compose run --rm mcts mcts docs generate` ``) and `mcts docs generate`
  (splice the renderer output between the marker pair, idempotent).
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

1. `docker compose run --rm mcts mcts docs check` exits 0 on a freshly-generated
   worktree.
2. `docker compose run --rm mcts mcts docs generate` is idempotent: running it
   twice produces no diff.
3. Hand-editing a marker region produces a
   `docker compose run --rm mcts mcts docs check` failure with the three-element
   error message.
4. Hand-editing a `trackingGeneratedPaths` entry produces a
   `docker compose run --rm mcts mcts lint files` failure.

### Closure Notes

- `mcts docs check` / `mcts docs generate` compare and write
  `documents/cli/commands.md`, `share/man/man1/mcts.1`, and the bash/zsh/fish
  completion files from the command registry through
  `src/MCTS/Generated/Paths.hs`; `mcts lint files` fails on drift in tracked
  generated paths.
- `src/MCTS/Generated/Sections.hs` owns a non-empty `GeneratedSectionRule`
  registry. The governed
  `documents/engineering/cli_command_surface.md` command matrix is now enclosed
  by `<!-- mcts:command-matrix:start -->` /
  `<!-- mcts:command-matrix:end -->`, declares
  `**Generated sections**: command-matrix`, and is rendered from the same
  `CommandSpec` registry that drives parser topology and generated CLI artefacts.
- `runDocs` traverses both registries: `mcts docs check` checks
  fully-generated paths and marker-delimited sections; `mcts docs generate`
  writes fully-generated files and splices each section rule. File reads are
  forced before rewrites so marker regeneration can safely overwrite a file it
  just inspected.
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`, byte-idempotence of two
  consecutive `docker compose run --rm mcts mcts docs generate` runs over the
  generated surfaces, a synthetic marker-region drift rejected by
  `docker compose run --rm mcts mcts docs check` with the path/key/remedy message,
  a synthetic `documents/cli/commands.md` edit rejected by
  `docker compose run --rm mcts mcts lint files`, and final green
  `docker compose run --rm mcts mcts docs check` plus
  `docker compose run --rm mcts mcts lint files`.

### Remaining Work

None.

## Sprint 1.4: Lint Stack, `fourmolu.yaml`, `mcts-haskell-style` Stanza ✅

**Status**: Done
**Implementation**: `fourmolu.yaml`, `.hlint.yaml`, `src/MCTS/CLI/Lint.hs`,
`src/MCTS/App.hs` (`CheckCode` branch), `test/haskell-style/Main.hs`, `mcts.cabal`
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
  direct-symbol negative-space rules for `print`, `exitFailure`,
  `Text.IO.putStrLn`, direct terminal formatting, `callProcess`,
  `readCreateProcess`, `System.Process.createProcess`, `System.Process.proc`,
  and `System.Process.shell`. The owning interpreter module uses a source-level
  HLint annotation for its scoped exception; external HLint is the hard gate for
  emitted `Error:` findings.
- `src/MCTS/CLI/Lint.hs` owns the current `mcts lint files|docs|haskell|all` runners.
  `mcts lint files` enforces the `forbiddenPathRegistry` (`.github/workflows/`,
  `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, `pre-commit-*.yaml`, root
  `Makefile`, host-level `.build/`, `bootstrap/`, repository `.sh` wrappers,
  root `justfile`, root `Taskfile.yml`) plus the
  `trackingGeneratedPaths` no-hand-edit check, per
  [../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../HASKELL_CLI_TOOL.md).
- `src/MCTS/CheckCode.hs` owns the `check-code` dispatcher. `src/MCTS/App.hs` routes the
  top-level `CheckCode` constructor to that owner, which dispatches lint, docs check,
  and style checks per [../HASKELL_CLI_TOOL.md → CLI surface](../HASKELL_CLI_TOOL.md).
  Warning-clean compilation is Dockerfile-owned so runtime `check-code` does not
  compile or link Cabal components.
- `src/MCTS/CLI/Command.hs` gains the `CheckCode` constructor on the top-level
  `Command` ADT and a matching `CommandSpec` leaf in the registry per
  [Sprint 1.2 ownership note](#sprint-12-commandspec-registry-and-parser-generation-).
  The leaf carries a single logical `Example` (`mcts check-code`) so the
  `mcts <subcommand> --help`, `documents/cli/commands.md`, and `mcts commands --json`
  outputs all reflect the CLI surface; host-runnable docs wrap that logical command in
  `docker compose run --rm mcts mcts check-code`.
- `mcts.cabal` declares the `mcts-haskell-style` test-suite with
  `type: exitcode-stdio-1.0`, `main-is: Main.hs`, `hs-source-dirs: test/haskell-style`.
  The suite asserts `fourmolu --mode check` succeeds, `hlint --with-group=default
  --with-group=extra` (with `.hlint.yaml` picked up from the repo root) runs and emits
  no `Error:` findings, and `cabal format` round-trips byte-equally via a temp file. The
  exact `hlint` flag pair is pinned per
  [../documents/engineering/unit_testing_policy.md → Test Stanza Layout](../documents/engineering/unit_testing_policy.md)
  and [system-components.md → Test Stanzas](system-components.md).

### Validation

1. `docker compose run --rm mcts mcts lint haskell` passes.
2. `docker compose run --rm mcts mcts lint files` exits 0;
   `docker compose run --rm mcts mcts lint all` exits 0.
3. `docker compose run --rm mcts mcts check-code` exits 0 on a clean worktree.
4. A synthetic violation (e.g. a `print` call in `src/MCTS/App.hs`) is rejected by
   `docker compose run --rm mcts mcts lint haskell` with a clear hlint error.

### Closure Notes

- Baseline landed: `fourmolu.yaml`, `.hlint.yaml`, `mcts lint files|docs|haskell|all`,
  `mcts check-code`, and the `mcts-haskell-style` Cabal stanza.
  `.hlint.yaml` now carries the full doctrine-mandated forbidden-symbol names:
  the `System.Process.*` constructors (`callProcess`, `readCreateProcess`,
  `readCreateProcessWithExitCode`, `createProcess`, `proc`, `shell`) and the
  direct output primitives (`print`, `exitFailure`, `Data.Text.IO.putStrLn`,
  `Data.Text.IO.hPutStrLn`). The `mcts-haskell-style` stanza enforces a
  conservative source-walker subset by walking every `.hs` file
  (excluding the lint stanza itself), rejecting tab characters, the direct
  subprocess primitives it can identify textually, and direct
  `exitFailure` / `Data.Text.IO.*PutStrLn` output calls outside their owner
  modules. Unqualified `print` and the module-scoped rules are enforced by
  the external container-pinned `hlint` path. The forbidden-path set is a typed
  `forbiddenPathRegistry :: [ForbiddenPath]` value in `MCTS.CLI.Lint`,
  where each entry pairs a path with a rationale string; the `mcts-unit`
  stanza pins the registry against the doctrine's expected set and
  asserts every entry carries a non-empty reason.
- The `mcts-haskell-style` stanza now runs `cabal format` through a temp-file
  round-trip unconditionally and requires
  `/opt/hostbootstrap/haskell-style/bin/fourmolu` and `/opt/hostbootstrap/haskell-style/bin/hlint`
  from the container image. Host `PATH` fallback and skipped external style
  tools are not supported closure paths. The project compiler and the
  formatter tools share GHC `9.12.4` (Phase 1 reopen Sprints `1.14` +
  `1.16`).
- The `check-code` dispatcher now lives in dedicated `src/MCTS/CheckCode.hs`;
  `src/MCTS/App.hs` only routes the top-level constructor to that owner.
- Validated on 2026-05-15 through the root Compose entrypoint:
  `docker compose run --rm mcts mcts lint haskell`,
  `docker compose run --rm mcts mcts lint all`,
  `docker compose run --rm mcts mcts check-code`, plus a temporary synthetic `print`
  violation rejected by container-pinned HLint with `Error: Use output boundary`.
- Reopened on 2026-05-18 for the Compose-only operator-surface doctrine update:
  `bootstrap/` and repository `.sh` workflow wrappers are now forbidden surfaces,
  the obsolete bootstrap script was removed, and the unit registry expectation was
  updated.
- Reclosure validation passed on 2026-05-18 through the root Compose service:
  `docker compose run --rm --build mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts lint files`,
  `docker compose run --rm mcts mcts lint all`, and
  `docker compose run --rm mcts mcts check-code`.
- The 2026-05-19 alignment sweep retained the committed `fourmolu.yaml` as the
  formatter SSoT and updated governed docs to link to it instead of copying a
  conflicting YAML sample. Supported-path uses of `!!`, `init`, `last`, and
  `read` were replaced with total helpers or `readMaybe`; the
  `mcts-haskell-style` source walker now rejects the documented partial-function
  set under `src/` and `app/` while keeping tests free to use fixture indexing.
  Validation passed `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`, `git diff --check`, and
  `docker compose run --rm mcts mcts check-code`.
- The style boundary is closed by the container-pinned HLint path, the committed
  `.hlint.yaml`, and the conservative source walker where HLint cannot express the
  boundary precisely. Later style-rule changes reopen this sprint explicitly rather
  than leaving action items in a `Done` sprint.
- **Phase 9 closure pointer (2026-06-04):** Sprint `1.16` retired the
  separate `STYLE_GHC_VERSION` install layer after the Phase 1 project GHC
  moved to `9.12.4` (Sprint `1.14`); the formatter tools
  (`fourmolu-0.19.0.1`, `hlint-3.10`) install at
  `/opt/hostbootstrap/haskell-style/bin/` against the single project GHC. The Sprint
  `1.4` closure prose above is preserved as historical
  narrative per [development_plan_standards.md → §D Declarative Plan
  Language](development_plan_standards.md); the Sprint `1.16` doctrine portion
  has landed in this phase doc, the governed engineering docs, and the root
  doctrine, while the code-side removal of the legacy install layer is bound
  to Phase 9 Sprint `9.2` and tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Remaining Work

None.

## Sprint 1.5: `Plan / Apply` Boundary ✅

**Status**: Done
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
- The rendered plan is deterministic: semantic-testable, no timestamps, no
  environment-dependent paths.

### Validation

1. Current Plan/Apply leaves such as `mcts build rust --dry-run` and
   `mcts test all --dry-run` support `--dry-run` and `--plan-file <path>` and
   round-trip through semantic renderer tests.
2. A property test (Sprint 7.1) asserts `render is deterministic` over the `Plan`
   renderer.

### Closure Notes

- `MCTS.Plan` exports the doctrine-shaped `buildPlan`, `applyPlan`,
  `applySubprocessPlan`, `applyWithEnv`, and `applySubprocessWithEnv` helpers.
  Plan rendering is deterministic and byte-stable over repeated renders.
- `mcts test all`, `mcts test parity-anchor`, `mcts docs generate`,
  `mcts inspect cache prune`, `mcts build <backend>`, and
  `mcts build legacy-fixtures` all support `--dry-run` and
  `--plan-file <path>` at the parser level and declare those options in their
  `CommandSpec` leaf metadata. `mcts-unit` asserts the metadata for every current
  Plan/Apply leaf.
- `MCTS.CLI.Build` executes backend plans through `applySubprocessWithEnv`, and
  `MCTS.CLI.Test` now uses `applyWithEnv` with a custom `runStep` that preserves
  its explicit `renderError` output on subprocess failure.
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts test all --dry-run --plan-file /tmp/mcts-test-plan.txt`,
  `docker compose run --rm mcts mcts docs generate --dry-run --plan-file /tmp/mcts-docs-plan.txt`,
  and a Rust backend build-recipe dry-run with `--plan-file`.

### Remaining Work

None.

## Sprint 1.6: `Subprocess` ADT and Interpreter ✅

**Status**: Done
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

- Pure `renderSubprocess :: Subprocess -> Text` for logs, `--dry-run`, semantic tests.
- Interpreter API: `runStreaming :: Subprocess -> IO (Either AppError ExitCode)` and
  `capture :: Subprocess -> IO (Either AppError ProcessOutput)`. These are the **only**
  IO boundary for subprocess execution.
- `.hlint.yaml` rules name `callProcess`, `readCreateProcess`,
  `System.Process.createProcess`, `System.Process.proc`, `System.Process.shell`, and
  `typed-process` smart constructors per
  [../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed Values
  → Forbidden patterns](../HASKELL_CLI_TOOL.md). The current source-walker guard
  enforces owner-module exceptions for the direct textual subset it can check safely.

### Validation

1. `docker compose run --rm mcts mcts check-code` succeeds with the `Subprocess`
   module compiled.
2. A synthetic violation (e.g. a `callProcess` call in `src/MCTS/Lint.hs`) is
   rejected by `docker compose run --rm mcts mcts lint haskell`.
3. A semantic renderer test of `renderSubprocess` over a sample value passes.

### Closure Notes

- `Subprocess`, `renderSubprocess`, `runStreaming`, and `capture` exist and are
  used by the lint, docs/build gate, build harness, prerequisite probes, and test
  runner. The interpreter now uses the doctrine-standard `typed-process`
  dependency; the library no longer depends directly on the lower-level
  `process` package.
- The external container-pinned HLint path rejects emitted `Error:` findings for
  direct `System.Process.*` and `System.Process.Typed.*` smart constructors
  outside `src/MCTS/Subprocess.hs`. The source walker remains as an additional
  source-walker guard for the conservative textual subset.
- The unit suite semantically pins `renderSubprocess` shell quoting and asserts
  `AppError SubprocessFailed` includes the rendered command and exit code.
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts check-code`,
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts lint haskell`, and a synthetic
  `/tmp/HlintTypedSynthetic.hs` using `System.Process.Typed.proc` rejected by the
  container-pinned HLint as `Error: Use typed subprocess boundary`.

### Remaining Work

None.

## Sprint 1.7: `prerequisiteRegistry` ✅

**Status**: Done
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
- The prerequisite registry carries concrete nodes for the current
  toolchain/build surfaces: exact GHC `9.12.4`, Cabal `3.16.1.0`,
  LLVM/BOLT/LLD `19`, Rust `1.95.0`, `mimalloc`, live Rust shared-library
  artefacts, C++ PGO/BOLT profile and shared-library artefacts, optional legacy
  evidence prerequisites, and retained profile directory checks.
- The transitive closure runs before `apply`; a single unmet node emits
  `AppError PrerequisiteUnmet` carrying the failing `nodeId`, `nodeDescription`, and
  remedy hint.

### Validation

1. A unit test exercises the transitive-closure pass with a synthetic unmet node and
   asserts the `AppError PrerequisiteUnmet` payload.
2. A property test asserts the registry has no cycles.

### Closure Notes

- `PrerequisiteNode`, `prerequisiteRegistry`, `checkPrerequisites`,
  `transitiveClosure`, and `registryHasCycle` exist. The registry carries
  version-aware probes for `ghcup`, `ghc-9.12.4`, `cabal`, `c++`,
  `llvm-config` (LLVM `19.x`), `llvm-bolt` (LLVM `19.x`), `rustup`,
  `cargo` / `rustc` (`1.95.0`), LLD `19`, and `mimalloc` via library-path probes,
  plus backend-local C++ and Rust profile-directory probes, the `logical-backends`
  node, and canonical foreign shared-library artefact nodes. C++ PGO/BOLT profile
  and artefact prerequisite coverage closed in Sprint `5.3`.
- `nodeDependsOn` carries dependency edges (`cargo`/`rustc` depend on
  `rustup`; `bolt` depends on `llvm`; `ghc-9.12.4`/`cabal-3.16.1.0` depend
  on `ghcup`). `prerequisitesForBuild` and `prerequisitesForTest` resolve
  through `transitiveClosure`.
- `mcts build *` checks backend build prerequisites before apply, and
  `mcts test all` / `mcts test <stanza>` check the pinned GHC/Cabal, installed
  `mcts`, installed test-suite executables, installed `mcts-criterion`, logical
  backend, and foreign shared-library prerequisite closure before applying
  image-local test plans.
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts test mcts-unit` and
  `docker compose run --rm mcts mcts test mcts-integration`.

### Remaining Work

None.

## Sprint 1.8: `Env` Record and `ReaderT App` ✅

**Status**: Done
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

1. `docker compose run --rm mcts mcts check-code` succeeds.
2. Every command runner module imports `MCTS.Env` and uses `App`.

### Closure Notes

- `src/MCTS/Env.hs` declares the shared `Env` record carrying
  `envOutputOptions`, `envCommandSpec`, `envGeneratedSectionRules`,
  `envTrackingGeneratedPaths`, `envPrerequisites`, `envCacheDir`,
  `envLogHandle`, `envRawArguments`, and the `envClockMonotonic` test-hook
  field. The `App` newtype is `newtype App a = App (ReaderT Env IO a)` with
  `MonadIO` and the standard instances derived via `DerivingStrategies` +
  `GeneralizedNewtypeDeriving`.
- `MCTS.App.runCommand` and the public runners in `MCTS.CLI.Bench`,
  `MCTS.CLI.Build`, `MCTS.CLI.Docs`, `MCTS.CLI.Inspect`, `MCTS.CLI.Lint`,
  `MCTS.CLI.Test`, and `MCTS.CLI.Verify` now return `App ExitCode` and read
  shared state through `askEnv`. `MCTS.CheckCode` uses the same boundary for
  the aggregate gate.
- `runAppIO`, `askEnv`, `withTestClock`, the generated registry fields, and the
  default command spec round-trip through the `mcts-unit` stanza.
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts check-code`,
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts commands --tree`,
  `docker compose run --rm mcts mcts docs check`,
  `docker compose run --rm mcts mcts lint files`, and
  a Rust backend build-recipe dry-run, plus a container
  signature check showing every public command runner returns `Env.App ExitCode`.

### Remaining Work

None.

## Sprint 1.9: `AppError`, `renderError`, Output Discipline ✅

**Status**: Done
**Implementation**: `src/MCTS/Error.hs`, `src/MCTS/CLI/Output.hs`, `.hlint.yaml`
**Docs to update**: `documents/engineering/code_quality.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Implement the single `AppError` ADT, the `renderError` boundary, and the `--format` /
`--color` output discipline.

### Deliverables

- `src/MCTS/Error.hs` declares the single `AppError` ADT covering the canonical
  19-variant set:
  `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
  `VerifyMismatch`, `VerifyLengthMismatch`, `VerifyTerminatorMismatch`,
  `VerifyCohortTooSmall`, `RecomputeMismatch`, `LegacyParityRolloutOverflow`,
  `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidMove`, `ParseError`, `IOErrorText` per
  [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md). The set
  matches [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md)
  exactly;
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
    spans more than one `host_arch`; see
    [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md).
  - `EngineEnvelopeMismatch` is raised by `mcts verify` when the layered
    engine-envelope check finds a disagreement: either a cohort-invariant
    field (`host_arch`, `rng_source`, `shared_rng_build_id`,
    `cohort_config_hash`) disagrees across the cohort, or a per-backend-slot
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
  - `ParseError` is raised by parser and option validation paths that need to
    render through the same `AppError` boundary as runtime failures.
  - `IOErrorText` carries textual IO failures at command boundaries where the
    lower-level exception cannot be kept as a typed project error.
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
- `.hlint.yaml` rules name `print`, `exitFailure`, `Text.IO.putStrLn`,
  `Text.IO.hPutStrLn`, and direct terminal-formatting calls. The source-walker
  enforces owner-module exceptions for `exitFailure` / `Data.Text.IO.*PutStrLn`;
  HLint carries the broad syntactic hints and the source-walker carries the
  module-scoped owner policy.

### Validation

1. Semantic tests over `renderError` for each `AppError` variant.
2. A synthetic violation (e.g. a `print` outside `Output.hs`) is rejected by
   `docker compose run --rm mcts mcts lint haskell`.
3. `docker compose run --rm mcts mcts <subcommand> --format json` emits valid JSON;
   `docker compose run --rm mcts mcts <subcommand> --format table` emits a
   TTY-friendly table; `docker compose run --rm mcts mcts <subcommand> --format plain`
   emits newline-delimited output suitable for piping.

### Closure Notes

- `AppError`, `EnvelopeMismatchScope`, and the canonical
  `MCTS.Error.renderError :: AppError -> Text` boundary exist. `MCTS.CLI.Output`
  re-exports the Text boundary and owns `renderErrorString :: OutputOptions -> AppError -> String`
  for final stdout/stderr emission.
- `OutputOptions`, `--format json|table|plain`, `--color auto|always|never`,
  `--no-color`, stdout/stderr helpers, and command-level JSON/table/plain rendering
  paths exist. `--color always` renders errors with ANSI red at the output boundary;
  `--color never` / `--no-color` render plain text.
- The `mcts-unit` stanza smoke-renders every `AppError` variant and asserts the
  `TranscriptNotFound`,
  `DocsCheckDrift`, and `PrerequisiteUnmet` renderings carry the user-visible
  references (ref, remedy command, remedy hint).
- Validated on 2026-05-15 through the root Compose entrypoint with
  `docker compose run --rm mcts mcts check-code`,
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts inspect list --format json`,
  `docker compose run --rm mcts mcts inspect list --format table`,
  `docker compose run --rm mcts mcts commands --format plain`,
  `docker compose run --rm mcts mcts --color always verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell`,
  and a synthetic `/tmp/HlintPrintSynthetic.hs` using `print` rejected by the
  container-pinned HLint as `Error: Use output boundary`.

### Remaining Work

None.

## Sprint 1.10: Generated-Doc and Style Contract Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Sections.hs`,
`src/MCTS/CheckCode.hs`, `src/MCTS/CLI/Lint.hs`, `test/haskell-style/Main.hs`
**Docs to update**: `documents/documentation_standards.md`,
`documents/engineering/code_quality.md`, `documents/engineering/haskell_code_guide.md`,
`documents/engineering/unit_testing_policy.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the CLI-owned documentation and style gates say exactly what they enforce, and
enforce the metadata checks the governed documentation topology requires.

### Deliverables

- `mcts docs check` parses each governed document's `**Generated sections**:` metadata
  and verifies that the declared keys, physically-present marker pairs, and
  `GeneratedSectionRule` registry agree. A document declaring `none` while carrying a
  generated marker pair fails, and a document declaring a generated key whose markers
  are absent fails.
- `mcts check-code` runs the documented lint/docs/style sequence once per stage; any
  intentional duplicate check is removed or documented as an explicit safeguard.
- `documents/engineering/haskell_code_guide.md`,
  `documents/engineering/code_quality.md`, and the `mcts-haskell-style` source walker
  agree on the supported-path partial-function policy. If hot-path invariant failures
  such as `error` remain permitted, the policy says so narrowly instead of claiming an
  unconditional ban.
- `system-components.md` marks the generated-doc and style gates done after the code,
  governed docs, and validation commands agree.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts lint docs`
- `docker compose run --rm mcts mcts test mcts-haskell-style`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

- Closed on 2026-05-21 after `docker compose run --rm mcts mcts docs check`,
  `docker compose run --rm mcts mcts lint docs`,
  `docker compose run --rm mcts mcts test mcts-haskell-style`,
  `docker compose run --rm mcts mcts check-code`, and `git diff --check` passed.

## Sprint 1.11: README and Lint-Write Contract Realignment ✅

**Status**: Done
**Implementation**: `README.md`, `src/MCTS/CLI/Lint.hs`,
`src/MCTS/Generated/Paths.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/documentation_standards.md`,
`documents/engineering/code_quality.md`, `documents/engineering/cli_command_surface.md`,
`documents/engineering/haskell_code_guide.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Restore the root README to its operator-facing role and make the lint `--write`
flags repair the fixable drift they advertise.

### Deliverables

- `README.md` is reference-only: it keeps project intent, the Compose entrypoint,
  backend cohort summary, short operator commands, validation gates, and links to
  authoritative contracts instead of duplicating transcript, FFI, determinism, or
  performance doctrine.
- Governed docs and plan files cite the owning contract documents directly when they
  need detailed rules formerly duplicated in README prose.
- `mcts lint files --write` trims trailing whitespace/final-newline drift and rewrites
  fully generated command/man/completion files from the generated-file registry before
  rechecking.
- `mcts lint docs --write` runs the generated-document writer before `docs check`.
- `mcts lint haskell --write` runs the pinned Fourmolu formatter and `cabal format`
  before the Haskell style stanza.

### Validation

- `docker compose run --rm mcts mcts lint files --write`
- `docker compose run --rm mcts mcts lint docs --write`
- `docker compose run --rm mcts mcts lint haskell --write`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after the root README, generated-document standards, lint
documentation, and command implementation were aligned with the documented
single-entrypoint workflow.

## Sprint 1.12: Generated Rollouts Command Summary Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Spec.hs`, `src/MCTS/Generated/Sections.hs`,
`documents/cli/commands.md`, `documents/engineering/cli_command_surface.md`,
`test/unit/Main.hs`
**Docs to update**: `documents/cli/commands.md`,
`documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make generated command summaries agree with the implemented benchmark metric taxonomy:
`mcts bench rollouts` is a legacy played-game workload, while terminal playout
throughput lives at `mcts bench terminal-playouts`.

### Deliverables

- `CommandSpec` and generated-section renderers describe `mcts bench rollouts` as a
  legacy played-game benchmark, not a random-rollout or terminal-playout primitive.
- Fully generated command docs and marker-delimited command-matrix docs are regenerated
  through the `mcts docs generate` surface.
- `mcts-unit` carries a focused semantic assertion that generated command docs preserve
  the legacy played-game wording and do not regress to the stale random-rollout label.
- The cleanup ledger records the generated `bench rollouts` summary drift as completed.

### Validation

- `docker compose run --rm mcts mcts docs generate`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

## Sprint 1.13: Self-Describing CLI Introspection ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`,
`src/MCTS/CLI/Command.hs`, `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Paths.hs`,
`src/MCTS/Generated/Sections.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `documents/engineering/cli_command_surface.md`,
`documents/engineering/README.md`, `documents/cli/commands.md`,
`share/man/man1/mcts.1`, `share/completion/bash/mcts`,
`share/completion/zsh/_mcts`, `share/completion/fish/mcts.fish`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the `mcts` CLI fully self-describing through introspection alone while keeping
`optparse-applicative` as the idiomatic parser implementation. An operator must be able
to discover valid backend identifiers, Q3 verify backend subsets, RNG modes, side values,
threading modes, defaults, examples, list syntax, and command-specific notes from
`--help`, `mcts help <path>`, `mcts commands --json`, generated Markdown/manpages, and
shell completions without reading source code or the development plan.

### Deliverables

- Introduce a typed choice metadata layer for enum-like CLI values. The first-class choice
  sets are the complete backend list (`cpp-legacy`, `cpp-imperative`,
  `cpp-functional`, `rust`, `haskell`), the Q3 verify cohort
  (`cpp-imperative`, `cpp-functional`, `rust`, `haskell`), `RngSource`
  (`native`, `cpp`), `Side` (`hero`, `villain`), `Threading` (`single`, `multi`),
  output formats, color modes, and any build/test identifiers that are accepted as
  closed sets. Each choice carries the parser token, a short summary, and any
  command-specific availability rule.
- Replace ad hoc enum readers with choice-aware `OA.ReadM` readers built from those
  choice sets. Unknown values and malformed comma lists render the rejected token plus
  the accepted values. The Q3 verify reader continues to reject `cpp-legacy`, but its
  diagnostic names the valid Q3 choices and points operators to
  `mcts verify legacy-parity` for all-five legacy-envelope checks.
- Enrich `OptionSpec` and the command registry with defaults, value sets, positional
  arguments, list semantics, examples, notes, and completion metadata. The enriched
  metadata supplements `optparse-applicative`; it does not replace typed semantic
  parsers for flags such as `--sims N|A:B`.
- Add reusable option builders for common surfaces: single backend, backend list, Q3
  backend list, RNG, side, threading/workers, simulation budget, cache directory,
  output format/color, dry-run/plan-file, and hash-prefix positional arguments. Each
  builder emits the `optparse-applicative` modifier set (`metavar`, `help`, default,
  completer) and the registry metadata from the same definition.
- Make every leaf `mcts <path> --help` show required inputs, optional flags, defaults,
  accepted enum values, list syntax, examples, and command-specific side effects.
  `mcts play --help` must enumerate all valid backend identifiers for both `--backend`
  and `--vs`.
- Rework `mcts help <path>` to render the actual focused parser help for that command
  path. Unknown help targets render the nearest valid command tree context.
- Expand `mcts commands --json` so downstream tools can inspect command paths,
  summaries, descriptions, options, positional arguments, defaults, requiredness,
  accepted values, examples, and notes from one stable schema. `mcts commands --tree`
  remains the compact topology view.
- Regenerate `documents/cli/commands.md`, `share/man/man1/mcts.1`, and
  `share/completion/{bash,zsh,fish}/` from the enriched registry. Generated docs must
  include the same value-set and example data visible through parser help.
- Add unit tests that assert every enum-valued option exposes accepted values in help
  and JSON, invalid enum input reports the valid values, `mcts help play` carries the
  same important sections as `mcts play --help`, every registered example parses, and
  the generated command docs retain the enriched value metadata.

### Validation

- `docker compose run --rm mcts mcts play --help`
- `docker compose run --rm mcts mcts help play`
- `docker compose run --rm mcts mcts play --backend nope --side hero`
- `docker compose run --rm mcts mcts commands --json`
- `docker compose run --rm mcts mcts docs generate`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

- Closed on 2026-06-03 after `CommandSpec` / `OptionSpec` gained typed choice,
  default, positional, list-syntax, note, and completion metadata; parser readers now
  consume the same value sets that generated docs, JSON, manpages, completions, and
  diagnostics render.
- `mcts play --help` and `mcts help play` render focused help with accepted backend,
  side, RNG, format, and color values; invalid enum/list values report the accepted
  choices, and Q3 verify backend parsing rejects `cpp-legacy` with the
  `legacy-parity` remedy.
- Validation passed through the Compose entrypoint: `docker compose run --rm --build
  mcts mcts test mcts-unit`, `docker compose run --rm mcts mcts docs check`,
  `docker compose run --rm mcts mcts lint haskell`, `docker compose run --rm mcts
  mcts lint docs`, `docker compose run --rm mcts mcts lint files`, `docker compose run
  --rm mcts mcts check-code`, `docker compose run --rm mcts mcts play --help`,
  `docker compose run --rm mcts mcts help play`, `docker compose run --rm mcts mcts
  commands --json`, expected-failing `docker compose run --rm mcts mcts play --backend
  nope --side hero` (exit `2` with accepted backend values), and `git diff --check`.

## Sprint 1.14: Toolchain pin update to GHC 9.12.4 + Cabal 3.16.1.0 ✅

**Status**: Done
**Implementation**: inline doctrine edits in this phase doc (Sprint `1.1` deliverables at the pin-assertion lines, Sprint `1.1` Validation gate `ghc --version` line, Sprint `1.1` closure notes pin row, Sprint `1.4` closure-note project-compiler row, Sprint `1.7` prerequisite-registry pin assertions). Coordinated doctrine edits landed in [`00-overview.md`](00-overview.md), [`system-components.md`](system-components.md), [`../documents/engineering/code_quality.md`](../documents/engineering/code_quality.md), [`../documents/engineering/compiler_runtime_tuning.md`](../documents/engineering/compiler_runtime_tuning.md), [`../documents/engineering/haskell_code_guide.md`](../documents/engineering/haskell_code_guide.md), [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md), [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md), [`../README.md`](../README.md). Source edits to `mcts.cabal`, `cabal.project`, `src/MCTS/Prerequisite.hs`, `src/MCTS/ReportCard.hs`, `src/MCTS/Engine/Envelope.hs`, `test/unit/Main.hs`, and the project `docker/Dockerfile` migration landed with Phase 9 Sprint `9.2`.
**Blocked by**: N/A
**Docs to update**: `00-overview.md`, `system-components.md`, `../documents/engineering/code_quality.md`, `../documents/engineering/compiler_runtime_tuning.md`, `../documents/engineering/haskell_code_guide.md`, `../HASKELL_CLI_TOOL.md`, `../CLAUDE.md`, `../AGENTS.md`, `../README.md`, `phase-9-hostbootstrap-adoption.md`.

### Objective

Update Phase 1's toolchain pin doctrine from GHC `9.14.1` to GHC `9.12.4`
(Cabal `3.16.1.0` unchanged) to align with the warm Cabal store baked into
the hostbootstrap base image (see
[phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md)).
MCTS uses no GHC 9.14-specific language features, and the existing
`base >=4.20 && <5` constraint is satisfied by GHC `9.12.4`'s `base-4.21`,
so the pin update is a source-compatible adjustment.

### Deliverables

- Inline edits at the Sprint `1.1` `mcts.cabal` `tested-with` doctrine line,
  the `cabal.project` `with-compiler` doctrine line, the
  `docker/Dockerfile` "pins GHC X" doctrine line, the Sprint `1.1` Validation
  `ghc --version` line, the Sprint `1.1` `mcts.cabal` static-check
  `tested-with` line, and the Sprint `1.1` closure-note "Docker toolchain
  pinning is now encoded" doctrine row.
- Inline edits in Sprint `1.4`'s closure note that referenced the project
  compiler pin and the isolated formatter-tools GHC model (the latter
  collapsed by Sprint `1.16`).
- Inline edits in Sprint `1.7`'s prerequisite-registry deliverable and
  closure-note pin assertions (`ghc-9.14.1` → `ghc-9.12.4` at every
  occurrence inside Sprint `1.7`).
- Coordinated doctrine edits in [`00-overview.md`](00-overview.md),
  [`system-components.md`](system-components.md), the named governed
  engineering docs, [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md),
  [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md), and
  [`../README.md`](../README.md). Historical evidence narratives (Sprint
  `8.18` / `8.19` measurement blocks, the Sprint `7.4` `allow-newer`
  history, Sprint-X dated validation lines) are preserved verbatim per
  [development_plan_standards.md → §D](development_plan_standards.md).
- The former Pending-Removal row covering source surfaces pinned at GHC
  `9.14.1` moved to Completed after the source edits landed.

### Validation

`hostbootstrap run test all` exits 0 under GHC `9.12.4`;
`hostbootstrap run docs check` and
`hostbootstrap run check-code` are the closing documentation and
style gates. Grep for `9.14.1`
across `DEVELOPMENT_PLAN/`, `documents/`, `README.md`, `CLAUDE.md`,
`AGENTS.md`, `HASKELL_CLI_TOOL.md` returns hits only inside historical
evidence blocks (Sprint `8.18` / `8.19` narratives, Sprint-X dated
validation lines), the Sprint `7.4` `allow-newer` history
(`cabal.project` comment and Phase 7 closure narrative), and completed
ledger history.

### Remaining Work

None.

## Sprint 1.15: Canonical command shape — `hostbootstrap run <mcts-args>` ✅

**Status**: Done
**Implementation**: inline doctrine edits in this phase doc (Sprint `1.1` Implementation list, Sprint `1.1` Compose-entrypoint doctrine row, Sprint `1.1` closure-note Compose entrypoint row). Coordinated doctrine edits landed in [`00-overview.md`](00-overview.md), [`system-components.md`](system-components.md), every governed engineering doc that quotes the entrypoint, [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md), [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md), [`../README.md`](../README.md), and the Phase 8 validation-gate example at the line outside the Sprint `8.18` historical evidence block. `compose.yaml` was deleted and root `hostbootstrap.dhall` landed with Phase 9 Sprint `9.2`.
**Blocked by**: N/A
**Docs to update**: same list as Sprint `1.14`, plus `phase-8-haskell-performance-parity-closure.md` at the validation-gate example outside Sprint `8.18` historical evidence.

### Objective

Replace `docker compose run --rm mcts mcts <command>` with
`hostbootstrap run <mcts-args>` as the canonical invocation shape for
all build, run, validation, formatting, linting,
documentation-generation, test, benchmark, and backend-build work. The
Dockerfile's tini-wrapped `mcts` ENTRYPOINT supplies the executable, so
host invocations pass only the arguments after `mcts`. The `hostbootstrap`
tool itself is owned by Phase 9 Sprint `9.1`; this sprint owns only the
*shape* of the canonical command line in Phase 1's doctrine and the
governed docs that mirror it.

### Deliverables

- Inline edits at the Sprint `1.1` Implementation list (replacing
  `compose.yaml` with `hostbootstrap.dhall` and forward-pointing to
  Phase 9 Sprint `9.2`), the Sprint `1.1` Compose-entrypoint doctrine
  row in the `docker/Dockerfile` deliverable bullet, and the Sprint
  `1.1` closure-note Compose-entrypoint row.
- Coordinated doctrine edits in [`00-overview.md`](00-overview.md)
  (entrypoint doctrine line, the `compose.yaml`-as-only-supported-entrypoint
  sentence, the layout-row reference), [`system-components.md`](system-components.md)
  (Docker development environment row), the named governed engineering
  docs (`code_quality.md` entrypoint example, `unit_testing_policy.md`
  entrypoint references, others by audit),
  [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md) (operator-facing
  entrypoint sentences), [`../CLAUDE.md`](../CLAUDE.md),
  [`../AGENTS.md`](../AGENTS.md), and [`../README.md`](../README.md)
  (Supported Workflow block, Common Operator Commands, Validation
  block). Historical evidence and Sprint-X-dated validation lines are
  preserved verbatim.
- The former Pending-Removal row for `compose.yaml` moved to Completed.

### Validation

`hostbootstrap run docs check` exits 0;
`hostbootstrap run check-code` exits 0. Grep for
`docker compose run --rm mcts mcts` returns hits only inside (a)
historical evidence blocks and (b) completed ledger history.

### Remaining Work

None.

## Sprint 1.16: Lint stack — formatter-tools GHC unified with project GHC ✅

**Status**: Done
**Implementation**: inline doctrine edits in this phase doc (Sprint `1.1` `docker/Dockerfile` deliverable bullet at the formatter-tools-isolation wording, Sprint `1.1` closure-note style-tool compiler row, Sprint `1.4` closure-note project-compiler-pinned row, the forward-pointer footnote at end of Sprint `1.4` closure narrative). Coordinated doctrine edits landed in [`00-overview.md`](00-overview.md), [`../documents/engineering/code_quality.md`](../documents/engineering/code_quality.md), [`../documents/engineering/unit_testing_policy.md`](../documents/engineering/unit_testing_policy.md). The `STYLE_GHC_VERSION` ARG and its separate install layer were removed from `docker/Dockerfile` with Phase 9 Sprint `9.2`.
**Blocked by**: N/A
**Docs to update**: `00-overview.md`, `../documents/engineering/code_quality.md`, `../documents/engineering/unit_testing_policy.md`, and the Sprint `1.4` forward-pointer footnote in this file.

### Objective

Collapse the lint stack's separate formatter-tools GHC into the project
GHC. Under Sprint `1.14`'s pin both are GHC `9.12.4` — the single GHC
the hostbootstrap base image ships. The formatter tools
(`fourmolu-0.19.0.1`, `hlint-3.10`) are installed by the base image at
`/opt/hostbootstrap/haskell-style/bin/` against the project GHC. The
`mcts-haskell-style` test stanza is unchanged; it still resolves the
tools by absolute path. The `fourmolu.yaml` twelve-settings file and
`.hlint.yaml` are unchanged.

### Deliverables

- Inline edit at the Sprint `1.1` `docker/Dockerfile` deliverable bullet:
  drop the "separate formatter-tools GHC `9.12.4`" and "isolated from
  the main project compiler" wording; restate the lint stack as sharing
  the project GHC `9.12.4` under Sprint `1.14`.
- Inline edit at the Sprint `1.1` closure note "style-tool compiler GHC
  `9.12.4`" row: collapse to the unified GHC wording.
- Inline edit at the Sprint `1.4` closure note "the project compiler
  pinned to GHC `9.14.1` while matching the isolated formatter-tools
  GHC model" row: restate as the project compiler and the formatter
  tools sharing GHC `9.12.4`.
- Forward-pointer footnote appended at end of Sprint `1.4` closure
  narrative (above) naming Sprint `1.16` as the supersession owner and
  preserving the original Sprint `1.4` closure prose per
  [development_plan_standards.md → §D](development_plan_standards.md).
- Coordinated doctrine edits in
  [`00-overview.md`](00-overview.md) (lint-stack narrative collapses
  separate-GHC implication; file list unchanged),
  [`../documents/engineering/code_quality.md`](../documents/engineering/code_quality.md)
  (drop "separate container-owned install" wording; state unified GHC),
  [`../documents/engineering/unit_testing_policy.md`](../documents/engineering/unit_testing_policy.md)
  (parallel sweep if the doc carries the same wording).
- The former Pending-Removal row for `STYLE_GHC_VERSION` and the
  separate formatter-tools compiler install moved to Completed.

### Validation

`hostbootstrap run docs check` exits 0;
`hostbootstrap run check-code` exits 0. The lint stack
contents are unchanged in this sprint's scope (`fourmolu.yaml`,
`.hlint.yaml`, the `cabal format` round-trip, the `mcts-haskell-style`
stanza); the lint-stack regression surface is zero.

### Remaining Work

None.

## Sprint 1.17: Action-Oriented Command-Use Text ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`,
`test/unit/Main.hs`, `documents/cli/commands.md`, `share/man/man1/mcts.1`,
`share/completion/bash/mcts`, `share/completion/zsh/_mcts`,
`share/completion/fish/mcts.fish`
**Docs to update**: `README.md`, `documents/documentation_standards.md`,
`documents/engineering/README.md`, `documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make every leaf command surface self-describing in the operator workflow sense, not
only the accepted-value sense. The immediate failure case is `mcts play`: help and
generated docs exposed `BACKEND` metavars and backend values, but did not clearly
teach which backend controls which side, how a human plays the opposite side, or
how `--vs` turns the TUI into AI-vs-AI spectator mode.

### Deliverables

- `src/MCTS/CLI/Spec.hs` carries action-oriented descriptions for every leaf
  command instead of falling back to terse summaries. For `mcts play`, examples
  and notes spell out the valid backend identifiers, human-vs-AI mode, spectator
  mode, and Space-to-advance behavior in the typed registry that renders generated
  docs, JSON, manpages, and completions.
- `src/MCTS/CLI/Parser.hs` uses matching `optparse-applicative` help text for
  `--backend`, `--side`, and `--vs`, including accepted backend values and the
  side-control semantics. `BACKEND` remains the metavar, but it is no longer the
  only explanation.
- `test/unit/Main.hs` asserts that every leaf description is action-oriented and
  that focused help plus generated command Markdown include accepted backend values
  and human/spectator-mode text, preserving the Sprint `1.13` value-discovery tests.
- `documents/engineering/cli_command_surface.md` strengthens the
  Self-Describing CLI Contract: every leaf command must explain how to use the
  command, not merely list flags; metavars such as `BACKEND` require accepted
  values and behavior-specific explanation.
- `documents/documentation_standards.md` records the generated-CLI-doc rule that
  command pages must be action-oriented and include accepted closed-set values,
  minimal invocations, and side effects or interactive controls.
- `README.md` keeps a concise operator play walkthrough with the full backend
  identifier set and points to focused help / command JSON as the self-describing
  surfaces.
- The stale command-use residue is recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) and moved to
  Completed with this sprint.

### Validation

- `hostbootstrap run docs generate`
- `hostbootstrap run docs check`
- `hostbootstrap run test mcts-unit`
- `hostbootstrap run check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

- Closed on 2026-06-04 after every leaf command carried action-oriented registry
  text, and the play leaf plus parser help described valid backends,
  human-vs-AI side ownership, AI-vs-AI spectator mode, and the Space-to-advance
  interaction through the same registry-backed surfaces.
- Phases `2` through `8` remain closed on their owned backend, transcript,
  verification, report-card, and performance surfaces; the reopening touched only
  Phase `1` command metadata, help, generated command artefacts, and governed docs.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — fill in the MCTS-specific command
  matrix derived from `CommandSpec`, add the self-describing CLI introspection
  contract, and defer to the doctrine on Command Topology and Progressive
  Introspection.
- `documents/engineering/code_quality.md` — describe `mcts check-code` /
  `mcts lint *` / `mcts docs check`; defer to the doctrine on Lint, Format,
  Code-Quality Stack, Generated Artifacts, and Forbidden Surfaces.
- `documents/engineering/unit_testing_policy.md` — describe the `mcts-haskell-style`
  stanza and the lint-first ordering of `mcts test all`; defer to the doctrine on
  Test Organization.
- `documents/engineering/haskell_code_guide.md` — describe how the project uses
  `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `Env`, and `AppError`; defer
  to the doctrine on each pattern.
- `documents/documentation_standards.md` — align the generated-section metadata rule with
  the Sprint `1.10` implementation and the Sprint `1.17` action-oriented generated CLI
  doc rule.
- `documents/engineering/README.md` — index the self-describing CLI contract and record
  Sprint `1.13` / Sprint `1.17` as closed.

**Product docs to create/update:**

- `README.md` — link operators to the implemented self-describing CLI contract plus the
  current backend identifier table and the `mcts play` human/spectator workflow.

**Cross-references to add:**

- `documents/cli/commands.md` (generated by Sprint `1.3`) is reachable from the
  `documents/engineering/README.md` index.
- `legacy-tracking-for-deletion.md` carries any Sprint `1.10` doctrine-deviation residue
  until the generated-doc and style contracts are reclosed.
- `legacy-tracking-for-deletion.md` records the pointer-only help / missing enum-value
  metadata row as completed by Sprint `1.13`.
- `legacy-tracking-for-deletion.md` records the thin play command-use text row as
  completed by Sprint `1.17`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
