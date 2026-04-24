# Recipe: Input Dispatch

Dispatch key or `InputMap` action events in a running Godot game and
capture the resulting scene state — with a single script invocation.

## Prerequisites

- A Godot editor running against your integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md`).
- A tracked request fixture under
  `tools/tests/fixtures/runbook/input-dispatch/` **or** an inline JSON
  payload with an `inputDispatchScript` field.
- `pwsh` (PowerShell 7+) available on `PATH`.

## Run it

```pwsh
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

Replace `<name>` with your sandbox directory name.

### Using an inline payload instead of a fixture

```pwsh
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestJson '{
  "requestId": "placeholder",
  "scenarioId": "my-scenario",
  "runId": "my-run",
  "targetScene": "res://scenes/main.tscn",
  "outputDirectory": "res://evidence/automation/my-run",
  "artifactRoot": "tools/tests/fixtures/runbook/input-dispatch/evidence",
  "capturePolicy": { "startup": true, "manual": true, "failure": true },
  "stopPolicy": { "stopAfterValidation": true },
  "requestedBy": "agent",
  "createdAt": "2026-01-01T00:00:00Z",
  "inputDispatchScript": {
    "events": [
      { "kind": "key", "identifier": "ENTER", "phase": "press",   "frame": 30 },
      { "kind": "key", "identifier": "ENTER", "phase": "release", "frame": 32 }
    ]
  }
}'
```

The `requestId` in the payload is always overridden by the script with a
fresh value.

## Expected output

On success the script emits a single JSON object to stdout:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "requestId": "runbook-input-dispatch-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": {
    "outcomesPath": "<absolute path to input-dispatch-outcomes.jsonl>",
    "dispatchedEventCount": 2,
    "firstFailureSummary": null
  }
}
```

Stderr: `OK: dispatched 2 events; manifest at <path>`

Exit code: `0`

To read the outcomes file:

```pwsh
Get-Content ($envelope.outcome.outcomesPath) | ConvertFrom-Json
```

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `editor-not-running` | The editor is not running or capability.json is stale. | Launch: `godot --editor --path <ProjectRoot>` |
| `request-invalid` | Parameter error (missing or conflicting payload). | Check `-RequestFixturePath` / `-RequestJson` flags. |
| `build` | GDScript compile error in the project. | Read `diagnostics[0]` for file and line. Fix the error. |
| `runtime` | GDScript runtime error during the run. | Use `invoke-runtime-error-triage.ps1` to get full detail. |
| `timeout` | Run did not complete within `-TimeoutSeconds`. | Increase `-TimeoutSeconds` or check if the editor is frozen. |
| `internal` | Harness-internal error. | Read `diagnostics[0]`; file a bug against the harness. |

On failure: exit code is non-zero, `diagnostics[0]` is the actionable
message, `firstFailureSummary` in the outcome reports the first failed
event (if available).

## Automatic cleanup

Before every invocation the script clears the transient zone
(`harness/automation/results/` and `evidence/automation/`) so stale output
from a previous run never contaminates new evidence. You do **not** need to
delete files manually between runs.

To keep a run for later comparison, pin it before the next invocation:

```pwsh
pwsh ./tools/automation/invoke-pin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName my-baseline
```

See [Recipe: Pin Run](pin-run.md) for details.

## Anti-patterns

- **Do not** hand-roll the capability → request → poll loop. Use this
  script instead — it is the single-call interface that satisfies SC-001.
- **Do not** hardcode frame numbers without understanding the game's frame
  rate. Use the existing pong-testbed fixture frame values as a starting
  point and adjust if the game runs at a different tick rate.
- **Do not** manually delete files under `harness/automation/results/` or
  `evidence/automation/`. The script handles cleanup automatically.

<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->

## See also

- `tools/tests/fixtures/runbook/input-dispatch/` — tracked fixture templates.
- `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json` — input event schema.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — envelope schema.
- `RUNBOOK.md` — workflow index.
