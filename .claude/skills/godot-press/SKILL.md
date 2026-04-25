---
name: "godot-press"
description: "Dispatch keyboard keys or InputMap actions in the running Godot game and capture the resulting scene state. Use when the user asks to press a key, simulate input, drive the game programmatically, or test what happens after a button press."
argument-hint: "fixture path OR bare key name (e.g. tools/tests/fixtures/runbook/input-dispatch/press-enter.json or ENTER)"
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

Treat `$ARGUMENTS` as either a **fixture path** (under `tools/tests/fixtures/runbook/input-dispatch/`) or a **bare key name** (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`). Ask the user which project root to target; do not guess. If they named a key without giving a fixture, synthesize inline JSON with a press+release pair.

## Execution

Fixture form (preferred when a fixture exists):

```powershell
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<project-root>" `
  -RequestFixturePath "<fixture-path>"
```

Inline form (when no fixture fits — synthesize a payload):

```powershell
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<project-root>" `
  -RequestJson '{"requestId":"placeholder","scenarioId":"runbook-input-dispatch","runId":"runbook-input-dispatch","targetScene":"<main scene res:// path>","outputDirectory":"res://evidence/automation/agent","artifactRoot":"evidence/automation/agent","expectationFiles":[],"capturePolicy":{"startup":true,"manual":true,"failure":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"<UTC ISO-8601>","inputDispatchScript":{"events":[{"kind":"key","identifier":"ENTER","phase":"press","frame":30},{"kind":"key","identifier":"ENTER","phase":"release","frame":32}]}}'
```

`requestId` is always overridden by the script. Key identifiers are bare Godot logical names — **not** `KEY_ENTER`. For InputMap actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `failureKind` | `null` on success; see failure table |
| `manifestPath` | Absolute path to `evidence-manifest.json` on success |
| `outcome.outcomesPath` | Absolute path to `input-dispatch-outcomes.jsonl` |
| `outcome.declaredEventCount` | Number of events the script declared |
| `outcome.actualDispatchedCount` | Number of events that **actually fired** (status=`dispatched`) |
| `outcome.dispatchedEventCount` | Backwards-compat alias of `declaredEventCount`. Prefer `actualDispatchedCount`. |
| `outcome.firstFailureSummary` | First non-`dispatched` event's reason, or `null` on clean success |

Report `actualDispatchedCount` of `declaredEventCount`. Surface `firstFailureSummary` whenever it is non-null. When the two counts differ, the envelope returns `failureKind=runtime` — the run ended before the requested frames were reached. Tell the user the keys did **not** all fire; do not claim the input was delivered.

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Capability missing or stale | Tell the user to launch: `godot --editor --path "<project-root>"` |
| `request-invalid` | Payload schema violation | Read `diagnostics[0]`; fix the fixture or inline JSON |
| `build` | GDScript compile error before dispatch | Report `diagnostics[0]` verbatim |
| `runtime` | Editor-side blocker | Read `harness/automation/results/capability.json` for `blockedReasons` / `singleTargetReady`. If `target_scene_missing`: tell the user to open the target scene in the editor dock. **Do not blind-retry.** |
| `timeout` | Run did not complete | Editor may be frozen or not in play mode |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not manually poll `run-result.json`** — the invoke script owns the loop.
- **Do not vary `capturePolicy` / `stopPolicy` speculatively** — fixture defaults are correct.
- **Do not invent alternate input entrypoints** — this script is the only way.
