# Agent Runbook — Godot Agent Harness

A one-stop index of the supported runtime-verification and evidence-lifecycle
workflows. Each row links to a copy-pasteable orchestration script and a
step-by-step recipe.

> **Where to start**: Pick the workflow you need, run the linked script,
> read the stdout JSON envelope, then follow the linked recipe for failure
> handling. You do **not** need to understand the harness internals to use
> this runbook — the scripts wrap the full capability-check → request →
> poll → manifest-read loop.

## How runs are cleaned

Every runtime-verification script automatically clears the transient zone
(`harness/automation/results/` and `evidence/automation/`) before dispatching
a new request. You never need to delete output files manually. To keep a run
across future cleanups, pin it first — see the lifecycle workflows below and
[specs/009-evidence-lifecycle/quickstart.md](specs/009-evidence-lifecycle/quickstart.md).

## Workflows

### Runtime verification

| Workflow | Description | Orchestration script | Fixture | Recipe |
|---|---|---|---|---|
| Input dispatch | Dispatch keys / actions and capture the resulting scene state. | `tools/automation/invoke-input-dispatch.ps1` | `tools/tests/fixtures/runbook/input-dispatch/press-enter.json` | [Recipe](docs/runbook/input-dispatch.md) |
| Scene inspection | Capture the running game's scene tree with no payload authoring. | `tools/automation/invoke-scene-inspection.ps1` | no payload | [Recipe](docs/runbook/inspect-scene-tree.md) |
| Behavior watch | Sample a node property over a frame window. | `tools/automation/invoke-behavior-watch.ps1` | `tools/tests/fixtures/runbook/behavior-watch/single-property-window.json` | [Recipe](docs/runbook/behavior-watch.md) |
| Build-error triage | Run the project and surface any build / compile errors. | `tools/automation/invoke-build-error-triage.ps1` | `tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json` | [Recipe](docs/runbook/build-error-triage.md) |
| Runtime-error triage | Run the project and surface any GDScript runtime errors. | `tools/automation/invoke-runtime-error-triage.ps1` | `tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json` | [Recipe](docs/runbook/runtime-error-triage.md) |

### Evidence lifecycle

| Workflow | Description | Orchestration script | Recipe |
|---|---|---|---|
| Pin run | Copy the current transient run to a stable named slot. | `tools/automation/invoke-pin-run.ps1` | [Recipe](docs/runbook/pin-run.md) |
| Unpin run | Remove a named pin to free disk space. | `tools/automation/invoke-unpin-run.ps1` | [Recipe](docs/runbook/unpin-run.md) |
| List pinned runs | Enumerate all named pins for a project. | `tools/automation/invoke-list-pinned-runs.ps1` | [Recipe](docs/runbook/list-pinned-runs.md) |

## Stdout envelope

Every orchestration script emits a single JSON object to stdout:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "requestId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": { "...": "workflow-specific — see recipe" }
}
```

On failure: `status = "failure"`, `failureKind` is one of
`editor-not-running | request-invalid | build | runtime | timeout | internal`,
`diagnostics[0]` contains the actionable message.

## Failure handling quick-reference

| `failureKind` | Recommended next step |
|---|---|
| `editor-not-running` | Launch editor: `godot --editor --path <ProjectRoot>` |
| `request-invalid` | Check `-RequestFixturePath` / `-RequestJson` parameter. |
| `build` | Read `outcome.firstDiagnostic` for file + line. Fix the GDScript error. |
| `runtime` | Read `outcome.latestErrorSummary` and `outcome.terminationReason`. |
| `timeout` | Increase `-TimeoutSeconds` or check if the editor is stuck. |
| `internal` | Read `diagnostics[0]`; file a bug against the harness. |

## Prerequisites

- PowerShell 7+ (`pwsh`) on `PATH`.
- A Godot editor running against an integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md` for setup).
- *(Tests only — no live editor needed)*: `pwsh ./tools/tests/run-tool-tests.ps1`.

## See also

- `docs/INTEGRATION_TESTING.md` — how to scaffold and launch a sandbox.
- `docs/AGENT_RUNTIME_HARNESS.md` — harness architecture overview.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — stdout envelope schema.
- `specs/008-agent-runbook/contracts/orchestration-cli.md` — common parameter contract.
