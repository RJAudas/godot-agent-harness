# Recipe: Pin Run

Copy the current transient run to a stable, agent-chosen name so it survives
future automatic cleanups.

## When to use

Every runtime-verification run writes to the transient zone, which is wiped
before the next run. Pin a run when you want to:

- Compare two runs side-by-side.
- Preserve a bug-reproduction baseline for later reference.
- Hand a named run off to another agent or reviewer.

## Run it

```pwsh
pwsh ./tools/automation/invoke-pin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName bug-repro-jumpscare
```

`-PinName` must match `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`.

### Preview without copying (dry run)

```pwsh
pwsh ./tools/automation/invoke-pin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName bug-repro-jumpscare `
    -DryRun
```

### Overwrite an existing pin

```pwsh
pwsh ./tools/automation/invoke-pin-run.ps1 `
    -ProjectRoot integration-testing/<name> `
    -PinName bug-repro-jumpscare `
    -Force
```

## Expected output

On success the script emits a lifecycle envelope to stdout:

```json
{
  "status": "ok",
  "failureKind": null,
  "operation": "pin",
  "dryRun": false,
  "plannedPaths": [
    { "path": "harness/automation/pinned/bug-repro-jumpscare/evidence/<runId>/evidence-manifest.json", "action": "copy" },
    { "path": "harness/automation/pinned/bug-repro-jumpscare/results/run-result.json", "action": "copy" },
    { "path": "harness/automation/pinned/bug-repro-jumpscare/pin-metadata.json", "action": "create" }
  ],
  "pinName": "bug-repro-jumpscare",
  "pinnedRunIndex": null,
  "diagnostics": [],
  "completedAt": "2026-04-23T14:45:00.000Z",
  "manifestPath": null
}
```

`plannedPaths[]` is the audit trail of every file copied.

## Failure handling

| `failureKind` | What it means | Recommended next step |
|---|---|---|
| `pin-name-collision` | A pin with that name already exists. | Choose a different name or add `-Force` to overwrite. |
| `pin-source-missing` | No `evidence-manifest.json` in the transient zone. | Run a workflow first, then pin. |
| `pin-name-invalid` | Name does not match the allowed pattern. | Use only `[A-Za-z0-9][A-Za-z0-9_.-]{0,63}`. |

## What gets pinned

The pin is a byte-identical copy of the transient zone at pin time:

```
harness/automation/pinned/<pin-name>/
├── pin-metadata.json
├── results/
│   ├── run-result.json
│   └── lifecycle-status.json
└── evidence/<runId>/
    ├── evidence-manifest.json
    └── <all artifacts referenced by the manifest>
```

## See also

- [Recipe: Unpin Run](unpin-run.md) — remove a pin when you are done with it.
- [Recipe: List Pinned Runs](list-pinned-runs.md) — enumerate all pins.
- `specs/009-evidence-lifecycle/quickstart.md` — end-to-end lifecycle walkthrough.
- `RUNBOOK.md` — workflow index.
