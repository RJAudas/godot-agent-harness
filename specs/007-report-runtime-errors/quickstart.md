# Quickstart: Report Runtime Errors And Pause-On-Error

## Goal

Implement a plugin-first runtime-error-reporting flow that captures every GDScript runtime error and warning observed after the runtime harness attaches, pauses the running playtest on `error`-severity records and unhandled exceptions, lets the agent submit a `continue` or `stop` decision through the existing brokered automation contract, and persists per-run runtime-error and pause-decision artifacts plus a manifest-level termination classification (`completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, `killed_by_harness`).

## Implementation Outline

1. Extend the editor-side capability artifact emitted by `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` with three new entries: `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression`. Mirror the existing `inputDispatch` capability shape (`{ supported, reason }`).
2. Extend `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` to capture engine-reported errors and `push_error`/`push_warning` records through the existing `EngineDebugger` channel, deduplicate by `(scriptPath, line, severity)` with a rolling `repeatCount` capped at 100, and forward each new dedup-key occurrence to the editor as a `runtime_error_record` debugger message.
3. On the runtime side, when an `error`-severity record or an unhandled exception is observed and `pauseOnError.supported = true`, raise an engine debug-pause and send a `runtime_pause` debugger message carrying the pause cause, originating script/line/function/message, and the current `Engine.get_process_frames()` ordinal; do NOT advance frames or dispatch queued input-dispatch events while paused.
4. On the editor side, extend `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd` to recognize the new `runtime_error_record`, `runtime_pause`, and `pause_decision_ack` messages, and extend `scenegraph_automation_broker.gd` to poll `harness/automation/requests/pause-decision.json` while a pause is outstanding and forward an accepted `pause_decision` message back to the runtime.
5. Add `addons/agent_runtime_harness/shared/pause_decision_request_validator.gd` modeled on `behavior_watch_request_validator.gd` and `input_dispatch_request_validator.gd`. Reject malformed decisions with `missing_field`, `unsupported_field`, `invalid_decision`, `unknown_pause`, or `decision_already_recorded`.
6. Implement the documented decision timeout (default 30 s) on the editor side; on expiry, apply `decision = timeout_default_applied`, send the runtime a `stop` instruction, and stamp the manifest termination classification `stopped_by_default_on_pause_timeout`.
7. Persist `runtime-error-records.jsonl` and `pause-decision-log.jsonl` through `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`, register both kinds in `tools/evidence/artifact-registry.ps1`, and add the `runtimeErrorReporting` block (with `termination`, `pauseOnErrorMode`, `lastErrorAnchor` when crashed, and the two artifact references) to the manifest writer.
8. Implement breakpoint suppression on the runtime side using the documented engine-debugger entry path; when suppression is unavailable on the current platform, advertise `breakpointSuppression.supported = false` with `reason = "engine_hook_unavailable"` and route any breakpoint pause as `cause = paused_at_user_breakpoint`.
9. Add a workspace-side helper `tools/automation/submit-pause-decision.ps1` that writes a validated `pause-decision.json` request mirroring `tools/automation/request-editor-evidence-run.ps1`.

## Primary Source Areas

- [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd)
- [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd)
- [addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd](../../addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd)
- [addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd](../../addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd)
- [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd)
- [addons/agent_runtime_harness/shared/inspection_constants.gd](../../addons/agent_runtime_harness/shared/inspection_constants.gd)
- [addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd](../../addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd)
- [specs/007-report-runtime-errors/contracts/runtime-error-record.schema.json](contracts/runtime-error-record.schema.json)
- [specs/007-report-runtime-errors/contracts/pause-decision-record.schema.json](contracts/pause-decision-record.schema.json)
- [specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json](contracts/pause-decision-request.schema.json)
- [tools/evidence/artifact-registry.ps1](../../tools/evidence/artifact-registry.ps1)
- [tools/automation/request-editor-evidence-run.ps1](../../tools/automation/request-editor-evidence-run.ps1)
- [tools/automation/get-editor-evidence-capability.ps1](../../tools/automation/get-editor-evidence-capability.ps1)

## Example Pause Decision Request

After the agent reads `harness/automation/results/run-result.json` and observes a pause notification (or sees a pending pause through the editor lifecycle artifact), it writes:

```json
{
  "runId": "runtime-error-loop-run-001",
  "pauseId": 0,
  "decision": "stop",
  "submittedBy": "runtime-error-loop-fixture",
  "submittedAt": "2026-04-19T00:00:00Z"
}
```

to `harness/automation/requests/pause-decision.json` inside the running project. The broker consumes the file, validates it, forwards the decision through the debugger channel, and deletes the request file so a stale decision is never reused.

## Recommended Validation Flow

1. Validate request fixtures for one valid `continue` decision, one valid `stop` decision, and at least one invalid decision per rejection code (`missing_field`, `unsupported_field`, `invalid_decision`, `unknown_pause`, `decision_already_recorded`):

   ```powershell
   pwsh ./tools/validate-json.ps1 -InputPath specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json -SchemaPath specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json
   ```

2. Create an `integration-testing/runtime-error-loop/` sandbox using the documented integration-testing flow (per [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md) and [tools/README.md](../../tools/README.md)), deploy the harness into it, then run the capability check and confirm all three new entries are present:

   ```powershell
   pwsh ./tools/deploy-game-harness.ps1 -GameRoot integration-testing/runtime-error-loop
   pwsh ./tools/check-addon-parse.ps1
   pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot integration-testing/runtime-error-loop
   ```

3. Submit the seeded `error_on_frame.gd` fixture run through the existing automation helper:

   ```powershell
   pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot integration-testing/runtime-error-loop -RequestFixturePath tools/tests/fixtures/runtime-error-loop/harness/automation/requests/error-on-frame.json
   ```

4. While the run is paused, submit a `stop` decision:

   ```powershell
   pwsh ./tools/automation/submit-pause-decision.ps1 -ProjectRoot integration-testing/runtime-error-loop -RunId runtime-error-loop-run-001 -PauseId 0 -Decision stop
   ```

5. Read `harness/automation/results/run-result.json` first. Then open the persisted `evidence-manifest.json` and confirm:
   - `runtimeErrorReporting.termination = "stopped_by_agent"` for the stop case (`stopped_by_default_on_pause_timeout` if you let the timeout elapse).
   - `runtimeErrorReporting.pauseOnErrorMode = "active"`.
   - `runtimeErrorReporting.runtimeErrorRecordsArtifact` and `pauseDecisionLogArtifact` reference current-run files.
   - `runtime-error-records.jsonl` contains exactly one row with `severity: "error"`, the seeded script path/line/function/message, and `repeatCount: 1`.
   - `pause-decision-log.jsonl` contains exactly one row with `cause: "runtime_error"`, `decision: "stopped"`, `decisionSource: "agent"`, and a positive `latencyMs`.

6. Validate the manifest and run the regression suite:

   ```powershell
   pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>
   pwsh ./tools/tests/run-tool-tests.ps1
   pwsh ./tools/check-addon-parse.ps1
   ```

7. Repeat with the `unhandled_exception.gd`, `warning_only.gd`, and `pong-no-errors.json` fixtures to verify each path:
   - Unhandled exception → `cause: "unhandled_exception"`, agent decision honored.
   - Warning only → record persisted with `severity: "warning"`, no pause raised, `termination = "completed"`.
   - No errors → empty `runtime-error-records.jsonl`, empty `pause-decision-log.jsonl`, `termination = "completed"`.

## Expected Outcomes

- Every `error`-severity record and every unhandled exception observed after attachment pauses the run and emits a pause notification through the broker; the agent's `continue` or `stop` decision is honored.
- Every `error` and `warning` observed after attachment is persisted as a deduplicated row in `runtime-error-records.jsonl` for the current run only, with a rolling `repeatCount` capped at 100 per `(scriptPath, line, severity)` key.
- Every pause produces exactly one row in `pause-decision-log.jsonl` for the current run only, with the cause, decision, decision source, and latency.
- The current run manifest carries a `runtimeErrorReporting` block with the termination classification and (when crashed) a `lastErrorAnchor`.
- The capability artifact carries first-class `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression` entries.
- A runtime that exits normally produces termination `completed` and an empty pause-decision log; a runtime killed by the harness produces `killed_by_harness`; a runtime that crashes without a clean shutdown produces `crashed` with a `lastErrorAnchor`.
- On environments where `pauseOnError.supported = false`, runs are NOT rejected; they execute in capture-only degraded mode with the manifest stamped `pauseOnErrorMode = "unavailable_degraded_capture_only"`.
