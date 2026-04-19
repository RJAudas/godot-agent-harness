# Feature Specification: Report Runtime Errors And Pause-On-Error

**Feature Branch**: `007-report-runtime-errors`  
**Created**: 2026-04-19  
**Status**: Draft  
**Input**: User description: "Capture and report runtime errors. Currently agents can build the game and see build errors, run the app and send keys and inspect the scene. We want agents to be able to run the game and then hear back if the game errors crashes or hits a breakpoint and needs to stop or continue. If the game breaks because an exception is hit/handled the agent needs to hear about the details of where the exception happened and what the exception is and then be able to stop or continue execution."

## Clarifications

### Session 2026-04-19

- Q: Which conditions should pause the running playtest and require an agent stop-or-continue decision? → A: Runtime script errors of severity `error` or higher and unhandled exceptions only; user-set GDScript `breakpoint` statements are out of scope for the first release. The harness MUST attempt to suppress engine debug-pause on `breakpoint` statements when the runtime debugger session is owned by the harness, and MUST document the assumption that users do not set manual breakpoints during agent runs when suppression is unavailable on the current editor or platform.
- Q: Which severities should be persisted as records in the runtime-error artifact? → A: Severity `error` (including unhandled exceptions and failed `assert`) and severity `warning`. Capture is decoupled from pause: only `error`-or-higher pauses, while `warning` records are persisted for diagnostic context but do not pause. Each record carries an explicit severity field so an agent can filter by severity from the artifact alone.
- Q: What default decision should the harness apply when the pause-decision timeout elapses without an agent decision? → A: `stop`. The harness terminates the run cleanly, marks the per-pause record decision as `timeout_default_applied`, and sets the manifest termination classification to `stopped_by_default_on_pause_timeout` so the agent receives a complete evidence bundle instead of a hung runtime.
- Q: How should the runtime-error artifact bound repeating records? → A: Deduplicate by `(script_path, line, severity)`. The first occurrence for a key is kept verbatim and subsequent occurrences increment a rolling `repeat_count` on that record. After `repeat_count` reaches 100 for a key, no further occurrences for that key are appended and the record is annotated `truncated_at: 100`. Distinct keys are unaffected, so cause diversity is preserved.
- Q: How should the harness behave when capability reports `pause_on_error: unsupported` and the agent submits a run? → A: Apply a documented degraded mode automatically. The harness captures runtime errors and warnings as records (read-only), does NOT pause, terminates the run with classification `completed` or `crashed` as appropriate, and stamps the manifest with `pause_on_error_mode: "unavailable_degraded_capture_only"` so the agent never assumes a pause was missed. The request is not rejected on this basis.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture Runtime Errors With Location And Cause (Priority: P1)

As a coding agent driving an editor-launched playtest, I want every runtime script error, unhandled exception, or engine-reported error that occurs after the runtime harness attaches to be captured as a stable, machine-readable record that names the originating script, line, function, and error message so I can fix the root cause without reading screen recordings or retelling the failure from a human.

**Why this priority**: Build errors are already covered before launch. The autonomous loop still breaks the moment the running game hits a runtime error (a `push_error`, a null dereference, an `assert` failure, an unhandled GDScript exception) because the agent currently learns only that "the run ended" without knowing what went wrong inside the playtest. This is the first piece of post-build visibility that makes the loop self-healing.

**Independent Test**: Launch a deterministic seeded playtest that intentionally triggers a runtime script error at a known script and line (for example, calling a missing method on a null reference) and a separate seeded playtest that emits only a `push_warning`; confirm the run completes with an evidence bundle whose manifest references a runtime-error artifact containing exactly one record per emission, each naming the originating script path, line number, function name, error message, severity (`error` or `warning`), and the run identity for the current run.

**Acceptance Scenarios**:

1. **Given** an editor-launched playtest reaches the runtime harness and then triggers a GDScript runtime error (for example, a null call, a failed `assert`, or an explicit `push_error`), **When** the run completes, **Then** the evidence bundle's manifest references a runtime-error artifact that contains a record naming the originating script path, line, function, message, and severity (`error`) for the current run.
2. **Given** the playtest emits multiple runtime errors and warnings during the same run, **When** the run completes, **Then** the runtime-error artifact contains an ordered record per emission with an explicit severity field (`error` or `warning`) and never collapses distinct records into a single generic entry.
3. **Given** a previous run already wrote a runtime-error artifact in the output location, **When** a new run executes and produces no errors or warnings, **Then** the new run's manifest reports an empty runtime-error record set for the current run rather than referencing the stale prior artifact as if it belonged to the new run.
4. **Given** the playtest emits a `push_warning` but no `error`-or-higher record, **When** the run completes, **Then** the warning is persisted as a `warning`-severity record in the runtime-error artifact and the run is NOT paused on the warning alone.

---

### User Story 2 - Notify The Agent Of A Pause-On-Error And Wait For Stop-Or-Continue (Priority: P1)

As a coding agent investigating an in-flight problem, I want the harness to pause the running playtest when it observes a runtime script error of severity `error` or higher or an unhandled exception, and surface the pause to me with the location and cause so I can decide whether to stop the run or resume execution before the playtest cascades or is torn down.

**Why this priority**: Without an explicit pause-and-decide handshake, every runtime error either silently continues into a worse state (cascading errors hide the root cause) or kills the run before the agent can capture the local context. The user's request is explicit: when the game errors, the agent must hear about it and then choose stop or continue. This is the control half of the feature; without it, the agent can read errors only after the fact and cannot intervene during the failure.

**Independent Test**: Launch a deterministic seeded playtest that raises an unhandled exception or emits a severity-`error` runtime error at a known location, observe through the brokered automation contract that the run reports a paused state with the originating script, line, function, cause kind (`runtime_error` or `unhandled_exception`), and human-readable message; submit a `continue` decision in one run and a `stop` decision in another run; confirm in both cases that the playtest acted on the decision and that the per-pause outcome (resumed or stopped) is recorded in the evidence bundle for that run.

**Acceptance Scenarios**:

1. **Given** the running playtest emits a runtime script error of severity `error` or higher, or an unhandled runtime exception, after the runtime harness has attached, **When** the harness observes the error, **Then** the playtest is paused and the agent receives a machine-readable pause notification through the same brokered automation contract used for capability and run results, and the notification names the cause kind (`runtime_error` or `unhandled_exception`), the originating script, line, function, and the error message when one is available.
2. **Given** a pause notification is outstanding for the current run, **When** the agent submits a `continue` decision, **Then** the playtest resumes execution and the per-pause record in the evidence bundle reports the decision as `continued` with a timestamp.
3. **Given** a pause notification is outstanding for the current run, **When** the agent submits a `stop` decision, **Then** the playtest terminates cleanly, the run result reflects an agent-requested stop (not a crash), and the per-pause record in the evidence bundle reports the decision as `stopped`.
4. **Given** a pause notification is outstanding and no decision is received within the harness's documented decision timeout, **When** the timeout elapses, **Then** the harness applies the documented default decision, terminates the run if the default is `stop`, and records the timeout and applied default in the per-pause record so the agent can see that no decision was honored.
5. **Given** the running project executes a user-set GDScript `breakpoint` statement, **When** the harness owns the runtime debugger session and breakpoint suppression is supported on the current editor and platform, **Then** the breakpoint MUST NOT pause the run; **Otherwise** the harness records the unsupported-suppression state in the run result so the agent can see why the run paused at a user breakpoint.

---

### User Story 3 - Capture Crashes And Abnormal Exits With Last-Known Context (Priority: P2)

As a coding agent reading post-run evidence after a run ended unexpectedly, I want the evidence bundle to identify whether the run terminated normally, was stopped by an agent decision, was killed for exceeding harness limits, or crashed (process exit without a clean shutdown) and to carry the last runtime-error context the harness was able to capture before the process went away so I can distinguish a crash from a clean exit and start debugging from a known anchor.

**Why this priority**: Pause-and-decide handles failures the harness can intercept. Some failures (engine asserts that abort the process, hard segmentation faults, native-side crashes, the OS killing the process) cannot be paused. The agent still needs to tell those apart from a normal end-of-run, and it needs the last runtime-error record the harness saw so it does not start the next iteration blind.

**Independent Test**: Run a seeded playtest that triggers a process-level crash (or simulate one by terminating the runtime mid-run) and a parallel seeded playtest that exits normally; for each, confirm the evidence manifest reports a distinct termination kind drawn from a fixed enum (`completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, `killed_by_harness`) and that the crashed run carries the last runtime-error record the harness captured before the process exited, while the completed run does not misreport a crash.

**Acceptance Scenarios**:

1. **Given** a playtest exits normally after capture completes, **When** the evidence bundle is written, **Then** the manifest reports the termination kind as `completed` and does not invent a crash record.
2. **Given** the playtest process exits without a clean shutdown handshake (a crash, an engine abort, or an OS kill), **When** the evidence bundle is written, **Then** the manifest reports the termination kind as `crashed` and includes the last runtime-error record (script, line, function, message) that the harness captured before the process went away, or an explicit `last_error: none` marker when no runtime error had been observed.
3. **Given** the playtest is terminated because the agent submitted a `stop` decision in response to a pause, **When** the evidence bundle is written, **Then** the manifest reports the termination kind as `stopped_by_agent` and not as `crashed`.

---

### User Story 4 - Advertise Runtime Error, Pause-On-Error, And Breakpoint-Suppression Capability Before Request (Priority: P3)

As a coding agent deciding how aggressively to depend on pause-on-error, I want the existing capability artifact to state whether runtime-error capture, pause-on-error stop-or-continue control, and user-set GDScript `breakpoint` suppression are supported on the current editor and platform so I can fall back to read-only error capture (or skip the run) when pause control is blocked, and so I am not surprised when a project's leftover `breakpoint` statement halts a run on an environment where suppression is unavailable.

**Why this priority**: Capability advertisement keeps the brokered automation contract honest, and the same pattern already exists for input dispatch and editor evidence. An agent that reads capability up front will not block on a pause notification that will never arrive, will not assume it can stop a pause that was never observable, and will know in advance whether user breakpoints in the project are guaranteed to be suppressed.

**Independent Test**: Query the existing capability artifact on an environment where pause-on-error and breakpoint suppression are supported and on an environment where one or both are explicitly blocked; confirm the artifact names runtime-error capture, pause-on-error, and breakpoint suppression as separate capability entries with supported/unsupported values and a machine-readable reason when unsupported, and confirm that submitting a run that depends on pause control on an unsupported environment produces a rejection or a clearly degraded run result that cites the same reason.

**Acceptance Scenarios**:

1. **Given** the harness is installed in an editor where runtime-error capture, pause-on-error, and breakpoint suppression are all supported, **When** an agent reads the capability artifact, **Then** the artifact reports all three capabilities as supported.
2. **Given** the harness is installed in an editor where pause-on-error is blocked for a known reason (for example, the platform cannot suspend the runtime safely), **When** an agent reads the capability artifact, **Then** the artifact reports pause-on-error as unsupported with a machine-readable reason while runtime-error capture may still be reported as supported.
3. **Given** the harness is installed in an editor where breakpoint suppression is unavailable, **When** an agent reads the capability artifact, **Then** the artifact reports breakpoint suppression as unsupported with a machine-readable reason and the agent is expected to assume the project does not contain user-set GDScript `breakpoint` statements during agent runs.
4. **Given** a run is requested on an environment that reports pause-on-error as unsupported, **When** the harness validates the request, **Then** it MUST NOT reject the request on that basis; instead it MUST apply a documented degraded mode in which runtime errors and warnings are captured as records (read-only), no pause is raised, and the manifest is stamped with `pause_on_error_mode: "unavailable_degraded_capture_only"` for the current run. When pause-on-error is supported, the manifest is stamped with `pause_on_error_mode: "active"`.

---

### Edge Cases

- The same runtime error fires every frame (for example, an error inside `_process`); the runtime-error artifact MUST deduplicate by `(script_path, line, severity)`, keeping the first occurrence verbatim and incrementing a rolling `repeat_count` on that record for each subsequent occurrence with the same key. Once `repeat_count` reaches 100 for a key, the harness MUST stop appending occurrences for that key and annotate the record with `truncated_at: 100`. Distinct keys are unaffected so cause diversity is preserved. Because the first error of severity `error` or higher pauses the run, the unbounded-repeat case is bounded in practice by the agent's stop decision; the cap still applies for `continue` decisions and for warnings that do not pause.
- A user-set GDScript `breakpoint` is encountered on an environment where breakpoint suppression is unavailable; the harness MUST NOT silently treat that pause as a runtime error. Instead it MUST record the pause as `paused_at_user_breakpoint` in the run result, hold the run while waiting for an agent decision, and surface the unsupported-suppression state through the capability artifact so the agent knows the project should not contain user breakpoints during agent runs.
- A pause is raised during a frame that is also processing a queued input-dispatch event from feature 006; the pause notification MUST identify the frame and the harness MUST NOT continue dispatching further queued events until the agent's decision is honored.
- A pause notification is raised but the brokered transport is not currently being polled by the agent; the harness MUST hold the pause until either the decision arrives or the documented decision timeout elapses, and MUST NOT silently resume.
- The editor or runtime detaches the debugger session while a pause is outstanding; the harness MUST treat that as a forced termination, mark the per-pause record as `stopped_by_disconnect`, and write the evidence bundle for the current run rather than leaving an empty manifest.
- The runtime emits an error during shutdown after capture has already completed; the harness MUST still attach that error to the current run's runtime-error artifact instead of dropping it because capture has ended.
- A non-GDScript runtime fault occurs (a C# exception, a GDExtension error, or a native abort); the harness MUST record what it can observe through the engine debugger pipeline and MUST mark fields it cannot resolve (for example, source line for native crashes) with explicit unknown markers rather than fabricating a script location.
- The agent submits both `continue` and `stop` decisions for the same outstanding pause; the harness MUST honor the first decision received and reject the second with a machine-readable `decision_already_recorded` reason.
- The runtime exits normally between when the pause notification is raised and when the agent's decision arrives; the harness MUST record the pause as `resolved_by_run_end` rather than acting on the late decision.
- A previous run left a runtime-error artifact and a pause-decision log in the output location; the new run MUST report only its own current-run records and MUST never attribute stale prior records to the new run.

## References *(mandatory)*

### Internal References

- README.md
- AGENTS.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/AGENT_TOOLING_FOUNDATION.md
- docs/GODOT_PLUGIN_REFERENCES.md
- specs/003-editor-evidence-loop/spec.md
- specs/004-report-build-errors/spec.md
- specs/005-behavior-watch-sampling/spec.md
- specs/006-input-dispatch/spec.md
- addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd
- addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd
- addons/agent_runtime_harness/runtime/scenegraph_runtime.gd
- addons/agent_runtime_harness/shared/inspection_constants.gd
- tools/automation/get-editor-evidence-capability.ps1
- tools/automation/request-editor-evidence-run.ps1
- tools/evidence/artifact-registry.ps1

### External References

- Godot EditorDebuggerPlugin reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EngineDebugger reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html
- Godot debugger session and `error`/`debug_enter` message documentation: https://docs.godotengine.org/en/stable/tutorials/scripting/debug/index.html
- GDScript `breakpoint` keyword: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html

### Source References

- ../godot/editor/debugger/ for editor-side debugger session and pause-resume control flow
- ../godot/core/debugger/ for engine-side error and breakpoint reporting

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST capture every runtime script error (severity `error` or higher, including unhandled exceptions and failed `assert`) and every script warning (severity `warning`, including `push_warning`) observed through the runtime harness's debugger session after attachment, and persist them as ordered, machine-readable records in a runtime-error artifact referenced from the current run's evidence manifest. Severities below `warning` (for example, plain `print` output) are out of scope for this artifact.
- **FR-002**: Each captured runtime-error record MUST identify the originating script path, line number, function name, error message, an explicit severity field drawn from `error` or `warning`, and the current run identity, and MUST mark fields the engine could not resolve (for example, native-side faults) with explicit unknown markers rather than fabricated values.
- **FR-003**: System MUST detect when the running playtest emits a runtime script error of severity `error` or higher, or raises an unhandled exception, after attachment and emit a pause notification through the existing brokered automation contract that names the cause kind (`runtime_error` or `unhandled_exception`), the originating script, line, function, and message when available. User-set GDScript `breakpoint` statements MUST NOT trigger a pause notification when breakpoint suppression is supported on the current editor and platform; when suppression is unavailable, the harness MUST record the resulting pause as `paused_at_user_breakpoint` and surface the unsupported-suppression state through the capability artifact rather than misclassifying the pause as a runtime error.
- **FR-004**: System MUST hold the playtest in a paused state while a pause notification is outstanding for the current run and MUST NOT advance frames, dispatch further queued input-dispatch events, or write capture for that pause until the agent's decision is recorded or the documented decision timeout elapses.
- **FR-005**: Users (coding agents) MUST be able to submit a `continue` or `stop` decision for an outstanding pause through the same brokered automation contract used for capability and run requests, and the harness MUST honor the first decision received for a given pause and reject any later decision for the same pause with a machine-readable `decision_already_recorded` reason.
- **FR-006**: System MUST record per-pause outcomes in the evidence bundle as ordered, machine-readable records that name the pause cause (`runtime_error`, `unhandled_exception`, or `paused_at_user_breakpoint`), the originating script/line/function/message, the decision (`continued`, `stopped`, `timeout_default_applied`, `stopped_by_disconnect`, or `resolved_by_run_end`), the decision timestamp, and the run identity for the current run.
- **FR-007**: System MUST classify run termination using a fixed enum drawn from `completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, and `killed_by_harness`, expose that classification in the evidence manifest for the current run, and never silently relabel a crash as a normal completion.
- **FR-008**: For a `crashed` termination, system MUST attach the last runtime-error record the harness captured before the process exited (or an explicit `last_error: none` marker when no runtime error had been observed) so the agent has a starting anchor for diagnosis.
- **FR-009**: System MUST guarantee that runtime-error records and per-pause records reported under a manifest belong to the current run and MUST never reference stale artifacts from a previous run as if they belonged to the new run.
- **FR-010**: System MUST extend the existing capability artifact with explicit entries for runtime-error capture, pause-on-error stop-or-continue, and user-set GDScript `breakpoint` suppression, each carrying a supported/unsupported value and a machine-readable reason when unsupported, so agents can route around blocked capability before submitting a run. When pause-on-error capability is unsupported on the current environment, system MUST NOT reject the run on that basis; instead it MUST apply a degraded mode that captures runtime-error records without raising pauses and MUST stamp the run manifest with `pause_on_error_mode` drawn from `active` (when pause-on-error is supported and used) or `unavailable_degraded_capture_only` (when pause-on-error is unsupported on the current environment).
- **FR-011**: System MUST bound the runtime-error artifact by deduplicating records on the key `(script_path, line, severity)`, keeping the first occurrence verbatim and incrementing a rolling `repeat_count` on that record for each subsequent occurrence with the same key. Once `repeat_count` reaches 100 for a key, system MUST stop appending occurrences for that key and annotate the record with `truncated_at: 100`. Distinct keys MUST remain independently captured so cause diversity is preserved.
- **FR-012**: System MUST describe which supported Godot extension points it uses (preferably the existing `EditorDebuggerPlugin` and `EngineDebugger` paths already used by the harness) and justify any escalation beyond addon, autoload, debugger, or GDExtension layers.
- **FR-013**: System MUST emit or identify the machine-readable runtime artifacts agents will inspect to validate behavior, specifically the runtime-error artifact, the per-pause decision log, the termination-kind classification on the manifest, and the new capability entries.

### Key Entities *(include if feature involves data)*

- **RuntimeErrorRecord**: A single observed runtime error or warning captured during the current run, identified by ordinal, script path, line, function, message, an explicit severity field drawn from `error` or `warning`, repeat count when deduplicated, and the run identity it belongs to.
- **PauseNotification**: An outstanding signal that the playtest has stopped, carrying the cause kind (`runtime_error`, `unhandled_exception`, or `paused_at_user_breakpoint`), the originating script/line/function/message, the frame at which it was raised, and the run identity. A pause notification is resolved by exactly one decision outcome.
- **PauseDecisionRecord**: The recorded resolution of a pause notification, drawn from `continued`, `stopped`, `timeout_default_applied`, `stopped_by_disconnect`, or `resolved_by_run_end`, with the decision timestamp and the run identity. Together with `PauseNotification` these form the per-pause records persisted in the evidence bundle.
- **RunTerminationClassification**: The single, manifest-level value drawn from `completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, or `killed_by_harness` that tells the agent how the run ended for the current run, plus the optional last-known runtime-error anchor when the value is `crashed`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a seeded playtest that triggers a runtime script error at a known script and line, the agent can identify the offending script, line, function, and message from the persisted evidence manifest alone (without opening screen recordings or asking a human) on the first read.
- **SC-002**: For a seeded playtest that emits a severity-`error` runtime error or raises an unhandled exception, the agent receives a pause notification with the cause kind and originating location through the brokered contract before the playtest cascades or is torn down, and a submitted decision (`continue` or `stop`) is observed by the harness and reflected in the per-pause record for the same run.
- **SC-003**: For a run that exits normally and a parallel run that crashes, the manifest's termination classification distinguishes the two outcomes correctly on every attempt and the crashed run's manifest carries either a last-known runtime-error anchor or an explicit `last_error: none` marker.
- **SC-004**: The runtime-error artifact for any single run never grows unbounded under a repeating error condition; an `_process`-level `push_error` produces a single deduplicated record per `(script, line, severity)` key with a `repeat_count` capped at 100 and an explicit `truncated_at: 100` marker that an agent can read without scanning every individual occurrence.
- **SC-005**: A run completes its evidence bundle with the runtime-error artifact, the per-pause decision log, the termination classification, and the capability entries present without manual inspection or hand-edited files.

## Assumptions

- The first release targets GDScript runtime errors of severity `error` or higher and unhandled GDScript exceptions observed through the existing `EditorDebuggerPlugin` and `EngineDebugger` paths the harness already uses. C# exceptions, GDExtension-side faults, and native crashes are reported on a best-effort basis with explicit unknown markers when fields cannot be resolved; first-class non-GDScript exception capture is a later slice.
- User-set GDScript `breakpoint` statements are out of scope as a pause trigger for the first release. Where the editor and platform allow, the harness suppresses breakpoint-triggered pauses while it owns the runtime debugger session. Where suppression is unavailable, the harness assumes users do not set manual breakpoints during agent runs and surfaces the unsupported-suppression state through the capability artifact so the agent can see why a `paused_at_user_breakpoint` outcome occurred.
- "Pause" means the engine debugger holds the runtime in its existing debug-pause state, raised by the harness in response to an observed runtime error; the harness does not introduce a new threading model. If the platform cannot expose that pause to the brokered contract, capability advertises pause-on-error as unsupported, the run is NOT rejected on that basis, and the harness applies the documented degraded mode (capture-only, no pause) with the manifest stamped `pause_on_error_mode: "unavailable_degraded_capture_only"`.
- The default decision applied when the pause-decision timeout elapses is `stop`, so an unattended agent never leaves a paused playtest running indefinitely. The harness MUST mark the per-pause record decision as `timeout_default_applied` and set the manifest termination classification to `stopped_by_default_on_pause_timeout`. The exact timeout value is a harness configuration concern and not a user-facing requirement.
- Build-time errors before runtime attachment remain owned by feature 004 (Report Build Errors On Run); this feature only covers errors observed after the runtime harness has attached.
- Input dispatch from feature 006 cooperates with pause: queued input-dispatch events do not advance while a pause is outstanding for the current run, and per-pause records reference the frame at which the pause was raised so input-dispatch outcomes and pause records remain reconcilable.
- The brokered automation contract used for capability, run requests, and run results (the same surface used by `tools/automation/request-editor-evidence-run.ps1`) is the supported transport for both pause notifications and pause decisions; no new agent-facing transport is introduced.
- Relevant Godot APIs can be validated against `docs/GODOT_PLUGIN_REFERENCES.md` and the local `../godot` checkout relative to the repository root.
