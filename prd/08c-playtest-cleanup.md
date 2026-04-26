# Pass 8c — Clean up the playtest after `stopAfterValidation: false` runs

## Scope

One broker-side bug, re-confirmed in [pass 8](08-test-pass-results.md) after [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39) shipped a fix that did not actually land.

| ID | Workflow | What's broken | Fix area |
|---|---|---|---|
| B18 | Runtime-error triage | After a `stopAfterValidation: false` run reports `status=success` and exits, the playtest child process is *not* terminated by the broker. The next workflow invocation hits `scene_already_running` and is blocked | broker-side cleanup in the run coordinator |

## Why this is its own batch

- **Broker-side, not runtime-side.** Distinct fix surface from [Pass 8a](08a-ready-runtime-capture.md) / [Pass 8b](08b-process-runtime-capture.md) (which are addon-runtime). 8c can land in parallel without merge conflicts.
- **Severity downgraded by [B19's fix](08-test-pass-results.md#b19--orchestration-scripts-no-longer-crash-on-the-blocked-status-path--fixed)** — agents now get a clean `failureKind=runtime` envelope with an actionable hint ("Restart the editor: invoke-stop-editor.ps1 then invoke-launch-editor.ps1") instead of a raw PowerShell stack trace. 8c is no longer a contract violation, just real friction + recoverable data hygiene. Lower priority than 8a/8b.
- **Verifiable by process inspection alone** — no scene/script injection needed, which makes the live regression cheaper to run than 8a/8b's.

## Problem

After a `runtime-error-triage` run with `stopAfterValidation: false` exits cleanly, the playtest godot.exe child process keeps running. The broker reports `finalStatus=completed` but does not signal/terminate the playtest. Subsequent workflow invocations against the same project then hit `scene_already_running`.

**Reproduction (verified live in pass 8 against both probe and runtime-error-loop)**:
```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
# Returns status=success in ~3s. Now check the process tree:
Get-Process godot* | Select-Object Id, StartTime
# Expected: 1 process (the editor). Actual: 2 processes — the editor + a leaked playtest started ~3s ago.

# Then any follow-up workflow blocks:
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
# {"status":"failure","failureKind":"runtime","diagnostics":["Run was blocked … blockedReasons: scene_already_running. … Restart the editor: invoke-stop-editor.ps1 then invoke-launch-editor.ps1."]}
```

**Where**: [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) — broker-side run-finalization path. The coordinator writes `completedAt` and `finalStatus=completed` but does not terminate the playtest. The `terminationStatus` field in `run-result.json` may also be left in an inconsistent state (pass 7 noted `terminationStatus="running"` co-existing with `finalStatus="completed"` — re-verify live whether that contradiction still holds after PR #39's partial changes).

## Resolution: live testing feedback as the verification gate

Same methodology as [Pass 8a](08a-ready-runtime-capture.md) and [Pass 8b](08b-process-runtime-capture.md): **the fix loop must be live-editor-driven**.

1. **Reproduce live before writing code.** Run the reproduction above on probe; confirm the leaked process via `Get-Process godot*` and the blocked next invocation. This is the failing baseline. ~30 seconds.
2. **Investigate the `terminationStatus` shape.** Read `harness/automation/results/run-result.json` after the leaking run completes. Document whether `terminationStatus="running"` + `finalStatus="completed"` still co-exist, or whether PR #39 partially fixed that and only the process-cleanup half was missed. ~5 minutes.
3. **Write the fix in the run coordinator.** When finalizing a `stopAfterValidation: false` run, signal the playtest to exit (or kill it directly via PID), wait for the process to actually exit, and only *then* write `completedAt`/`finalStatus=completed` and release the scene-running guard. ~1–2 hours.
4. **Verify against the live repro after every meaningful change.** Round trip is fast (~10s): re-run the workflow, check `Get-Process godot*` shows only the editor, then run `invoke-scene-inspection` against the same project and confirm it succeeds (not blocks). If both hold, the fix is real.
5. **Verify the converse path also works.** Run with `stopAfterValidation: true` (the default fixture) and confirm the playtest is still terminated correctly — do not break the working path while fixing the broken one.
6. **Add a Pester regression test** that constructs a synthetic `run-result.json` and asserts the coordinator's finalization path terminates a registered playtest PID before writing `finalStatus=completed`. Useful as a guardrail; not a substitute for the live process-leak check.
7. **Lock the live regression into PR review.** PR description must include `Get-Process godot*` output (showing only the editor remains after the run) and a successful follow-up `invoke-scene-inspection` envelope, both pasted from a real run.

## Fix proposal (concrete)

In `scenegraph_run_coordinator.gd`'s run-finalization path:

1. **Track the playtest PID.** When the playtest is launched, capture its PID into the coordinator's run state.
2. **On finalization (any path — clean stop, validation gate, error exit):**
   - If the tracked PID is still alive, send a graceful shutdown signal first (or use Godot's existing scene-quit mechanism if exposed).
   - Wait up to ~5s for the process to exit on its own.
   - If still alive after the timeout, terminate forcefully (the F3 tree-kill in `invoke-stop-editor.ps1` already implements the right Windows-side primitive — reuse the same approach).
   - Only after the process is confirmed gone, write `completedAt` and `finalStatus=completed` to `run-result.json`.
3. **Reconcile `terminationStatus`.** It should never be `running` when `finalStatus=completed`. The state-machine should only allow transitions to `completed` after `terminationStatus` is `stopped`.
4. **Belt-and-suspenders for the scene-running guard.** Before granting a new run, verify the previously-tracked PID (if any) is actually gone, not just that `finalStatus=completed` was written. This guards against a future regression where the writer order gets reversed.

## Subtasks

1. **Live baseline.** Reproduce; confirm leaked PID; confirm next-invocation block. Capture `run-result.json` shape including `terminationStatus`. ~5 minutes.
2. **Plumb playtest PID tracking through the coordinator.** Add to run state, set on launch, clear on confirmed exit. ~30 minutes.
3. **Add the kill-on-finalization step.** Use the F3 tree-kill primitive from `invoke-stop-editor.ps1` for the Windows-side termination if a graceful exit times out. ~1 hour.
4. **Reconcile `terminationStatus` ordering.** State-machine fix — `completed` requires `stopped`. ~30 minutes.
5. **Live regression — leak path.** Run the reproduction; assert single godot.exe remains; assert next workflow succeeds. ~5 minutes.
6. **Live regression — non-leak path.** Run `stopAfterValidation: true`; assert the same single-process state and successful next workflow. ~5 minutes.
7. **Pester case.** Synthetic `run-result.json` + mock PID; assert finalization-order invariant. ~30 minutes.
8. **Run `tools/check-addon-parse.ps1`** after every addon edit.
9. **PR description must paste `Get-Process godot*` before-and-after** + the follow-up workflow envelope as proof-of-fix.

## How to verify

Same reproduction as above. After the fix:
- After `invoke-runtime-error-triage` returns `status=success`, `Get-Process godot*` shows **only the editor PID** (not the editor + playtest).
- Immediately running `invoke-scene-inspection` against the same project succeeds (not blocked with `scene_already_running`).
- `run-result.json`'s `terminationStatus` is `stopped` (or equivalent terminal value), not `running`.
- The default `stopAfterValidation: true` path still works exactly as before.

## Cross-batch dependencies

- **Independent of 8a / 8b.** Different fix surface; can land in parallel.
- **Pairs naturally with the [B19 fix](08-test-pass-results.md#b19--orchestration-scripts-no-longer-crash-on-the-blocked-status-path--fixed) that already shipped.** B19 made the *symptom* of B18 a clean envelope instead of a crash; 8c removes the symptom entirely. Together they close the blocked-state failure mode.

## Not in scope

- B10, B17 — see [Pass 8a](08a-ready-runtime-capture.md) and [Pass 8b](08b-process-runtime-capture.md).
- A general "playtest lifecycle" redesign — out of scope. The minimum here is "kill what we launched before saying we're done."
