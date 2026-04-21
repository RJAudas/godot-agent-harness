
# Research: Report Runtime Errors And Pause-On-Error

## Decision 1: Error Capture Surface

**Decision**: Capture runtime errors and warnings through the existing `EditorDebuggerPlugin` channel already owned by `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`. The runtime addon (`addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`) already sends `runtime_error` messages back to the editor; extend that path with a new `runtime_error_record` message that carries the structured fields (`script_path`, `line`, `function`, `message`, `severity`) and reuse the same channel for the new `runtime_pause` and `pause_decision` messages.

**Rationale**: The harness already owns this debugger channel for scenegraph and behavior-watch traffic. Reusing the same `EngineDebugger` capture/`EditorDebuggerSession` send pair keeps the plugin-first stack intact, avoids inventing a parallel transport, and means existing consumers (run coordinator, capability publisher, manifest writer) only have to learn new message names. Godot's debugger session already exposes the engine-reported error stream through `EngineDebugger`-side hooks; the runtime addon will subscribe with `EngineDebugger.register_message_capture` for engine-reported errors and additionally hook `get_tree().get_root().connect("script_error_log", ...)` style logs through the documented `EngineDebugger` error message API.

**Alternatives Considered**:

- A separate `EditorDebuggerPlugin` registration for runtime errors. Rejected because each plugin registration adds editor-side surface area without removing any responsibility from the existing bridge.
- Polling Godot's `OS.alert` or scraping editor stderr. Rejected because it bypasses the debugger contract, depends on editor UI behavior, and produces no structured fields.
- A GDExtension that taps the engine error reporter directly. Rejected for v1 because the existing addon-owned debugger channel meets the requirement; GDExtension is a documented escalation only when addon/debugger surfaces prove insufficient.

## Decision 2: Severity Vocabulary

**Decision**: Persist `error` and `warning` severities in the runtime-error artifact. Pause is triggered only by `error` (which includes engine-reported runtime errors, failed `assert`, `push_error`, and unhandled GDScript exceptions). `warning` (including `push_warning`) is captured but never pauses. Severities below `warning` (for example, plain `print` output) are out of scope for this artifact.

**Rationale**: Matches clarification Q2. Decoupling capture from pause keeps the agent-readable diagnostic context wide while keeping the control-flow strict: only conditions that would have been catastrophic pause the run. The existing `BUILD_DIAGNOSTIC_SEVERITY_*` constants in `addons/agent_runtime_harness/shared/inspection_constants.gd` already use the same `error`/`warning`/`unknown` vocabulary, so the new `RUNTIME_ERROR_SEVERITY_*` constants will follow that precedent.

**Alternatives Considered**:

- Capture only `error` (Option A from clarification Q2). Rejected because warnings frequently flag the cause of a later error (deprecated, shadowed name, unused variable) and the agent benefits from seeing them in the same artifact.
- Capture all `print`/`print_rich` output (Option C). Rejected because it explodes the artifact size and conflates diagnostics with general logging.

## Decision 3: Pause Mechanism

**Decision**: Use Godot's existing engine debug-pause state, raised by the harness from the runtime side in response to an observed `error`-severity record. The runtime addon will call `EngineDebugger.script_debug` semantics through the documented engine-debugger-script API to enter the same paused state the engine already uses for an unhandled error or a user `breakpoint`. The editor-side bridge holds the run, emits a `runtime_pause` message to the broker, and waits for a `pause_decision` reply (`continue` or `stop`) before sending the corresponding `EditorDebuggerSession` continue/stop request back to the runtime.

**Rationale**: The clarification deliberately restricts "pause" to the engine debugger's existing debug-pause state so the harness does not introduce a new threading model. This is the smallest plugin-first surface that produces a real engine pause the runtime respects. Letting the runtime initiate the pause (instead of the editor) ensures the runtime is already at a safe stop point before the editor records the pause notification, which simplifies the per-pause record's frame field.

**Alternatives Considered**:

- Pause from the editor side by issuing `EditorDebuggerSession.send_message("break")` on each runtime-error record. Rejected because the editor has no way to know which runtime errors should pause and which should not; severity classification belongs at the runtime where the error is observed.
- Sleep the runtime addon's `_process` loop via `OS.delay_msec` while a pause is outstanding. Rejected because it does not actually pause the engine (physics, signals, and other autoloads keep ticking) and would violate the "real engine pause" expectation the clarifications encode.

## Decision 4: Pause-Decision Transport

**Decision**: Carry the agent's `continue`/`stop` decision through the existing plugin-owned file broker (`addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`) using a new `harness/automation/requests/pause-decision.json` request file written by the agent and consumed by the broker. The broker forwards the decision through the debugger channel as `pause_decision` to the runtime, which then resumes (`EditorDebuggerSession.send_message("continue")`) or terminates the run.

**Rationale**: The brokered file path is the supported v1 control surface for capability and run requests; reusing it for pause decisions keeps the contract honest and avoids inventing a second transport. Polling the request file every editor frame while a pause is outstanding is inexpensive and matches the existing `request-editor-evidence-run.ps1` flow agents already use.

**Alternatives Considered**:

- Direct `EngineDebugger`-side socket from the agent to the running game. Rejected because it bypasses the editor and breaks the plugin-owned broker as the single control plane.
- Embed the decision in a new automation run request. Rejected because it would tie the decision to a fresh request lifecycle when the existing run is already mid-flight.

## Decision 5: Decision Timeout And Default

**Decision**: The pause-decision timeout is a harness-level configuration with a documented default of 30 seconds. When the timeout elapses without a decision, the harness applies the documented default `stop`, marks the per-pause record decision as `timeout_default_applied`, sets the manifest termination classification to `stopped_by_default_on_pause_timeout`, and writes the evidence bundle for the current run.

**Rationale**: Matches clarification Q3. A bounded timeout prevents a hung agent from leaving a paused playtest indefinitely. 30 seconds is short enough to keep the autonomous loop responsive but long enough to absorb editor activation overhead, file-broker poll cadence, and an agent that just submitted an unrelated tool call. The exact value is a configuration concern (FR-007) and not a user-facing requirement.

**Alternatives Considered**:

- Default `continue`. Rejected because it can resume into cascading errors and produce noisy artifacts before the agent has a chance to look.
- No timeout, hang indefinitely. Rejected because it leaves the harness blocked, never produces an evidence bundle, and breaks every downstream automation that watches for `run-result.json`.

## Decision 6: Outcome Artifact Shape

**Decision**: Register two new artifact kinds in `tools/evidence/artifact-registry.ps1`:

- `runtime-error-records` (file `runtime-error-records.jsonl`, media type `application/jsonl`) — one row per captured error/warning record, with the deduplication key `(script_path, line, severity)` and a rolling `repeat_count` capped at 100 with `truncated_at: 100` annotation.
- `pause-decision-log` (file `pause-decision-log.jsonl`, media type `application/jsonl`) — one row per pause notification with cause, originating script/line/function/message, the frame at which it was raised, the decision (`continued`, `stopped`, `timeout_default_applied`, `stopped_by_disconnect`, or `resolved_by_run_end`), and the decision timestamp.

The current run manifest gains a top-level `runtimeErrorReporting` section that carries the termination classification (`completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, `killed_by_harness`), an optional `lastErrorAnchor` (matching the dedup key plus message) when classification is `crashed`, and a `pauseOnErrorMode` field (`active` or `unavailable_degraded_capture_only`).

**Rationale**: JSONL matches the existing `trace.jsonl` and `input-dispatch-outcomes.jsonl` patterns, supports per-event flushing during partial-run paths, and keeps each row independently parseable. Registering both kinds in the shared registry keeps `tools/evidence/validate-evidence-manifest.ps1` aware of the new artifacts without one-off schemas. Putting the termination classification on the manifest (not on a separate artifact) makes it the first thing an agent reads from the manifest-first flow.

**Alternatives Considered**:

- Single `runtime-error.json` document. Rejected because it does not survive a playtest crash partway through writing, which is the exact case where the artifact is most valuable.
- Embed errors in `summary.json`. Rejected because it conflates two unrelated agent-facing surfaces (summary is for high-level outcome; errors are detailed diagnostic context) and would force the summary schema to grow unboundedly.

## Decision 7: Capability Advertisement

**Decision**: Extend the existing capability artifact produced by `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` with three new entries:

- `runtimeErrorCapture` — `supported: bool` plus `reason` when `false`. Always `true` for v1 because the existing debugger channel is sufficient.
- `pauseOnError` — `supported: bool` plus `reason` when `false`. Reports `false` when `EditorDebuggerSession` debug-pause is not exposed (for example, headless export builds).
- `breakpointSuppression` — `supported: bool` plus `reason` when `false`. Reports `true` when the harness can install the runtime hook that suppresses user `breakpoint` statements; `false` otherwise.

When `pauseOnError.supported = false`, the harness applies degraded mode automatically (capture-only, no pause) and stamps the manifest `pauseOnErrorMode = "unavailable_degraded_capture_only"` rather than rejecting the request.

**Rationale**: Matches clarifications Q1 and Q5. Three separate entries let agents reason about each capability independently. Following the input-dispatch precedent keeps the capability artifact internally consistent.

**Alternatives Considered**:

- Single `runtimeErrors` capability with sub-fields. Rejected because it makes `supported` ambiguous (does it mean any of the three or all of the three?) and complicates the rejection logic.
- Reject the request when `pauseOnError` is unsupported. Rejected per clarification Q5 in favor of degraded capture-only mode so agents always get error visibility.

## Decision 8: Breakpoint Suppression

**Decision**: When the runtime addon initializes, install a runtime hook that intercepts user-set GDScript `breakpoint` statements through the engine-debugger entry path and treats them as a `paused_at_user_breakpoint` cause rather than letting them trigger the editor's normal debug-pause UI. When the engine exposes no documented suppression hook on the current platform, leave breakpoints active, advertise `breakpointSuppression.supported = false` with `reason = "engine_hook_unavailable"`, and record any breakpoint-triggered pause as `paused_at_user_breakpoint` so the agent can still resolve it through the same `pause-decision` flow.

**Rationale**: Matches clarification Q1's hybrid expectation: "suppress where possible, otherwise document the assumption that users do not set manual breakpoints during agent runs." Routing breakpoints through the same pause-decision flow (with a distinct cause) means the harness never silently stalls on a user breakpoint even when suppression is unavailable — the agent can see it and choose to stop.

**Alternatives Considered**:

- Always suppress breakpoints unconditionally. Rejected because not every editor platform exposes a documented suppression hook, and silently swallowing a `breakpoint` would surprise developers who run the agent loop on a project they were debugging by hand.
- Treat user breakpoints as full pause-on-error events. Rejected because they are not errors and conflating them would corrupt the runtime-error artifact's severity statistics.

## Decision 9: Repeat-Cap Policy

**Decision**: Deduplicate runtime-error records by the key `(script_path, line, severity)`. The first occurrence is persisted verbatim. Each subsequent occurrence with the same key increments a rolling `repeat_count` field on the existing record. Once `repeat_count` reaches 100 for a key, the harness stops appending occurrences for that key and annotates the record with `truncated_at: 100`. Distinct keys are independently bounded.

**Rationale**: Matches clarification Q4. The cap protects against `_process`-level error floods without losing the first-cause anchor, and per-key dedup preserves cause diversity. A cap of 100 is large enough to characterize a flood but small enough to keep the artifact bounded for agents to read in one pass.

**Alternatives Considered**:

- Global cap on total records. Rejected because one runaway `_process` loop would crowd out unrelated errors.
- Rolling cap that drops the oldest distinct keys when a new key arrives. Rejected because it loses the first-cause anchor under sustained churn.

## Decision 10: Termination Classification

**Decision**: Manifest carries a `runtimeErrorReporting.termination` field drawn from the fixed enum `completed | stopped_by_agent | stopped_by_default_on_pause_timeout | crashed | killed_by_harness`, computed by the run coordinator from the existing `terminationStatus` field (`stopped_cleanly`, `crashed`, `shutdown_failed`, etc.) plus the new pause-decision history. When termination is `crashed`, the field also includes `lastErrorAnchor` carrying the most recent runtime-error record's dedup key plus message, or an explicit `last_error: none` marker when no runtime error was observed.

**Rationale**: Existing `automation-run-result.schema.json` `terminationStatus` already distinguishes some of these cases (`stopped_cleanly`, `crashed`, `shutdown_failed`). The new classification is a normalized, agent-facing roll-up that includes pause-decision context the existing field does not. Putting it on the manifest (not the run-result alone) keeps the manifest self-sufficient for evidence triage.

**Alternatives Considered**:

- Reuse `terminationStatus` only. Rejected because it does not distinguish `stopped_by_agent` from `killed_by_harness` and does not carry the `lastErrorAnchor`.
- Compute the classification client-side. Rejected because every agent would have to re-implement the same rules.

## Decision 11: Validation Strategy

**Decision**: Add a new `PauseDecisionRequestValidator` class in `addons/agent_runtime_harness/shared/`, modeled on `BehaviorWatchRequestValidator` and `InputDispatchRequestValidator`, that validates `harness/automation/requests/pause-decision.json` shape and rejects malformed decisions with one of the codes `missing_field | unsupported_field | invalid_decision | unknown_pause | decision_already_recorded`. Deterministic Pester coverage runs against fixture files exercising each code. Runtime-error records and pause notifications themselves are runtime-emitted and do not need a request validator; they are validated through their JSON Schema contracts at write time.

**Rationale**: Reusing the validator pattern keeps rejection style consistent across features. Fixture-driven coverage proves rejection paths without needing an editor session.

**Alternatives Considered**:

- Inline validation inside the broker. Rejected because it couples request rules to broker orchestration and makes it hard to dry-run.

## Decision 12: Deterministic Reproduction Target

**Decision**: Use a new `integration-testing/runtime-error-loop/` sandbox (per `docs/INTEGRATION_TESTING.md` and `tools/README.md`) with three fixture scenes:

- `error_on_frame.gd` — calls `push_error("seeded error")` on a known frame to verify capture and pause-on-error.
- `unhandled_exception.gd` — calls a method on a `null` reference on a known frame to verify unhandled-exception capture.
- `warning_only.gd` — calls `push_warning(...)` on a known frame to verify capture without pause.

Plus one negative fixture that reuses the Pong testbed with no errors to verify `completed` classification and an empty `runtime-error-records.jsonl`.

**Rationale**: Grounding the feature on small, single-purpose scenes makes the acceptance signal unambiguous, exercises both capture and pause paths separately, and keeps the integration sandbox small enough to redeploy quickly. The existing `integration-testing/input-dispatch/` sandbox is a working precedent.

**Alternatives Considered**:

- Reuse the Pong testbed alone. Rejected because Pong does not currently emit errors and instrumenting it to do so would muddy the fixture intent.
- Synthetic unit-only validation through Pester without a real editor run. Rejected because the user explicitly needs end-to-end pause-on-error verified against a real editor (per the durable repo rule about runtime-visible behavior).
