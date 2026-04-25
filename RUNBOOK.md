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

> **Claude Code users**: every workflow has a `/godot-*` slash command. Type the command or describe the intent in natural language; Claude's skill router handles invocation. Other tools continue to call `invoke-*.ps1` directly — the script contracts are unchanged.

| Workflow | Description | Orchestration script | Fixture | Recipe |
|---|---|---|---|---|
| Input dispatch | Dispatch keys / actions and capture the resulting scene state. | `tools/automation/invoke-input-dispatch.ps1` | `tools/tests/fixtures/runbook/input-dispatch/press-enter.json` | [Skill](.claude/skills/godot-press/SKILL.md) |
| Scene inspection | Capture the running game's scene tree with no payload authoring. | `tools/automation/invoke-scene-inspection.ps1` | no payload | [Skill](.claude/skills/godot-inspect/SKILL.md) |
| Behavior watch | Sample a node property over a frame window. | `tools/automation/invoke-behavior-watch.ps1` | `tools/tests/fixtures/runbook/behavior-watch/single-property-window.json` | [Skill](.claude/skills/godot-watch/SKILL.md) |
| Build-error triage | Run the project and surface any build / compile errors. | `tools/automation/invoke-build-error-triage.ps1` | `tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json` | [Skill](.claude/skills/godot-debug-build/SKILL.md) |
| Runtime-error triage | Run the project and surface any GDScript runtime errors. | `tools/automation/invoke-runtime-error-triage.ps1` | `tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json` | [Skill](.claude/skills/godot-debug-runtime/SKILL.md) |

### Evidence lifecycle

| Workflow | Description | Orchestration script | Recipe |
|---|---|---|---|
| Pin run | Copy the current transient run to a stable named slot. | `tools/automation/invoke-pin-run.ps1` | [Skill](.claude/skills/godot-pin/SKILL.md) |
| Unpin run | Remove a named pin to free disk space. | `tools/automation/invoke-unpin-run.ps1` | [Skill](.claude/skills/godot-unpin/SKILL.md) |
| List pinned runs | Enumerate all named pins for a project. | `tools/automation/invoke-list-pinned-runs.ps1` | [Skill](.claude/skills/godot-pins/SKILL.md) |

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

## Exit-code convention

Runtime-verification scripts exit non-zero for any `status=failure` envelope.

Lifecycle scripts (pin / unpin) distinguish two non-success outcomes:

- `status="refused"` → **exit 0**. The script ran successfully and correctly declined a precondition (e.g. `pin-name-collision`, `pin-target-not-found`). Read the envelope's `failureKind` and `diagnostics[0]` to learn why.
- `status="failed"` → **exit 1**. An unexpected error the caller should investigate (e.g. `io-error`).

The envelope's `status` field is authoritative in both cases; the exit code is a fast-path signal for shell pipelines.

## Prerequisites

- PowerShell 7+ (`pwsh`) on `PATH`.
- A Godot editor running against an integration-testing sandbox. Either launch
  it manually, or pass `-EnsureEditor` to any runtime-verification script and
  the harness will idempotently launch one for you. See "Editor lifecycle helpers"
  below.
- *(Tests only — no live editor needed)*: `pwsh ./tools/tests/run-tool-tests.ps1`.

## Editor lifecycle helpers

Two sibling helpers manage the editor process so agents don't have to:

| Helper | What it does |
|---|---|
| `tools/automation/invoke-launch-editor.ps1` | Idempotently launch (or attach to) a Godot editor for `-ProjectRoot`. Returns success in <1s when an editor is already running and capability.json is fresh; otherwise spawns Godot with `--editor --path ROOT --verbose` and polls capability.json until it appears. `-ForceRestart` stops any existing editor first. Output envelope carries `outcome.editorPid`, `outcome.capabilityPath`, `outcome.capabilityAgeSeconds`, `outcome.reusedExistingEditor`. |
| `tools/automation/invoke-stop-editor.ps1` | Stop the Godot editor for `-ProjectRoot`. Matches by `--path` command-line so it leaves unrelated editor instances alone. Output envelope carries `outcome.stoppedPids` and `outcome.remainingPids`. |

Every runtime-verification invoker also accepts a `-EnsureEditor` switch that delegates to `invoke-launch-editor.ps1` before running the workflow. Auto-launch failures surface as the workflow's own `editor-not-running` envelope.

```powershell
# One-step convenience: spawn editor (if needed) + run workflow
pwsh ./tools/automation/invoke-scene-inspection.ps1 `
    -ProjectRoot ./integration-testing/probe -EnsureEditor

# Two-step explicit (idempotent reuse, then run)
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json

# Cleanup
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
```

## See also

- `docs/INTEGRATION_TESTING.md` — how to scaffold and launch a sandbox.
- `docs/AGENT_RUNTIME_HARNESS.md` — harness architecture overview.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — stdout envelope schema.
- `specs/008-agent-runbook/contracts/orchestration-cli.md` — common parameter contract.
