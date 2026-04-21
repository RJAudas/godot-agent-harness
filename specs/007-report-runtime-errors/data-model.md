
# Data Model: Report Runtime Errors And Pause-On-Error

## Entities

### Runtime Error Record

- **Purpose**: One observed runtime error or warning captured during the current run, persisted as a JSONL row in the runtime-error artifact.
- **Fields**:
  - `runId`: Current run identifier.
  - `ordinal`: Zero-based index of the first occurrence of this dedup key in the current run, in capture order.
  - `scriptPath`: Originating script `res://` path, or `unknown` marker for native faults the engine could not resolve.
  - `line`: Originating line number (positive integer), or `null` when unknown.
  - `function`: Originating function name, or `null` when unknown.
  - `message`: Engine-reported error or warning message text.
  - `severity`: Fixed enum `error | warning`.
  - `firstSeenAt`: ISO-8601 timestamp of the first occurrence.
  - `lastSeenAt`: ISO-8601 timestamp of the most recent occurrence (updated on each repeat).
  - `repeatCount`: Integer count of total occurrences observed for this dedup key (clamped at 100).
  - `truncatedAt`: Optional integer; present and equal to 100 when `repeatCount` reached the cap and further occurrences were dropped.
- **Validation Rules**:
  - Records MUST be deduplicated on the key `(scriptPath, line, severity)`. The first occurrence is persisted verbatim; subsequent occurrences increment `repeatCount` and update `lastSeenAt` on the existing row.
  - `repeatCount` MUST NOT exceed 100; once it reaches 100, the harness MUST set `truncatedAt: 100` and MUST stop appending occurrences for that key.
  - `severity = error` MUST be used for engine-reported runtime errors, failed `assert`, `push_error`, and unhandled GDScript exceptions.
  - `severity = warning` MUST be used for `push_warning` and engine-reported script warnings.
  - Fields the engine could not resolve MUST be set to the explicit unknown markers (`scriptPath = "unknown"` or `line = null`); they MUST NOT be fabricated.
  - Records MUST be tagged with the current `runId` and MUST NOT reference any prior run.

### Runtime Error Cause

- **Purpose**: A first-class cause vocabulary for any condition that pauses the run.
- **Values**:
  - `runtime_error` — A captured error-severity record triggered the pause.
  - `unhandled_exception` — A GDScript runtime exception escaped its frame and was not handled.
  - `paused_at_user_breakpoint` — The engine entered debug-pause because of a user-set GDScript `breakpoint` statement on an environment where suppression is unavailable.
- **Validation Rules**:
  - All cause values are mutually exclusive for a single pause notification.
  - `paused_at_user_breakpoint` MUST only appear on environments where capability advertises `breakpointSuppression.supported = false`.

### Pause Notification

- **Purpose**: An outstanding signal that the playtest has stopped at a runtime-error or unhandled-exception condition (or, on environments without breakpoint suppression, at a user `breakpoint`), awaiting an agent decision.
- **Fields**:
  - `runId`: Current run identifier.
  - `pauseId`: Stable identifier for this pause within the current run (monotonically increasing integer).
  - `cause`: One of the Runtime Error Cause values.
  - `scriptPath`: Originating script path, or `unknown`.
  - `line`: Originating line number, or `null`.
  - `function`: Originating function name, or `null`.
  - `message`: Originating error message when available; empty string for `paused_at_user_breakpoint` when no message exists.
  - `processFrame`: Process-frame ordinal at which the pause was raised (sourced from `Engine.get_process_frames()` baseline used by feature 006).
  - `raisedAt`: ISO-8601 timestamp when the pause was emitted.
- **Lifecycle**:
  1. `outstanding` — Notification emitted; harness is holding the runtime in debug-pause; no decision has been received.
  2. `resolved` — One Pause Decision Record has been recorded for this `pauseId`. Subsequent decisions are rejected with `decision_already_recorded`.
- **Validation Rules**:
  - Exactly one Pause Decision Record MUST exist per Pause Notification by the time the run terminates.
  - While a Pause Notification is `outstanding`, the runtime MUST NOT advance frames, dispatch further queued input-dispatch events, or write capture for that pause.

### Pause Decision Request

- **Purpose**: The agent-supplied decision (`continue` or `stop`) for an outstanding pause, written to `harness/automation/requests/pause-decision.json` and consumed by the broker.
- **Fields**:
  - `runId`: Current run identifier.
  - `pauseId`: Pause identifier the decision applies to.
  - `decision`: Fixed enum `continue | stop`.
  - `submittedBy`: Caller identifier (mirrors `requestedBy` on the run request).
  - `submittedAt`: ISO-8601 timestamp.
- **Validation Rules**:
  - `runId` MUST match the current run; mismatched values reject with `unknown_pause`.
  - `pauseId` MUST match an outstanding Pause Notification; otherwise reject with `unknown_pause`.
  - `decision` MUST be `continue` or `stop`; other values reject with `invalid_decision`.
  - When a Pause Decision Record already exists for the matching `(runId, pauseId)`, reject with `decision_already_recorded`.
  - Missing required fields reject with `missing_field`; unknown top-level fields reject with `unsupported_field`.

### Pause Decision Record

- **Purpose**: The recorded resolution of one Pause Notification, persisted as a JSONL row in the pause-decision-log artifact.
- **Fields**:
  - `runId`: Current run identifier.
  - `pauseId`: Pause identifier this record resolves.
  - `cause`: Copied from the Pause Notification.
  - `scriptPath`, `line`, `function`, `message`: Copied from the Pause Notification.
  - `processFrame`: Copied from the Pause Notification.
  - `decision`: Fixed enum `continued | stopped | timeout_default_applied | stopped_by_disconnect | resolved_by_run_end`.
  - `decisionSource`: Fixed enum `agent | timeout_default | disconnect | run_end`.
  - `recordedAt`: ISO-8601 timestamp.
  - `latencyMs`: Integer milliseconds between `raisedAt` and `recordedAt`.
- **Validation Rules**:
  - Exactly one Pause Decision Record MUST exist per Pause Notification.
  - `decision = continued` MUST come from `decisionSource = agent` only.
  - `decision = stopped` MAY come from `decisionSource = agent` or, when applicable, the explicit harness path; `decisionSource = agent` is the normal value.
  - `decision = timeout_default_applied` MUST come from `decisionSource = timeout_default` only.
  - `decision = stopped_by_disconnect` MUST come from `decisionSource = disconnect` only and MUST be recorded when the debugger session detaches while the pause is outstanding.
  - `decision = resolved_by_run_end` MUST come from `decisionSource = run_end` only and MUST be recorded when the runtime exits normally between `raisedAt` and the agent's decision arrival.

### Run Termination Classification

- **Purpose**: Manifest-level field that tells the agent how the run ended for the current run, plus the optional last-known runtime-error anchor when the run crashed.
- **Fields**:
  - `termination`: Fixed enum `completed | stopped_by_agent | stopped_by_default_on_pause_timeout | crashed | killed_by_harness`.
  - `pauseOnErrorMode`: Fixed enum `active | unavailable_degraded_capture_only`.
  - `lastErrorAnchor`: Optional object present only when `termination = crashed`; either an object with the dedup-key fields plus message (`scriptPath`, `line`, `severity`, `message`) or the explicit `{ "lastError": "none" }` marker.
  - `runtimeErrorRecordsArtifact`: Manifest reference (kind `runtime-error-records`).
  - `pauseDecisionLogArtifact`: Manifest reference (kind `pause-decision-log`).
- **Validation Rules**:
  - `termination` MUST be set on every manifest emitted by a harness version that ships this feature.
  - `pauseOnErrorMode = unavailable_degraded_capture_only` MUST be set when capability advertises `pauseOnError.supported = false` for the current run.
  - `lastErrorAnchor` MUST be present iff `termination = crashed`.
  - `runtimeErrorRecordsArtifact` and `pauseDecisionLogArtifact` MUST reference current-run files only; stale artifacts from prior runs MUST NOT be referenced.

### Runtime Error Reporting Capability

- **Purpose**: Three first-class entries in the editor-evidence capability artifact that tell agents whether runtime-error capture, pause-on-error, and breakpoint suppression are supported in the current editor and platform.
- **Fields**:
  - `runtimeErrorCapture.supported`: Boolean. Always `true` in v1.
  - `runtimeErrorCapture.reason`: Optional short machine-readable reason when `supported = false`.
  - `pauseOnError.supported`: Boolean.
  - `pauseOnError.reason`: Optional short machine-readable reason when `supported = false` (for example, `headless_export_no_debug_pause`, `plugin_disabled`).
  - `breakpointSuppression.supported`: Boolean.
  - `breakpointSuppression.reason`: Optional short machine-readable reason when `supported = false` (for example, `engine_hook_unavailable`).
- **Validation Rules**:
  - All three entries MUST be present in every capability artifact emitted by a harness version that ships this feature.
  - When `pauseOnError.supported = false`, the harness MUST NOT reject the run on that basis; it MUST apply the documented degraded mode and stamp the manifest `pauseOnErrorMode = "unavailable_degraded_capture_only"`.
  - When `breakpointSuppression.supported = false`, the harness MUST still record any breakpoint-triggered pause as `paused_at_user_breakpoint` and route it through the same pause-decision flow.

## Relationships

- One run produces zero or more Runtime Error Records (deduplicated by `(scriptPath, line, severity)`, capped at 100 per key).
- One run produces zero or more Pause Notifications. Each Pause Notification resolves to exactly one Pause Decision Record.
- The Pause Decision Request entity is a transient inbound message; the Pause Decision Record is the persisted resolution.
- One run produces exactly one Run Termination Classification on the manifest.
- The Runtime Error Reporting Capability governs whether pause is raised for the current run and whether breakpoint suppression is active.

## State Transitions

### Runtime Error Record Lifecycle

1. `observed` — Engine debugger reports an error or warning.
2. `deduplicated` — Existing row for the same dedup key is updated (or a new row is appended for a new key).
3. `truncated` — Optional terminal state for a key whose `repeatCount` reached 100; further occurrences for that key are silently dropped after the row is annotated `truncated_at: 100`.
4. `persisted` — Row is flushed to `runtime-error-records.jsonl` (rows are flushed at least at run shutdown and SHOULD be flushed eagerly on each new key or on `truncated` transition).

### Pause Notification Lifecycle

1. `outstanding` — Notification emitted, runtime is in debug-pause, broker is polling for `pause-decision.json`.
2. `resolved` — A Pause Decision Record has been recorded; the runtime continues or terminates as instructed.
3. `expired` — Decision timeout elapsed without a decision; recorded as `timeout_default_applied` (effectively `stopped`).
4. `disconnected` — Debugger session detached while outstanding; recorded as `stopped_by_disconnect`.
5. `superseded_by_run_end` — Runtime exited normally between `raisedAt` and decision arrival; recorded as `resolved_by_run_end`.

### Run Termination Classification Lifecycle

1. `pending` — Run is in flight; classification is not yet computed.
2. `computed` — Run coordinator computes the classification at shutdown by combining the existing `terminationStatus`, the pause-decision history, and the harness-internal kill state.
3. `stamped` — Classification is written to the manifest `runtimeErrorReporting.termination` field; manifest is finalized.

## Invariants

- Every Pause Notification has exactly one Pause Decision Record by the time the manifest is stamped.
- Every Runtime Error Record carries the current `runId`; no record from a prior run appears in the current manifest.
- `pauseOnErrorMode` is `active` iff capability advertises `pauseOnError.supported = true`; `unavailable_degraded_capture_only` otherwise.
- `lastErrorAnchor` is present iff `termination = crashed`.
- The runtime does not advance frames or dispatch queued input-dispatch events while any Pause Notification is `outstanding`.
- A pause raised by `paused_at_user_breakpoint` MUST NOT increment any Runtime Error Record's `repeatCount`; user breakpoints are not errors.
