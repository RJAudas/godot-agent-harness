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

This skill takes no arguments. Ask the user which project root to target.

## Execution

```powershell
pwsh ./tools/automation/invoke-list-pinned-runs.ps1 `
  -ProjectRoot "<project-root>"
```

## Envelope fields

Lifecycle envelope:

| Field | Meaning |
|---|---|
| `status` | `"ok"` (always, on success; there is no refusal state for listing) |
| `operation` | `"list"` |
| `pinnedRunIndex[]` | Array of pin records — each with `pinName`, `pinnedAt`, `sourceRunId`, `sourceScenarioId`, `status` (`pass`/`fail`/`unknown`) |

Report the pin count and each pin's name, status, and age. If the index is empty, say so — do not invent pins.

## Failure handling

| `status` / `failureKind` | Meaning | Next step |
|---|---|---|
| `failed` / `io-error` | Unexpected filesystem failure reading the pin directory | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not scan the filesystem manually** for pins. Use this skill — the index also surfaces health diagnostics for malformed pin directories.
