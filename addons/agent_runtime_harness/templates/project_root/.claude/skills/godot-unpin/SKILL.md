---
name: "godot-unpin"
description: "Remove a named pinned run from the Godot harness. Use when the user asks to unpin, delete, or drop a saved run."
argument-hint: "pin name to remove"
compatibility: "Requires access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-unpin-run.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as the pin name to remove. Default project root is the current project (`.`). Suggest `/godot-pins` first if the user is unsure which pins exist.

## Execution

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-unpin-run.ps1 `
  -ProjectRoot "<project-root>" `
  -PinName "<pin-name>"
```

Pass `-DryRun` to preview without deleting.

## Envelope fields

Lifecycle envelope:

| Field | Meaning |
|---|---|
| `status` | `"ok"` / `"refused"` / `"failed"` |
| `operation` | `"unpin"` |
| `plannedPaths[]` | Files marked for deletion (`action=delete`) |
| `pinName` | Echoes the name removed |
| `dryRun` | `true` if `-DryRun` was passed |

## Refusal / failure handling

| `status` / `failureKind` | Meaning | Next step |
|---|---|---|
| `refused` / `pin-target-not-found` | No pin with that name | Offer `/godot-pins` to list valid names |
| `refused` / `pin-name-invalid` | Name failed the regex | Suggest a conforming pin name |
| `failed` / `io-error` | Unexpected filesystem failure | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not manually delete files** under `harness/automation/pinned/` — use this skill.
- **Do not unpin without confirming the name** — run `/godot-pins` first if unsure. Irreversible.
