# Pass 8 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md), [pass 5](05-test-pass-results.md), [pass 6](06-test-pass-results.md) (split into [6a](06a-outcome-shape-cleanup.md), [6b](06b-runtime-semantic-correctness.md), [6c](06c-editor-lifecycle-hardening.md)), and [pass 7](07-test-pass-results.md) (whose four findings — B10, B17, B18, B19 — were bundled into [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39)), this pass re-runs the full matrix against a real Godot editor (`Godot_v4.6.2-stable_win64`) and a real Godot project to confirm the PR #39 bundle landed cleanly and to surface any regressions or new defects.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox, restored to default Control + Label between mutating tests) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures).
- **Editor instances**: launched via `tools/automation/invoke-launch-editor.ps1`. Both probe and runtime-error-loop editors were active concurrently during 6b.
- **Fixtures**: shipping fixtures under `tools/tests/fixtures/runbook/<workflow>/` plus a synthesized inline payload (loaded from a temp file under `runtime-error-loop/harness/test.json`) for the 6b override case.
- **Failure-path coverage**: where a workflow has both clean and failure paths (build-error triage, runtime-error triage, pin/unpin), both were exercised — including injecting deliberate compile and runtime errors into probe and reverting after. Refusal paths for pin (collision + invalid name) were also exercised.

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Stderr heartbeats (`spawned Godot PID …`, `editor ready …`) alongside pure JSON stdout. Capability ready in 5s. |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | nodeCount=2, no doubled prefix. |
| 3 | Input dispatch | `/godot-press` | probe | 2 | ⚠️ partial | Envelope correctly reports `status=failure`, `failureKind=runtime`, `actualDispatchedCount=0`, `firstFailureSummary='Run ended before the requested frame was reached.'` Behavior unchanged from pass 7: probe ends before frame 30 in the press-enter fixture, so no events dispatch. The press-enter+probe combo is still a fixture/sandbox mismatch (longstanding), not a regression — envelope honesty is correct. |
| 4 | Behavior watch | `/godot-watch` | probe | 2 | ✅ pass | `warnings` is a flat `["target node not found …"]` array; `status=success`, `sampleCount=0`, `samplesPath=null` when target missing. B15 fix still in place. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | `outcome.runResultPath` exposed; `firstDiagnostic` null. |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | 3 | ✅ pass | `failureKind=build`, `firstDiagnostic={file:res://scripts/broken.gd, line:3, column:1, message:'Unexpected "Indent" in class body.'}`. Verbatim parser message. Exit 1. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | Clean smoke fixture. `latestErrorSummary=null`, `terminationReason=completed`, `runtimeErrorRecordsPath` populated (empty JSONL referenced as artifact). |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | 4 | ❌ broken | **B8 still fixed** — manifest's `runId=runbook-runtime-error-triage` matches request, not config's `runtime-error-loop-run-01`. **B17 STILL PRESENT** — runtime-error in `error_on_frame.gd:_process` (line 20) is **not captured**. JSONL is 0 bytes, `latestErrorSummary=null`, `status=success`. Snapshot shows trigger=`startup`, frame=0, run completed in ~3s. **B18 STILL PRESENT** — leaked playtest PID 25456 stayed alive after the run; subsequent invocations got `scene_already_running`. |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | 3 | ❌ broken | **B10 STILL PRESENT.** Tested with both `run-and-watch-for-errors.json` (stopAfterValidation=true) and `run-and-watch-for-errors-no-early-stop.json` (stopAfterValidation=false). Both: `status=success`, `terminationReason=completed`, `latestErrorSummary=null`, `runtime-error-records.jsonl` is 0 bytes. **B18 also still present** — the no-early-stop variant leaked playtest PID 12460. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | 8-file pin (manifest + 4 scenegraph artifacts + run-result + lifecycle-status + pin-metadata). Refusal paths verified: `pin-name-collision` and `pin-name-invalid` both `status="refused"`. |
| 8 | List pinned (1 pin / 2 pins) | `/godot-pins` | probe | 4 | ✅ pass | `pinnedRunIndex` is a JSON array in both 1-pin and 2-pin states. `scenarioId` values are `runbook-scene-inspection-scenario` / `runbook-runtime-error-triage-scenario` (no doubled prefix). |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | 2 | ✅ pass | Success: `plannedPaths` lists 8 deletions. Refusal: `status=refused`, `failureKind=pin-target-not-found`, exit 0. |
| 10 | Stop editor | — | probe | 1 | ✅ pass | Active stop returns `stoppedPids:[<pid>]`; idempotent re-call returns `noopReason="no-matching-editor"`. **F3 verified again** — the 6b cleanup `invoke-stop-editor` killed both runtime-error-loop's editor (2392) and the leaked playtest (25456) in one call. |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe (cold-start) | 1 | ✅ pass | End-to-end cold-start scene-inspection completed in **8.9s** wallclock: `[invoke-launch-editor] spawned Godot PID 47580` → `editor ready (capability.json mtime 0s ago); dispatching workflow` → workflow envelope (`status=success`, `nodeCount=2`). No hang. |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 13 distinct workflows / paths exercised. **10 passed clean**, **1 partial**, **2 broken**. Pass-7-via-PR-#39 verified fixes: **B19** ✅. Pass-7-via-PR-#39 claimed-but-still-broken: **B10 ❌, B17 ❌, B18 ❌** — three of the four bundled defects regressed despite the merge.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction). Pass 7 ended at B19; no new IDs are needed this pass — every observed failure is a regression of a Pass-7 issue that PR #39 claimed to address.

### B10 — Runtime errors in `_ready` still not captured (regression of [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39)'s claimed fix)

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
# Edit scenes/main.tscn so Main has script = ExtResource("res://scripts/error_main.gd").

pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
# Both fixtures behave the same:
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
```

**Observed** (both fixtures, manifest IDs vary):
```json
{ "status": "success",
  "failureKind": null,
  "outcome": {
    "terminationReason": "completed",
    "latestErrorSummary": null,
    "runtimeErrorRecordsPath": "…/runtime-error-records.jsonl"
  } }
```
The referenced JSONL is **0 bytes** in both runs. The manifest still emits the `runtime-error-records` artifactRef and `runtimeErrorReporting.pauseOnErrorMode="active"`, but the runtime side never writes any error rows.

**Symptom**: Runtime-error triage is the workflow agents reach for first when triaging crashes. On a real `_ready`-time null deref it lies — reports clean. PR #39 ("fix: Pass 7 bundled defects (B10, B17, B18, B19)", commit [0afd615](https://github.com/RJAudas/godot-agent-harness/commit/0afd615)) was titled to address this exact case but the fix did not land — the live repro is unchanged from pass 7.

**Hypothesis** (unchanged from pass 7): The deferred-finalization merge path runs only on `stopAfterValidation: false` clean stops; if the playtest exits abnormally (the `_ready` crash itself terminates the run before the coordinator's deferred path runs), the late-arriving error records never make it into the JSONL. Even with `stopAfterValidation: false`, the playtest is exiting in ~3s — the crash itself terminates the run, not the validation gate. The fix needs to capture errors that fire *during* `_ready` and write them before the runtime exits — the error-record write needs to happen synchronously inside the runtime's pause-on-error handler, not via post-hoc merge.

**Fix**: Re-open the targeted fix from PR #39. Investigation should focus on the runtime-side write path in `scenegraph_runtime.gd`'s pause-on-error handler — specifically whether the JSONL is opened/flushed before `_ready` runs, and whether the playtest's abnormal exit truncates an in-flight write. Pester unit tests around `Get-RunbookRuntimeErrorOutcome` validate the *projection* contract but cannot exercise the live runtime write path; **the regression check has to be a live editor run against an injected `_ready` deref** (i.e. exactly this row's test plan). PR #39 evidently shipped without this regression gate.

**How to verify**: Re-run the reproduction above; expect `status=failure`, `failureKind=runtime`, `latestErrorSummary={file:"res://scripts/error_main.gd", line:5, message:"<null deref message>"}`, and a JSONL with at least one record.

---

### B17 — Runtime errors in `_process` still not captured (regression of PR #39's claimed fix)

**Where**: same surfaces as B10. Sibling defect — same root cause family but a different lifecycle slot.

**Reproduction**:
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
JSONL is 0 bytes. `scenegraph-snapshot.json` shows `trigger.trigger_type="startup"`, `trigger.frame=0`, run completed in ~3s. The `_process` error never fires because the playtest exits before the first frame is ticked — same as pass 7.

**Symptom**: Same shape as B10 — silent data loss. Any scene whose runtime error fires in `_process`, `_physics_process`, signal handlers, deferred calls, or post-startup `await` paths is invisible to the harness. PR #39's title claimed B17 was fixed; the live repro is unchanged from pass 7.

**Fix**: The pause-on-error harness needs to keep the playtest alive long enough for at least one `_process` tick after attach, OR the runtime needs a "minimum frame budget" knob. At minimum, the workflow should refuse to claim `success` when the playtest exited in <30 frames without ever reaching the user's scene-level `_process` code.

**How to verify**: Same reproduction; expect `status=failure`, `latestErrorSummary={file:"res://scenes/error_on_frame.gd", line:20, message:"…"}`.

---

### B18 — Playtest still leaks across runs when `stopAfterValidation: false` (regression of PR #39's claimed fix)

**Where**: [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) (broker-side cleanup).

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
# Returns status=success in ~3s. Now check the process tree:
Get-Process godot* | Select-Object Id, StartTime
```

**Observed**: Two godot.exe processes alive — the editor (53420) and a playtest (12460) that started 35 seconds *after* the editor and is still running. The next workflow invocation is then blocked:

```json
{ "status": "failure",
  "failureKind": "runtime",
  "diagnostics": [
    "Run was blocked before evidence was captured. blockedReasons: scene_already_running. A previous playtest is still running. Restart the editor: invoke-stop-editor.ps1 then invoke-launch-editor.ps1."
  ] }
```

The same leak was reproduced independently in 6b: PID 25456 leaked after a `stopAfterValidation:false` runtime-error-triage on `runtime-error-loop`, and a follow-up scene-inspection on the same project blocked with `scene_already_running`.

**Symptom**: After a "clean" runtime-error-triage run with `stopAfterValidation: false`, the playtest process is *not* terminated by the broker. PR #39's title claimed B18 was fixed; the leak still happens. The workaround (call `invoke-stop-editor.ps1`) still works, and the F3 tree-kill correctly cleans up both editor + leaked playtest in one shot — but agents won't know to call it because the previous run reported `status=success`.

**Note** — this defect now manifests as a *correct, actionable* envelope on the *next* invocation thanks to **B19's fix** (see below). The pass-7 user-facing failure mode ("orchestration script crashes with a raw PowerShell exception") is gone; agents now get a clean `failureKind=runtime` envelope with a hint to restart the editor. That's a meaningful improvement even though the underlying leak remains.

**Fix**: When the runtime-error-triage workflow finalizes (writes `completedAt`/`finalStatus=completed`), the broker must also signal the playtest to exit (or kill it directly) and wait for `terminationStatus` to flip to `stopped` before releasing the scene-running guard.

**How to verify**: Re-run the reproduction; after the first invocation, `Get-Process godot*` should show only the editor; the second invocation should succeed instead of blocking.

---

### B19 — Orchestration scripts no longer crash on the blocked-status path ✅ FIXED

**Where**: [tools/automation/invoke-scene-inspection.ps1](../tools/automation/invoke-scene-inspection.ps1) and parallel branches in every other invoke script.

**Reproduction (verified live)**:
```powershell
# Trigger blocked outcome by reproducing B18, then call any runtime-verification invoke script:
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/runtime-error-loop `
    -RequestFixturePath ./integration-testing/runtime-error-loop/harness/test.json   # leaks playtest
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/runtime-error-loop
```

**Observed (clean envelope, exit 1, no PowerShell stack trace)**:
```json
{ "status": "failure",
  "failureKind": "runtime",
  "manifestPath": null,
  "runId": "runbook-scene-inspection-20260426T173836Z-12c244",
  "requestId": "runbook-scene-inspection-20260426T173836Z-12c244",
  "completedAt": "2026-04-26T17:38:37.388Z",
  "diagnostics": [
    "Run was blocked before evidence was captured. blockedReasons: scene_already_running. A previous playtest is still running. Restart the editor: invoke-stop-editor.ps1 then invoke-launch-editor.ps1."
  ],
  "outcome": { "sceneTreePath": null, "nodeCount": 0 } }
```

The diagnostic now carries an actionable hint ("Restart the editor: …") in the same blocked-state envelope — that's a bonus over what pass 7 expected. Exit code is 1, contract-correct. **No PowerShell `PropertyNotFoundException` on stderr.**

**Status**: ✅ Verified fixed by PR #39. This was the only one of the four bundled defects that actually shipped a working fix in that PR. Worth noting because the unparseable-stack-trace failure mode it removes is what made B18 catastrophic in pass 7; with B19 fixed, B18 is now a recoverable inconvenience instead of a contract violation.

---

## Summary

**Critical (workflow broken)**: **B10, B17**.
- **B10** — runtime-error triage still silently masks `_ready`-time null derefs. PR #39 was titled to fix this and did not. **Highest priority for pass 9** — this is the workflow agents call when triaging crashes, and it lies on the most common shape of crash.
- **B17** — same data loss in `_process` (and presumably every other lifecycle slot). Sibling of B10; same fix surface; same PR-#39 regression.

**Significant (misleading semantics)**: **B18**. Playtest leaks after `stopAfterValidation: false` clean stops; the next workflow invocation gets `scene_already_running` blocked. Severity downgraded from pass 7's "Significant + cascading-Critical-via-B19" to "Significant only" because **B19's fix means agents now get a clean diagnostic envelope** with a clear restart-editor hint instead of an unparseable stack trace. Still real data loss / friction, still needs the broker-side cleanup, but no longer breaks the contract.

**Minor**: none new this pass.

**Verified pass-7 / PR-#39 fixes**:
- **B19** ✅ verified live — blocked-status envelope is valid JSON with actionable diagnostic, exits 1.

**Pass-7 / PR-#39 claimed-but-still-broken**:
- **B10** ❌ — same live repro as pass 7. PR title misleading.
- **B17** ❌ — same live repro as pass 7. PR title misleading.
- **B18** ❌ — same leak still occurs after both 6b and 6c with `stopAfterValidation:false`. PR title misleading.

**Verified earlier-pass fixes still in place**:
- **B8** ✅ (pass 6b) — request fields override `inspection-run-config.json` (manifest's `runId=runbook-runtime-error-triage`, not `runtime-error-loop-run-01`).
- **B11** ✅ (pass 5) — `pinnedRunIndex` is a JSON array in both the 1-pin and 2-pin cases.
- **B13** ✅ (pass 6c) — `-EnsureEditor` cold-start completes in 8.9s wallclock, no hang.
- **B14** ✅ (pass 6a) — no vestigial `dispatchedEventCount` field on the input-dispatch envelope.
- **B15** ✅ (pass 6a) — `warnings` is a flat array on behavior-watch.
- **F3** ✅ (pass 6c) — single `invoke-stop-editor` call kills editor + orphan playtest in one tree-walk (verified by 6b cleanup killing PIDs 2392 + 25456 in one call).

**Tool-call ergonomics**: 10 of 13 workflows hit the 2-call ideal. Test 6b cost 4 calls because the inline-override case still requires a temp payload file. Test 5b cost 3 (Write broken script + scene edit + invoke), unchanged from pass 7.

**Suggested next pass**: split into two narrowly-scoped batches.

- **[09a — Runtime capture correctness, take 2 (B10 + B17)](09a-runtime-capture-correctness.md)** *(new)*: redo the PR #39 attempt. The fix must land at the runtime-side write path (`scenegraph_runtime.gd` pause-on-error handler), not just the orchestrator projection. **The verification gate must be a live-editor regression test** against both `_ready` and `_process` injected derefs — Pester unit tests passed last time and PR #39 still shipped without a working fix. Add the live-editor regression to CI or to a pre-merge check.
- **[09b — Playtest cleanup on `stopAfterValidation:false` (B18)](09b-playtest-cleanup.md)** *(new)*: broker-side cleanup of the playtest after clean stops, plus reconciling any remaining `terminationStatus="running"` + `finalStatus="completed"` contradiction. Lower priority than 09a now that B19 is fixed and the failure mode is a clean envelope agents can interpret.

If schedule pressure forces a single batch, prioritize **B10 → B17 → B18**. B10 and B17 are silent data loss on the most-used workflow; B18 is recoverable friction now that B19 is fixed.

A meta-recommendation for whoever drives 09a/09b: **PR #39's title overpromised vs. what landed**. Three of four defects in the bundled commit message did not actually ship. The one that did (B19) is real and valuable. Future bundled "fix N defects" PRs should verify each defect via the matching live-editor row in this template *before* the merge — a passing Pester suite is necessary but not sufficient for runtime-capture work.
