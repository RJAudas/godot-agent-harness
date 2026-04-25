---
name: "godot-press"
description: "Dispatch keyboard keys or InputMap actions in the running Godot game and capture the resulting scene state. Use when the user asks to press a key, simulate input, drive the game programmatically, or test what happens after a button press."
argument-hint: "fixture path OR bare key name (e.g. ENTER)"
compatibility: "Requires a Godot editor running against the target project and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-input-dispatch.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as either a **fixture path** or a **bare key name** (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`). Default project root is the current project (`.`). If the user named a key without a fixture, synthesize inline JSON with a press+release pair.

## Execution

`-EnsureEditor` idempotently launches a Godot editor for the project (or reuses one if already running and capability.json is fresh). Pass it on every call.

Fixture form (preferred when a fixture exists):

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestFixturePath "<fixture-path>"
```

Inline form (when no fixture fits):

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestJson '{"requestId":"placeholder","scenarioId":"runbook-input-dispatch","runId":"runbook-input-dispatch","targetScene":"<main scene res:// path>","outputDirectory":"res://evidence/automation/agent","artifactRoot":"evidence/automation/agent","expectationFiles":[],"capturePolicy":{"startup":true,"manual":true,"failure":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"<UTC ISO-8601>","inputDispatchScript":{"events":[{"kind":"key","identifier":"ENTER","phase":"press","frame":30},{"kind":"key","identifier":"ENTER","phase":"release","frame":32}]}}'
```

`requestId` is always overridden. Key identifiers are bare Godot logical names — **not** `KEY_ENTER`. InputMap actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `failureKind` | `null` on success; see failure table |
| `manifestPath` | Absolute path to `evidence-manifest.json` on success |
| `outcome.outcomesPath` | Absolute path to `input-dispatch-outcomes.jsonl` |
| `outcome.dispatchedEventCount` | Number of events actually dispatched |
| `outcome.firstFailureSummary` | First failed event's message, or `null` on clean success |

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Auto-launch failed (e.g. missing `$env:GODOT_BIN`, project failed to import) | Read `diagnostics[0]` for the underlying reason; common fix is to ensure `$env:GODOT_BIN` points at a Godot 4 binary |
| `request-invalid` | Payload schema violation | Read `diagnostics[0]`; fix the fixture or inline JSON |
| `build` | GDScript compile error before dispatch | Report `diagnostics[0]` verbatim |
| `runtime` | Editor-side blocker | Read `harness/automation/results/capability.json` for `blockedReasons` / `singleTargetReady`. If `target_scene_missing`: tell the user to open the target scene in the editor dock. **Do not blind-retry.** |
| `timeout` | Run did not complete | Editor may be frozen or not in play mode |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not manually poll `run-result.json`** — the invoke script owns the loop.
- **Do not vary `capturePolicy` / `stopPolicy` speculatively** — fixture defaults are correct.
- **Do not invent alternate input entrypoints** — this script is the only way.
