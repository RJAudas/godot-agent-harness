---
name: "godot-pin"
description: "Pin the most recent transient Godot harness run under a stable name so it survives the next automatic cleanup. Use when the user asks to preserve, save, or keep a run for later comparison."
argument-hint: "pin name (alphanumeric/dashes/underscores, ≤64 chars)"
compatibility: "Requires a completed harness run in the transient zone and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-pin-run.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as the pin name (must match `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`). Default project root is the current project (`.`).

## Execution

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-pin-run.ps1 `
  -ProjectRoot "<project-root>" `
  -PinName "<pin-name>"
```

Pass `-Force` only when the user explicitly asks to overwrite. Pass `-DryRun` to preview without modifying.

## Envelope fields

Lifecycle envelope (different shape from runtime-verification):

| Field | Meaning |
|---|---|
| `status` | `"ok"` / `"refused"` (precondition) / `"failed"` (I/O error) |
| `operation` | `"pin"` |
| `failureKind` | `null` on success; see refusal table |
| `plannedPaths[]` | Files copied (`action=copy`) plus `pin-metadata.json` (`action=create`) |
| `pinName` | Echoes the name |
| `dryRun` | `true` if `-DryRun` was passed |

## Refusal / failure handling

| `status` / `failureKind` | Meaning | Next step |
|---|---|---|
| `refused` / `pin-name-collision` | Pin name already exists | Offer `-Force` or a different name |
| `refused` / `pin-name-invalid` | Name failed the regex | Suggest a conforming slug |
| `refused` / `pin-source-missing` | No manifest in transient zone | Run a workflow first (`/godot-inspect`, `/godot-press`, …) |
| `refused` / `run-in-progress` | Another invoke script is active | Wait for the in-flight run |
| `failed` / `io-error` | Unexpected filesystem failure | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not manually copy files** into `harness/automation/pinned/` — use this skill.
- **Do not use `-Force` without explicit user consent** — it destroys an existing pin.
