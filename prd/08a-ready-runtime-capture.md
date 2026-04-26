# Pass 8a — Capture `_ready`-time runtime errors

## Scope

One addon-side bug, re-confirmed in [pass 8](08-test-pass-results.md) after [PR #39](https://github.com/RJAudas/godot-agent-harness/pull/39) shipped a fix that did not actually land. Live repro is unchanged from [pass 7](07-test-pass-results.md).

| ID | Workflow | What's broken | Fix area |
|---|---|---|---|
| B10 | Runtime-error triage | Runtime errors during a scene's `_ready()` are not captured; `runtime-error-records.jsonl` stays 0 bytes; envelope reports clean `success` | addon runtime-error capture pipeline |

## Why this is its own batch

- **Highest-impact defect in the matrix.** Runtime-error triage is the workflow agents reach for when triaging real crashes; right now it lies on the most common shape of crash (`_ready`-time null deref).
- **Self-contained at the runtime layer.** No design-precedence questions, no orchestrator changes — purely the addon's pause-on-error → JSONL writer path.
- **PR #39 evidently shipped without a live-editor regression check.** Pester passed; the bug shipped. The methodology for this fix has to be different (see *Verification methodology* below).

## Problem

PR #39 commit message ("fix: Pass 7 bundled defects (B10, B17, B18, B19)", [0afd615](https://github.com/RJAudas/godot-agent-harness/commit/0afd615)) claimed to address B10, but pass-8 live testing reproduces the same broken behavior:

**Reproduction** (matrix row 6c):
```powershell
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

**Observed** (both fixtures):
```json
{ "status": "success",
  "failureKind": null,
  "outcome": {
    "terminationReason": "completed",
    "latestErrorSummary": null,
    "runtimeErrorRecordsPath": "…/runtime-error-records.jsonl"
  } }
```
The referenced JSONL is **0 bytes**.

**Hypothesis**: the deferred-finalization merge path runs only on `stopAfterValidation: false` clean stops; when the playtest exits abnormally (the `_ready` crash itself terminates the run before the coordinator's deferred path runs), the late-arriving error records never make it into the JSONL. Even with `stopAfterValidation: false`, the playtest exits in ~3s — the crash itself terminates the run, not the validation gate. The fix needs to capture errors that fire *during* `_ready` and write them before the runtime exits — the error-record write must happen synchronously inside the runtime's pause-on-error handler, not via post-hoc merge.

**Where**: addon runtime-error capture pipeline. Files to investigate:

- [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd) — pause-on-error handler
- [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd) — JSONL writer
- [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) — deferred-finalization merge path

## Resolution: live testing feedback as the verification gate

PR #39 passed Pester unit tests and shipped without a working runtime-side fix. **The fix loop for this batch must be live-editor-driven**, not Pester-driven:

1. **Reproduce live before writing code.** Inject the `error_main.gd` script as in the reproduction above; run `invoke-runtime-error-triage.ps1`; confirm the 0-byte JSONL. This is the failing baseline.
2. **Write the fix in `scenegraph_runtime.gd`'s pause-on-error handler.** The error-record append must happen synchronously — the file open + write + flush + close must complete inside the handler before returning to the engine. Do not rely on the run coordinator's deferred merge path; that path does not run when the playtest exits abnormally.
3. **Verify against the live repro after every meaningful change.** A round trip is ~10 seconds: edit `.gd`, run `tools/check-addon-parse.ps1` (1s), run `invoke-runtime-error-triage.ps1` against the injected sandbox (~3s), inspect the JSONL. If the JSONL has at least one record with the right `file`/`line`/`message`, the fix is real.
4. **Add a Pester regression test only after the live fix works.** The Pester test should construct a synthetic JSONL on disk and assert the orchestrator projects it correctly into the envelope — that's what unit tests are good for. They are *not* a substitute for the live capture-path test.
5. **Lock the live regression into PR review.** The PR description must include the matrix-row-6c repro output (envelope JSON + JSONL contents) before merge. PR #39's mistake was a Pester-only verification; do not repeat it.

## Fix proposal (concrete)

In `scenegraph_runtime.gd`'s pause-on-error handler:

1. **Open the JSONL eagerly** at autoload `_enter_tree` time (before any scene `_ready` runs), with append mode. Keep the file handle hot for the lifetime of the playtest.
2. **In the pause-on-error handler**, append a single line to the JSONL with `{file, line, function, message, timestamp_ms, frame}` and call `flush()` *synchronously* before returning. If Godot's `FileAccess` does not flush-to-disk reliably on script error, close-and-reopen the handle after each append (slower but durable).
3. **Update `latestErrorSummary` projection in the orchestrator** to read the JSONL on completion regardless of `terminationReason` — even if the playtest exited via `terminationReason="crashed"` or `"unknown"`, the JSONL is the source of truth.
4. **Set `status=fail` in the manifest** when the JSONL is non-empty, regardless of how the playtest exited.

## Subtasks

1. **Live baseline.** Run the reproduction above; capture the 0-byte JSONL state as the failing case. ~3 minutes.
2. **Spike eager-open + sync-flush.** Modify the autoload to open the JSONL in `_enter_tree` and write a known-test row immediately. Run the harness; verify the row lands. This proves the write path works before `_ready` runs. ~30 minutes.
3. **Wire the pause-on-error handler.** Hook `EngineDebugger` (or the project's existing error-print intercept) to write a JSONL row per error. ~1 hour.
4. **Live regression: matrix row 6c.** Run the injected `_ready` deref repro; confirm the JSONL has at least one record and the envelope reports `failureKind=runtime` with `latestErrorSummary` populated. ~5 minutes.
5. **Add a Pester test that the orchestrator correctly projects a non-empty JSONL into the envelope.** This is a projection test, not a capture test. ~30 minutes.
6. **Run `tools/check-addon-parse.ps1`** after every addon edit. Non-zero exit blocks.
7. **PR description must paste the matrix-6c envelope JSON + JSONL excerpt** as the proof-of-fix evidence.

## How to verify

Same reproduction as above. After the fix:
- `runtime-error-records.jsonl` contains ≥1 row with `file=res://scripts/error_main.gd`, `line=5`, `message` containing "null".
- Envelope reports `status=failure`, `failureKind=runtime`, `outcome.latestErrorSummary={file: "res://scripts/error_main.gd", line: 5, message: "<verbatim>"}`.
- Exit code 1.
- Behavior identical for both `run-and-watch-for-errors.json` and `run-and-watch-for-errors-no-early-stop.json` fixtures.

## Cross-batch dependencies

- **8a → 8b ([Pass 8b](08b-process-runtime-capture.md))**: B17 is the same root-cause family as B10 in a different lifecycle slot. If 8a's fix is general (eager-open + sync-flush in pause-on-error handler), 8b should be a near-no-op verification — but verify live, do not assume.
- **8a is independent of 8c ([Pass 8c](08c-playtest-cleanup.md))**: the playtest-leak fix is broker-side and orthogonal to runtime-capture.

## Not in scope

- B17 (`_process`-time capture) — see [Pass 8b](08b-process-runtime-capture.md).
- B18 (playtest leak) — see [Pass 8c](08c-playtest-cleanup.md).
- B19 — already fixed and verified live in pass 8.
