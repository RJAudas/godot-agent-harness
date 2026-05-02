---
name: "godot-watch"
description: "Sample Godot node properties over a frame window and emit a trace. Use when the user asks to track a value over time, record how a property changes during gameplay, or observe behavior drift."
argument-hint: "fixture path with a behaviorWatchRequest block"
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

Treat `$ARGUMENTS` as a fixture path under `{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/behavior-watch/`. For ad-hoc watches that no fixture covers, synthesize inline JSON with a `behaviorWatchRequest` block. Default project root is the current project (`.`).

## Execution

`-EnsureEditor` idempotently launches a Godot editor for the project (or reuses one if already running and capability.json is fresh). Pass it on every call.

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestFixturePath "<fixture-path>"
```

Or with inline JSON:

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot "<project-root>" -EnsureEditor `
  -RequestJson '{"requestId":"placeholder","scenarioId":"runbook-behavior-watch","runId":"runbook-behavior-watch","targetScene":"<main scene>","outputDirectory":"res://evidence/automation/agent","artifactRoot":"evidence/automation/agent","capturePolicy":{"startup":true},"stopPolicy":{"stopAfterValidation":true,"minRuntimeFrames":10},"requestedBy":"agent","createdAt":"<UTC ISO-8601>","behaviorWatchRequest":{"targets":[{"nodePath":"/root/Main/Paddle","properties":["position"]}],"frameCount":10}}'
```

## Lifetime requirement

A behavior watch needs the playtest to live `startFrameOffset + frameCount` process frames. The post-validation stop is unconditional (B18 fix), so the only knob that grants more frames is `stopPolicy.minRuntimeFrames`. Set it to ≥ `startFrameOffset + frameCount`. If you forget, the harness rejects the request with a diagnostic containing `incompatible_stop_policy` naming the required value.

## Frame-field semantics

The trace's `frame` field is the physics-tick counter (`Engine.get_physics_frames()`). When `cadence: every_frame`, consecutive trace rows are guaranteed contiguous and single-physics-tick events (teleports, brief signal transients) are always captured. `cadence.everyNFrames` and `startFrameOffset` / `frameCount` count physics frames. (Fixed in issue #53.)

## Envelope fields

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `manifestPath` | Absolute path to `evidence-manifest.json` on success |
| `outcome.samplesPath` | Absolute path to `trace.jsonl` |
| `outcome.sampleCount` | Number of frames sampled |
| `outcome.frameRangeCovered.first` / `.last` | Frame range in the trace |

## Failure handling

| `failureKind` | What it means | Next step |
|---|---|---|
| `editor-not-running` | Auto-launch failed (e.g. missing `$env:GODOT_BIN`, project failed to import) | Read `diagnostics[0]` for the underlying reason; common fix is to ensure `$env:GODOT_BIN` points at a Godot 4 binary |
| `request-invalid` | Payload schema violation | Read `diagnostics[0]`; fix the fixture or inline JSON |
| `build` | GDScript compile error | Report `diagnostics[0]` verbatim |
| `runtime` | Editor-side blocker or in-game error | Read `harness/automation/results/capability.json` for `blockedReasons`. If `target_scene_missing`, tell the user to open the scene in the editor dock. |
| `timeout` | Sampling did not complete | Editor may be frozen or frame count too high |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not sample unbounded frame counts** — keep `frameCount` under 600 unless the user has a specific reason.
- **Do not bypass the request schema** — always go through fixture or `-RequestJson`.
