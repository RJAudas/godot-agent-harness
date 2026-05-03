# 00 — Test Matrix Template

This template captures the recipe for running a hardening test pass against a real Godot editor + real Godot project. Use it whenever the runbook surface changes (new workflows, new fixtures, new orchestration parameters) or as a periodic regression sweep.

## How to use

1. **Copy the [Output template](#output-template) below** into a new `prd/NN-test-pass-results.md`. Strip everything else.
2. **Follow the [Test plan](#test-plan)** to actually run each row. The plan stays in this template — it is not part of the results doc.
3. **Fill in the matrix row** as you go. One row per test; populate calls / status / notes.
4. **Capture issues** under the issues section using the `B<n>` (bug) or `F<n>` (friction) convention from prior passes. Reference issue IDs from the Notes column so each row links to its details.
5. **Write the summary** as critical / significant / minor; recommend the next pass(es).

Do not paste the test-plan instructions into the results doc — the goal is a focused, scannable matrix + issues report. The template is the reproducible recipe; the results doc is the report.

---

## Output template

Copy from here to the end-of-output marker into your new `prd/NN-test-pass-results.md`. Replace `<N>` with the pass number, populate the matrix and issues sections.

> **--- BEGIN OUTPUT ---**

````markdown
# Pass <N> — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md) [, …], this pass exercises every runbook tool against a real Godot editor and a real Godot project — not via Pester, not via the broker mock — and captures any unexpected behaviors or bugs that show up only against a live editor.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: <list>
- **Editor instances**: launched via `tools/automation/invoke-launch-editor.ps1`
- **Fixtures**: shipping fixtures under `tools/tests/fixtures/runbook/<workflow>/` plus inline `-RequestJson` payloads where no fixture matched
- **Failure-path coverage**: <which workflows had both clean and failure paths exercised>

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | | | |
| 2 | Scene inspection | `/godot-inspect` | probe | | | |
| 3 | Input dispatch | `/godot-press` | probe | | | |
| 4a | Behavior watch (success path) | `/godot-watch` | probe | | | |
| 4b | Behavior watch (missing target) | `/godot-watch` | probe | | | |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | | | |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | | | |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | | | |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | | | |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | | | |
| 7 | Pin run | `/godot-pin` | probe | | | |
| 8 | List pinned (1 pin / N pins) | `/godot-pins` | probe | | | |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | | | |
| 10 | Stop editor | — | probe | | | |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe | | | |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: <X> distinct workflows / paths exercised. **<n> passed clean**, **<n> partial / misleading**, **<n> broken**.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction).

### B<n> — <one-line title>

**Where**: <file:line links>

**Reproduction**:
```powershell
<commands>
```

**Observed**:
```json
<envelope or artifact excerpt>
```

**Symptom**: <impact on agents/users>

**Fix**: <proposed change, with code where possible>

**How to verify**: <repro that should now pass>

---

[repeat per issue]

## Summary

**Critical (workflow broken)**: <list IDs>. <one-line interpretation>

**Significant (misleading semantics)**: <list IDs>. <one-line interpretation>

**Minor (cosmetic / churn)**: <list IDs>. <one-line interpretation>

**Tool-call ergonomics**: <observations on which workflows took more calls than the 2-call ideal and why>

**Suggested next pass**: <split recommendation, e.g. 6a semantic correctness vs 6b surface polish>
````

> **--- END OUTPUT ---**

---

## Test plan

This section is the recipe. Do not copy it into the results doc.

Each numbered subsection corresponds to a matrix row above. For each: pre-conditions, command, expected envelope shape, and bugs to watch for. The bugs-to-watch list is updated as new issues are found across passes — when a bug is reported, add it here so the next pass automatically checks for regression.

### Sandbox setup

- **probe**: minimal canonical sandbox. Run `pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru` if missing. Restored to default `scenes/main.tscn` (Control + Label) before each pass. The `integration-testing/` directory is git-ignored, so destructive testing is safe.
- **runtime-error-loop**: ships in repo with multiple `*.tscn` (no_errors, error_on_frame, crash_after_error, etc.). Has a `harness/inspection-run-config.json` that may shadow request-time fields — see B8.
- **input-dispatch**: ships an `input_logger.gd` that records keypresses. Useful when you want a target where input *actually has visible effects*.

When a test injects a runtime or compile error, **revert the sandbox** before the next test. The harness automatically clears the transient zone, but injected `.gd` / `.tscn` changes are not reverted automatically.

### Counting tool calls

- "Min path" means the call sequence a fresh agent following the skill SKILL.md would take.
- Slash command invocation = 1 call (the `Skill` tool).
- Each `pwsh` invocation = 1 call (the `Bash` tool).
- Don't include calls made to *investigate* a bug (reading `run-result.json`, listing fixtures, etc.) — those are friction notes, not part of the happy-path count.
- If the skill SKILL.md references a fixture without naming it, an `ls` of the fixtures directory counts as part of the min path. (This is the "skill discovery friction" pattern.)

---

### Cross-cutting regression checks

These apply to **every runtime-launching row** (3, 4a/4b, 5b, 6a–c). Don't add a dedicated row for them — verify opportunistically while running those rows, and note any failure under the relevant row's Notes column.

- **#58 regression — `targetScene` fallback**: a request that *omits* `targetScene` must fall back to the project's `application/run/main_scene` and run cleanly. To exercise: synthesize an inline payload with no `targetScene` field and confirm the run targets the project's default scene.
- **#59 regression — split target-scene failure codes**: omitting `targetScene` in a project that has no `application/run/main_scene` configured must produce `failureKind=target_scene_unspecified`. A request pointing to a nonexistent `.tscn` must produce `failureKind=target_scene_file_not_found`. The legacy generic `target_scene_missing` must never appear.

---

### 1. Editor launch

**Sandbox**: probe
**Pre-conditions**: editor stopped (`pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe` returns `noopReason=no-matching-editor` if so).

**Command**:
```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
```

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "editorPid": <int>, "reusedExistingEditor": false, "capabilityAgeSeconds": <0..N> } }
```

**Bugs to watch for**:
- Non-JSON content on stdout (re-run with `2>/dev/null` to verify stdout is pure JSON).
- `reusedExistingEditor: true` when editor was supposed to be stopped (means stop-editor lied).

**Tool-call expectation**: 1.

---

### 2. Scene inspection

**Sandbox**: probe (with editor running).

**Command**:
```powershell
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
```

Or via skill: `/godot-inspect ./integration-testing/probe`.

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "nodeCount": >=2, "sceneTreePath": "<path>" } }
```

For probe (Main + Label), nodeCount = 2.

**Bugs to watch for**:
- Doubled `runbook-scene-inspection-` prefix in `manifestPath` directory or in pinned `scenarioId` (B1 / B12).
- nodeCount = 0 when scene clearly has nodes (capability missing, target_scene_missing).

**Tool-call expectation**: 2 (skill + invoke).

---

### 3. Input dispatch

**Sandbox**: probe (or input-dispatch sandbox for visible effects).
**Fixture**: `tools/tests/fixtures/runbook/input-dispatch/press-enter.json`.

**Command**:
```powershell
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "declaredEventCount": >=1, "actualDispatchedCount": >=1, "firstFailureSummary": null } }
```

**Always inspect** the produced `input-dispatch-outcomes.jsonl` and confirm each event row has `status: "dispatched"` (not `skipped_frame_unreached`). Mismatch between envelope and JSONL = B2.

**Bugs to watch for**:
- B2: `actualDispatchedCount` matches `declaredEventCount` even when every JSONL row is `skipped_frame_unreached` (the envelope should classify the run as `failure`).
- B1: doubled prefix in output directory.
- `firstFailureSummary` non-null with `status: success`.

**Tool-call expectation**: 2 (skill + invoke). Add 1 if the agent has to `ls` the fixtures dir (skill should ideally enumerate).

---

### 4a. Behavior watch — success path

**Sandbox**: probe (the default Control + Label scene contains the watched node at `/root/Main/Label`).
**Fixture**: `tools/tests/fixtures/runbook/behavior-watch/probe-label-window.json` (watches probe's Label `text`/`visible` — paired with the probe scaffold so the matrix has a real success path, not just a missing-target case). Note: `label-text-window.json` exists in the same directory but targets a Pong-style `/root/Main/HUD/ScoreLeftLabel` and is not appropriate for probe.

**Command**:
```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/probe-label-window.json
```

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "samplesPath": "<path>", "sampleCount": >=1, "warnings": [] } }
```

The trace JSONL referenced by `samplesPath` should contain at least one row per requested property, with a monotonic `frame` field.

**Bugs to watch for**:
- **#54 regression**: requesting an allowlisted property on a real node returns `sampleCount > 0`. Requesting a *disallowed* property returns an enriched enum error that names the bad property and lists valid ones — not a generic "validation failed".
- **#55 regression**: a request whose `windowFrames` exceeds `stopPolicy.minRuntimeFrames` must be rejected at validation, not silently truncated. Force this case with an inline payload that violates the gate.
- **#56 regression**: trace rows' `frame` field is the physics-tick counter (`Engine.get_physics_frames()`), not the idle-process frame counter. Verify samples grow at physics cadence (60Hz default), not idle cadence.
- **#60 regression**: `samplesPath`, warnings, and the missing-target/property notes in the envelope come from the **manifest**, not the request payload. Cross-check by reading the manifest's `behaviorWatch` section and confirming envelope fields match byte-for-byte.

**Tool-call expectation**: 2 (skill + invoke).

---

### 4b. Behavior watch — missing-target path

**Sandbox**: probe (will produce sampleCount=0 because Paddle doesn't exist — *use this to check that case*).
**Fixture**: `tools/tests/fixtures/runbook/behavior-watch/single-property-window.json` (watches `/root/Main/Paddle`).

**Command**:
```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/single-property-window.json
```

**Expected envelope (target node missing)**:
```json
{ "status": "failure" or "success",
  "outcome": { "samplesPath": "<path>", "sampleCount": 0,
               "warnings": [ "target node not found...", "target node sampled but properties never observed..." ] } }
```

Pre-#60 the envelope had `samplesPath: null` and warnings synthesized from the request payload. Post-#60, `samplesPath` is non-null (points at the empty trace artifact) and warnings come from the manifest's `missingTargets[]` / `missingProperties[]`.

If `status: success` with `sampleCount: 0` and no diagnostic / empty warnings, that's B3 — silent partial failure.

**Bugs to watch for**: B3, B1, **#60 regression** (envelope diverging from manifest — see 4a).

**Tool-call expectation**: 2 (skill + invoke). Often 3 because the SKILL.md doesn't enumerate fixtures.

---

### 5a. Build-error triage — clean path

**Sandbox**: probe (default state, no compile errors).
**Fixture**: `tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json`.

**Command**:
```powershell
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json
```

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "firstDiagnostic": null, "rawBuildOutputPath": null } }
```

**Tool-call expectation**: 2.

---

### 5b. Build-error triage — compile error path

**Sandbox**: probe + deliberate broken script.

**Setup**:
1. Write `integration-testing/probe/scripts/broken.gd`:
   ```gdscript
   extends Node
   func _ready() -> void
       print("missing colon")
   ```
2. Edit `integration-testing/probe/scenes/main.tscn` so the Main node references `res://scripts/broken.gd` via `[ext_resource type="Script"]`.

**Command**: same as 5a.

**Expected envelope**:
```json
{ "status": "failure",
  "failureKind": "build",
  "outcome": {
    "firstDiagnostic": {
      "file": "res://scripts/broken.gd",
      "line": <int>,
      "column": <int>,
      "message": "<verbatim parser message>"
    }
  } }
```

If `outcome.firstDiagnostic` is `null` while `failureKind=build`, that's B4 — the data is in `harness/automation/results/run-result.json` but not propagated to the envelope. If the envelope's `diagnostics[0]` says "Check the run-result for details" without a path, that's B5.

**Cleanup**: delete `scripts/broken.gd`, remove the `scripts/` dir if empty, restore `scenes/main.tscn` to its default (Control + Label, no `script = ExtResource(...)`).

**Bugs to watch for**: B4, B5, B1.

**Tool-call expectation**: 3 minimum (skill + Write broken script + invoke), excluding cleanup. Real-world: 4–5 with the tscn edit.

---

### 6a. Runtime-error triage — clean path

**Sandbox**: probe (no runtime errors).
**Fixture**: `tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json`.

**Command**:
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json
```

**Expected envelope**:
```json
{ "status": "success",
  "outcome": { "terminationReason": "completed",
               "runtimeErrorRecordsPath": null,
               "latestErrorSummary": null } }
```

**Tool-call expectation**: 2.

---

### 6b. Runtime-error triage — non-default scene

**Sandbox**: runtime-error-loop (ship multiple scenes).
**Pre-condition**: runtime-error-loop sandbox's editor running.

**Command** (synthesize inline payload to override the fixture's `targetScene`):
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot ./integration-testing/runtime-error-loop `
    -RequestJson '{"requestId":"placeholder","scenarioId":"runbook-runtime-error-triage","runId":"runbook-runtime-error-triage","targetScene":"res://scenes/error_on_frame.tscn","outputDirectory":"res://evidence/automation/$REQUEST_ID","capturePolicy":{"startup":true,"manual":true,"failure":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"<UTC ISO-8601>"}'
```

**Expected envelope**:
```json
{ "status": "failure",
  "failureKind": "runtime",
  "outcome": {
    "latestErrorSummary": { "file": "res://scenes/error_on_frame.gd", "line": 18, "message": "..." },
    "terminationReason": "completed" } }
```

**Bugs to watch for**:
- B8: sandbox's `inspection-run-config.json` may silently override `targetScene` and `outputDirectory`. Inspect the resulting manifest's `runId` / `scenarioId` — if they don't match the request, that's B8.
- F1: default fixture targets `res://scenes/main.tscn` which doesn't exist in runtime-error-loop.
- B7/B9: misleading `failureKind=internal` when the underlying issue was `validation`.

**Cleanup**: stop runtime-error-loop's editor.

**Tool-call expectation**: 4+ (launch second editor, ls/inspect fixture, invoke, plus inspect run-result on failure).

---

### 6c. Runtime-error triage — null-deref in `_ready`

**Sandbox**: probe + deliberate runtime error.

**Setup**:
1. Write `integration-testing/probe/scripts/error_main.gd`:
   ```gdscript
   extends Control
   func _ready() -> void:
       var n: Node = null
       n.get_name()  # null deref
   ```
2. Edit `scenes/main.tscn` so Main has `script = ExtResource("res://scripts/error_main.gd")`.

**Command**: same as 6a.

**Expected envelope** (what *should* happen):
```json
{ "status": "failure",
  "failureKind": "runtime",
  "outcome": {
    "latestErrorSummary": { "file": "res://scripts/error_main.gd", "line": 5, "message": "<null deref message>" } } }
```

**Observed previously (B10)**: `status: success`, empty `runtime-error-records.jsonl`, runtime exited via `stopAfterValidation` before the error was captured. If you reproduce B10, ALSO try with a fixture variant that sets `stopAfterValidation: false` and a `frameLimit: 600` — the error should surface.

**Cleanup**: delete `scripts/error_main.gd`, remove `scripts/` dir if empty, restore `scenes/main.tscn`.

**Bugs to watch for**:
- B10 (the load-bearing one), B1.
- **#57 regression**: the captured record's `function`/`scriptPath`/`line` must point at the *user* GDScript frame (`_ready` in `error_main.gd:4`), not the engine-side C++ emission point. Two distinct user call sites of the same engine error must appear as two records, not deduped into one.

**Tool-call expectation**: 3–4 minimum.

---

### 7. Pin run

**Sandbox**: probe (with at least one transient run on disk).
**Pre-condition**: run any workflow (e.g. scene-inspection) so there is an evidence-manifest.json under `evidence/automation/` to pin.

**Command**:
```powershell
pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName probe-test1
```

**Expected envelope**:
```json
{ "status": "ok",
  "operation": "pin",
  "pinName": "probe-test1",
  "plannedPaths": [ <list with action: "copy" entries plus one "create"> ] }
```

**Refusal paths to also exercise**: `pin-name-collision` (re-pin same name without `-Force`), `pin-name-invalid` (non-conforming slug).

**Tool-call expectation**: 2.

---

### 8. List pinned

**Sandbox**: probe.

**Command**:
```powershell
pwsh ./tools/automation/invoke-list-pinned-runs.ps1 -ProjectRoot ./integration-testing/probe
```

**Critical test**: list with **exactly 1 pin**, then list with **2+ pins**. Compare the shape of `pinnedRunIndex`.

**Expected envelope (always)**:
```json
{ "status": "ok",
  "operation": "list",
  "pinnedRunIndex": [ { "pinName": "...", ... }, ... ] }
```

If `pinnedRunIndex` is an *object* (not an array) when there is exactly one pin, that's B11 — PowerShell's `ConvertTo-Json` collapsed the single-element array. Use `,@($pins)` to force array shape before serializing.

**Bugs to watch for**: B11, B12.

**Tool-call expectation**: 2 (or 4 if you exercise both 1-pin and N-pin cases).

---

### 9. Unpin run

**Sandbox**: probe (with at least one pin).

**Commands** (success + refusal):
```powershell
pwsh ./tools/automation/invoke-unpin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName probe-test1
pwsh ./tools/automation/invoke-unpin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName does-not-exist
```

**Expected envelopes**:
- Success: `status=ok`, `operation=unpin`, `plannedPaths` list with `action=delete`.
- Refusal: `status=refused`, `failureKind=pin-target-not-found`, exit 0 (per RUNBOOK convention).

**Bugs to watch for**: refusal exit code != 0 (RUNBOOK contract violation).

**Tool-call expectation**: 2.

---

### 10. Stop editor

**Sandbox**: probe (and any other editor that was started).

**Commands** (active stop + idempotent no-op):
```powershell
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe   # again — should no-op
```

**Expected envelopes**:
- Active: `status=success`, `outcome.stoppedPids = [<pid>]`.
- No-op: `status=success`, `outcome.noopReason = "no-matching-editor"`.

**Bugs to watch for**:
- Stops the wrong editor (matches by `--path`; verify only the targeted instance dies).
- `stoppedPids` empty when an editor *was* running for that ProjectRoot.

**Tool-call expectation**: 1.

---

### 11. `-EnsureEditor` shortcut (cold-start)

**Sandbox**: probe.
**Pre-condition**: editor fully stopped.

**Command**:
```powershell
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe -EnsureEditor
```

**Expected envelope**: same as 2 (scene inspection success), with the launch step transparently completed first.

**Bugs to watch for**:
- B13: cold-start hang — the orchestration waits indefinitely after editor launch, never writes the `run-request.json`. If wallclock exceeds 60s without progress, kill the task and fall back to the explicit two-step (`invoke-launch-editor` then plain workflow). Mark this row as ❌ broken until B13 is fixed.

**Tool-call expectation**: 1 (when working).

---

## Issue ID conventions

- `B<n>` — bugs (incorrect behavior, broken envelopes, schema lies, hangs).
- `F<n>` — friction (works as designed but takes too many calls / is misleading / requires guess).
- Continue numbering across passes — do not restart at B1 for each pass. Cross-reference prior pass IDs in Notes column ("regression of B4").

## Severity ladder

- **Critical**: workflow broken or returns silently wrong data. Agents acting on the envelope will mis-report to users.
- **Significant**: misleading semantics — envelope is technically correct but the contract surface lies (schema mismatch, contradictory fields, silent partial failure).
- **Minor**: cosmetic, churn, doc nits, ergonomic friction (extra discovery calls).

When the matrix has a critical issue (`❌`), recommend either standalone-pass landing or splitting the pass into semantic-correctness vs surface-polish batches.

## When to update this template

- Add new rows when the runbook gains a workflow or invoke script.
- Update bugs-to-watch-for under an existing row each time a new bug is found in that workflow — that lets the next pass automatically check for regression.
- Keep the output template stable; the test plan is where new instructions go.
