# Pass 9 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md), [pass 5](05-test-pass-results.md), [pass 6](06-test-pass-results.md) (split into [6a](06a-outcome-shape-cleanup.md), [6b](06b-runtime-semantic-correctness.md), [6c](06c-editor-lifecycle-hardening.md)), [pass 7](07-test-pass-results.md), and [pass 8](08-test-pass-results.md) (whose three load-bearing defects — B10, B17, B18 — were addressed in three separate PRs: [#40](https://github.com/RJAudas/godot-agent-harness/pull/40) for [8a](08a-ready-runtime-capture.md), [#41](https://github.com/RJAudas/godot-agent-harness/pull/41) for [8b](08b-process-runtime-capture.md), [#42](https://github.com/RJAudas/godot-agent-harness/pull/42) for [8c](08c-playtest-cleanup.md)), this pass re-runs the full matrix against a real Godot editor (`Godot_v4.6.2-stable_win64`) and a real Godot project to confirm the three pass-8 PRs landed cleanly and to surface any regressions or new defects.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox, restored to default Control + Label between mutating tests) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures, multi-scene).
- **Editor instances**: launched via [tools/automation/invoke-launch-editor.ps1](../tools/automation/invoke-launch-editor.ps1). Both probe and runtime-error-loop editors were active concurrently during 6b.
- **Fixtures**: shipping fixtures under [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/) plus a synthesized inline payload (loaded from a temp file under `runtime-error-loop/harness/test.json`) for the 6b override case. 6c was exercised against both `run-and-watch-for-errors.json` (`stopAfterValidation:true`) and `run-and-watch-for-errors-no-early-stop.json` (`stopAfterValidation:false`).
- **Failure-path coverage**: where a workflow has both clean and failure paths (build-error triage, runtime-error triage, pin/unpin), both were exercised — including injecting deliberate compile and runtime errors into probe and reverting after. Refusal paths for pin (collision + invalid name) were also exercised.

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Stderr heartbeats (`spawned Godot PID …`, `editor ready …`) alongside pure JSON stdout. Capability ready in 5s. |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | nodeCount=2, no doubled prefix. |
| 3 | Input dispatch | `/godot-press` | probe | 2 | ⚠️ partial | Same fixture/sandbox mismatch as passes 7–8: probe ends before frame 30, so press-enter's events skip with `status=skipped_frame_unreached`. Envelope reports `status=failure`, `failureKind=runtime`, `actualDispatchedCount=0`, `firstFailureSummary='Run ended before the requested frame was reached.'` JSONL rows match envelope. Envelope honesty correct; longstanding fixture mismatch. |
| 4 | Behavior watch | `/godot-watch` | probe | 2 | ✅ pass | `warnings=["target node not found …"]` flat array; `status=success`, `sampleCount=0`, `samplesPath=null` when target missing. B15 still fixed. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | `outcome.runResultPath` exposed; `firstDiagnostic` null. |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | 3 | ✅ pass | `failureKind=build`, `firstDiagnostic={file:res://scripts/broken.gd, line:3, column:1, message:'Unexpected "Indent" in class body.'}`. Verbatim parser message. Exit 1. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | Clean smoke fixture. `latestErrorSummary=null`, `terminationReason=completed`, `runtimeErrorRecordsPath` populated (empty JSONL referenced as artifact). |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | 4 | ✅ pass | **B17 ✅ fixed by PR #41** — `error_on_frame.gd:_process` (line 20) null deref captured: `latestErrorSummary={file:"res://scripts/error_on_frame.gd", line:20, message:"Cannot call method 'get_name' on a null value."}`, `failureKind=runtime`, `status=failure`. **B18 ✅ fixed by PR #42** — `Get-Process godot*` after the run shows only the editor (29088); no leaked playtest. JSONL has 1 record with `function="_trigger_error"`. **B8 ✅ still fixed** — manifest's `runId="runbook-runtime-error-triage"` matches the request, not the config's `"runtime-error-loop-run-01"`. Side finding: see [B20](#b20--scene-inspection-misclassifies-clean-early-quit-as-crash--gameplay-failurekind) and [B21](#b21--orchestrator-leaves-broker-failurekind-string-in-diagnostic-message-after-mapping-it). |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | 3 | ✅ pass | **B10 ✅ fixed by PR #40** — both fixtures now capture: `stopAfterValidation:true` → `latestErrorSummary={file:"res://scripts/error_main.gd", line:4, message:"Cannot call method 'get_name' on a null value."}`, `failureKind=runtime`, `status=failure`, JSONL with 1 record (`function="_ready"`). `stopAfterValidation:false` → identical capture. **B18 ✅ fixed for both variants** — process check after each run shows only the editor (41104); no leaked playtest. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | 8-file pin (manifest + 4 scenegraph artifacts + run-result + lifecycle-status + pin-metadata). Refusal paths verified: `pin-name-collision` and `pin-name-invalid` both `status="refused"`, exit 0. |
| 8 | List pinned (1 pin / 2 pins) | `/godot-pins` | probe | 4 | ✅ pass | `pinnedRunIndex` is a JSON array in both 1-pin and 2-pin states. `scenarioId` values are `runbook-runtime-error-triage-scenario` / `runbook-scene-inspection-scenario` (no doubled prefix). B11 still fixed. |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | 2 | ✅ pass | Success: `plannedPaths` lists 8 deletions, exit 0. Refusal: `status=refused`, `failureKind=pin-target-not-found`, exit 0. |
| 10 | Stop editor | — | probe | 1 | ✅ pass | Active stop returns `stoppedPids:[<pid>]`; idempotent re-call returns `noopReason="no-matching-editor"`. |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe (cold-start) | 1 | ✅ pass | End-to-end cold-start scene-inspection completed in **10s** wallclock: spawned editor PID 45564 → `editor ready (capability.json mtime 0s ago); dispatching workflow` → `status=success`, `nodeCount=2`. No hang. B13 still fixed. |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 13 distinct workflows / paths exercised. **12 passed clean**, **1 partial** (longstanding fixture mismatch, not a regression), **0 broken**. **All three pass-8 PRs (#40, #41, #42) verified live**: B10 ✅, B17 ✅, B18 ✅. Two new defects surfaced during 6b's cleanup investigation: **B20** (scene-inspection misclassifies clean early-quit as crash) and **B21** (envelope/diagnostic `failureKind` mismatch).

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction). Pass 8 ended at B19; this pass adds B20 and B21.

### B20 — Scene-inspection misclassifies clean early-quit as crash / `gameplay` failureKind

**Where**: orchestrator projection layer for [tools/automation/invoke-scene-inspection.ps1](../tools/automation/invoke-scene-inspection.ps1) and broker-side run finalization (`finalStatus="failed"`, `terminationStatus="crashed"`, `failureKind="gameplay"` in run-result.json). Most likely the broker's "gameplay" branch in [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) or the validator's "scenegraph bundle never written" handling.

**Reproduction** (against runtime-error-loop, whose `run/main_scene = res://scenes/no_errors.tscn` is a fixture script that calls `get_tree().quit()` in `_ready`):

```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/runtime-error-loop
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/runtime-error-loop
```

**Observed** (envelope on stdout):
```json
{
  "status": "failure",
  "failureKind": "runtime",
  "manifestPath": null,
  "diagnostics": [ "Run failed with failureKind='gameplay'." ],
  "outcome": { "sceneTreePath": null, "nodeCount": 0 }
}
```

`harness/automation/results/run-result.json`:
```json
{
  "completedAt": "2026-04-26T23:36:50Z",
  "failureKind": "gameplay",
  "finalStatus": "failed",
  "terminationStatus": "crashed",
  "validationResult": {
    "bundleValid": false,
    "manifestExists": false,
    "notes": [
      "Validation has not completed yet.",
      "runtime_error_records: none_observed",
      "The play session ended abnormally before a scenegraph bundle was persisted."
    ]
  }
}
```

The scene actually exited cleanly via `get_tree().quit()` — there was no crash, no error, no exception. The editor's stderr log only shows Vulkan loader warnings; nothing indicates an abnormal exit. The harness conflates "playtest exited before the scenegraph snapshot was written" with "playtest crashed."

**Symptom**: Any project whose main scene (a) finishes its work in `_ready`, (b) calls `get_tree().quit()` in early autoload setup, (c) has a `--scene` override that exits before frame 1, will be reported as having `status=failure`, `terminationStatus=crashed`, `failureKind=gameplay/runtime` even though no error occurred. Agents using `/godot-inspect` on such a project get a misleading "the game crashed" report instead of an actionable "the scene exited before scenegraph capture; either inspect a different scene or add a frame budget" message. This is *not* a regression of any prior pass — it's been latent since scene-inspection shipped, but no prior pass exercised the failure path on a project that exits in `_ready`.

**Fix**: Differentiate "playtest exited before producing artifacts" from "playtest crashed" in the broker. The broker has the playtest's exit code; a clean `OS.get_exit_code() == 0` should yield `terminationStatus="completed"` and `failureKind="validation"` (or a new `"scene_exited_before_capture"`), with a diagnostic that tells the agent the scene quit before frame N. The orchestrator's outcome projection should then surface `outcome.sceneTreePath=null` with a hint such as `"The scene called get_tree().quit() before scenegraph capture. Either inspect a non-quitting scene or pass -frameLimit ≥ 1."`. Bonus: add a smoke test fixture that targets a `get_tree().quit()`-in-`_ready` scene so this regression is caught automatically.

**How to verify**: After the fix, the reproduction should yield either `status=success` with a diagnostic explaining the empty capture, or `status=failure` with `failureKind="validation"` and a non-`crashed` termination status. The diagnostic should explicitly mention `quit()` / "scene ended before frame 1" rather than the generic "Run failed with failureKind='gameplay'."

---

### B21 — Orchestrator leaves broker `failureKind` string in diagnostic message after mapping it

**Where**: [tools/automation/lib/orchestration-stdout.ps1](../tools/automation/lib/orchestration-stdout.ps1) (or the projection helper used by `invoke-scene-inspection.ps1` and friends).

**Reproduction**: same as B20. The envelope's `failureKind` is `"runtime"` but the embedded diagnostic message is the literal string `"Run failed with failureKind='gameplay'."` — a verbatim quote of the broker's classification.

**Observed**:
```json
{
  "failureKind": "runtime",
  "diagnostics": [ "Run failed with failureKind='gameplay'." ]
}
```

**Symptom**: An agent that reads the envelope sees one classification (`"runtime"`); an agent that reads the diagnostic sees a different one (`"gameplay"`). Schema-level field and human-level message disagree. This violates the principle in [specs/008-agent-runbook/contracts/orchestration-stdout.schema.json](../specs/008-agent-runbook/contracts/orchestration-stdout.schema.json) that the envelope and diagnostics describe the same outcome. It also makes the failureKind taxonomy harder to reason about — agents may build heuristics around the diagnostic text expecting it to match the envelope field.

**Fix**: The orchestrator either (a) emits the same value in both places (e.g., diagnostic should say `"Run failed with failureKind='runtime'."` if it intends to map "gameplay"→"runtime"), or (b) stops mapping and uses the broker's value verbatim in both places, or (c) drops the failureKind from the diagnostic text entirely and relies on the envelope field. Option (c) is cleanest: the diagnostic should describe what *happened* (e.g., "The play session ended abnormally before a scenegraph bundle was persisted.") rather than restate the classification.

**How to verify**: Re-run the reproduction; the envelope's `failureKind` and any failureKind reference inside `diagnostics[]` must be identical (or the diagnostic must avoid mentioning failureKind altogether).

---

## Summary

**Critical (workflow broken)**: none. Pass 8's three load-bearing defects (B10, B17, B18) all verified fixed by their respective PRs (#40, #41, #42). The runtime-error-triage workflow now correctly captures `_ready`-time and `_process`-time errors and cleans up the playtest after `stopAfterValidation:false` runs.

**Significant (misleading semantics)**: **B20**. Scene-inspection on a project whose main scene calls `get_tree().quit()` in `_ready` is reported as a crash with `failureKind=runtime` / broker-side `gameplay`. Misleading enough to send an agent debugging a non-existent crash. Not a regression — latent since scene-inspection shipped, surfaced only because pass 9 ran scene-inspection against the runtime-error-loop project for the first time as part of B17 cleanup.

**Minor (cosmetic / churn)**: **B21**. Envelope's `failureKind="runtime"` contradicts the embedded diagnostic message which says `failureKind='gameplay'`. Same root cause family as B20 (orchestrator's broker→envelope mapping); cosmetic on its own but compounds B20's misleading-ness.

**Verified pass-8 fixes**:
- **B10** ✅ fixed by [PR #40](https://github.com/RJAudas/godot-agent-harness/pull/40) — `_ready` null deref captured for both `stopAfterValidation:true` and `stopAfterValidation:false`. JSONL has the record with `function="_ready"`. Live-editor regression confirmed.
- **B17** ✅ fixed by [PR #41](https://github.com/RJAudas/godot-agent-harness/pull/41) — `_process` null deref in `error_on_frame.gd:20` captured. JSONL has the record with `function="_trigger_error"`. Live-editor regression confirmed.
- **B18** ✅ fixed by [PR #42](https://github.com/RJAudas/godot-agent-harness/pull/42) — no leaked playtest after either 6b or 6c with `stopAfterValidation:false`. `Get-Process godot*` after each run shows only the editor PID.

**Verified earlier-pass fixes still in place**:
- **B8** ✅ (pass 6b) — request fields override `inspection-run-config.json` (manifest's `runId="runbook-runtime-error-triage"`, not config's `"runtime-error-loop-run-01"`).
- **B11** ✅ (pass 5) — `pinnedRunIndex` is a JSON array in both 1-pin and 2-pin cases.
- **B13** ✅ (pass 6c) — `-EnsureEditor` cold-start completes in 10s wallclock, no hang.
- **B14** ✅ (pass 6a) — no vestigial `dispatchedEventCount` field on the input-dispatch envelope.
- **B15** ✅ (pass 6a) — `warnings` is a flat array on behavior-watch.
- **B19** ✅ (pass 8) — blocked-status envelope is valid JSON with actionable diagnostic, exits 1.

**Tool-call ergonomics**: 11 of 13 workflows hit the 2-call ideal (or fewer for 1-call workflows like editor launch and stop). Test 6b cost 4 calls (launch second editor, write inline-override payload, invoke). Test 5b cost 3 (Write broken script + edit scene + invoke). No regressions versus pass 8.

**Suggested next pass**: a single narrowly-scoped batch.

- **[10 — Scene-inspection clean-quit handling (B20 + B21)](10-scene-inspection-clean-quit.md)** *(new)*: differentiate clean playtest exit from crash in the broker; align envelope `failureKind` and diagnostic text. Add a fixture (`integration-testing/quit-in-ready/` or a new sandbox row) whose main scene calls `get_tree().quit()` in `_ready` and a test row for it in this template's matrix so the regression is caught automatically. Lower priority than pass 8's three batches — this is misleading-semantics, not data loss — but worth doing because pass 9 is the first pass with a fully-clean main matrix and shipping B20/B21 fixes would consolidate that win.

A meta-observation for future passes: pass 8's three-PR strategy (one PR per defect, each with its own live-editor regression test) worked. Three PRs landed three working fixes; pass 9 verified all three on the first try. Compare to pass 7 / [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39) where bundling four defects into a single PR resulted in three of the four not actually shipping despite passing Pester. The split-pass discipline established in [pass 6](06-test-pass-results.md) and refined in [pass 8](08-test-pass-results.md) is the working model.
