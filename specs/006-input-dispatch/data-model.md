
# Data Model: Runtime Input Dispatch

## Entities

### Input Dispatch Script

- **Purpose**: Run-scoped declarative list of keyboard and input-action events the agent wants the runtime to deliver through Godot's real input pipeline.
- **Fields**:
  - `events`: Ordered list of 1..256 Input Event Declaration values.
- **Validation Rules**:
  - Must contain at least one event.
  - Must not exceed 256 events (`script_too_long`).
  - Must contain only supported slice-1 fields; later-slice fields reject with `later_slice_field`.
  - Release events must be preceded by a matching press for the same identifier (`unmatched_release`).
  - Must be immutable for the duration of the run.

### Input Event Declaration

- **Purpose**: One declared press or release event anchored to the playtest's process-frame timeline.
- **Fields**:
  - `kind`: `key` or `action`.
  - `identifier`: For `kind = key`, a logical `Key` enum name (for example, `KP_ENTER`, `SPACE`, `ESCAPE`). For `kind = action`, an input-action name declared in the project's `InputMap`.
  - `phase`: `press` or `release`.
  - `frame`: Non-negative integer process-frame offset from playtest start.
  - `order`: Optional non-negative integer used to order events that share a `frame`; defaults to declared index.
- **Validation Rules**:
  - `kind` MUST be `key` or `action`; any other value rejects with `unsupported_field`.
  - For `kind = key`, `identifier` MUST resolve to a supported `Key` enum name; otherwise rejects with `unsupported_identifier`.
  - For `kind = action`, `identifier` MUST be present in the project `InputMap` at validation time; otherwise rejects with `unsupported_identifier`.
  - `phase` MUST be `press` or `release`; any other value rejects with `invalid_phase`.
  - `frame` MUST be a non-negative integer; otherwise rejects with `invalid_frame`.
  - Duplicate `(kind, identifier, phase, frame, order)` tuples reject with `duplicate_event`.
  - `physicalKeycode` and `physicsFrame` are later-slice fields and reject with `later_slice_field`.

### Applied Input Dispatch Summary

- **Purpose**: Normalized snapshot of the script the harness actually applied to the current run.
- **Fields**:
  - `runId`: Current run identifier.
  - `events`: Normalized Input Event Declaration values in dispatch order.
  - `eventCount`: Integer count of events accepted for dispatch.
  - `outcomeArtifact`: Fixed `input-dispatch-outcomes.jsonl`.
  - `rejectedFields`: Structured list of rejected field names and codes when validation fails.
- **Lifecycle**:
  - `submitted` -> script loaded from the run request `overrides.inputDispatchScript` field.
  - `validated` -> script accepted or rejected with explicit machine-readable reasons.
  - `normalized` -> defaults made explicit for the active run.

### Input Dispatch Outcome Row

- **Purpose**: One JSONL row persisted for every declared event, recording whether dispatch happened and why.
- **Fields**:
  - `runId`: Current run identifier.
  - `eventIndex`: Zero-based declared index of the event in the script.
  - `declaredFrame`: Frame offset declared by the agent.
  - `dispatchedFrame`: Integer frame at which the runtime called `Input.parse_input_event`, or `-1` when the event was not dispatched.
  - `kind`: `key` or `action`.
  - `identifier`: Logical `Key` enum name or action name.
  - `phase`: `press` or `release`.
  - `status`: Fixed enum `dispatched | skipped_frame_unreached | skipped_run_ended | failed`.
  - `reasonCode`: Optional machine-readable code when `status` is not `dispatched`.
  - `reasonMessage`: Optional short human-readable description when `status` is not `dispatched`.
- **Validation Rules**:
  - One row per declared event; rows MUST NOT be emitted for events that do not appear in the normalized script.
  - `status = dispatched` MUST be recorded only when `Input.parse_input_event` was called successfully on the declared event.
  - `status = skipped_frame_unreached` MUST be recorded when the playtest ended before reaching `declaredFrame`.
  - `status = skipped_run_ended` MUST be recorded when the playtest ended mid-script after the event's `declaredFrame` passed without dispatch.
  - `status = failed` MUST be recorded with a `reasonCode` when the runtime could not construct or parse the event.

### Input Dispatch Outcome Artifact

- **Purpose**: Represents the persisted `input-dispatch-outcomes.jsonl` file and its manifest reference for the current run.
- **Fields**:
  - `runId`: Current run identifier.
  - `outputDirectory`: Run-scoped output directory.
  - `artifactPath`: Resolved path to `input-dispatch-outcomes.jsonl`.
  - `artifactKind`: Fixed `input-dispatch-outcomes`.
  - `mediaType`: Fixed `application/jsonl`.
  - `manifestPath`: Current run manifest that references the artifact.

### Input Dispatch Capability Entry

- **Purpose**: First-class entry in the editor-evidence capability artifact that tells agents whether input dispatch is supported in the current editor and platform.
- **Fields**:
  - `supported`: Boolean.
  - `reason`: Optional short machine-readable reason string when `supported` is `false` (for example, `headless_display`, `plugin_disabled`).
  - `supportedKinds`: Fixed `["key", "action"]` in v1.
- **Validation Rules**:
  - MUST be present in every capability artifact emitted by a harness version that ships this feature.
  - When `supported` is `false`, requests carrying `inputDispatchScript` MUST reject with a machine-readable code aligned with `reason`.

## Relationships

- One Input Dispatch Script contains one or more Input Event Declaration values.
- One Input Dispatch Script produces one Applied Input Dispatch Summary per run.
- One Applied Input Dispatch Summary produces zero or more Input Dispatch Outcome Row values (one per declared event when the run reaches normalization).
- One current run manifest references one Input Dispatch Outcome Artifact when an Input Dispatch Script was accepted.
- One Input Dispatch Capability Entry governs whether an Input Dispatch Script is accepted for the current editor and platform.

## State Transitions

### Script Lifecycle

1. `submitted` -> script is loaded from the run request.
2. `validated` -> script is accepted or rejected with explicit machine-readable reasons.
3. `normalized` -> defaults are applied and the summary is attached to the run.
4. `dispatch_active` -> runtime delivers events and appends outcome rows.
5. `persisted` -> `input-dispatch-outcomes.jsonl` is written and referenced from the manifest.

### Outcome Row Lifecycle

1. `pending` -> event has not yet reached its declared frame.
2. `dispatched` -> `Input.parse_input_event` called; row written.
3. `skipped_frame_unreached` -> run ended before declared frame reached; row written at shutdown.
4. `skipped_run_ended` -> run ended after declared frame without dispatch; row written at shutdown.
5. `failed` -> event construction failed; row written immediately with `reasonCode`.

## Invariants

- The first release supports only keyboard `Key` enum identifiers and declared `InputMap` action names.
- The first release anchors frames to `Engine.get_process_frames()` offset from playtest start.
- The dispatcher MUST NOT invoke game scripts, signals, or autoloads as substitutes for `Input.parse_input_event`.
- The dispatcher MUST NOT synthesize OS-level keystrokes.
- Every declared event MUST produce exactly one outcome row in the persisted artifact before the run ends.
- The current run manifest MUST reference the current run's outcome artifact only; a failed or missing artifact MUST NEVER be satisfied by an older run's file.
