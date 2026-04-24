---
name: "godot-watch"
description: "Sample Godot node properties over a frame window and emit a trace. Use when the user asks to track a value over time, record how a property changes during gameplay, or observe behavior drift."
argument-hint: "fixture path with a behaviorWatchRequest block (under tools/tests/fixtures/runbook/behavior-watch/)"
compatibility: "Requires a Godot editor running against the target project and access to the godot-agent-harness invoke-*.ps1 scripts."
metadata:
  author: "godot-agent-harness"
  source: "tools/automation/invoke-behavior-watch.ps1"
user-invocable: true
disable-model-invocation: false
---

## User Input

```text
$ARGUMENTS
```

Treat `$ARGUMENTS` as a fixture path under `tools/tests/fixtures/runbook/behavior-watch/`. If the user wants to watch a specific node/property that no fixture covers, synthesize inline JSON with a `behaviorWatchRequest` block describing the targets, properties, and frame count. Ask the user which project root to target.

## Execution

```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot "<project-root>" `
  -RequestFixturePath "<fixture-path>"
```

Or with inline JSON (when no fixture fits):

```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot "<project-root>" `
  -RequestJson '{"requestId":"placeholder","scenarioId":"runbook-behavior-watch","runId":"runbook-behavior-watch","targetScene":"<main scene>","outputDirectory":"res://evidence/automation/agent","artifactRoot":"evidence/automation/agent","capturePolicy":{"startup":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"<UTC ISO-8601>","behaviorWatchRequest":{"targets":[{"nodePath":"/root/Main/Paddle","properties":["position"]}],"frameCount":10}}'
```

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `manifestPath` | Absolute path to `evidence-manifest.json` on success |
| `outcome.samplesPath` | Absolute path to the behavior-watch trace (`trace.jsonl`) |
| `outcome.sampleCount` | Number of frames sampled |
| `outcome.frameRangeCovered.first` / `.last` | First and last frame numbers in the trace |

Report `sampleCount` and the frame range; read `samplesPath` only if the user asks for specific values.

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Capability missing or stale | Tell the user to launch: `godot --editor --path "<project-root>"` |
| `request-invalid` | Payload schema violation | Read `diagnostics[0]`; fix the fixture or inline JSON |
| `build` | GDScript compile error | Report `diagnostics[0]` verbatim |
| `runtime` | Editor-side blocker or in-game error | Read `harness/automation/results/capability.json` for `blockedReasons`. If `target_scene_missing`, tell the user to open the scene in the editor dock. |
| `timeout` | Sampling did not complete | Editor may be frozen or frame count too high |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not sample unbounded frame counts** — high values lock the editor. Keep `frameCount` under 600 unless the user has a specific reason.
- **Do not bypass the request schema** — always go through the fixture or `-RequestJson` parameter.
