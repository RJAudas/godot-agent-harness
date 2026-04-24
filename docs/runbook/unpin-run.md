# Recipe: Unpin Run

Remove a named pinned run from `harness/automation/pinned/` to free disk space.

## Run it

```pwsh
pwsh ./tools/automation/invoke-unpin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName bug-repro-jumpscare
```

### Preview without deleting (dry run)

```pwsh
pwsh ./tools/automation/invoke-unpin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName bug-repro-jumpscare `
    -DryRun
```

The `-DryRun` envelope lists every file that _would_ be deleted in
`plannedPaths[]`, but nothing is removed from disk.

## Expected output

On success:

```json
{
  "status": "ok",
  "failureKind": null,
  "operation": "unpin",
  "dryRun": false,
  "plannedPaths": [
    { "path": "harness/automation/pinned/bug-repro-jumpscare/pin-metadata.json", "action": "delete" },
    { "path": "harness/automation/pinned/bug-repro-jumpscare/evidence/<runId>/evidence-manifest.json", "action": "delete" }
  ],
  "pinName": "bug-repro-jumpscare",
  "pinnedRunIndex": null,
  "diagnostics": [],
  "completedAt": "2026-04-23T14:50:00.000Z",
  "manifestPath": null
}
```

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `pin-target-not-found` | No pin with that name exists. | Run `invoke-list-pinned-runs.ps1` to see available pins. |
| `pin-name-invalid` | Name does not match the allowed pattern. | Use only `[A-Za-z0-9][A-Za-z0-9_.-]{0,63}`. |

## See also

- [Recipe: Pin Run](pin-run.md) — create a pin.
- [Recipe: List Pinned Runs](list-pinned-runs.md) — enumerate all pins before unpinning.
- `RUNBOOK.md` — workflow index.
