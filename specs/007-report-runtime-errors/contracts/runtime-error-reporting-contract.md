# Runtime Error Reporting Contract

## Purpose

Define the agent-facing contract that the harness uses to publish runtime errors and warnings, raise pause-on-error notifications, accept agent decisions to stop or continue, classify run termination, and advertise capability. This contract sits on top of the existing editor-evidence loop contract (`specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`) and the existing automation run request/result contracts.

## Surfaces

### 1. Runtime Error Records artifact

- **Kind**: `runtime-error-records` (registered in `tools/evidence/artifact-registry.ps1`).
- **File**: `runtime-error-records.jsonl`.
- **Media type**: `application/jsonl`.
- **Schema**: [runtime-error-record.schema.json](runtime-error-record.schema.json).
- **Lifecycle**: One row per dedup key `(scriptPath, line, severity)`, written for the current run only; rows are deduplicated with a rolling `repeatCount` and capped at `repeatCount = 100` per key with `truncatedAt: 100` annotation. Severities `error` and `warning` are persisted; `error`-severity records pause the run, `warning`-severity records do not.
- **Manifest reference**: `runtimeErrorReporting.runtimeErrorRecordsArtifact` on the manifest points to the current run's file.

### 2. Pause Decision Log artifact

- **Kind**: `pause-decision-log` (registered in `tools/evidence/artifact-registry.ps1`).
- **File**: `pause-decision-log.jsonl`.
- **Media type**: `application/jsonl`.
- **Schema**: [pause-decision-record.schema.json](pause-decision-record.schema.json).
- **Lifecycle**: Exactly one row per pause notification, recorded at resolution. Captures the cause, originating location, raised frame, decision, decision source, and latency.
- **Manifest reference**: `runtimeErrorReporting.pauseDecisionLogArtifact` on the manifest points to the current run's file.

### 3. Manifest extension: runtimeErrorReporting

- **Location**: New top-level `runtimeErrorReporting` object on the existing evidence manifest.
- **Required fields**:
  - `termination`: Fixed enum `completed | stopped_by_agent | stopped_by_default_on_pause_timeout | crashed | killed_by_harness`.
  - `pauseOnErrorMode`: Fixed enum `active | unavailable_degraded_capture_only`.
  - `runtimeErrorRecordsArtifact`: Manifest artifact reference (kind `runtime-error-records`).
  - `pauseDecisionLogArtifact`: Manifest artifact reference (kind `pause-decision-log`).
- **Conditional fields**:
  - `lastErrorAnchor`: REQUIRED when `termination = crashed`. Either `{ "scriptPath": "...", "line": ..., "severity": "error", "message": "..." }` (the dedup-key fields plus message of the most recent runtime-error record) or the explicit marker `{ "lastError": "none" }` when no runtime error was observed before the crash.

### 4. Pause Decision Request

- **Path**: `harness/automation/requests/pause-decision.json` inside the running project.
- **Schema**: [pause-decision-request.schema.json](pause-decision-request.schema.json).
- **Lifecycle**: Written by the agent while a pause notification is outstanding; consumed by the plugin-owned broker (`addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`); deleted after consumption so a stale decision file from a prior pause is never reused.
- **Validation rejection codes**:
  - `missing_field` — required field is absent.
  - `unsupported_field` — unknown top-level field is present.
  - `invalid_decision` — `decision` is not `continue` or `stop`.
  - `unknown_pause` — `(runId, pauseId)` does not match an outstanding Pause Notification (including stale decisions from a prior run).
  - `decision_already_recorded` — a Pause Decision Record already exists for the matching `(runId, pauseId)`.

### 5. Capability extension: runtimeErrorCapture, pauseOnError, breakpointSuppression

- **Location**: Three first-class entries on the existing capability artifact emitted by `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and consumed by `tools/automation/get-editor-evidence-capability.ps1`.
- **Shape per entry**: `{ "supported": bool, "reason": "<short-machine-readable-reason>" }` (`reason` is omitted when `supported = true`).
- **Behavior bindings**:
  - `runtimeErrorCapture.supported = true` is the v1 invariant; the harness only emits this contract when capture is active.
  - `pauseOnError.supported = false` causes the harness to apply the documented degraded mode automatically (capture-only, no pause) and stamp the manifest `pauseOnErrorMode = "unavailable_degraded_capture_only"`. The run is NOT rejected on this basis.
  - `breakpointSuppression.supported = false` causes any user `breakpoint`-triggered pause to be reported with `cause = paused_at_user_breakpoint` rather than as a runtime error.

## Status And Cause Vocabulary

- **Pause cause** (on `Pause Decision Record.cause`): `runtime_error | unhandled_exception | paused_at_user_breakpoint`.
- **Decision** (on `Pause Decision Record.decision`): `continued | stopped | timeout_default_applied | stopped_by_disconnect | resolved_by_run_end`.
- **Decision source** (on `Pause Decision Record.decisionSource`): `agent | timeout_default | disconnect | run_end`.
- **Termination classification** (on `runtimeErrorReporting.termination`): `completed | stopped_by_agent | stopped_by_default_on_pause_timeout | crashed | killed_by_harness`.
- **Severity** (on `Runtime Error Record.severity`): `error | warning`.

## Default Behaviors

- **Pause-decision timeout default**: 30 seconds; on expiry the harness applies `decision = timeout_default_applied`, `decisionSource = timeout_default`, and termination `stopped_by_default_on_pause_timeout`. Exact value is harness configuration; the default exists so an unattended agent never leaves a paused playtest indefinitely.
- **Repeat cap**: `repeatCount` capped at 100 per `(scriptPath, line, severity)` key with `truncatedAt: 100` annotation; distinct keys are independently bounded.
- **Degraded mode on unsupported pause**: Capture-only; manifest stamped `pauseOnErrorMode = "unavailable_degraded_capture_only"`; never reject.

## Cross-Feature Cooperation

- **Feature 006 (Runtime Input Dispatch)**: While any Pause Notification is outstanding, the runtime MUST NOT advance queued input-dispatch events. The pause notification's `processFrame` field uses the same `Engine.get_process_frames()` baseline that feature 006 uses, so input-dispatch outcome rows and pause records remain reconcilable.
- **Feature 004 (Report Build Errors On Run)**: Build errors observed before runtime attachment remain owned by feature 004's `buildDiagnostics` field on the run result. This contract only covers errors observed after the runtime harness has attached. A run that fails build never produces a `runtimeErrorReporting` block on the manifest because no manifest is written for build-failed runs.
- **Feature 003 (Editor Evidence Loop)**: This contract extends the manifest produced by the editor evidence loop with the `runtimeErrorReporting` block; the existing artifact-reference and current-run-only invariants continue to apply.

## Stale-Artifact Protections

- Both `runtime-error-records.jsonl` and `pause-decision-log.jsonl` are written under the current run's output directory only; the manifest's `runtimeErrorRecordsArtifact` and `pauseDecisionLogArtifact` references point at current-run files only.
- `harness/automation/requests/pause-decision.json` is consumed-and-deleted by the broker so a stale decision from a prior pause is never reused.
- `runId` and `pauseId` are required on every record and request; mismatches reject with `unknown_pause`.
