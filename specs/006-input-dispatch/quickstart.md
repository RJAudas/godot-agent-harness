# Quickstart: Runtime Input Dispatch

## Goal

Implement a plugin-first input-dispatch flow that lets an agent declare a bounded, frame-anchored keyboard and input-action script as part of the existing automation run request, deliver each accepted event from the runtime addon through Godot's real input pipeline, persist a fixed `input-dispatch-outcomes.jsonl` artifact in the current run's evidence bundle, and reproduce the Pong testbed numpad-Enter `_unhandled_input` crash described in issue #12 end-to-end.

## Implementation Outline

1. Extend the current automation run request so a run-scoped `inputDispatchScript` can be passed without creating a second broker entrypoint.
2. Validate and normalize that script before launch using a new `InputDispatchRequestValidator` (modeled on `BehaviorWatchRequestValidator`) that enforces the 256-event cap, the logical-`Key`-enum whitelist, the declared-`InputMap`-action check, the press/release matching rule, and the machine-readable rejection codes.
3. Deliver accepted events from the runtime addon through `Input.parse_input_event()` using `InputEventKey` (logical `keycode`, `pressed` per phase) for keyboard events and `InputEventAction` for action events, anchored to process frames counted from the first `_process()` callback.
4. Persist a fixed `input-dispatch-outcomes.jsonl` file in the current run's output directory, register the `input-dispatch-outcomes` artifact kind in `tools/evidence/artifact-registry.ps1`, and add an artifact reference to the current manifest.
5. Advertise input-dispatch support as an `inputDispatch` entry in the editor-evidence capability artifact and gate the validator on the advertised value.
6. Reuse the current run-result and manifest-first workflow so agents inspect the run result, then the manifest, then the outcome artifact.

## Primary Source Areas

- `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`
- `addons/agent_runtime_harness/shared/inspection_constants.gd`
- `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`
- `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`
- `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`
- `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`
- `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json`
- `specs/006-input-dispatch/contracts/input-dispatch-outcome-row.schema.json`
- `tools/evidence/artifact-registry.ps1`
- `tools/automation/get-editor-evidence-capability.ps1`
- `tools/automation/request-editor-evidence-run.ps1`

## Example Request Shape

Add a run-scoped input-dispatch script to an existing automation request fixture. The example below reproduces the Pong numpad-Enter crash from issue #12:

```json
{
  "requestId": "pong-request-input-dispatch-001",
  "scenarioId": "pong-title-numpad-enter",
  "runId": "pong-input-dispatch-run-001",
  "targetScene": "res://scenes/title.tscn",
  "outputDirectory": "res://evidence/automation/pong-input-dispatch-run-001",
  "artifactRoot": "examples/pong-testbed/evidence/automation/pong-input-dispatch-run-001",
  "expectationFiles": [],
  "capturePolicy": {
    "startup": true,
    "manual": true,
    "failure": true
  },
  "stopPolicy": {
    "stopAfterValidation": true
  },
  "requestedBy": "input-dispatch-fixture",
  "createdAt": "2026-04-19T00:00:00Z",
  "overrides": {
    "inputDispatchScript": {
      "events": [
        {
          "kind": "key",
          "identifier": "KP_ENTER",
          "phase": "press",
          "frame": 30
        },
        {
          "kind": "key",
          "identifier": "KP_ENTER",
          "phase": "release",
          "frame": 32
        }
      ]
    }
  }
}
```

## Recommended Validation Flow

1. Validate request fixtures for one valid Pong numpad-Enter script and at least one invalid script per rejection code (`unsupported_identifier`, `unmatched_release`, `script_too_long`, `later_slice_field`, `invalid_phase`, `invalid_frame`).
2. Run the existing capability check for the example project and confirm `inputDispatch.supported = true`:

```powershell
pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot examples/pong-testbed
```

3. Submit the input-dispatch request through the existing automation helper:

```powershell
pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot examples/pong-testbed -RequestFixturePath examples/pong-testbed/harness/automation/requests/input-dispatch.numpad-enter.json
```

4. Read `harness/automation/results/run-result.json` first. If the run completed (or crashed as expected for issue #12), open the persisted `evidence-manifest.json`.
5. Confirm the manifest references `input-dispatch-outcomes.jsonl` for the current run, exposes the normalized `appliedInputDispatch` summary for that run, and that the outcome artifact contains one row per declared event with the fixed status enum.
6. Validate the manifest and referenced files:

```powershell
pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>
pwsh ./tools/tests/run-tool-tests.ps1
```

## Expected Outcomes

- Valid scripts normalize into an applied-input-dispatch summary before dispatch starts.
- Invalid scripts fail with a machine-readable rejection and do not start the playtest.
- Successful runs persist a fixed `input-dispatch-outcomes.jsonl` file for the current run only, with one row per declared event.
- The Pong numpad-Enter fixture reproduces the issue #12 `_unhandled_input` crash; the press row records `status = dispatched`, and the release row records either `dispatched` (if the crash is asynchronous) or `skipped_run_ended` (if the crash precedes release dispatch). Either outcome is acceptable because the partial-run flush path guarantees a row for every declared event.
- The current run manifest references the outcome artifact, includes the normalized `appliedInputDispatch` summary, and lets the agent inspect the outcomes without reading unrelated full-scene logs.
