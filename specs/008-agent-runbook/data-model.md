# Data Model — Agent Runbook & Parameterized Harness Scripts

This feature does not introduce new runtime entities. The data model
below describes the tracked repo-side artifacts the feature *adds* and
the small JSON shapes those artifacts depend on. Existing harness
contracts (manifest, scene-tree JSON, input-dispatch outcomes JSONL,
behavior-watch samples, build/runtime error records) are reused as-is.

## Tracked Artifacts (added by this feature)

### Runbook (`RUNBOOK.md`)

Top-level Markdown file. Single workflow index. One row per workflow.

| Field | Description | Example |
|---|---|---|
| Workflow name | Human label, matches the recipe filename stem | `Input dispatch` |
| One-line description | What the workflow proves | `Dispatch keys / actions and capture the resulting scene state.` |
| Orchestration script | Repo-relative path to the `invoke-*.ps1` script | `tools/automation/invoke-input-dispatch.ps1` |
| Canonical fixture | Repo-relative path, or "no payload" | `tools/tests/fixtures/runbook/input-dispatch/press-enter.json` |
| Recipe link | Markdown link to `docs/runbook/<workflow>.md` | `[Recipe](docs/runbook/input-dispatch.md)` |

Constraints:
- All linked paths MUST exist (verified by Pester static check).
- The five workflows MUST appear in this order: input dispatch, scene
  inspection, behavior watch, build-error triage, runtime-error triage.

### Workflow Recipe (`docs/runbook/<workflow>.md`)

Per-workflow Markdown. Numbered, copy-pasteable steps. One file per
workflow (5 total).

Required sections (all H2):
1. **Prerequisites** — Bullet list (editor running, fixture chosen, etc.)
2. **Run it** — A single fenced PowerShell block showing the canonical
   `pwsh ./tools/automation/invoke-<workflow>.ps1 ... ` invocation.
3. **Expected output** — The successful stdout JSON envelope shape with
   the workflow-specific `outcome` block illustrated.
4. **Failure handling** — Bullet table of `failureKind` → recommended
   agent next step, citing the diagnostic field to read.
5. **Anti-patterns** — Explicit "do not do this" list. MUST contain the
   "do not read addon source" callout (canonical marker — see
   research.md SC-002 decision).

Optional section: **Inline payload** — example of using `-RequestJson`
instead of `-RequestFixturePath`.

### Request Fixture Template (`tools/tests/fixtures/runbook/<workflow>/<name>.json`)

Schema-valid request payloads. Tracked. One JSON file per template.

Each fixture MUST validate against the corresponding upstream contract:
- Input dispatch → `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json` (when wrapped in an `inputDispatchScript` field of the larger run-request shape used by `request-editor-evidence-run.ps1`).
- Behavior watch → `specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json`.
- Scene inspection → uses the standard `request-editor-evidence-run.ps1` payload with `capturePolicy.startup = true` (no behavior/input payload).

The fixture file's top-level shape mirrors the existing
`tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.healthy.json`
template: at minimum `requestId`, `scenarioId`, `runId`, `targetScene`,
`outputDirectory`, `artifactRoot`, `capturePolicy`, plus the
workflow-specific payload field.

### Orchestration Script (`tools/automation/invoke-<workflow>.ps1`)

PowerShell script. Five total. One per workflow. Each:

- Has comment-based help producing complete `Get-Help <script> -Full`
  output (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for every parameter,
  at least one `.EXAMPLE`).
- Accepts the parameters in the [Orchestration CLI Contract](contracts/orchestration-cli.md).
- Emits the [Stdout JSON Envelope](contracts/orchestration-stdout.schema.json)
  to stdout exactly once.
- Emits a one-line human summary to stderr.
- Exits 0 on success, non-zero on any failure.

## Stdout JSON Envelope

See [`contracts/orchestration-stdout.schema.json`](contracts/orchestration-stdout.schema.json) for the formal schema. Summary:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "C:/.../evidence-manifest.json",
  "runId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "requestId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": { "...": "workflow-specific" }
}
```

## Per-Workflow `outcome` Blocks

| Workflow | `outcome` keys |
|---|---|
| Input dispatch | `outcomesPath` (path to `input-dispatch-outcomes.jsonl`), `dispatchedEventCount` (int), `firstFailureSummary` (string \| null) |
| Scene inspection | `sceneTreePath` (path to captured `scene-tree.json`), `nodeCount` (int) |
| Behavior watch | `samplesPath` (path to behavior samples artifact), `sampleCount` (int), `frameRangeCovered` (`{first, last}` ints) |
| Build-error triage | `rawBuildOutputPath` (string \| null), `firstDiagnostic` (`{file, line, message}` \| null) |
| Runtime-error triage | `runtimeErrorRecordsPath` (string \| null), `latestErrorSummary` (`{file, line, message}` \| null), `terminationReason` (string) |

## Relationships

```
RUNBOOK.md (1) ──┬── docs/runbook/<workflow>.md (5)
                 ├── tools/automation/invoke-<workflow>.ps1 (5)
                 └── tools/tests/fixtures/runbook/<workflow>/*.json (≥6 total)

invoke-<workflow>.ps1
  → calls tools/automation/get-editor-evidence-capability.ps1   (existing)
  → calls tools/automation/request-editor-evidence-run.ps1      (existing)
  → reads <ProjectRoot>/harness/automation/results/capability.json
  → reads <ProjectRoot>/harness/automation/results/run-result.json
  → emits Stdout JSON Envelope (this feature's contract)
```

## Validation Rules

- Every `RUNBOOK.md` row's three paths (script, fixture, recipe) MUST resolve.
- Every fixture under `tools/tests/fixtures/runbook/` MUST validate against its upstream contract via `pwsh ./tools/validate-json.ps1`.
- Every orchestration script's stdout MUST validate against `contracts/orchestration-stdout.schema.json`.
- No agent-facing recipe text under `docs/runbook/` or in the updated `.github/prompts/`/`.github/agents/` files MAY contain `addons/agent_runtime_harness/` outside of the canonical "do not read" callout marker.

## Out of Scope (explicit)

- New addon code, autoload code, debugger code, or GDExtension code.
- New low-level harness contracts or schema changes.
- Diagnosis trace instrumentation (deferred per Q1).
- MCP server design or implementation (deferred).
