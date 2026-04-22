# Recipe: Build-Error Triage

Run a Godot project and surface any GDScript build or compile errors in a
single script invocation.

## Prerequisites

- A Godot editor running against your integration-testing sandbox (see
  `docs/INTEGRATION_TESTING.md`).
- A tracked request fixture under
  `tools/tests/fixtures/runbook/build-error-triage/` **or** an inline JSON
  payload.
- `pwsh` (PowerShell 7+) available on `PATH`.

## Run it

```pwsh
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json
```

Replace `<name>` with your sandbox directory name.

### Include the raw build output

```pwsh
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
    -ProjectRoot integration-testing/<name> `
    -RequestFixturePath tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json `
    -IncludeRawBuildOutput
```

## Expected output

On a **healthy** run the script emits:

```json
{
  "status": "success",
  "failureKind": null,
  "manifestPath": "<absolute path to evidence-manifest.json>",
  "runId": "runbook-build-error-triage-20260422T144501Z-a3f1",
  "requestId": "runbook-build-error-triage-20260422T144501Z-a3f1",
  "completedAt": "2026-04-22T14:45:08.123Z",
  "diagnostics": [],
  "outcome": {
    "rawBuildOutputPath": null,
    "firstDiagnostic": null
  }
}
```

On a **build failure** run:

```json
{
  "status": "failure",
  "failureKind": "build",
  "manifestPath": "<path or null>",
  "runId": "...",
  "requestId": "...",
  "completedAt": "...",
  "diagnostics": ["Build error at res://scripts/player.gd:42: Expected expression in assignment."],
  "outcome": {
    "rawBuildOutputPath": null,
    "firstDiagnostic": {
      "file": "res://scripts/player.gd",
      "line": 42,
      "message": "Expected expression in assignment."
    }
  }
}
```

Stderr: `FAIL: build; Build error at res://scripts/player.gd:42: ...`

Exit code: non-zero on failure, `0` on success.

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `editor-not-running` | The editor is not running or capability.json is stale. | Launch: `godot --editor --path <ProjectRoot>` |
| `request-invalid` | Parameter error. | Check `-RequestFixturePath` / `-RequestJson`. |
| `build` | GDScript compile error found. | Read `outcome.firstDiagnostic.file` and `outcome.firstDiagnostic.line`. Fix the error and re-run. |
| `timeout` | Run did not complete in time. | Increase `-TimeoutSeconds`. |
| `internal` | Harness-internal error. | Read `diagnostics[0]`; file a bug. |

## Anti-patterns

- **Do not** infer what is valid GDScript by reading the harness addon source.
  Fix the error at the reported file and line, re-run, and let the envelope tell
  you whether the build is now clean.

<!-- runbook:do-not-read-addon-source -->
> **Do not** read files under `addons/agent_runtime_harness/` to understand
> what inputs are valid or what the runtime does. All valid inputs are
> documented in `specs/` and `docs/`. Reading addon source is slow, fragile,
> and likely to mislead.
<!-- /runbook:do-not-read-addon-source -->

## See also

- `tools/tests/fixtures/runbook/build-error-triage/` — tracked fixture templates.
- `specs/004-report-build-errors/contracts/` — build-error schema reference.
- `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` — envelope schema.
- `RUNBOOK.md` — workflow index.
