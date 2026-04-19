# Feature Specification: Runtime Input Dispatch

**Feature Branch**: `006-input-dispatch`  
**Created**: 2026-04-19  
**Status**: Draft  
## Clarifications

### Session 2026-04-19

- Q: Which keyboard key identifier scheme should the first release support? → A: Godot logical `Key` enum names only (e.g. `KP_ENTER`, `ENTER`, `SPACE`), mapped to `InputEventKey.keycode`; physical scancodes are out of scope.
- Q: Which frame reference should target frame offsets use? → A: Process frames (`_process` / `Engine.get_process_frames()`); physics-frame anchoring is a later-slice field.
- Q: Which outcome status vocabulary should the per-event artifact use? → A: Fixed four-value enum: `dispatched`, `skipped_frame_unreached`, `skipped_run_ended`, `failed`.
- Q: How should a release event with no matching prior press in the same script be handled? → A: Reject at validation time with a machine-readable `unmatched_release` error before launch.
- Q: What is the maximum number of events per input-dispatch script? → A: 256 events per script; scripts exceeding this cap are rejected before launch with a machine-readable `script_too_long` error.

**Input**: User description: "Build a plugin-first runtime input dispatch feature for the Godot Agent Harness that lets an agent script a deterministic sequence of keyboard and input-action events to be delivered to an editor-launched playtest through Godot's real input pipeline, so that input-driven behavior such as a title-screen accept handler, an action-remapped key, or an _unhandled_input crash can be reproduced through the brokered automation contract instead of through autoload shims, direct method calls, or OS-level keystroke injection that bypass the input pipeline. The agent declares the script up front as part of the same run request that already carries the run identifiers, target scene, capture policy, and optional behavior watch, naming each event by its action or by a supported keyboard key together with whether it is a press or a release, and anchoring the events to the playtest's frame timeline so the sequence is reproducible from one run to the next. The harness validates the script before launch with the same strict, machine-readable rejection model used for behavior watch requests, advertises whether input dispatch is supported on the current editor and platform through the existing capability artifact, delivers each accepted event from the runtime side using Godot's real input dispatch APIs at the requested frame, and records the outcome of every dispatched event as a stable machine-readable artifact referenced from the manifest-centered evidence bundle alongside the existing scenegraph snapshot, diagnostics, summary, and behavior trace artifacts. Mouse, touch, gamepad, and recording of real human input for replay are out of scope for the first release; keyboard keys and input actions only, end-to-end through launch, dispatch, capture, persist, and shutdown. The concrete reproduction target is the Pong testbed crash described in issue #12 (numpad Enter on the title screen)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declare A Deterministic Input Script (Priority: P1)

As a coding agent, I want to declare an explicit ordered sequence of keyboard and input-action press/release events anchored to specific playtest frames so the harness either accepts a fully normalized script before launch or rejects it with a machine-readable reason, without ever partially executing an underspecified script.

**Why this priority**: The reproduction story only works if the request contract is deterministic and strict. An accepted script must define exactly which events fire at which frames, and anything ambiguous or unsupported must be rejected before a playtest begins so agents never confuse partial input with genuine gameplay evidence.

**Independent Test**: Validate a seeded valid input-dispatch script (for example, a numpad-Enter press/release pair targeting the Pong title screen) and several invalid scripts (unknown key, unknown action, missing phase, negative frame, out-of-order frames, later-slice mouse/touch/gamepad/replay fields) without starting a playtest. Confirm the valid script is normalized into an explicit event list ordered by frame and the invalid scripts fail with machine-readable rejections that name the offending field and reason.

**Acceptance Scenarios**:

1. **Given** a run request that includes an input-dispatch script listing a numpad-Enter press at frame N and a numpad-Enter release at frame N+1, **When** the harness prepares the next editor-launched playtest, **Then** it records an explicit normalized script that pairs each event with its run identity, frame offset, event kind (keyboard key or input action), identifier, and phase (press or release).
2. **Given** a script event omits the phase, **When** the request is validated, **Then** the harness rejects the request with a machine-readable error naming the missing phase field for that event index.
3. **Given** a script references a keyboard key name that is not in the supported set, an input action that is not declared in the project, a negative frame offset, or a later-slice field such as mouse, touch, gamepad, or recorded-replay input, **When** the request is validated, **Then** the harness rejects the entire request before launch with a machine-readable unsupported reason and does not apply a partial script.

---

### User Story 2 - Dispatch Events Through The Real Input Pipeline (Priority: P1)

As a coding agent investigating an `_unhandled_input` crash or an input-driven UI handler, I want the harness to deliver each accepted event at the requested frame through Godot's real input pipeline so the same code paths that handle real user input run during the automated playtest, including action remapping, input-event propagation, and any handlers that rely on `Input.is_action_*` or `_unhandled_input`.

**Why this priority**: The feature only earns its name if events reach the same input pipeline a real user would trigger. Autoload shims, direct method calls, or OS-level keystroke injection would not reproduce issue #12 reliably because they either skip engine input mapping or depend on the host window focus state, which is exactly what the harness is meant to remove from the reproduction loop.

**Independent Test**: Run a deterministic Pong title-screen playtest with an input-dispatch script that presses and releases the numpad-Enter key at a fixed frame. Confirm the runtime observes the event through the normal input pipeline (the same handler path a real keypress would reach), that the reported dispatch frame matches the requested frame within the harness's deterministic tolerance, and that any resulting crash or accept-handler transition is captured in the evidence bundle for the current run.

**Acceptance Scenarios**:

1. **Given** an accepted input-dispatch script is attached to an editor-launched playtest, **When** the playtest reaches each requested frame, **Then** the corresponding event is delivered through the engine's real input dispatch path so that normal input handlers (including `_unhandled_input` and action handlers) observe it as they would a real keypress or action event.
2. **Given** an accepted script defines a press followed by a release of the same key or action, **When** the run executes, **Then** both events are delivered in the declared order and the release event reverses the pressed state rather than leaving the input in a stuck-held state at shutdown.
3. **Given** an accepted script targets the Pong title-screen accept handler with numpad-Enter, **When** the run executes, **Then** the playtest reproduces the title-screen behavior (including any `_unhandled_input` crash described in issue #12) without needing any autoload shim, direct method call, or OS-level keystroke injection.

---

### User Story 3 - Persist Per-Event Outcomes In The Evidence Bundle (Priority: P2)

As a coding agent reading post-run evidence, I want every dispatched event and every skipped or failed event to be recorded as a stable machine-readable artifact referenced from the manifest so I can confirm from the manifest alone which events actually reached the runtime, at which frame they were dispatched, and how the runtime reacted, without inferring any of that from screen recordings or ad-hoc logs.

**Why this priority**: Input reproduction is only trustworthy when each event has an auditable outcome. Without a persisted per-event outcome record, an agent cannot distinguish "event never dispatched" from "event dispatched but handler did nothing" from "event dispatched and caused the crash under investigation".

**Independent Test**: Persist a completed input-dispatch run for the Pong title-screen scenario. Open only the manifest, confirm it references the input-dispatch outcome artifact for the current run, open that artifact, and confirm every declared event has an outcome row that identifies its frame, identifier, phase, and status (dispatched, skipped, or failed) for this run, with no stale rows from earlier runs.

**Acceptance Scenarios**:

1. **Given** an input-dispatch run completes successfully, **When** the evidence bundle is written, **Then** the manifest references the input-dispatch outcome artifact and the artifact contains one stable machine-readable row per declared event with the event's frame, kind, identifier, phase, dispatched-frame, and status (drawn from `dispatched | skipped_frame_unreached | skipped_run_ended | failed`) for the current run.
2. **Given** an accepted event cannot be dispatched because its target frame was never reached, the playtest exited early, or the runtime rejected the event at delivery time, **When** the run completes, **Then** the outcome artifact reports that event with the appropriate non-`dispatched` status (`skipped_frame_unreached`, `skipped_run_ended`, or `failed`) and a machine-readable reason instead of claiming success.
3. **Given** an earlier run already produced an input-dispatch outcome artifact in the output location, **When** a new input-dispatch run executes, **Then** the harness reports only the outcomes produced for the current run and never attributes a stale artifact from a previous run to the new run.

---

### User Story 4 - Advertise Input Dispatch Capability Before Request (Priority: P3)

As a coding agent deciding whether to issue an input-dispatch request at all, I want the existing capability artifact to explicitly state whether input dispatch is supported on the current editor and platform so I can route to an alternative reproduction strategy when the capability is blocked instead of sending a request that will be rejected at launch.

**Why this priority**: Capability advertisement keeps the brokered automation contract honest. An agent that can read capability up front will not waste a run by submitting a script the current environment cannot honor, and operators who cannot expose input dispatch on their platform will see a clear unsupported signal instead of a silent failure.

**Independent Test**: Query the existing capability artifact on an environment where input dispatch is supported and on an environment where it is explicitly unsupported. Confirm the artifact names input dispatch as a first-class capability entry with a supported/unsupported value and a machine-readable reason when unsupported, and confirm that submitting a request on an unsupported environment produces a rejection that cites the same reason.

**Acceptance Scenarios**:

1. **Given** the harness is installed in an editor where input dispatch is supported, **When** an agent reads the capability artifact, **Then** the artifact reports input dispatch as a supported capability.
2. **Given** the harness is installed in an editor where input dispatch is blocked for a known reason, **When** an agent reads the capability artifact, **Then** the artifact reports input dispatch as unsupported with a machine-readable reason.
3. **Given** an agent submits an input-dispatch request on an environment that reports input dispatch as unsupported, **When** the harness validates the request, **Then** it rejects the request with a machine-readable reason consistent with the capability artifact rather than partially launching the run.

---

### Edge Cases

- A script defines two events targeting the same frame; the harness must define a deterministic intra-frame ordering (declared order within that frame) instead of letting delivery order vary between runs.
- A script declares a press event without a matching release before the run ends; the harness must still report the unreleased state in the outcome artifact so the agent sees a "held at shutdown" signal rather than silent input leakage.
- A script declares a release event with no matching prior press in the declared order for the same identifier; the harness MUST reject the script at validation time with a machine-readable `unmatched_release` error and MUST NOT dispatch any events from that script.
- A script anchors events beyond the playtest's available frame window (for example, a frame that is never reached before the playtest exits); those events must be reported as non-dispatched with an explicit reason instead of silently dropped.
- A script names an input action that is not declared in the running project; the harness must reject the request with an explicit unsupported-action error rather than dispatching a no-op.
- A script uses a logical `Key` enum name that is valid in the supported key set but is not physically present on the current keyboard layout; the harness must still dispatch through the engine input pipeline using the declared logical keycode so the reproduction is stable across hosts.
- A script includes a later-slice input kind (mouse, touch, gamepad) or a recorded-replay payload; the harness must reject the request with a later-slice unsupported reason instead of partially executing the supported subset.
- The playtest crashes or exits before all events are dispatched; the outcome artifact must still be written with partial-run status so the evidence bundle is not empty for the current run.
- A prior run already wrote an input-dispatch outcome artifact in the output location; the new run must not reuse that older file as the current run's evidence.

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
- addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd
- addons/agent_runtime_harness/shared/inspection_constants.gd
- addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd
- addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd
- addons/agent_runtime_harness/runtime/scenegraph_runtime.gd
- addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd
- tools/evidence/artifact-registry.ps1
- tools/automation/get-editor-evidence-capability.ps1
- tools/automation/request-editor-evidence-run.ps1

### External References

- Godot Input class reference: https://docs.godotengine.org/en/stable/classes/class_input.html
- Godot InputEvent class reference: https://docs.godotengine.org/en/stable/classes/class_inputevent.html
- Godot InputEventKey class reference: https://docs.godotengine.org/en/stable/classes/class_inputeventkey.html
- Godot InputEventAction class reference: https://docs.godotengine.org/en/stable/classes/class_inputeventaction.html
- Godot InputMap class reference: https://docs.godotengine.org/en/stable/classes/class_inputmap.html
- Godot input examples tutorial: https://docs.godotengine.org/en/stable/tutorials/inputs/input_examples.html
- Godot unhandled input tutorial: https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
- Godot EngineDebugger class reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html

### Source References

- No `../godot` source files were inspected for this specification; the scope is grounded in repository documentation plus the existing plugin-first runtime transport, request validation, and evidence bundle contracts already present in this repository.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow an agent to submit a machine-readable input-dispatch script as part of the same run request that already carries run identifiers, target scene, capture policy, and optional behavior watch, without introducing a second out-of-band request channel.
- **FR-002**: System MUST allow an input-dispatch script to declare an ordered list of events where each event identifies its kind (keyboard key or input action), its identifier (a supported Godot logical `Key` enum name such as `KP_ENTER`, `ENTER`, or `SPACE` for keyboard events, or a declared input-action name for action events), its phase (press or release), and its target frame offset relative to the playtest's frame timeline.
- **FR-002a**: System MUST reject keyboard events whose identifier is not a Godot logical `Key` enum name (for example, raw physical scancodes, OS-specific virtual-key codes, or character literals) with a machine-readable unsupported-identifier error, and MUST treat physical scancode dispatch as an explicit later-slice field.
- **FR-003**: System MUST anchor every accepted event to the playtest's own process-frame timeline (the `_process` / `Engine.get_process_frames()` ordinal counted from playtest start) so that a given accepted script produces the same event order and same target-frame anchoring across repeated runs of the same scenario. Physics-frame anchoring is an explicit later-slice field and MUST be rejected if requested in the first release.
- **FR-004**: System MUST define a deterministic intra-frame ordering rule for multiple events sharing the same target frame so delivery order within a frame does not vary between runs.
- **FR-005**: System MUST validate and normalize every input-dispatch script before launch using a strict machine-readable rejection model consistent with the existing behavior-watch request validation, rejecting unsupported fields, unsupported keys or actions, malformed phases, invalid frame offsets, out-of-scope later-slice input kinds, and scripts that exceed the first-release cap of 256 events with a machine-readable `script_too_long` error, before the playtest begins.
- **FR-006**: System MUST reject input-dispatch requests that include mouse, touch, gamepad, or recorded-real-human-input replay fields with a machine-readable later-slice or unsupported-kind reason instead of partially executing the supported subset.
- **FR-007**: System MUST persist or expose an applied-input-dispatch summary that tells the agent which normalized script the harness actually used for the run, mirroring the applied-watch pattern used by behavior-watch sampling.
- **FR-008**: System MUST deliver each accepted event from the runtime side through Godot's real input dispatch path so the same engine code that processes a genuine keypress or input-action event handles the dispatched event, including action remapping, `_input`, `_unhandled_input`, and `Input.is_action_*` state queries.
- **FR-009**: System MUST NOT reproduce input through autoload shims, direct method calls into game scripts, or OS-level keystroke injection as a substitute for the engine input pipeline.
- **FR-010**: System MUST deliver press and release events for the same key or action in the declared order and MUST leave no dispatched key or action in a held state past run shutdown without recording that unreleased state explicitly.
- **FR-010a**: System MUST reject any input-dispatch script that contains a release event for a key or action without a matching prior press event for the same identifier earlier in the declared order, using a machine-readable `unmatched_release` validation error before launch.
- **FR-011**: System MUST record each declared event's outcome as a stable machine-readable row that includes at minimum the current run identity, declared frame, kind, identifier, phase, dispatched-frame (or null if not dispatched), and status drawn from the fixed enum `dispatched | skipped_frame_unreached | skipped_run_ended | failed`, with a machine-readable reason when the status is not `dispatched`.
- **FR-012**: System MUST persist the per-event outcomes as a fixed input-dispatch outcome artifact for the run using an agent-readable row format suitable for post-run inspection, and MUST register that artifact in the shared evidence artifact registry alongside the existing scenegraph snapshot, diagnostics, summary, and behavior trace artifacts.
- **FR-013**: System MUST reference the current run's input-dispatch outcome artifact from the persisted manifest-centered evidence bundle so agents can locate it from the manifest without scanning the output directory.
- **FR-014**: System MUST prevent stale input-dispatch outcome output from an earlier run from being reported as the evidence for the current run, consistent with the manifest-centered freshness rules already applied to other artifact kinds.
- **FR-015**: System MUST still produce an input-dispatch outcome artifact with partial-run status when the playtest crashes or exits before all declared events are dispatched, so the evidence bundle is never silently empty for the current run.
- **FR-016**: System MUST advertise input-dispatch support through the existing editor-evidence capability artifact with at minimum a supported/unsupported value and, when unsupported, a machine-readable reason.
- **FR-017**: System MUST reject input-dispatch requests submitted on environments whose capability artifact reports input dispatch as unsupported, and MUST surface a rejection reason consistent with the advertised capability reason.
- **FR-018**: System MUST keep the first release scoped to keyboard keys and declared input actions only and MUST treat mouse, touch, gamepad, and recorded-real-human-input replay as explicit later-slice fields.
- **FR-019**: System MUST keep the first release scoped to editor-launched playtests with the harness already installed and MUST NOT require packaged builds or engine-fork changes.
- **FR-020**: System MUST describe and justify the supported plugin-first extension points used for this feature, staying inside the editor plugin or addon, runtime addon plus autoload, and debugger messaging layers unless those surfaces cannot satisfy the deterministic input-dispatch outcomes described above.
- **FR-021**: System MUST be able to reproduce the Pong title-screen numpad-Enter crash described in issue #12 end-to-end through launch, dispatch, capture, persist, and shutdown when a valid input-dispatch script is supplied, so the feature has a concrete acceptance target.

### Key Entities *(include if feature involves data)*

- **Input Dispatch Script**: The run-scoped machine-readable request that declares an ordered list of input events along with run-level anchoring context. Submitted as part of the same run request that carries run identifiers, target scene, capture policy, and optional behavior watch.
- **Input Event Declaration**: One element of the script, defined by kind (keyboard key or input action), identifier (a Godot logical `Key` enum name for keyboard events or a declared input-action name for action events), phase (press or release), and target frame offset.
- **Applied Input Dispatch Summary**: The normalized representation of the accepted script that the harness associates with the run and exposes to the agent before or with the resulting evidence, mirroring the applied-watch summary for behavior-watch sampling.
- **Input Dispatch Outcome Row**: One machine-readable post-run entry per declared event containing run identity, declared frame, kind, identifier, phase, dispatched-frame, status (from the fixed enum `dispatched | skipped_frame_unreached | skipped_run_ended | failed`), and an optional machine-readable reason.
- **Input Dispatch Outcome Artifact**: The persisted file for the current run that holds all outcome rows, referenced from the manifest-centered evidence bundle alongside the existing artifact kinds.
- **Input Dispatch Capability Entry**: The supported/unsupported value and optional reason for input dispatch advertised through the existing editor-evidence capability artifact.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of seeded valid input-dispatch fixtures, the harness produces an explicit applied-input-dispatch summary before the playtest begins, and in 100% of seeded invalid fixtures the harness returns a machine-readable rejection before any event is dispatched.
- **SC-002**: In 100% of seeded Pong title-screen reproduction runs for issue #12, the harness delivers the declared numpad-Enter press and release through the engine input pipeline, and the resulting evidence bundle references an input-dispatch outcome artifact for the current run within 60 seconds of the playtest ending.
- **SC-003**: In 100% of completed input-dispatch runs, every declared event is represented by exactly one outcome row that reports its status (dispatched, skipped, or failed), its dispatched frame when applicable, and a machine-readable reason when not dispatched.
- **SC-004**: In 100% of runs where the capability artifact reports input dispatch as unsupported, the harness rejects input-dispatch requests before launch with a rejection reason consistent with the advertised capability reason.
- **SC-005**: In at least 90% of seeded input-driven reproduction exercises (title-screen accept handlers, action-remapped keys, `_unhandled_input` crash targets), an agent can identify the responsible input event from the manifest plus the input-dispatch outcome artifact within 5 minutes without relying on autoload shims, direct method calls, or OS-level keystroke injection.

## Assumptions

- This specification intentionally covers only keyboard keys and declared input actions for the first release; mouse, touch, gamepad, and recorded-real-human-input replay remain future work and are treated as later-slice fields at validation time.
- The first release targets a harness-enabled project that is already open in the Godot editor and can accept editor-launched playtest requests through the existing brokered automation contract.
- The input-dispatch script is run-scoped and is supplied as part of the same run request that already carries run identifiers, target scene, capture policy, and optional behavior watch rather than through a new manual editing step or a separate request channel.
- Declared input actions must already be present in the running project's input map; the harness does not modify the project's input map to make an unknown action resolve.
- Events are anchored to the playtest's own frame timeline so reproduction remains deterministic across hosts with different real-time clocks or frame pacing.
- The persisted input-dispatch outcome artifact is additive to the existing manifest-centered evidence bundle rather than a replacement for the scenegraph snapshot, diagnostics, summary, or behavior trace artifacts already produced by the harness.
- If any declared event is unsupported or malformed, the harness rejects the full script instead of silently downgrading to a partial dispatch set, matching the behavior-watch validator's strict rejection model.
- Capability advertisement uses the existing editor-evidence capability artifact; this feature does not introduce a second capability surface.
- The Pong testbed crash described in issue #12 (numpad Enter on the title screen) is the concrete acceptance target for the first release and is assumed to remain reproducible through the normal engine input pipeline when the declared script is dispatched.
- Relevant Godot APIs can be validated against `docs/GODOT_PLUGIN_REFERENCES.md` and the local `../godot` checkout relative to the repository root when engine-internal behavior needs confirmation.
