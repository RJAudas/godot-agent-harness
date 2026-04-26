# Orchestration Script CLI Contract

All five `tools/automation/invoke-<workflow>.ps1` scripts share the
following parameter contract. Per-workflow scripts MAY add
workflow-specific *optional* parameters (documented in the script's
own `Get-Help` output) but MUST NOT change the common parameters'
names, types, or defaults.

## Common Parameters

| Parameter | Type | Default | Mandatory | Description |
|---|---|---|---|---|
| `-ProjectRoot` | `string` | — | Yes | Repo-relative or absolute path to the integration-testing sandbox the editor is running against. |
| `-RequestFixturePath` | `string` | — | One of two | Repo-relative or absolute path to a tracked fixture under `tools/tests/fixtures/runbook/`. Mutually exclusive with `-RequestJson`. Not applicable for scene inspection (no payload). |
| `-RequestJson` | `string` | — | One of two | Inline JSON string. Mutually exclusive with `-RequestFixturePath`. Not applicable for scene inspection. |
| `-TimeoutSeconds` | `int` | `60` | No | End-to-end timeout (capability check + request + poll). On exceedance, exits with `failureKind = timeout`. |
| `-MaxCapabilityAgeSeconds` | `int` | `300` | No | Maximum age of `capability.json` mtime before the editor is considered not running. On exceedance, exits with `failureKind = editor-not-running`. |
| `-PollIntervalMilliseconds` | `int` | `250` | No | How often to re-read `run-result.json` while waiting for the request to complete. |

## Common Behavior

1. Validate parameter set:
   - For workflows that take a payload: exactly one of
     `-RequestFixturePath` and `-RequestJson` MUST be supplied.
     Otherwise exit with `failureKind = request-invalid`.
2. Resolve `-ProjectRoot` relative to the script's repo root (matching
   the convention in `tools/automation/get-editor-evidence-capability.ps1`).
3. Generate a fresh `requestId` of the form
   `runbook-<workflow>-<YYYYMMDDTHHmmssZ>-<short-rand>`.
4. Invoke `tools/automation/get-editor-evidence-capability.ps1
   -ProjectRoot <resolved>`. Read
   `<ProjectRoot>/harness/automation/results/capability.json`. If
   missing or older than `-MaxCapabilityAgeSeconds`, exit with
   `failureKind = editor-not-running`.
5. Materialize the request payload:
   - If `-RequestFixturePath`: load JSON, override its `requestId` with
     the freshly generated value, write to a temp file under
     `<ProjectRoot>/harness/automation/requests/`.
   - If `-RequestJson`: parse, override its `requestId`, write
     similarly.
6. Invoke `tools/automation/request-editor-evidence-run.ps1
   -ProjectRoot <resolved> -RequestPath <temp file>`.
7. Poll `<ProjectRoot>/harness/automation/results/run-result.json`
   every `-PollIntervalMilliseconds` until its `requestId` matches the
   generated value AND `completedAt` is non-empty, OR the wall-clock
   budget exceeds `-TimeoutSeconds`. On timeout, exit with
   `failureKind = timeout`.
8. Read the manifest at the path reported by `run-result.json`.
   Validate via `pwsh ./tools/evidence/validate-evidence-manifest.ps1`.
9. Build the workflow-specific `outcome` block by reading the
   appropriate manifest `artifactRefs` (e.g.,
   `input-dispatch-outcomes` for input dispatch).
10. Emit the [Stdout JSON Envelope](orchestration-stdout.schema.json)
    to stdout exactly once.
11. Emit a single-line human summary to stderr (e.g.,
    `"OK: dispatched 2 events; manifest at <path>"` or
    `"FAIL: editor-not-running; launch with: godot --editor --path <ProjectRoot>"`).
12. Exit `0` on success, non-zero on any failure.

## Request vs `inspection-run-config.json` precedence

For every overlapping field, an inbound automation request takes precedence
over the sandbox's `inspection-run-config.json`. The config is a **defaults
source only** — it applies when no automation request is active (for example,
editor-button playtests where a human presses Play in the editor without going
through the broker).

The fields the request always wins on:

- `runId`, `scenarioId`
- `targetScene`, `outputDirectory`, `artifactRoot`
- `capturePolicy`, `stopPolicy`

When the orchestrator generates a fresh `requestId` per invocation, it also
stamps `runId = requestId` if the payload omits one. The broker's
`_resolve_request` then carries those request values through unchanged; the
runtime's `_load_session_config` is skipped entirely when an automation
request is active. This three-layer guarantee is intentional belt-and-braces
so a config-bearing sandbox can never silently overrule the agent.

## Per-Workflow Differences

| Script | Takes payload? | Workflow-specific optional parameters |
|---|---|---|
| `invoke-input-dispatch.ps1` | Yes | — |
| `invoke-scene-inspection.ps1` | No (uses `capturePolicy.startup = true` payload synthesized internally) | — |
| `invoke-behavior-watch.ps1` | Yes | — |
| `invoke-build-error-triage.ps1` | Yes (a minimal "build then capture" request) | `-IncludeRawBuildOutput` (switch) |
| `invoke-runtime-error-triage.ps1` | Yes | `-IncludeFullStack` (switch) |

## Stability Guarantees

- Common parameter names, defaults, and types are **stable**. Changes
  require a spec amendment.
- Stdout envelope keys (status, failureKind, manifestPath, runId,
  requestId, completedAt, diagnostics, outcome) are **stable**.
- Workflow-specific `outcome` shapes follow the table in
  [data-model.md](../data-model.md). Adding optional keys is
  non-breaking; removing or renaming requires a spec amendment.
- A future MCP server SHOULD wrap these scripts as subprocesses with no
  re-implementation of orchestration; per-script MCP tool definitions
  map 1:1 to the parameter table above.
