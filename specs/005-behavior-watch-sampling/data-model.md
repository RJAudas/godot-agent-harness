# Data Model: Behavior Watch Sampling

## Entities

### Behavior Watch Request

- **Purpose**: Defines the run-scoped bounded sampling contract supplied by the agent for slice 1 and slice 2.
- **Fields**:
  - `targets`: One or more Watch Target values.
  - `cadence`: Watch Cadence value.
  - `startFrameOffset`: Non-negative frame offset from playtest frame 0.
  - `frameCount`: Positive bounded number of frames to sample.
- **Validation Rules**:
  - Must include at least one target.
  - Must reject any selector form other than an absolute runtime node path.
  - Must reject later-slice fields such as triggers, invariants, script probes, or open-ended full-scene capture requests.
  - Must reject any configuration that would produce zero eligible samples.

### Watch Target

- **Purpose**: Identifies one runtime node and the exact fields to sample for that node.
- **Fields**:
  - `nodePath`: Absolute runtime node path, such as `/root/Main/Ball`.
  - `properties`: Non-empty list of supported watch properties.
- **Validation Rules**:
  - `nodePath` must be absolute and stable for the duration of the run.
  - `properties` must be unique within the target.
  - Unsupported properties must reject the full request.

### Watch Cadence

- **Purpose**: Defines how often the runtime sampler emits rows during the active watch window.
- **Fields**:
  - `mode`: `every_frame` or `every_n_frames`.
  - `everyNFrames`: Positive integer used only when `mode = every_n_frames`.
- **Validation Rules**:
  - `everyNFrames` must be omitted for `every_frame`.
  - `everyNFrames` must be at least `2` for `every_n_frames`.

### Applied Watch Summary

- **Purpose**: Records the normalized request the harness actually applied to the current run.
- **Fields**:
  - `runId`: Current run identifier.
  - `targets`: Normalized Watch Target values.
  - `cadence`: Normalized Watch Cadence value.
  - `startFrameOffset`: Applied start-frame offset.
  - `frameCount`: Applied bounded frame count.
  - `traceArtifact`: Fixed `trace.jsonl`.
  - `rejectedFields`: Any rejected unsupported fields when validation fails.
- **Lifecycle**:
  - `submitted` -> request loaded from run metadata
  - `validated` -> request accepted or rejected
  - `normalized` -> defaults made explicit for the active run

### Trace Sample Row

- **Purpose**: One flat JSONL line that records the sampled state for one watched target at one sampled frame.
- **Fields**:
  - `frame`: Absolute sampled frame number within the playtest.
  - `timestampMs`: Milliseconds since run start or sampling epoch used by the harness.
  - `nodePath`: Absolute runtime node path for the sampled target.
  - `position`: Optional 2-element numeric vector.
  - `velocity`: Optional 2-element numeric vector.
  - `intendedVelocity`: Optional 2-element numeric vector when exposed by the target.
  - `collisionState`: Optional string state such as `none`, `contact`, or `overlap`.
  - `lastCollider`: Optional absolute node path or other machine-readable collider identity.
  - `movementVector`: Optional 2-element numeric vector when exposed.
  - `speed`: Optional numeric scalar.
  - `overlapFrames`: Optional non-negative integer.
- **Validation Rules**:
  - Must include only fields requested for the current target.
  - Must remain flat and machine-readable with no nested opaque blobs.

### Behavior Trace Artifact

- **Purpose**: Represents the persisted `trace.jsonl` file and its manifest reference for the current run.
- **Fields**:
  - `runId`: Current run identifier.
  - `outputDirectory`: Run-scoped output directory.
  - `artifactPath`: Resolved path to `trace.jsonl`.
  - `artifactKind`: Fixed `trace`.
  - `mediaType`: Fixed `application/jsonl`.
  - `manifestPath`: Current run manifest that references the trace.

## Relationships

- One Behavior Watch Request contains one or more Watch Target values.
- One Behavior Watch Request produces one Applied Watch Summary per run.
- One Applied Watch Summary governs zero or more Trace Sample Row values during the active watch window.
- One current run manifest references one Behavior Trace Artifact when sampling succeeds.

## State Transitions

### Request Lifecycle

1. `submitted` -> request is loaded from the run request.
2. `validated` -> request is accepted or rejected with explicit machine-readable reasons.
3. `normalized` -> defaults are applied and the summary is attached to the run.
4. `sampling_active` -> runtime collects rows during the active window.
5. `persisted` -> `trace.jsonl` is written and referenced from the manifest.

### Watch Window Lifecycle

1. `before_window` -> current frame is below `startFrameOffset`.
2. `active_window` -> sampler records rows according to the configured cadence.
3. `window_complete` -> configured bounded frame count has been consumed.

## Invariants

- The first release must use absolute runtime node paths only.
- The first release must persist only `trace.jsonl` for the bounded watch output.
- The sampler must never emit rows outside the configured watch window.
- The sampler must never add unrelated nodes or unrequested fields to a row.
- A failed or missing trace must never be satisfied by an older run's artifact.
