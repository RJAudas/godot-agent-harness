# Recipe: Behavior Watch

Sample a Godot node property over a frame window in a single script invocation.

## Prerequisites

- A Godot editor running against your integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md`).
- A tracked request fixture under
  `tools/tests/fixtures/runbook/behavior-watch/` **or** an inline JSON
  payload with a `behaviorWatchRequest` field.
- `pwsh` (PowerShell 7+) available on `PATH`.

## Run it

```pwsh
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/single-property-window.json
```

Replace `<name>` with your sandbox directory name.

### Inline payload example

```pwsh
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestJson '{
  "requestId": "placeholder",
  "scenarioId": "my-watch-scenario",
  "runId": "my-watch-run",
  "targetScene": "res://scenes/main.tscn",
  "outputDirectory": "res://evidence/automation/my-watch-run",
  "artifactRoot": "tools/tests/fixtures/runbook/behavior-watch/evidence",
  "capturePolicy": { "startup": true, "manual": true, "failure": true },
  "stopPolicy": { "stopAfterValidation": true },
  "requestedBy": "agent",
  "createdAt": "2026-01-01T00:00:00Z",
  "behaviorWatchRequest": {
    "targets": [
      { "nodePath": "/root/Main/Paddle", "properties": ["position"] }
    ],
    "frameCount": 10
  }
}'
```

## Expected output

On success the script emits a single JSON object to stdout:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-behavior-watch-20260422T144501Z-a3f1",
  "requestId": "runbook-behavior-watch-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": {
    "samplesPath": "<absolute path to behavior samples JSONL>",
    "sampleCount": 10,
    "frameRangeCovered": { "first": 5, "last": 14 }
  }
}
```

Stderr: `OK: 10 samples captured; manifest at <path>`

Exit code: `0`

To read the samples:

```pwsh
Get-Content ($envelope.outcome.samplesPath) | ConvertFrom-Json
```

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `editor-not-running` | The editor is not running or capability.json is stale. | Launch: `godot --editor --path <ProjectRoot>` |
| `request-invalid` | Parameter error. | Check `-RequestFixturePath` / `-RequestJson`. |
| `build` | GDScript compile error. | Use `invoke-build-error-triage.ps1`. |
| `runtime` | GDScript runtime error. | Use `invoke-runtime-error-triage.ps1`. |
| `timeout` | Run did not complete in time. | Increase `-TimeoutSeconds`. |
| `internal` | Harness-internal error. | Read `diagnostics[0]`; file a bug. |

## Anti-patterns

- **Do not** sample more than 60 frames without confirming the game runs
  at 60 fps. `frameCount` is a frame count, not a time in seconds.
- **Do not** watch properties that are not in the schema's `properties` enum
  (`position`, `velocity`, `collisionState`, etc.). Unsupported properties
  are silently ignored by the harness.

<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->

## See also

- `tools/tests/fixtures/runbook/behavior-watch/` — tracked fixture templates.
- `specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json` — request schema.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — envelope schema.
- `RUNBOOK.md` — workflow index.
