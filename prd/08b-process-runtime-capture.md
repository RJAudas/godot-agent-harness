# Pass 8b — Capture `_process`-time (and other post-`_ready`) runtime errors

## Scope

Sibling defect to [B10](08a-ready-runtime-capture.md). Re-confirmed in [pass 8](08-test-pass-results.md) after [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39) shipped a fix that did not actually land.

| ID | Workflow | What's broken | Fix area |
|---|---|---|---|
| B17 | Runtime-error triage | Runtime errors raised in `_process`, `_physics_process`, signal handlers, deferred calls, or post-startup `await` paths are not captured; `runtime-error-records.jsonl` stays 0 bytes; envelope reports clean `success` | addon runtime-error capture pipeline (same surface as B10) |

## Why this is its own batch

- **Same root-cause family as B10**, but a different lifecycle slot — verifying that B10's fix actually generalizes requires a separate live regression. PR #39 grouped them and shipped neither.
- **Different failure mechanism than B10**. B10 fails because the playtest crashes *during* `_ready` and exits before the deferred merge runs. B17 fails because the playtest exits *before the first `_process` tick fires* — the validation pass completes the run before the user's `_process` code ever executes. The fix has to address both.
- **Different scenes / fixtures.** B10 uses probe + injected `error_main.gd`. B17 uses the shipped `runtime-error-loop/scenes/error_on_frame.tscn`. Verifying both confirms the fix is general.

## Problem

PR #39 commit message claimed to fix B17 alongside B10. Live pass-8 testing shows the runtime-error-loop scene with a `_process`-time null deref still reports clean `success`:

**Reproduction** (matrix row 6b):
```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/runtime-error-loop

# Inline payload overriding targetScene + stopAfterValidation:false:
$payload = '{"requestId":"placeholder","scenarioId":"runbook-runtime-error-triage","runId":"runbook-runtime-error-triage","targetScene":"res://scenes/error_on_frame.tscn","outputDirectory":"res://evidence/automation/$REQUEST_ID","capturePolicy":{"startup":true,"manual":true,"failure":true},"stopPolicy":{"stopAfterValidation":false},"requestedBy":"agent","createdAt":"2026-04-26T17:38:00Z"}'
$payload | Out-File integration-testing/runtime-error-loop/harness/test.json -Encoding utf8
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/runtime-error-loop `
    -RequestFixturePath ./integration-testing/runtime-error-loop/harness/test.json
```

**Observed**:
```json
{ "status": "success",
  "outcome": {
    "terminationReason": "completed",
    "runtimeErrorRecordsPath": "…/runtime-error-records.jsonl",
    "latestErrorSummary": null
  } }
```
JSONL is 0 bytes. `scenegraph-snapshot.json` shows `trigger.trigger_type="startup"`, `trigger.frame=0`, run completed in ~3s.

The `_process` error in `error_on_frame.gd:20` never fires because the playtest exits before the first frame is ticked. This is a **different mechanism than B10**: B10 fails after the error fires; B17 fails before the error has a chance to fire.

**Where**: same surfaces as B10 plus a runtime-side "minimum frame budget" or "tick-before-validation" hook:

- [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd) — startup-validation gate
- [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) — termination policy

## Resolution: live testing feedback as the verification gate

Same methodology as [Pass 8a](08a-ready-runtime-capture.md): **the fix loop must be live-editor-driven**, not Pester-driven. PR #39 passed Pester for B17 too, and shipped a non-fix.

1. **Reproduce live before writing code.** Run the reproduction above on `runtime-error-loop` with `error_on_frame.tscn`; confirm the 0-byte JSONL and frame-0 snapshot. This is the failing baseline.
2. **Write the fix.** Two pieces (see *Fix proposal* below): (a) ensure the pause-on-error JSONL writer from 8a is also active for non-`_ready` errors, and (b) keep the playtest alive long enough for at least one `_process` tick so user code has a chance to fire.
3. **Verify against the live repro after every meaningful change.** ~10s round trip: edit `.gd`, parse-check, invoke, inspect JSONL.
4. **Verify cross-scene generality.** After the fix passes 6b, also re-run the other `runtime-error-loop` scenes (`crash_after_error.tscn`, `repeat_error.tscn`, `unhandled_exception.tscn`) and confirm each produces a non-empty JSONL with the expected error.
5. **Add a frame-budget Pester test** that asserts the workflow refuses to claim `success` when the playtest exited in <30 frames without ever reaching user `_process` code. This is a guardrail against the "exits before user code runs" failure mode.
6. **Lock the live regressions into PR review.** PR description must include matrix-row-6b envelope output for `error_on_frame.tscn` *and* at least one other runtime-error-loop scene as proof-of-fix.

## Fix proposal (concrete)

Two complementary changes:

### 1. JSONL writer must be active for any error, not just `_ready`-time

Whatever 8a does for the pause-on-error handler must apply uniformly — the handler should not branch on lifecycle slot. If 8a's fix is "eager-open in `_enter_tree`, append+flush per error in the handler," it should already capture `_process` errors. **Verify this by running 8b's repro after 8a lands** before assuming.

### 2. Frame budget — the playtest must run long enough for user code to fire

The current behavior (matrix-6b snapshot shows `frame=0`, run completes in ~3s with `stopAfterValidation:false`) means the validation pass completes before any `_process` tick. Options:

- **Option A (recommended): add a `minRuntimeFrames` to the stop policy.** Default to e.g. 30 frames (~0.5s at 60fps) for runtime-error-triage scenarios. The validation pass must wait for `Engine.get_process_frames() >= minRuntimeFrames` before terminating, even on `stopAfterValidation:true`. Sandbox authors / agents can override.
- **Option B: respect `stopAfterValidation:false` differently.** When `stopAfterValidation:false` is set, don't terminate at all on the validation pass — let the playtest run until it crashes, until a frame limit is hit, or until an explicit stop request arrives. This is closer to the *spirit* of `stopAfterValidation:false` but is a bigger change.

Option A is the pragmatic minimum and fits the existing schema; option B is the principled fix and may be the right follow-on. Suggest landing Option A in this batch and tracking Option B as a future capability.

### 3. Refuse to claim `success` on suspicious empty captures

Even with the fix, a defense-in-depth measure: when `runtime-error-records.jsonl` is empty *and* `Engine.get_process_frames() < minRuntimeFrames` *and* the user's scene has `_process`/`_physics_process` callbacks declared, the manifest should set `status=warn` or surface a diagnostic instead of `pass`. This is the "envelope must not lie" rule from pass 7's analysis.

## Subtasks

1. **Live baseline.** Run the reproduction above; capture the frame-0 snapshot + 0-byte JSONL as the failing case. ~3 minutes.
2. **Verify 8a's pause-on-error writer covers `_process` errors.** Land 8a first; then re-run 8b's repro. If JSONL is non-empty, the only remaining work is the frame-budget piece. ~5 minutes.
3. **Implement frame-budget gate (`minRuntimeFrames`).** Add to stop policy schema with sensible default; thread through to the runtime's validation-pass logic. ~1 hour.
4. **Live regression: matrix row 6b.** Re-run the `error_on_frame.tscn` repro; confirm JSONL has ≥1 record and envelope reports `failureKind=runtime`. ~5 minutes.
5. **Live regression: other runtime-error-loop scenes.** Run `crash_after_error.tscn`, `repeat_error.tscn`, `unhandled_exception.tscn`. Each should produce a non-empty JSONL with the expected error. ~15 minutes.
6. **Add Pester case: empty JSONL + low frame count must not project to `status=pass`.** ~30 minutes.
7. **Run `tools/check-addon-parse.ps1`** after every addon edit.
8. **PR description must paste matrix-6b envelope output for at least two scenes** as proof-of-fix.

## How to verify

Same reproduction as above. After the fix:
- `runtime-error-records.jsonl` contains ≥1 row with `file=res://scenes/error_on_frame.gd` (or `error_on_frame.gd`), the right line number, and a null-deref message.
- Envelope reports `status=failure`, `failureKind=runtime`, `outcome.latestErrorSummary` populated.
- Snapshot's `trigger.frame >= 30` (the new minimum frame budget), confirming the playtest actually ticked.
- Same shape for the other runtime-error-loop scenes.

## Cross-batch dependencies

- **8b → 8a** — land 8a first. If 8a's pause-on-error writer is built correctly (eager-open, sync-flush, no lifecycle-slot branch), 8b's first verification step should pass for free, and the only remaining work is the frame-budget gate.
- **8b is independent of 8c.** The playtest-leak fix is broker-side and orthogonal.

## Not in scope

- B10 (`_ready`-time capture) — see [Pass 8a](08a-ready-runtime-capture.md).
- B18 (playtest leak) — see [Pass 8c](08c-playtest-cleanup.md).
- A general "scene timeout" or "explicit stop request" capability — that's the principled fix for `stopAfterValidation:false` semantics and worth a dedicated future spec, not a fold-in here.
