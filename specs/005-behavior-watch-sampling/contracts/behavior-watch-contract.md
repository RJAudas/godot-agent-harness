# Contract: Behavior Watch Sampling

## Purpose

Define the planned machine-readable contract for slice 1 and slice 2 behavior-watch requests and their bounded `trace.jsonl` output within the existing editor-evidence loop.

## Contract Surfaces

The implemented v1 control surface remains the plugin-owned file broker and the current manifest-centered evidence bundle:

- Run request: `harness/automation/requests/run-request.json`
- Run result: `harness/automation/results/run-result.json`
- Persisted manifest: current run `evidence-manifest.json`
- Persisted trace artifact: current run `trace.jsonl`

### Behavior Watch Request

- **Role**: Tells the current run which runtime node paths and properties to sample during a bounded watch window.
- **Produced by**: VS Code agent or deterministic fixture workflow.
- **Consumed by**: Editor-owned run coordinator and runtime addon.
- **Embedded in**: Existing automation run request under `overrides.behaviorWatchRequest`.
- **Minimum fields**:
  - `targets`
  - `frameCount`
- **Defaults when omitted**:
  - `cadence.mode = every_frame`
  - `startFrameOffset = 0`

### Applied Watch Summary

- **Role**: Records the normalized watch request the harness actually used for the active run.
- **Produced by**: Runtime session configuration and validation flow.
- **Consumed by**: Agents inspecting the current run metadata and manifest.
- **Minimum fields**:
  - `runId`
  - normalized `targets`
  - normalized `cadence`
  - `startFrameOffset`
  - `frameCount`
  - `traceArtifact`

### Trace Artifact

- **Role**: Flat per-sample time-series data for watched node paths only.
- **Produced by**: Runtime watch sampler.
- **Consumed by**: Agents after reading the manifest.
- **File**: Fixed `trace.jsonl`
- **Artifact reference**:
  - `kind = trace`
  - `mediaType = application/jsonl`

## Request Rules

- Only absolute runtime node paths are supported in v1.
- Only slice-1 and slice-2 fields are supported in v1.
- Requests must fail before capture begins if they include unsupported selectors, unsupported properties, later-slice fields, or zero-sample windows.
- Requests are immutable for the duration of the run.

## Trace Row Rules

- Rows must be flat JSON objects, one row per sampled target per sampled frame.
- Rows must include `frame`, `timestampMs`, and `nodePath`.
- Rows must include only the fields explicitly requested for that target.
- Vector-valued trace fields are `Vector2`-shaped in v1; `Node3D` positions and `Vector3` properties are treated as unavailable instead of widening the row schema.
- Rows must not include unrelated nodes or fields.

## Manifest Rules

- The current run manifest remains the primary evidence entrypoint.
- The manifest must reference the current run's `trace.jsonl` artifact.
- The trace artifact must be attributable to the current `runId`.
- Older trace artifacts must not satisfy a new request accidentally.
