# Data Model: Run-Artifact Evidence Lifecycle

**Feature**: 009-evidence-lifecycle | **Plan**: [plan.md](./plan.md) | **Research**: [research.md](./research.md)

This document is the single documented location for zone classification (FR-001): every file the harness writes into a target project is mapped here to exactly one of `transient`, `pinned`, `oracle`, or `input`.

## Zones

### Transient zone

**Location** (inside any target project): `harness/automation/results/` and `evidence/automation/`.
**Ownership**: Written by the addon's `ScenegraphAutomationArtifactStore` (editor) and `ScenegraphArtifactWriter` (runtime). Cleared by `Initialize-RunbookTransientZone` in `tools/automation/RunbookOrchestration.psm1`.
**Lifecycle**:

```text
      ┌─────────┐   orchestration script invoked
      │  empty  │ ──────────────────────────────────┐
      └─────────┘                                   ▼
         ▲                                  ┌───────────────────┐
         │                                  │ in-flight marker  │
         │                                  │ written           │
         │                                  └───────────────────┘
         │                                           │
         │                                           ▼
         │                                  ┌───────────────────┐
         │                                  │ cleanup runs      │
         │                                  │ (clears prior     │
         │                                  │  run's files,     │
         │                                  │  keeps marker)    │
         │                                  └───────────────────┘
         │                                           │
         │                                           ▼
         │                                  ┌───────────────────┐
         │  next invocation's cleanup       │ request dispatched│
         └──────────────────────────────────│ addon writes      │
                                            │ run-result,       │
                                            │ lifecycle, evidence│
                                            └───────────────────┘
                                                    │
                                                    ▼
                                            ┌───────────────────┐
                                            │ in-flight marker  │
                                            │ cleared           │
                                            └───────────────────┘
```

**Tracked by git**: Never. Covered by the `.gitignore` rules in `research.md` §4.

### Pinned zone

**Location** (inside any target project): `harness/automation/pinned/<pin-name>/`.
**Ownership**: Created by `invoke-pin-run.ps1`, removed by `invoke-unpin-run.ps1`, read by `invoke-list-pinned-runs.ps1`. The addon never writes here directly.
**Lifecycle**: Created by explicit pin operation; immutable thereafter except by explicit unpin. No automatic cleanup paths reach it.
**Tracked by git**: Never by default. Pinned runs are per-project debugging snapshots; a contributor who wants to share one copies it out of the project tree by hand (a deliberate act, not an accident).

### Oracle files (not a zone — a distinct classification)

**Location**: `tools/tests/fixtures/**/*.expected.json` and any committed request fixtures under `tools/tests/fixtures/**/harness/automation/requests/*.json`.
**Ownership**: Hand-authored / reviewed / committed. Used as inputs and assertions by the Pester suite.
**Tracked by git**: Always. Re-included by the `!**/harness/automation/results/*.expected.json` line in the new `.gitignore` rules.

### Input files (not a zone — a distinct classification)

**Location**: `harness/automation/requests/` inside a target project.
**Ownership**: Written by orchestration scripts (`invoke-*.ps1`) immediately before dispatch; read by the editor-side addon.
**Tracked by git**: In fixture directories (yes, these are request oracles). In integration-testing sandboxes (no, those are per-agent scratch).

## Classification table

This is the FR-001 table. Every runtime-written filename is listed exactly once.

| Filename / glob                                         | Parent directory                    | Zone/Classification | Cleared by transient cleanup?                | Notes                                                                   |
| ------------------------------------------------------- | ----------------------------------- | ------------------- | -------------------------------------------- | ----------------------------------------------------------------------- |
| `capability.json`                                       | `harness/automation/results/`       | editor-state        | **No** — preserved by cleanup                | Editor heartbeats this file on its own cadence; wiping creates a window where invoke scripts mis-report `editor-not-running` |
| `lifecycle-status.json`                                 | `harness/automation/results/`       | transient           | Yes                                          | Written by editor-side run coordinator                                  |
| `run-result.json`                                       | `harness/automation/results/`       | transient           | Yes                                          | Written by editor-side run coordinator                                  |
| `run-request.json`                                      | `harness/automation/results/`       | transient           | Yes                                          | Echoed copy of the live request the editor is acting on                 |
| `.in-flight.json`                                       | `harness/automation/results/`       | transient marker    | **No** — preserved by cleanup; cleared on exit | See `contracts/in-flight-marker.schema.json`                            |
| `evidence-manifest.json`                                | `evidence/automation/<runId>/`      | transient           | Yes                                          | Referenced by FR-012; pinned copy lives under pinned zone instead       |
| `trace.jsonl`                                           | `evidence/automation/<runId>/`      | transient           | Yes                                          | Behavior-watch rows                                                     |
| `scenegraph-snapshot.json`                              | `evidence/automation/<runId>/`      | transient           | Yes                                          |                                                                          |
| `scenegraph-diagnostics.json`                           | `evidence/automation/<runId>/`      | transient           | Yes                                          |                                                                          |
| `scenegraph-summary.json`                               | `evidence/automation/<runId>/`      | transient           | Yes                                          |                                                                          |
| `input-dispatch-outcomes.jsonl`                         | `evidence/automation/<runId>/`      | transient           | Yes                                          |                                                                          |
| `runtime-error-records.jsonl`                           | `evidence/automation/<runId>/`      | transient           | Yes                                          | Runtime-error reporting rows (feature 007)                              |
| `pause-decision-log.jsonl`                              | `evidence/automation/<runId>/`      | transient           | Yes                                          | Pause-decision events (feature 007)                                     |
| `last-error-anchor.json`                                | `evidence/automation/<runId>/`      | transient           | Yes                                          | Most-recent runtime-error anchor (feature 007)                          |
| `build-errors.jsonl`                                    | `evidence/automation/<runId>/`      | transient           | Yes                                          | GDScript compile-error diagnostics                                      |
| `pin-metadata.json`                                     | `harness/automation/pinned/<pin>/`  | pinned              | No                                           | Sidecar metadata written at pin time                                    |
| `run-result.json` (pinned copy)                         | `harness/automation/pinned/<pin>/results/` | pinned       | No                                           | Byte-identical to transient at pin time                                 |
| `lifecycle-status.json` (pinned copy)                   | `harness/automation/pinned/<pin>/results/` | pinned       | No                                           | Byte-identical to transient at pin time                                 |
| `evidence-manifest.json` (pinned copy)                  | `harness/automation/pinned/<pin>/evidence/<runId>/` | pinned | No                                     | Byte-identical to transient at pin time                                 |
| (all artifacts referenced by pinned manifest)           | `harness/automation/pinned/<pin>/evidence/<runId>/` | pinned | No                                     | Byte-identical copies                                                   |
| `*.expected.json`                                       | `tools/tests/fixtures/*/harness/automation/results/` | oracle | Never (not in any zone) | Committed test oracles                                                  |
| `run-request.*.json` / `run-request.<variant>.json`     | `tools/tests/fixtures/*/harness/automation/requests/` | input | Never | Committed request fixtures used as script inputs                       |
| `run-request.json` (integration-testing sandbox)        | `integration-testing/*/harness/automation/requests/` | input (ephemeral) | No — written fresh per run | Still inside the sandbox; the outer `integration-testing/*` gitignore keeps them out of git |

**Rule derived from this table**: an artifact is cleared before a new run if-and-only-if its Zone column says `transient`. The in-flight marker is the sole named exception and is governed by §In-flight marker below.

## Entities

### `RunZoneClassification`

The rows above, encoded machine-readably as a static PowerShell map inside `RunbookOrchestration.psm1` so `Initialize-RunbookTransientZone` can compute the exact delete set from filename globs without hard-coding paths per script. One source of truth for the table.

### `InFlightMarker`

Schema: `contracts/in-flight-marker.schema.json`.
Fields: `schemaVersion`, `requestId`, `invokeScript`, `pid`, `hostname`, `startedAt`, `toolVersion` (optional).
Created: by `New-RunbookInFlightMarker` immediately before cleanup.
Cleared: by `Clear-RunbookInFlightMarker` in a `try/finally` block wrapping the orchestration body.
Staleness: per `research.md` §2 — alive-PID check + 2× timeout horizon.
Concurrent-invocation collision: fail fast with `failureKind: "run-in-progress"`, echo marker contents into `diagnostics[0]`.

### `PinnedRun`

Filesystem layout: `harness/automation/pinned/<pin-name>/` per `research.md` §3.
Name constraint: `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`.
Immutability: enforced by the three pin operations — pin refuses on name collision (FR-005), unpin refuses without `-Confirm` unless `-DryRun` (FR-007), list never writes.
Collision behavior: clarification Q3 — refuse by default; `-Force` overwrites.
Empty-run refusal: clarification Q5 scope + spec edge case — pin refuses if the transient zone has no `evidence-manifest.json`.

### `PinnedRunIndex`

Schema: `contracts/pinned-run-index.schema.json`.
Produced by: `Get-PinnedRunIndex` in `RunbookOrchestration.psm1`, consumed by `invoke-list-pinned-runs.ps1`.
Generation: walks `harness/automation/pinned/*/pin-metadata.json`, cross-references each pin's `run-result.json` for `status`.
Missing metadata: a pinned directory without `pin-metadata.json` shows up with `status: "unknown"` and a `diagnostics[]` note — the list operation never crashes on a legacy or hand-created pin directory.

### `LifecycleEnvelope`

Schema: `contracts/lifecycle-envelope.schema.json`.
Emitted by: cleanup, pin, unpin, list operations.
Shared core: `status`, `failureKind`, `diagnostics[]`, `completedAt` from `orchestration-stdout.schema.json`.
Extensions: `operation`, `dryRun`, `plannedPaths[]`, `pinName`, `pinnedRunIndex[]`.

## State transitions summary

1. **Transient zone** — each orchestration invocation drives the state machine in §Transient zone above. The zone's only steady states are `empty` (fresh clone, or post-cleanup pre-dispatch) and `complete` (post-run); any other state is transitional and bounded by the lifetime of a single invocation.
2. **Pinned zone** — states per pin: `absent` → (pin) → `present-immutable` → (unpin) → `absent`. Pin-with-force compresses `present-immutable → absent → present-immutable` atomically.
3. **In-flight marker** — `absent` → (new invocation) → `present-live` → (normal exit OR next-invocation staleness recovery) → `absent`. A `present-stale` pseudo-state is observable only from a *later* invocation's point of view and auto-transitions to `absent` immediately on detection.

## Invariants

- **I-01 (Zone partition)**: Every file written by the addon or by an orchestration script is in exactly one of `transient`, `pinned`, `oracle`, or `input`. No file is in two zones; no runtime-written file is unclassified.
- **I-02 (Cleanup locality)**: Transient cleanup never touches `pinned`, `oracle`, or `input` files. Enforced by filename-glob classification rather than directory traversal.
- **I-03 (In-flight exclusivity)**: At most one live marker exists per target project. A second live marker is a bug; a second *stale* marker is impossible (the only writer that encounters one deletes it before proceeding).
- **I-04 (Pinned immutability by default)**: A `PinnedRun`'s artifacts are byte-identical to the transient state they were copied from. Pin names are stable identifiers; pin contents are stable bytes.
- **I-05 (Git cleanliness)**: After any sequence of orchestration invocations against a clean working tree, `git status --porcelain` is empty relative to the transient and pinned zones. This is the US2/SC-001 invariant and the CI-enforceable one.
