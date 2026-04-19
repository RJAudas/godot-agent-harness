# Contract: Runtime Input Dispatch

## Purpose

Define the machine-readable contract for v1 input-dispatch scripts and their persisted `input-dispatch-outcomes.jsonl` artifact within the existing editor-evidence loop.

## Contract Surfaces

The v1 control surface remains the plugin-owned file broker and the current manifest-centered evidence bundle:

- Run request: `harness/automation/requests/run-request.json`
- Run result: `harness/automation/results/run-result.json`
- Persisted manifest: current run `evidence-manifest.json`
- Persisted outcome artifact: current run `input-dispatch-outcomes.jsonl`
- Capability artifact: current editor-evidence capability JSON

### Input Dispatch Script

- **Role**: Tells the current run which keyboard and input-action events to deliver, in what phase, and at which process-frame offsets.
- **Produced by**: VS Code agent or deterministic fixture workflow.
- **Consumed by**: Editor-owned run coordinator, shared validator, and runtime addon.
- **Embedded in**: Existing automation run request under `overrides.inputDispatchScript`.
- **Minimum fields**:
  - `events` (1..256 declarations)
- **Each event contains**:
  - `kind` (`key` or `action`)
  - `identifier` (logical `Key` enum name for `key`; declared `InputMap` action name for `action`)
  - `phase` (`press` or `release`)
  - `frame` (non-negative process-frame offset from playtest start)
  - Optional `order` for intra-frame tie-breaking

### Applied Input Dispatch Summary

- **Role**: Records the normalized script the harness actually used for the active run.
- **Produced by**: Runtime session configuration and validation flow.
- **Consumed by**: Agents inspecting the current run metadata and manifest.
- **Minimum fields**:
  - `runId`
  - normalized `events`
  - `eventCount`
  - `outcomeArtifact`

### Outcome Artifact

- **Role**: Flat per-event record of dispatch outcomes for the current run.
- **Produced by**: Runtime dispatcher and artifact writer.
- **Consumed by**: Agents after reading the manifest.
- **File**: Fixed `input-dispatch-outcomes.jsonl`
- **Artifact reference**:
  - `kind = input-dispatch-outcomes`
  - `mediaType = application/jsonl`

### Capability Entry

- **Role**: First-class advertisement of input-dispatch support in the current editor and platform.
- **Produced by**: Editor addon capability publisher.
- **Consumed by**: VS Code agents and the `tools/automation/get-editor-evidence-capability.ps1` helper.
- **Minimum fields**:
  - `supported` (boolean)
  - optional `reason` (machine-readable string when unsupported)
  - `supportedKinds` (fixed `["key", "action"]` in v1)

## Request Rules

- Only logical `Key` enum names are supported for `kind = key` in v1. `physicalKeycode` MUST reject with `later_slice_field`.
- Only declared `InputMap` actions are supported for `kind = action`. Unknown action names MUST reject with `unsupported_identifier`.
- Release events without a matching prior press for the same identifier MUST reject with `unmatched_release`.
- Scripts over 256 events MUST reject with `script_too_long`.
- Requests carrying any of `mouse`, `touch`, `gamepad`, `recordedReplay`, `physicalKeycode`, or `physicsFrame` MUST reject with `later_slice_field`.
- Requests submitted while the capability advertises `supported = false` MUST reject with a machine-readable code aligned with the capability `reason`.
- Requests are immutable for the duration of the run.

## Outcome Row Rules

- Every declared event MUST produce exactly one outcome row in the persisted artifact before the run ends.
- `status` MUST be one of `dispatched`, `skipped_frame_unreached`, `skipped_run_ended`, or `failed`.
- `dispatchedFrame` MUST equal the frame at which `Input.parse_input_event` was called when `status = dispatched`, and MUST be `-1` otherwise.
- Rows MUST be flat and machine-readable. No nested opaque blobs.
- The current run manifest MUST reference the current run's outcome artifact only; stale artifacts from prior runs MUST NEVER be reused.

## Dispatch Rules

- The runtime MUST call `Input.parse_input_event()` with a constructed `InputEventKey` for `kind = key` events and with a constructed `InputEventAction` for `kind = action` events.
- The runtime MUST NOT synthesize OS-level keystrokes.
- The runtime MUST NOT call game scripts, signals, or autoloads as substitutes for `Input.parse_input_event`.
- The runtime MUST anchor event delivery to process frames counted from the first post-boot `_process()` callback.

## Out of Scope for V1

- Mouse, touch, and gamepad events.
- Recording and replaying real human input.
- Physical scancode dispatch.
- Physics-frame anchoring.

These fields MUST reject at validation with `later_slice_field` so agents receive an unambiguous machine-readable signal that they are deferred.
