# Recipe: Scene Inspection

Capture the running Godot game's full scene tree with a single script
invocation — no payload authoring required.

## Prerequisites

- A Godot editor running against your integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md`).
- `pwsh` (PowerShell 7+) available on `PATH`.
- No fixture file needed — the script synthesizes the capture request internally.

## Run it

```pwsh
pwsh ./tools/automation/invoke-scene-inspection.ps1 `
    -ProjectRoot integration-testing/<name>
```

Replace `<name>` with your sandbox directory name. No `-RequestFixturePath`
or `-RequestJson` parameter is needed.

## Expected output

On success the script emits a single JSON object to stdout:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-scene-inspection-20260422T144501Z-a3f1",
  "requestId": "runbook-scene-inspection-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": {
    "sceneTreePath": "<absolute path to scene-tree.json>",
    "nodeCount": 42
  }
}
```

Stderr: `OK: 42 nodes captured; manifest at <path>`

Exit code: `0`

To read the scene tree:

```pwsh
$tree = Get-Content ($envelope.outcome.sceneTreePath) | ConvertFrom-Json
$tree.root | Select-Object name, type, children
```

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `editor-not-running` | The editor is not running or capability.json is stale. | Launch: `godot --editor --path <ProjectRoot>` |
| `build` | GDScript compile error. | Use `invoke-build-error-triage.ps1` to get the error details. |
| `timeout` | Capture did not complete in time. | Increase `-TimeoutSeconds` or check if the editor is frozen. |
| `internal` | Harness-internal error. | Read `diagnostics[0]`; file a bug. |

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
- **Do not** attempt to pass `-RequestFixturePath` — scene inspection uses
  no external payload. The script synthesizes a minimal startup-capture
  request internally.
- **Do not** parse the scene-tree.json manually to infer the game's logic.
  Use the captured tree as evidence, not as a substitute for reading the
  game's documented behaviour.

<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->

## See also

- `tools/tests/fixtures/runbook/inspect-scene-tree/startup-capture.json` — documented fixture stub.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — envelope schema.
- `RUNBOOK.md` — workflow index.
