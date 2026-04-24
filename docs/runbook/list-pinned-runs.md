# Recipe: List Pinned Runs

Enumerate all named pinned runs for a project. Returns an empty list when no
pins exist — this is not an error.

## Run it

```pwsh
pwsh ./tools/automation/invoke-list-pinned-runs.ps1 `
    -ProjectRoot integration-testing/<name>
```

## Expected output

```json
{
  "status": "ok",
  "failureKind": null,
  "operation": "list",
  "dryRun": false,
  "plannedPaths": [],
  "pinName": null,
  "pinnedRunIndex": [
    {
      "pinName": "baseline",
      "manifestPath": "harness/automation/pinned/baseline/evidence/<runId>/evidence-manifest.json",
      "scenarioId": "pong-behavior-watch-wall-bounce-every-frame",
      "runId": "<runId>",
      "pinnedAt": "2026-04-23T14:45:00.000Z",
      "status": "pass",
      "sourceInvokeScript": "invoke-behavior-watch.ps1"
    }
  ],
  "diagnostics": [],
  "completedAt": "2026-04-23T14:55:00.000Z",
  "manifestPath": null
}
```

`pinnedRunIndex[]` is sorted alphabetically by `pinName`. Each entry includes
`manifestPath` (project-root-relative) so you can pass it directly to
downstream tooling.

### Read a pinned manifest

```pwsh
$envelope = pwsh ./tools/automation/invoke-list-pinned-runs.ps1 `
    -ProjectRoot integration-testing/<name> | ConvertFrom-Json

$pin = $envelope.pinnedRunIndex | Where-Object { $_.pinName -eq 'baseline' }
Get-Content (Join-Path 'integration-testing/<name>' $pin.manifestPath) | ConvertFrom-Json
```

## Pins with missing metadata

Pins created before this spec was adopted may not have a `pin-metadata.json`.
They still appear in the index with `status = "unknown"` and
`sourceInvokeScript = null`.

## See also

- [Recipe: Pin Run](pin-run.md) — create a pin.
- [Recipe: Unpin Run](unpin-run.md) — remove a pin.
- `specs/009-evidence-lifecycle/contracts/pinned-run-index.schema.json` — index schema.
- `RUNBOOK.md` — workflow index.
