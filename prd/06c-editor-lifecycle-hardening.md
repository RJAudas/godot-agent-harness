# Pass 6c — Editor lifecycle hardening

## Scope

Three issues from [pass 6](06-test-pass-results.md) about how the harness coordinates between the editor process, its spawned playtest children, and the next request to land. Two are friction-class; one (B13) is a workflow-blocking hang.

| ID | Workflow | What's broken | Fix area |
|---|---|---|---|
| B13 | Any runtime workflow with `-EnsureEditor` | Cold-start hang: launcher reports success, chained workflow never writes a request | RunbookOrchestration.psm1 post-launch handoff |
| F2 | Runtime-error triage → next workflow | `scene_already_running` blocks next call; remediation hint blames targetScene | addon broker idle-state cleanup + orchestrator diagnostic mapping |
| F3 | Stop editor | `--path` matching kills the editor but leaves playtest child processes alive | invoke-stop-editor.ps1 process tracking |

## Why these fit together

- All three concern editor/playtest process lifecycle and the broker handoff between them.
- Fixing one likely informs the others (e.g., child-process tracking from F3 is useful background for B13's deadlock investigation; F2's runtime-side half is broker-state cleanup that touches the same surface as B13's "why isn't the broker accepting the next request" question).
- All three are addressable without addon source changes (F2 and F3 *might* benefit from runtime-side work, but a usable fix exists purely in orchestration).

## Recommended landing order

**F3 first** — smallest, cleanest, most self-contained. Use what you learn about Godot's process tree shape on Windows to inform B13's deadlock investigation.

**B13 second** — biggest unknown. If the deadlock turns out to be related to child-process handle ownership, F3's groundwork pays off here. Allocate time for a real spike; do not rush a heartbeat-only fix the way pass 5 did.

**F2 last** — partly stylistic (diagnostic mapping is a 10-line orchestrator change); the runtime-side half is optional cleanup that may overlap with [B8's investigation in pass 6b](06b-runtime-semantic-correctness.md#b8).

## Not in scope

- **B14, B15, B16** — orchestration outcome shape. See [pass 6a](06a-outcome-shape-cleanup.md).
- **B8, B10** — addon-side semantic correctness. See [pass 6b](06b-runtime-semantic-correctness.md). F2's runtime-side half (broker idle-state cleanup) is *adjacent* to B8 territory but not blocked on it.

---

## B13 — `-EnsureEditor` cold-start hang

**Status**: regression check — pass 5 added launcher heartbeats and a 90s capability-wait timeout; the actual deadlock was *not* fixed.

**Where**: orchestration glue between `-EnsureEditor` and the workflow dispatch in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1) — specifically the post-launch wait loop that bridges into the workflow's request-write step. The launcher itself ([tools/automation/invoke-launch-editor.ps1](../tools/automation/invoke-launch-editor.ps1)) is fine; the chained handoff is broken.

**Reproduction** (against a fully-stopped editor; cold cache):
```powershell
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe -EnsureEditor
```

**Observed**:
```
[invoke-launch-editor] spawned Godot PID 39692; waiting up to 90s for capability.json (mtime >= )
[invoke-launch-editor] editor ready (capability.json mtime 0s ago); dispatching workflow
OK: spawned editor PID 39692; capability ready in 5s (mtime 0s ago).
<…then 6+ minutes of silence, no further stderr, no JSON envelope…>
```

The launcher correctly emitted "editor ready" and "dispatching workflow" within 5s, but then the chained workflow step never wrote a `run-request.json` and never produced an envelope. Killed at 6+ minutes. The explicit two-step pattern (`invoke-launch-editor` then plain `invoke-scene-inspection` in a fresh `pwsh` invocation) ran in seconds — verified in pass 6 tests 1+2.

**Hypotheses** (refined from pass 5):

1. A second wait-for-capability loop in the workflow path that doesn't share state with the launcher's wait, and isn't bounded.
2. A deadlock when the launcher's spawned-process handle is held in the parent shell while the workflow tries to claim file-system primitives the launcher hasn't released.
3. Buffered stdout of the chained step that never gets flushed because the parent process is blocked on a child handle.

**Fix proposal** — three things to try, ideally in order:

1. **Run the workflow body in a detached child `pwsh`** rather than inline in the same process — proves the deadlock is in shared-process state if it succeeds. If it does, that's the simplest production fix: have `-EnsureEditor` mode shell out to a fresh `pwsh` for the workflow step.
2. **Add stderr heartbeats to the post-launch wait** (`waiting for run-request bridge … N seconds elapsed`) — silence is the worst symptom; even a hang with progress lines is debuggable.
3. **Hard-cap the post-launch chained workflow at 90s** with `failureKind: "internal"` and a clear diagnostic on timeout. This is a defense-in-depth fix even after the root cause lands — indefinite hangs should never be the user-visible failure mode.

**Subtasks**:
1. Spike: instrument the post-launch handoff with verbose stderr; reproduce with `-Verbose` to find the exact line that hangs.
2. If the spike points at shared-process state (likely), implement detached-child workflow dispatch.
3. Add the heartbeat + hard-cap regardless, as defense in depth.
4. Pester / harness integration test: cold-start scenario must complete in <30s or fail with a bounded timeout in <90s. Indefinite silence must not be possible.
5. Update the [RUNBOOK.md "⚠️ Known issue (B13)" warning](../RUNBOOK.md#editor-lifecycle-helpers) — either remove (if confident in the fix) or update to point at this doc.

**How to verify**: the reproduction must either complete within 30 seconds, or emit a clear timeout failure within ~90 seconds. Indefinite silence is not acceptable. Add the test as a smoke run in `tools/tests/run-tool-tests.ps1` (gated behind a `-Live` flag if it requires a real editor).

**Documentation impact**: the existing warning block in [RUNBOOK.md](../RUNBOOK.md) ("⚠️ Known issue (B13)") remains accurate until this fix lands; do not soften it.

---

## F2 — `scene_already_running` after a runtime-error-triage run blocks the next workflow with a misleading hint

**Where**: addon runtime broker (the part that classifies "this scene is already running" as a blockedReason after a runtime-error playtest exits) plus orchestrator diagnostic mapping.

**Reproduction**: run `invoke-runtime-error-triage.ps1` against probe, then immediately run `invoke-scene-inspection.ps1` against the same project root.

**Observed**:
```json
"status": "failure",
"failureKind": "runtime",
"diagnostics": [
  "Run was blocked before evidence was captured. blockedReasons: scene_already_running. Check that targetScene 'res://scenes/main.tscn' exists in the project."
]
```

The diagnostic's *advice* ("Check that targetScene 'res://scenes/main.tscn' exists in the project") is wrong — the scene exists; the blocker is leftover playtest state from the previous run. Stopping and relaunching the editor (`invoke-stop-editor`, then `invoke-launch-editor`) clears it.

**Symptom**: the second tool call fails with a misleading remediation hint. An agent following the diagnostic will check the (correct) targetScene, fail to find the problem, and conclude the harness is broken.

**Fix** — two surfaces, fixable independently:

**Orchestrator side** (small, safe — land first):

When `blockedReasons` contains `scene_already_running`, the diagnostic should say so explicitly and recommend `invoke-stop-editor` + `invoke-launch-editor`, not "check targetScene exists." The targetScene-existence hint should only appear when `blockedReasons` actually mentions a missing scene path. In [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1):

```powershell
# Map blockedReasons → diagnostic text (one entry per known reason)
$blockedReasonHints = @{
    'scene_already_running' = "A previous playtest is still running. Restart the editor: invoke-stop-editor.ps1 then invoke-launch-editor.ps1."
    'target_scene_missing'  = "Check that targetScene '$targetScene' exists in the project."
    # …additional reasons
}
foreach ($reason in $blockedReasons) {
    if ($blockedReasonHints.ContainsKey($reason)) {
        $envelope.diagnostics += $blockedReasonHints[$reason]
    }
}
```

**Runtime side** (larger, optional — investigate during 6b's B8 work):

When the editor finishes a runtime-error-triage playtest, ensure the playtest scene is fully stopped and the broker is back in idle state before the next request can land. May overlap with [B8](06b-runtime-semantic-correctness.md#b8) investigation since both touch broker state management.

**Subtasks**:
1. Audit `blockedReasons` enum — list every reason the runtime can emit. Likely small (5-10 values).
2. Build the `blockedReasonHints` table in the orchestrator with one diagnostic per reason.
3. Decide whether the runtime-side broker cleanup is in scope for this batch or deferred. If deferred, document the editor-restart workaround in [RUNBOOK.md](../RUNBOOK.md).
4. Pester test: synthesize a `run-result.json` with `blockedReasons=["scene_already_running"]` and assert the envelope's diagnostic mentions editor restart, not targetScene.

**How to verify**: run runtime-error-triage then immediately run scene-inspection. The diagnostic should mention `scene_already_running` and recommend an editor restart, not blame the targetScene. If the runtime-side fix lands too, the second call should *succeed* without needing the restart.

This is friction-class (workflow recovers after editor restart) but the misleading diagnostic is what makes it worth filing.

---

## F3 — Stop-editor leaves orphan playtest processes

**Where**: [tools/automation/invoke-stop-editor.ps1](../tools/automation/invoke-stop-editor.ps1) — process matching by `--path`.

**Observed**: after running through pass 6 tests 1–11, three Godot processes were still alive even after `invoke-stop-editor` had been called for each project root and reported success:
```
   Id ProcessName              StartTime
   -- -----------              ---------
 6816 Godot_v4.6.2-stable_win64 4/25/2026 3:57:00 PM
23512 Godot_v4.6.2-stable_win64 4/25/2026 3:46:02 PM
41160 Godot_v4.6.2-stable_win64 4/25/2026 3:46:39 PM
```

`--path`-matched stopping kills only the *editor* process; the editor's spawned playtest (a child Godot process running the game scene) does not match `--path` and survives. After several test cycles, these orphans accumulate.

**Symptom**: long-running test sessions (or repeated runs) leak Godot processes that consume memory and may interfere with future runs (capability.json contention, port collisions if the addon binds anything). On Windows this is especially bad — closing the parent does not always reap the child.

**Fix**: `invoke-stop-editor` should also identify and kill the editor's playtest children. Two implementation options:

**Option A — process-tree walk (preferred)**: on Windows, `Get-CimInstance Win32_Process -Filter "ParentProcessId=$editorPid"` enumerates direct children. For each child where `ProcessName` matches `Godot*`, `Stop-Process -Force`. Recursive descent if needed.

```powershell
function Stop-EditorAndChildren {
    param([int]$editorPid)
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$editorPid"
    foreach ($child in $children) {
        if ($child.Name -like 'Godot*') {
            Stop-EditorAndChildren -editorPid $child.ProcessId  # recursive
            Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Stop-Process -Id $editorPid -Force -ErrorAction SilentlyContinue
}
```

**Option B — addon writes pidfile**: have the addon write `harness/automation/results/playtest-pids.json` whenever it spawns a playtest, and have `invoke-stop-editor` consume that. Cleaner contract but requires addon work.

**Option A is recommended** — purely orchestration-side, no addon coupling, and `Win32_Process` is reliable for direct-child relationships on Windows.

**Subtasks**:
1. Implement `Stop-EditorAndChildren` (or inline the walk in `invoke-stop-editor.ps1`).
2. Update the envelope's `outcome.stoppedPids` to include both the editor PIDs and any killed children, so the user sees the full cleanup.
3. Pester test: launch an editor, manually spawn a child `Start-Process pwsh -PassThru` whose ParentProcessId is the editor, call stop-editor, assert both PIDs in `stoppedPids` and neither still running.
4. Manual verification: run pass 6 matrix, then `Get-Process Godot_v4.6.2-stable_win64 -ErrorAction SilentlyContinue` should return nothing.

**How to verify**: after a runtime-error-triage run, call `invoke-stop-editor` once, then `Get-Process Godot_v4.6.2-stable_win64 -ErrorAction SilentlyContinue` returns nothing. Run the full pass 6 matrix and verify no Godot processes remain at the end.

---

## Verification — whole batch

After all three fixes land:

1. **B13 — pass 6 test 11**: cold-start `-EnsureEditor` flow completes in <30s or fails cleanly within 90s. No indefinite hangs.
2. **F2 — sequenced workflow test**: `invoke-runtime-error-triage` → `invoke-scene-inspection` (same project). Either succeeds (if runtime-side fix landed) or fails with a diagnostic that mentions `scene_already_running` and recommends editor restart.
3. **F3 — process audit**: run the full pass 6 matrix; `Get-Process Godot_v4.6.2-stable_win64 -ErrorAction SilentlyContinue` returns nothing at the end.
4. **Documentation update**: [RUNBOOK.md](../RUNBOOK.md) "⚠️ Known issue (B13)" warning either removed or updated based on what landed.

## Cross-batch dependencies

- **F2 ↔ B8** — F2's runtime-side half (broker idle-state cleanup) overlaps with [B8's config-precedence work in 6b](06b-runtime-semantic-correctness.md#b8). If 6b is in flight, share investigation notes between the two.
- **F3 → B13** — fixing F3 first gives a clean process tree for B13's deadlock investigation. Without F3, leaked playtest children may confuse the deadlock symptom.
- **B13 → none** — once landed, the `-EnsureEditor` warning in [RUNBOOK.md](../RUNBOOK.md) can be removed.
