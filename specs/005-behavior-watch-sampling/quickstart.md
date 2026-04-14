# Quickstart: Behavior Watch Sampling

## Goal

Implement a plugin-first bounded watch-sampling flow that lets an agent request a normalized watch contract for selected runtime nodes, persist a fixed `trace.jsonl` artifact for the current run, and inspect that trace through the existing manifest-centered evidence bundle.

## Implementation Outline

1. Extend the current automation run request so a run-scoped `behaviorWatchRequest` can be passed without creating a second broker entrypoint.
2. Normalize and validate that watch request before sampling begins, defaulting omitted cadence to `every_frame` and omitted `startFrameOffset` to `0`, while still rejecting unsupported selectors, later-slice fields, or zero-sample windows with machine-readable errors.
3. Sample only the requested node paths and requested properties during the bounded watch window, using every-frame or every-N-frame cadence.
4. Persist a fixed `trace.jsonl` file in the current run's output directory and add a `trace` artifact reference to the current manifest.
5. Reuse the current run-result and manifest-first workflow so agents can inspect the run result, then the manifest, then the trace artifact.

## Primary Source Areas

- `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`
- `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`
- `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- `addons/agent_runtime_harness/shared/inspection_constants.gd`
- `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`
- `specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json`
- `specs/005-behavior-watch-sampling/contracts/behavior-trace-row.schema.json`
- `tools/evidence/artifact-registry.ps1`

## Example Request Shape

Add a run-scoped watch request to an existing automation request fixture:

```json
{
  "requestId": "pong-request-watch-001",
  "scenarioId": "pong-behavior-watch",
  "runId": "pong-watch-run-001",
  "targetScene": "res://scenes/main.tscn",
  "outputDirectory": "res://evidence/automation/pong-watch-run-001",
  "artifactRoot": "examples/pong-testbed/evidence/automation/pong-watch-run-001",
  "expectationFiles": [],
  "capturePolicy": {
    "startup": true,
    "manual": true,
    "failure": true
  },
  "stopPolicy": {
    "stopAfterValidation": true
  },
  "requestedBy": "behavior-watch-fixture",
  "createdAt": "2026-04-14T00:00:00Z",
  "overrides": {
    "behaviorWatchRequest": {
      "targets": [
        {
          "nodePath": "/root/Main/Ball",
          "properties": ["position", "velocity", "collisionState", "lastCollider"]
        }
      ],
      "cadence": {
        "mode": "every_frame"
      },
      "startFrameOffset": 0,
      "frameCount": 180
    }
  }
}
```

## Recommended Validation Flow

1. Validate request fixtures for one valid Pong watch request and at least one invalid request that proves unsupported selectors or fields are rejected before a playtest starts.
2. Run the existing capability check for the example project:

```powershell
pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot examples/pong-testbed
```

3. Submit a run request through the existing automation helper:

```powershell
pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot examples/pong-testbed -RequestFixturePath examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-frame.json
```

If you want to compose a watch fragment onto an existing healthy run fixture instead of using a precomposed request file, pass `-BehaviorWatchRequestFixturePath examples/pong-testbed/harness/automation/requests/behavior-watch-valid.json`.

4. Read `harness/automation/results/run-result.json` first. If the run completed and produced a manifest, open the persisted `evidence-manifest.json`.
5. Confirm the manifest references `trace.jsonl` for the current run, exposes the normalized `appliedWatch` summary for that run, and that `trace.jsonl` contains only the requested fields for `/root/Main/Ball`.
6. Validate the manifest and referenced files:

```powershell
pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>
pwsh ./tools/tests/run-tool-tests.ps1
```

## Expected Outcomes

- Valid watch requests normalize into an applied-watch summary before sampling starts.
- Invalid watch requests fail with a machine-readable rejection and do not start capture.
- Successful watch runs persist a fixed `trace.jsonl` file for the current run only.
- The current run manifest references the trace artifact, includes the normalized `appliedWatch` summary, and lets the agent inspect the trace without reading unrelated full-scene logs.
