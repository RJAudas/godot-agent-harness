# Phase 0 Research: Run-Artifact Evidence Lifecycle

**Feature**: 009-evidence-lifecycle | **Plan**: [plan.md](./plan.md)

Six open questions raised in `plan.md` §Phase 0. Each is resolved here with Decision / Rationale / Alternatives.

---

## 1. Atomic transient-zone cleanup on Windows

**Decision**: Use a two-step clear: enumerate the transient-zone files that match the declared classification, then `Remove-Item -LiteralPath -Force` one by one. On failure, retry once after a 50 ms back-off; on a second failure, abort the orchestration call and surface the unreleased path in the stdout envelope's `diagnostics[]` array (honoring FR-010 — no silent partial cleanup). Clearing is performed inside `Initialize-RunbookTransientZone` in `RunbookOrchestration.psm1` and runs **after** the in-flight marker is written (so a concurrent second caller sees the marker and fails fast before the first caller's cleanup races against it).

**Rationale**: The transient zone is small (a handful of JSON/JSONL files + the `evidence/<runId>/` subtree that belongs to the *prior* run), so a per-file loop is fast enough to meet the Technical Context ≤ 500 ms budget. A single `Remove-Item -Recurse` on a directory the Godot editor still holds open would raise an opaque "in use" error whose diagnostic value is poor; per-file deletes let the script attribute the lock to the exact file and report it. The retry covers the common Windows lag between process-exit and OS handle release (antivirus scanners, indexer). This matches the pattern already used in `RunbookOrchestration.psm1` for `.tmp/` test-sandbox teardown.

**Alternatives considered**:
- *Rename-then-delete (swap-out)*: Move the transient directory to `harness/automation/results.old/` and delete asynchronously. Rejected — adds a new directory that `git status` must also ignore, and Windows rename-while-open on a locked file fails too.
- *Blow away the whole `harness/automation/results/` directory*: Rejected — the `requests/` sibling holds `.gitkeep` files and fixture requests that the orchestration run *needs* to preserve (they are the input, not output). The classification table in `data-model.md` enumerates exactly what is transient.
- *Filesystem transaction APIs (TxF)*: Rejected — deprecated by Microsoft, no pwsh surface.

---

## 2. In-flight marker format

**Decision**: A single JSON file at `<project>/harness/automation/results/.in-flight.json`, classified as transient. Schema (full spec in `contracts/in-flight-marker.schema.json`):

```json
{
  "schemaVersion": "1.0.0",
  "requestId": "<GUID>",
  "invokeScript": "invoke-input-dispatch.ps1",
  "pid": 12345,
  "hostname": "DEV-BOX-03",
  "startedAt": "2026-04-23T14:30:22Z",
  "toolVersion": "0.9.0"
}
```

Created immediately before `Initialize-RunbookTransientZone` runs its cleanup (so the marker survives the clear — cleanup explicitly skips `.in-flight.json`), cleared in a `try/finally` on script exit regardless of success/failure. A concurrent invocation that finds an existing marker calls `Test-InFlightMarkerStaleness`:

- If `Get-Process -Id <pid>` returns a live process **and** that process's name is `pwsh.exe` or `powershell.exe`, the marker is treated as *active* and the new invocation fails fast with `failureKind: "run-in-progress"` and the marker contents echoed into `diagnostics[0]`.
- Otherwise (PID gone, or PID reassigned to a non-pwsh process, or `startedAt` older than 2× the orchestration timeout — 120 s default), the marker is treated as *stale*, deleted, and the new invocation proceeds. The stdout envelope records a `diagnostics` entry noting the recovered-from-stale-marker condition so the agent can correlate with a prior crash.

**Rationale**: The marker must (a) survive the very cleanup it guards, (b) be inspectable by humans without specialized tooling, (c) carry enough identity to recover safely after a process crash. A filename that starts with `.` keeps it visually distinct from artifact files that start with letters; putting it inside `harness/automation/results/` avoids needing a new directory (so the gitignore rules from §4 cover it automatically). PID + hostname + timestamp gives deterministic staleness detection without requiring OS-level lock primitives (which would not survive a reboot). The 2× timeout horizon handles the case where the orchestration script itself died mid-poll — the next invocation auto-recovers instead of the user being told to manually delete a file.

**Alternatives considered**:
- *OS advisory lock via `[System.IO.FileStream]` with `FileShare.None`*: Rejected — releases on process crash (good) but provides no readable metadata for the failure message (bad), and the "what crashed when" context is the whole value proposition here.
- *PID-only, no timestamp*: Rejected — PID reuse on long-running machines would falsely claim a run is active. Combining PID + process-name match + timestamp horizon makes false positives vanishingly rare.
- *Separate lock directory*: Rejected — one more path to ignore; a single JSON file in an already-ignored directory is simpler.

---

## 3. Pinned zone path convention

**Decision**: `<project>/harness/automation/pinned/<pin-name>/` with a layout that mirrors the live transient zone's shape:

```text
harness/automation/pinned/<pin-name>/
├── pin-metadata.json          # schemaVersion, pinName, pinnedAt, sourceRunId, sourceScenarioId
├── results/
│   ├── run-result.json        # copy of the transient run-result at pin time
│   └── lifecycle-status.json  # copy of the transient lifecycle-status at pin time
└── evidence/<runId>/
    ├── evidence-manifest.json
    └── <workflow artifacts the manifest references>
```

The copy is byte-identical to the transient state at pin time — no fields rewritten, so `jq`/schema-based diffs between a pinned run and a live run compare apples to apples. The one exception is `pin-metadata.json`, a new file present only in the pinned copy. Pin names are validated against `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$` (no path separators, no leading dots, length-bounded) to prevent filesystem-traversal pranks and cross-platform breakage.

**Rationale**: Mirroring the live layout means the recipe docs can say *"run `invoke-*.ps1` against the pinned subtree to inspect it the same way you'd inspect a live run"* without any mental translation. The `pin-metadata.json` sidecar records the pin's name and source so a list operation can enumerate pins without walking into every manifest, and so a human who stumbles into the directory sees context immediately. The regex for pin names is a standard cross-platform safe-identifier pattern.

**Alternatives considered**:
- *Flat per-pin directory* (`<pin-name>/everything-in-one-place.json`): Rejected — breaks the "diff against a live run" ergonomic and loses the manifest→artifacts relationship that agents already know how to walk.
- *Repo-level pinned store* (`.speckit/pins/` or similar at the repo root): Rejected — pinned runs are per-sandbox-project by nature (they reference `runId`s that only make sense in the project that produced them). Keeping the pinned zone inside the target project matches the transient zone's scoping.
- *Hash-addressed pin names* (auto-generate SHA from manifest): Rejected — the spec's explicit requirement is "a stable, agent-chosen name" (FR-005).

---

## 4. `.gitignore` pattern precedence

**Decision**: Add the following block to the repo-root `.gitignore` (and to the deployed-project `.gitignore` under `addons/agent_runtime_harness/templates/project_root/.gitignore`):

```gitignore
# Harness runtime output (see specs/009-evidence-lifecycle/)
# Transient zone — cleared between runs
**/harness/automation/results/
# Pinned zone — preserved deliberately; ignored by default, pin explicitly to share
**/harness/automation/pinned/
# Per-run evidence trees
**/evidence/automation/

# Re-include committed test oracles (*.expected.json) so the Pester suite still sees them
!**/harness/automation/results/
!**/harness/automation/results/*.expected.json
```

The re-include pattern works because `.expected.json` files live at the first level inside `harness/automation/results/` — no nested directories to traverse — so the negation `!` rule is a valid re-include per Git's rule-precedence ordering. The re-include opens the directory (required: Git won't descend into an ignored directory to find `!`-exceptions) and then only surfaces files matching `*.expected.json`.

Before shipping this block, run `git check-ignore -v` against:

- `tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.success.expected.json` → must be *not* ignored.
- `tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.json` → must be ignored.
- `tools/tests/fixtures/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-frame/evidence-manifest.json` → must be ignored.
- `tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.healthy.json` → must be *not* ignored (requests are committed fixtures).

**Rationale**: The `**/` prefix is required because the fixture-doubled-as-runtime pattern isn't unique to one sandbox — it also applies to any future testbed under `tools/tests/fixtures/*` and to deployed projects. The re-include comes paired with re-opening the parent directory because of Git's documented descendant-rule: *"it is not possible to re-include a file if a parent directory of that file is excluded."*

**Alternatives considered**:
- *Per-fixture `.gitignore` files inside each testbed*: Rejected — requires remembering to add one for every new fixture, violating the spec's "clean by default for fresh contributors" (SC-005).
- *Global exclude file* (`.git/info/exclude`): Rejected — not shared across contributors.
- *`.gitattributes` with `export-ignore`*: Rejected — affects archive generation, not working-tree status.

---

## 5. Dry-run envelope format

**Decision**: Lifecycle operations (cleanup, pin, unpin, list) emit an envelope defined by a new `contracts/lifecycle-envelope.schema.json` that `$ref`s the existing `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` shared-core fields (`status`, `failureKind`, `diagnostics[]`, `completedAt`) and adds:

- `operation`: enum `["cleanup" | "pin" | "unpin" | "list"]`
- `dryRun`: boolean — true when the caller passed `-WhatIf` / `-DryRun`; mutations MUST NOT occur when true.
- `plannedPaths[]`: array of `{ "path": "<relative-to-project-root>", "action": "delete" | "copy" | "create" }` — populated on both dry-run and real runs (on a real run, this is the audit trail of what the operation did).
- `pinName`: string | null — populated for pin/unpin/list responses.
- `pinnedRunIndex[]`: array — populated only for `list`, shape defined in `contracts/pinned-run-index.schema.json`.

The `manifestPath` field from the shared core is omitted for cleanup/pin/unpin/list (it is workflow-evidence-bearing, which these operations don't produce), but remains present-and-null so Pester assertions that reach for it don't need a new code path.

**Rationale**: Reusing the core envelope fields means the `RunbookOrchestration.psm1` `Write-RunbookEnvelope` helper extends naturally — one new code path inside the existing writer instead of a parallel writer. Keeping `plannedPaths[]` populated on real runs (not only dry-runs) gives the agent a free audit trail of every file touched, which is the evidence backbone for SC-006 ("no recipe instructs ad-hoc deletion") — the agent can always point at `plannedPaths[]` rather than doing its own enumeration.

**Alternatives considered**:
- *Disjoint new schema with no shared core*: Rejected — doubles the Pester assertion surface and forces agents to learn two envelope shapes.
- *Only populate `plannedPaths[]` on dry-run*: Rejected — loses the audit trail on real runs, which the recipe static-check needs.

---

## 6. Pinned-run index schema

**Decision**: `contracts/pinned-run-index.schema.json` defines an array of pin records:

```json
{
  "schemaVersion": "1.0.0",
  "pins": [
    {
      "pinName": "bug-repro-jumpscare",
      "manifestPath": "harness/automation/pinned/bug-repro-jumpscare/evidence/<runId>/evidence-manifest.json",
      "scenarioId": "pong-behavior-watch-wall-bounce-every-frame",
      "runId": "<runId from source manifest>",
      "pinnedAt": "2026-04-23T14:45:00Z",
      "status": "pass | fail | mixed | unknown",
      "sourceInvokeScript": "invoke-behavior-watch.ps1"
    }
  ]
}
```

All pin-record fields are required except `sourceInvokeScript` (some legacy pins predating this spec may omit it — the list operation tolerates null there and records `unknown`). `manifestPath` is project-root-relative so an agent can pass it straight to downstream tooling without path surgery. `status` is sourced from the pinned `run-result.json`'s `status` field, not re-derived.

**Rationale**: Every field above answers a specific agent question: "which pin?" (`pinName`), "where's the evidence?" (`manifestPath`), "what scenario?" (`scenarioId`), "did it pass?" (`status`), "when?" (`pinnedAt`), "which workflow?" (`sourceInvokeScript`). Anything more (diagnostics, full outcomes) should be read from the pinned manifest — duplicating it in the index would drift.

**Alternatives considered**:
- *Flat map keyed by pinName*: Rejected — arrays serialize deterministically for diff-ability, objects do not.
- *Include a content-hash for tamper detection*: Rejected — over-engineering for a per-project local zone; callers that need integrity can walk the manifest themselves.
- *Embed the full manifest inline*: Rejected — breaks streaming reads and forces every list call to parse potentially-large manifests.

---

## Cross-cutting: migration of the existing pong-testbed artifacts

Not a new research question — already decided in the spec clarification (FR-004: remove from the index). Phase 2 tasks will:

1. `git rm --cached` the 14 files enumerated in the survey (13 evidence/* + 1 `harness/expected-evidence-manifest.json`).
2. Commit the new `.gitignore` rules **in the same commit** so no intermediate state has the files ignored-but-tracked.
3. Re-run the Pester suite against the fixture to confirm oracle files (`*.expected.json`) still resolve correctly.

No filesystem delete of the working-tree copies is necessary — they become untracked and can be removed locally at each contributor's discretion.
