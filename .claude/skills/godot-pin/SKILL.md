---
name: "godot-pin"
description: "Pin the most recent transient Godot harness run under a stable name so it survives the next automatic cleanup. Use when the user asks to preserve, save, or keep a run for later comparison."
argument-hint: "pin name (alphanumeric / dashes / underscores, ≤64 chars; e.g. bug-repro-jumpscare)"
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

Treat `$ARGUMENTS` as the pin name (must match `^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`). If the user passes something with spaces, suggest a slug they'd accept. Ask the user which project root to target.

## Execution

```powershell
pwsh ./tools/automation/invoke-pin-run.ps1 `
  -ProjectRoot "<project-root>" `
  -PinName "<pin-name>"
```

Pass `-Force` only when the user explicitly asks to overwrite an existing pin. Pass `-DryRun` to preview which files would be copied without modifying the filesystem.

## Envelope fields

This skill emits a **lifecycle envelope** (different from runtime-verification envelopes):

| Field | Meaning |
|---|---|
| `status` | `"ok"` (success) / `"refused"` (precondition failure) / `"failed"` (I/O error) |
| `operation` | Always `"pin"` |
| `failureKind` | `null` on success; see refusal table on `refused` or `failed` |
| `plannedPaths[]` | Every file copied (`action=copy`) plus the pin-metadata.json (`action=create`) |
| `pinName` | Echoes the name you pinned under |
| `dryRun` | `true` if `-DryRun` was passed |

Report the pin name and the number of files preserved.

## Refusal / failure handling

| `status` / `failureKind` | What it means | Next step |
|---|---|---|
| `refused` / `pin-name-collision` | A pin with this name already exists | Offer `-Force` or suggest a different name |
| `refused` / `pin-name-invalid` | Name failed the regex | Suggest a conforming slug |
| `refused` / `pin-source-missing` | No `evidence-manifest.json` in the transient zone | Run a workflow (`/godot-inspect`, `/godot-press`, etc.) first |
| `refused` / `run-in-progress` | Another invoke script is active | Wait for the in-flight run to finish |
| `failed` / `io-error` | Unexpected filesystem failure | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not manually copy files** into `harness/automation/pinned/` — use this skill.
- **Do not use `-Force` without the user's explicit consent** — it destroys an existing pin.
