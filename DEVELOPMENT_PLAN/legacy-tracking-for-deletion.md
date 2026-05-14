# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Record every surviving compatibility helper, deprecated path, doctrine
> deviation, and tooling residue still slated for deletion, plus the completed
> retirement history under the (i)→(ii)→(iii)→(v) protocol.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

The repository now contains an active logical baseline. The rows below track
intentional stand-ins that keep the CLI, transcript, cache, and test surfaces runnable
while the real backend and parity work lands. These rows must move to `Completed` only
when the owning sprint replaces the stand-in with the target implementation and the
validation gate passes.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented code
   does not yet honour against an in-scope doctrine section, scheduled through the
   owning sprint per standards rule L.
2. **Retirement protocol entries.** Each retiring backend's CLI flag value, build
   artefact, and shared library is moved to `Pending Removal` at the start of its
   retirement (Phase `8`) and to `Completed` when the surviving cohort's golden
   transcripts and throughput numbers freeze in `test/golden/<backend>/`. The
   retirement order is `cpp-legacy` (after Q6 closure), then `cpp-imperative` (after
   `cpp-functional` reaches parity), then `cpp-functional` (after `haskell` reaches
   parity). Backend (iv) Rust remains live throughout.

`MCTS_legacy` itself lives at `~/MCTS_legacy/` and is not in this repository; legacy
entries here track only shims and compatibility helpers introduced *inside* this
repository that are slated for removal. The `cpp-legacy/` sources are themselves a
verbatim re-port plus FFI shims, not a legacy artefact — they are a current supported
backend until Phase `8` retirement closes Q6.

## Pending Removal

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| Logical five-backend in-process stand-in | `src/MCTS/Engine.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Verify.hs` | Lets CLI and tests validate determinism surfaces before real Haskell/C++/Rust engines are complete; must be replaced by real backend dispatch | Sprint 3.3, Sprint 4.4, Sprint 5.4, Sprint 6.2, Sprint 6.4 |
| Foreign backend smoke skeletons | `cpp-legacy/`, `cpp-imperative/`, `cpp-functional/`, `rust/` | Provides concrete source homes and smoke build targets; final contract requires verbatim legacy port, optimized C++ engines, Rust engine, and Haskell FFI bindings | Sprint 4.1, Sprint 5.1, Sprint 6.1, Sprint 6.3 |
| Generated command-doc drift | `src/MCTS/CLI/Docs.hs`, `documents/cli/commands.md` | The on-disk command markdown currently contains governed-doc metadata and an extra command row not emitted by `renderCommandMarkdown`; final docs generation must be byte-stable before `mcts docs check` can close | Sprint 1.3 |
| Comma-list report-card benchmark placeholder | `src/MCTS/CLI/Test.hs`, `src/MCTS/CLI/Parser.hs` | `mcts test all` passes comma-separated backend lists to `bench`, while the current bench parser selects a single backend; final report-card execution must iterate the typed backend matrix | Sprint 7.3 |
| Logical report-card placeholders | `src/MCTS/ReportCard.hs` | Allows `mcts test all --dry-run` and renderer smoke tests; final report card must use measured Q1-Q7 evidence | Sprint 7.3, Sprint 8.3 |

## Pending Removal Notes

Each pending-removal row resolves on the closure of the owning sprint listed in the
relevant phase document. Each row will move to `Completed` when the owning sprint closes
and the doctrine-required replacement is verified (or, for retirement entries, when the
surviving cohort's golden anchor freezes).

The expected populating events are:

- **Phase 1.** Any doctrine-adoption gap surfaced by Sprint `0.2`'s grep audit enqueues
  here under its owning Phase `1`–`8` sprint. The audit's job is to ensure no gap is
  silently adopted; the ledger is where unowned gaps would become visible.
- **Phase 4.** If backend (i)'s verbatim re-port introduces any code-level adjustment
  beyond FFI shims (an adjustment that goes beyond what the legacy itself contained), the
  adjustment enqueues here under Sprint `4.N` as residue to revert before retirement.
- **Phase 5/6.** If backend (ii)'s or (iii)'s tuning stack departs from the doctrine's
  named flags in either direction — extra flags or missing flags — the deviation
  enqueues here. The 16-item tuning checklist in
  [../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md)
  is the reference list against which the deviation is judged.
- **Phase 8.** The retirement protocol populates this section with one row per retiring
  backend at the start of its retirement, then moves the row to `Completed` once the
  surviving cohort's golden anchor freezes.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Deterministic placeholder transcript hash | Sprint 2.2 baseline closure | Replaced `pseudoSha256Hex` in `src/MCTS/Transcript.hs` with the pure SHA-256 implementation in `src/MCTS/Crypto/SHA256.hs`; `runConfigHash` and `playTranscriptHash` now emit SHA-256 hex digests. |
| No-op sidecar cache and divergence inspect placeholders | Sprint 2.7 / Sprint 7.5 baseline closure | Replaced fixed `inspect cache list`, `inspect cache prune`, and `inspect divergence` output with `MCTS.Transcript.EquitySidecar` cache discovery/pruning and `MCTS.Verify.Divergence` metric rendering. |
| Missing baseline envelope verification and legacy-parity workload dispatch | Sprint 7.5 baseline closure | Added `MCTS.Verify.Envelope`, `--allow-stale` parser/execution plumbing, `inspect show --envelope`, and fixed `verify legacy-parity rollouts` so the parsed workload reaches execution. |

## Retirement Protocol Reference

The retirement chain documented in [00-overview.md](00-overview.md) and owned by
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md):

| Order | Retiring Backend | Trigger | Surviving Cohort | Frozen Anchor |
|-------|------------------|---------|------------------|---------------|
| 1 | `cpp-legacy` (i) | Q6 closure: `cpp-legacy` reproduces `MCTS_legacy` byte-for-byte on benchmark (b) under the golden fixture set | `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | `test/golden/cpp-legacy/` |
| 2 | `cpp-imperative` (ii) | `cpp-functional` reaches parity with `cpp-imperative` on Q1 and Q2 | `cpp-functional`, `rust`, `haskell` | `test/golden/cpp-imperative/` |
| 3 | `cpp-functional` (iii) | `haskell` reaches parity with `cpp-functional` on Q1 and Q2 | `rust`, `haskell` | `test/golden/cpp-functional/` |
| — | `rust` (iv) | _(does not retire; kept as the long-running cross-language second opinion throughout)_ | — | — |
| — | `haskell` (v) | _(target; does not retire)_ | — | — |

Q7 and the `mcts-legacy-parity` test stanza retire alongside backend (i), since both
require a live (i) binary to participate in the 5-way round-robin. The transitive parity
chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)` becomes a frozen historical fact recorded in
`test/golden/legacy/` rather than a continuously re-run check. Q3 and the
`mcts-cross-backend` stanza continue with whatever subset of (ii)–(v) is still live.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
