# Recipe: Runtime-Error Triage

Run a Godot project with pause-on-error enabled and surface any GDScript
runtime errors in a single script invocation.

## Prerequisites

- A Godot editor running against your integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md`).
- A tracked request fixture under
  `tools/tests/fixtures/runbook/runtime-error-triage/` **or** an inline JSON
  payload. The fixture should include `"pauseOnError": true` to enable error
  capture.
- `pwsh` (PowerShell 7+) available on `PATH`.

## Run it

```pwsh
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json
```

Replace `<name>` with your sandbox directory name.

### Include the full stack trace

```pwsh
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json `
    -IncludeFullStack
```

## Expected output

On a **healthy** run:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-runtime-error-triage-20260422T144501Z-a3f1",
  "requestId": "runbook-runtime-error-triage-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": {
    "runtimeErrorRecordsPath": null,
    "latestErrorSummary": null,
    "terminationReason": "completed"
  }
}
```

On a **runtime error** run:

```json
{
  "status": "failure",
  "failureKind": "runtime",
  "manifestPath": "<path>",
  "runId": "...",
  "requestId": "...",
  "completedAt": "...",
  "diagnostics": ["Runtime error at res://scripts/ball.gd:17: Invalid call."],
  "outcome": {
    "runtimeErrorRecordsPath": "<absolute path to runtime-error-records.jsonl>",
    "latestErrorSummary": {
      "file": "res://scripts/ball.gd",
      "line": 17,
      "message": "Invalid call. Nonexistent function 'apply_impulse' in base 'RigidBody2D'."
    },
    "terminationReason": "stopped_by_default_on_pause_timeout"
  }
}
```

Stderr: `FAIL: runtime; Runtime error at res://scripts/ball.gd:17: ...`

Exit code: non-zero on failure, `0` on success.

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `editor-not-running` | The editor is not running or capability.json is stale. | Launch: `godot --editor --path <ProjectRoot>` |
| `request-invalid` | Parameter error. | Check `-RequestFixturePath` / `-RequestJson`. |
| `build` | GDScript compile error (before runtime). | Use `invoke-build-error-triage.ps1` for details. |
| `runtime` | GDScript runtime error captured. | Read `outcome.latestErrorSummary.file` and `outcome.latestErrorSummary.line`. |
| `timeout` | Run did not complete in time. | Increase `-TimeoutSeconds`. |
| `internal` | Harness-internal error. | Read `diagnostics[0]`; file a bug. |

### Reading `terminationReason`

| `terminationReason` | Meaning |
|---|---|
| `completed` | Run completed normally — no errors. |
| `stopped_by_agent` | Agent submitted a stop-decision during the run. |
| `stopped_by_default_on_pause_timeout` | Broker paused on error and timed out waiting for a decision. |
| `crashed` | The game process crashed. Check `lastErrorAnchor` in the manifest. |
| `killed_by_harness` | The harness forcibly terminated the run. |

## Automatic cleanup

Before every invocation the script clears the transient zone
(`harness/automation/results/` and `evidence/automation/`) automatically.
To keep a run for later comparison, pin it before the next invocation:

```pwsh
pwsh ./tools/automation/invoke-pin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName my-baseline
```

See [Recipe: Pin Run](pin-run.md) for details.

## Anti-patterns

- **Do not** manually delete files under `harness/automation/results/` or
  `evidence/automation/`. The script handles cleanup automatically.
- **Do not** use this script to detect build errors — use
  `invoke-build-error-triage.ps1` for that. Build errors appear before
  runtime and have their own envelope shape.
- **Do not** submit pause-decisions inline while using this script; this
  recipe is for read-only error surfacing. Use
  `tools/automation/submit-pause-decision.ps1` directly if you need to
  interact with a paused run.

<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->

## See also

- `tools/tests/fixtures/runbook/runtime-error-triage/` — tracked fixture templates.
- `specs/007-report-runtime-errors/contracts/` — runtime-error schema reference.
- `tools/automation/submit-pause-decision.ps1` — submit a continue/stop decision.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — envelope schema.
- `RUNBOOK.md` — workflow index.
