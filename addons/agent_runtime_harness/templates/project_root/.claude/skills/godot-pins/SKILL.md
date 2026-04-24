---
name: "godot-pins"
description: "List all pinned Godot harness runs for this project. Use when the user asks what runs are saved, what's pinned, or wants to see the pin inventory."
argument-hint: "none"
compatibility: "Requires access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-list-pinned-runs.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

This skill takes no arguments. Default project root is the current project (`.`).

## Execution

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-list-pinned-runs.ps1 `
  -ProjectRoot "<project-root>"
```

## Envelope fields

Lifecycle envelope:

| Field | Meaning |
|---|---|
| `status` | `"ok"` (always on success) |
| `operation` | `"list"` |
| `pinnedRunIndex[]` | Array of pin records — `pinName`, `pinnedAt`, `sourceRunId`, `sourceScenarioId`, `status` (`pass`/`fail`/`unknown`) |

Report pin count and each pin's name, status, and age. If the index is empty, say so — do not invent pins.

## Failure handling

| `status` / `failureKind` | Meaning | Next step |
|---|---|---|
| `failed` / `io-error` | Filesystem read failure | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not scan the filesystem manually** — use this skill so the index surfaces health diagnostics for malformed pin directories.
