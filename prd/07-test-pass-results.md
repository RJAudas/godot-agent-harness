# Pass 7 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md), [pass 5](05-test-pass-results.md), and [pass 6](06-test-pass-results.md) (split into [6a](06a-outcome-shape-cleanup.md), [6b](06b-runtime-semantic-correctness.md), [6c](06c-editor-lifecycle-hardening.md)), this pass re-runs the full matrix against a real Godot editor (`Godot_v4.6.2-stable_win64`) and a real Godot project to confirm the three pass-6 batches landed cleanly and to surface any regressions or new defects.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures).
- **Editor instances**: launched via `tools/automation/invoke-launch-editor.ps1`. Two editors used at one point (probe + runtime-error-loop) since the harness is per-project.
- **Fixtures**: shipping fixtures under `tools/tests/fixtures/runbook/<workflow>/` plus an inline payload (loaded from a temp file) where no fixture matched the override case.
- **Failure-path coverage**: where a workflow has both clean and failure paths (build-error triage, runtime-error triage, pin/unpin), both were exercised — including injecting deliberate compile and runtime errors into probe and reverting after.

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Stderr heartbeats (`spawned Godot PID …`, `editor ready …`) alongside pure JSON stdout. Capability ready in 5s. |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | nodeCount=2, no doubled prefix. |
| 3 | Input dispatch | `/godot-press` | probe | 2 | ⚠️ partial | **B14 FIXED** — vestigial `dispatchedEventCount` field is gone; envelope only carries `actualDispatchedCount`/`declaredEventCount`. Behavior unchanged: probe ends before frame 30, so `actualDispatchedCount=0`, `status=failure`, `skipped_frame_unreached` per JSONL. Envelope is now correct; the press-enter+probe fixture combination is still not a working happy-path (longstanding fixture/sandbox mismatch, not a regression). |
| 4 | Behavior watch | `/godot-watch` | probe | 2 | ✅ pass | **B15 FIXED** — `warnings` is now a flat `["target node not found …"]` array. status=success, sampleCount=0 when target missing. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | Clean. `outcome.runResultPath` exposed; `firstDiagnostic` null. |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | 3 | ✅ pass | `failureKind=build`, `firstDiagnostic={file:res://scripts/broken.gd, line:3, column:1, message:'Unexpected "Indent" in class body.'}`. Verbatim parser message. Exit 1. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | Clean smoke fixture. `latestErrorSummary=null`, `terminationReason=completed`, `runtimeErrorRecordsPath` populated (empty JSONL referenced as artifact). |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | 4 | ⚠️ partial | **B8 FIXED** — manifest's `runId`/`scenarioId`/`outputDirectory` now match the request, not `inspection-run-config.json` (verified: manifest at `evidence/automation/runbook-runtime-error-triage-…`, runId=`runbook-runtime-error-triage`, not `runtime-error-loop-run-01`). However, the runtime error in `error_on_frame.gd:_process` (line 18) is **not captured** — `runtime-error-records.jsonl` is 0 bytes, `latestErrorSummary=null`, `status=success`. Same root cause as B10 but in a `_process` rather than `_ready` lifecycle slot. Tested with both `stopAfterValidation: true` and `false`. |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | 3 | ❌ broken | **B10 STILL PRESENT** despite the [pass 6b](06b-runtime-semantic-correctness.md) fix. Tested with both `run-and-watch-for-errors.json` (stopAfterValidation=true) and `run-and-watch-for-errors-no-early-stop.json` (stopAfterValidation=false). Both: `status=success`, `terminationReason=completed`, `latestErrorSummary=null`, `runtime-error-records.jsonl` is 0 bytes. Manifest's `runtimeErrorReporting.pauseOnErrorMode="active"` and the artifactRef is emitted (06b's manifest-shape fix verified), but no error rows ever land in the JSONL — the runtime side is still not capturing the `_ready`-time null deref before the playtest exits. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | 8-file pin (manifest + 4 scenegraph artifacts + run-result + lifecycle-status + pin-metadata). Refusal paths verified: `pin-name-collision` and `pin-name-invalid` both exit 0 with `status="refused"`. |
| 8 | List pinned (1 pin / 2 pins) | `/godot-pins` | probe | 4 | ✅ pass | `pinnedRunIndex` is a JSON array in both cases. `scenarioId="runbook-runtime-error-triage-scenario"` / `"runbook-scene-inspection-scenario"` (no doubled prefix). |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | 2 | ✅ pass | Success: `plannedPaths` lists 8 deletions. Refusal: `status=refused`, `failureKind=pin-target-not-found`, exit 0. |
| 10 | Stop editor | — | probe | 1 | ✅ pass | Active stop returns `stoppedPids:[<pid>]`; idempotent re-call returns `noopReason="no-matching-editor"`. **F3 verified independently** — earlier in the run, a single stop-editor call killed both the editor (24624) and an orphan playtest (14420) in one shot. |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe (cold-start) | 1 | ✅ pass | **B13 FIXED.** End-to-end cold-start scene-inspection completed in **8s**: `[invoke-launch-editor] spawned Godot PID 8896` → `editor ready (capability.json mtime 0s ago); dispatching workflow` → workflow envelope (`status=success`, `nodeCount=2`). No hang. The pipe-free subprocess + 90s hard cap from [pass 6c](06c-editor-lifecycle-hardening.md) is doing its job. |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 13 distinct workflows / paths exercised. **9 passed clean**, **3 partial**, **1 broken**. Pass-6 fixes for **B8, B13, B14, B15, F3** verified live; **B10 still present**; **two new defects (B17, B18) and one new orchestration crash (B19) discovered out of scope of pass 6**.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction). Pass 6 ended at B16/F3; new issues start at B17 and at this pass.

### B10 — Runtime errors in `_ready` still not captured (regression of pass-6b fix)

**Where**: [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd), [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd), [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd).

**Reproduction**:
```powershell
# Setup
Set-Content integration-testing/probe/scripts/error_main.gd @'
extends Control
func _ready() -> void:
    var n: Node = null
    n.get_name()
'@
# Edit scenes/main.tscn to attach error_main.gd to Main.

pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
```

**Observed**:
```json
{ "status": "success",
  "failureKind": null,
  "outcome": {
    "terminationReason": "completed",
    "latestErrorSummary": null,
    "runtimeErrorRecordsPath": "…/runtime-error-records.jsonl"
  } }
```
The referenced JSONL is **0 bytes**. The manifest correctly emits the `runtime-error-records` artifactRef (06b's `scenegraph_artifact_writer.gd` change is in place) and `runtimeErrorReporting.pauseOnErrorMode="active"`, but the runtime side never writes any error rows to the file.

**Symptom**: Runtime-error triage is the workflow agents reach for first when triaging crashes, and on a real `_ready`-time null deref it lies — reports clean. This is the same Critical issue called out in pass 6 and the targeted fix in [b853c71](https://github.com/RJAudas/godot-agent-harness/commit/b853c71) ("B10 — runtime errors raised during a scene's `_ready()` are now captured") landed correctly at the manifest/orchestrator layer but does not produce a populated JSONL when the playtest actually crashes in `_ready`.

**Hypothesis**: 06b's deferred-finalization merge path runs only on `stopAfterValidation: false` clean stops; if the playtest exits abnormally (the `_ready` crash itself terminates the run before the coordinator's deferred path runs), the late-arriving error records never make it into the JSONL. The playtest is exiting in **2–3 seconds** even with `stopAfterValidation: false`, suggesting the crash itself terminates the run, not the validation gate. The fix needs to capture errors that fire *during* `_ready` and write them before the runtime exits — the error-record write needs to happen synchronously inside the runtime's pause-on-error handler, not via post-hoc merge.

**Fix**: Re-open [06b](06b-runtime-semantic-correctness.md). Investigation should focus on the runtime-side write path in `scenegraph_runtime.gd`'s pause-on-error handler — specifically whether the JSONL is opened/flushed before `_ready` runs, and whether the playtest's abnormal exit truncates an in-flight write. Pester unit tests around `Get-RunbookRuntimeErrorOutcome` validate the *projection* contract but cannot exercise the live runtime write path; the regression check has to be a live editor run against an injected `_ready` deref (i.e. exactly the matrix-row 6c test plan).

**How to verify**: Re-run the reproduction above; expect `status=failure`, `failureKind=runtime`, `latestErrorSummary={file:"res://scripts/error_main.gd", line:5, message:"<null deref message>"}`, and a JSONL with at least one record.

---

### B17 — Runtime errors raised in `_process` (or any post-`_ready` lifecycle) not captured

**Where**: same surfaces as B10. Sibling defect — same root cause family but a different lifecycle slot.

**Reproduction**:
```powershell
# runtime-error-loop ships error_on_frame.gd which fires a null deref in _process on the first frame.
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/runtime-error-loop

# Inline payload overriding targetScene (run-and-watch-for-errors.json defaults to res://scenes/main.tscn which doesn't exist here):
$payload = '{"requestId":"placeholder","scenarioId":"runbook-runtime-error-triage","runId":"runbook-runtime-error-triage","targetScene":"res://scenes/error_on_frame.tscn","outputDirectory":"res://evidence/automation/$REQUEST_ID","capturePolicy":{"startup":true,"manual":true,"failure":true},"stopPolicy":{"stopAfterValidation":false},"requestedBy":"agent","createdAt":"2026-04-26T15:25:00Z"}'
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
JSONL is 0 bytes; scenegraph snapshot shows trigger=`startup`, frame=0, run completed in ~3s with `stopAfterValidation: false`. The `_process` error never fires because the playtest exits before the first frame is ticked.

**Symptom**: Same shape as B10 — silent data loss. Any scene whose runtime error fires in `_process`, `_physics_process`, signal handlers, deferred calls, or post-startup `await` paths is invisible to the harness. Pass-6b's claim that "runtime errors raised during a scene's `_ready()` are now captured" did not generalize to other lifecycle slots, and even `_ready` is still broken (B10).

**Fix**: The pause-on-error harness needs to keep the playtest alive long enough for at least one `_process` tick after attach, OR the runtime needs a "minimum frame budget" knob (the pass-6c test plan note for B10 mentions `frameLimit: 600` as a workaround). At minimum, the workflow should refuse to claim `success` when the playtest exited in <30 frames without ever reaching the user's scene-level `_process` code.

**How to verify**: Same reproduction; expect `status=failure`, `latestErrorSummary={file:"res://scenes/error_on_frame.gd", line:20, message:"…"}`.

---

### B18 — Playtest leaks across runs when `stopAfterValidation: false`; subsequent invocations get blocked

**Where**: [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) (broker-side cleanup).

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
# Returns status=success in ~3s. But check: a Godot playtest child process is still alive.
Get-Process godot* | Select-Object Id, StartTime
# id 14420 alive, started at the same second the previous run completed.

pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
```

**Observed (run-result.json from the *next* invocation)**:
```json
{ "blockedReasons": ["scene_already_running"],
  "finalStatus": "blocked",
  "manifestPath": null }
```

**Symptom**: After a "clean" runtime-error-triage run with `stopAfterValidation: false`, the playtest process is *not* terminated by the broker. The broker-side `terminationStatus` reports `running` even after `completedAt` is written (see Test 6c's `run-result.json` output: `terminationStatus: "running"` co-existing with `finalStatus: "completed"` and a `completedAt` timestamp — internally inconsistent state). Subsequent calls hit the broker's `scene_already_running` guard and refuse to dispatch. `invoke-stop-editor.ps1` correctly tree-kills the orphan (F3 works), but agents won't know to call it.

**Fix**: When the runtime-error-triage workflow finalizes (writes `completedAt`/`finalStatus=completed`), the broker must also signal the playtest to exit (or kill it directly) and wait for `terminationStatus` to flip to `stopped` before releasing the scene-running guard. Reconcile the contradictory `terminationStatus="running"` + `finalStatus="completed"` shape — those should never coexist.

**How to verify**: Re-run the reproduction; after the first invocation, `Get-Process godot*` should show only the editor; the second invocation should succeed instead of blocking.

---

### B19 — Orchestration scripts crash with `PropertyNotFoundException` on the blocked-status path under StrictMode

**Where**: [tools/automation/invoke-scene-inspection.ps1:237](../tools/automation/invoke-scene-inspection.ps1#L237) and the parallel branch in every other invoke script that handles `finalStatus="blocked"` (likely all of `invoke-input-dispatch.ps1`, `invoke-runtime-error-triage.ps1`, `invoke-build-error-triage.ps1`, `invoke-behavior-watch.ps1`).

**Reproduction**:
```powershell
# Trigger any blocked outcome (e.g. via B18 above), then call any runtime-verification invoke script:
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
```

**Observed**:
```
invoke-scene-inspection.ps1: The property 'Count' cannot be found on this object. Verify that the property exists.
```
Full stack:
```
PropertyNotFoundException: PropertyNotFoundStrict
ScriptStackTrace: at <ScriptBlock>, …\invoke-scene-inspection.ps1: line 237
```

The relevant code:
```powershell
# line 235-239
if ($rr.finalStatus -eq 'blocked') {
    $reasons    = if ($null -ne $rr.blockedReasons) { @($rr.blockedReasons | ForEach-Object { [string]$_ }) } else { @() }
    $reasonList = if ($reasons.Count -gt 0) { $reasons -join ', ' } else { 'unknown' }
    …
}
```

The `if`-as-expression assignment unwraps the single-element array `@("scene_already_running")` to the bare string under StrictMode + PowerShell's pipeline-unwrap rules; `[string].Count` then throws `PropertyNotFoundStrict`. **No JSON envelope is emitted** — the script exits with the raw PS error on stderr.

**Symptom**: Critical contract break. Agents driving the harness through the documented stdout-envelope protocol get an *unparseable* stderr blurb instead of the expected `{"status":"failure","failureKind":"runtime","diagnostics":["scene_already_running …"]}`. There's nothing in the envelope schema or RUNBOOK.md that prepares an agent for "the script may exit with a raw PowerShell exception." Combined with B18, this is the user-facing failure mode after any runtime-error-triage run with `stopAfterValidation: false`.

**Fix**: Force array shape with the comma operator so the unwrap can't happen:
```powershell
$reasons = if ($null -ne $rr.blockedReasons) { ,@($rr.blockedReasons | ForEach-Object { [string]$_ }) } else { ,@() }
```
Or use `($reasons | Measure-Object).Count` instead of `.Count`. The former is the same shape fix used for B11 (`,@($pins)`).

Audit every invoke script for the same pattern. Add a Pester case that constructs a synthetic `run-result.json` with `finalStatus=blocked, blockedReasons=["x"]` and asserts each invoke script emits a valid envelope (not a raw PS exception) and exits 1.

**How to verify**: Repro the blocked state (kill capability.json mid-run, or trigger B18); script should emit `{"status":"failure","failureKind":"runtime","diagnostics":["Run was blocked before evidence was captured. blockedReasons: scene_already_running. …"]}` and exit 1, instead of a stderr stack trace.

---

## Summary

**Critical (workflow broken)**: **B10, B17, B19**.
- **B10** — runtime-error triage still silently masks `_ready`-time null derefs; the load-bearing pass-6b fix landed at the manifest/projection layer but did not address the live runtime write path. **Highest priority** — this workflow is what agents call when triaging crashes, and it lies on the most common shape of crash.
- **B17** — same data loss in `_process` (and presumably every other lifecycle slot). Sibling of B10; same fix surface.
- **B19** — orchestration crashes with raw PowerShell exception on the blocked-status path, breaking the envelope contract. Agents get an unparseable error instead of the documented `failureKind=runtime` envelope. Trivial fix (force array shape), broad blast radius (likely affects all five runtime-verification invoke scripts).

**Significant (misleading semantics)**: **B18**. After `stopAfterValidation: false` runtime-error-triage runs, the playtest leaks; the next workflow invocation gets `scene_already_running` blocked, and the broker reports an internally-contradictory `terminationStatus="running"` + `finalStatus="completed"` shape. Combined with B19, the user-facing UX is "next call mysteriously crashes." `invoke-stop-editor.ps1` works around it but agents don't know to call it.

**Minor**: none new this pass.

**Verified pass-6 fixes**:
- **6a — Outcome shape cleanup**: B14 ✅ (no vestigial `dispatchedEventCount`), B15 ✅ (flat `warnings` array). B16 not specifically retested — no validation-failure path naturally surfaced in this pass.
- **6b — Runtime semantic correctness**: B8 ✅ (request fields win over `inspection-run-config.json` — manifest's runId/scenarioId/outputDirectory all match the request, not the config). **B10 ❌ NOT fixed** in the live editor — see issue above.
- **6c — Editor lifecycle hardening**: B13 ✅ (`-EnsureEditor` cold-start completes in 8s, no hang), F3 ✅ (single `invoke-stop-editor` call kills editor + orphan playtest in one tree-walk). F2 not specifically retested — no `scene_already_running` was deliberately induced via the F2-target path; B19 short-circuits the diagnostic the F2 fix added.

**Tool-call ergonomics**: most workflows hit the 2-call ideal (skill + invoke). Test 6b cost 4 calls because the inline-override case still requires a temp payload file (the bash/PowerShell single-quote interaction is unchanged from pass 6). The orchestration crash in B19 ate roughly 5 investigation calls before the root cause became clear — the lack of a structured envelope is exactly the friction the runbook contract was supposed to prevent.

**Suggested next pass**: split into two batches.

- **[07a — Runtime capture correctness (B10 + B17)](07a-runtime-capture-correctness.md)** *(new)*: re-open 06b. The fix needs to land at the runtime-side write path (`scenegraph_runtime.gd` pause-on-error handler), not just the orchestrator projection. **Verification gate must be a live-editor regression test** against both `_ready` and `_process` injected derefs — Pester alone passed last time and the bug shipped. Highest priority — this is the workflow agents trust most.
- **[07b — Blocked-path hardening (B18 + B19)](07b-blocked-path-hardening.md)** *(new)*: B19 is a one-character fix per script (force array shape with comma operator) plus a Pester case per script. B18 needs broker-side cleanup of the playtest after `stopAfterValidation: false` clean stops, plus reconciling the `terminationStatus="running"` + `finalStatus="completed"` contradiction. Land B19 first — it's a contract violation that hides every other blocked-state defect (including B18's symptom). Once B19 is fixed, B18 will surface as a clean envelope and triage will be straightforward.

If schedule pressure forces a single batch, prioritize **B19 → B10 → B17 → B18** by visibility-of-failure: an unparseable script crash is worse than silent data loss is worse than orphan-process leakage. B19 is the cheapest fix and unblocks every observation downstream.
