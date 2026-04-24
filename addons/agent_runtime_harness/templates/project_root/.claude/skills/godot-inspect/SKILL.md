---
name: "godot-inspect"
description: "Capture the running Godot game's scene tree in one call. Use when the user asks to inspect the scene, check the node hierarchy, list what is running in the game, or verify node presence at runtime."
argument-hint: "(optional) absolute path to a Godot project root; defaults to the project open in the current shell"
compatibility: "Requires a Godot editor running against the target project and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-scene-inspection.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as the absolute path to a Godot project root (the directory containing `project.godot`). If the user did not supply one, default to the current project root (`.`).

## Execution

Run the `invoke-scene-inspection.ps1` script once. It owns the full capability-check → request → poll → manifest-read loop and emits a single JSON envelope to stdout.

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 -ProjectRoot "<project-root>"
```

Parse the stdout as JSON. Report `outcome.nodeCount` to the user and, if asked, read `outcome.sceneTreePath` to summarize notable nodes.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `failureKind` | `null` on success; see failure table below |
| `manifestPath` | Absolute path to `evidence-manifest.json` on success |
| `diagnostics` | Human-readable messages; `diagnostics[0]` is the actionable one on failure |
| `outcome.sceneTreePath` | Absolute path to `scene-tree.json` |
| `outcome.nodeCount` | Total number of nodes captured |

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Capability artifact missing or stale | Tell the user to launch: `godot --editor --path "<project-root>"` |
| `build` | GDScript compile error before the scene could load | Report `diagnostics[0]` verbatim; no manifest will exist |
| `runtime` | Editor-side blocker (no scene staged, wrong target scene, etc.) | **Read `harness/automation/results/capability.json`** next. Check `blockedReasons` and `singleTargetReady`. If `target_scene_missing`: tell the user to open the target scene in the editor dock or set `Project Settings → Application → Run → Main Scene`. **Do not blind-retry** — this gate is editor-side, not something the script can override. |
| `timeout` | Capture did not complete | The editor may be frozen or not in play mode |
| `internal` | Harness-internal error | Report `diagnostics[0]` and advise filing a harness bug |

## Do not

- **Do not manually poll `run-result.json` or author `run-request.json`.** The invoke script owns the broker loop.
- **Do not read prior-run artifacts** under `harness/automation/results/` or `evidence/automation/` to plan this run. The transient zone is wiped before every invocation.
