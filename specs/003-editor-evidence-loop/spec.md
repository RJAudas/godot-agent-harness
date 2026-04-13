# Feature Specification: Autonomous Editor Evidence Loop

**Feature Branch**: `[003-create-feature-branch]`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: User description: "We now have a working plugin that will deploy assets and generate files based on the runtime state of the scene graph. We want to complete the automation circle so agents working from VS Code can edit the game, run the open project from the Godot editor, capture a scenegraph snapshot, persist the evidence bundle, and inspect the output without further user interaction after the one-time asset deployment step. The first release must stay focused on the game opened in the Godot editor and should define the viable options for closing that loop with the current plugin or with additional plugin hooks if needed."

## Clarifications

### Session 2026-04-12

- Q: What level of editor-run autonomy is required in the first release? → A: Full autonomy is required: the agent must start the playtest and terminate it after it has captured and validated the evidence it needs.
- Q: Is evidence validation part of the same automated run contract? → A: Yes. Validation is mandatory before the run is reported as successful.
- Q: How should the first release handle target selection if multiple editor projects or sessions are open? → A: First release is single-project only. If the target is ambiguous, the run must block instead of guessing.
- Q: What should determine which scene the editor launches for an autonomous run? → A: The requested scenario or harness configuration must declare the target scene.
- Q: How should per-run settings be supplied for autonomous runs? → A: Shared harness configuration stays stable, and each run request may provide temporary request-scoped overrides.
- Q: How should the first release handle overlapping autonomous run requests? → A: First release rejects overlapping requests with a machine-readable blocked result instead of queueing them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start An Editor Run Autonomously (Priority: P1)

As a coding agent operator, I want an agent working against a project that is already open in the Godot editor to start an in-editor playtest run and wait for the harness session to attach so I can verify gameplay changes without taking over the keyboard after the initial setup.

**Why this priority**: The automation loop does not close unless the agent can move from source edits to a live playtest session on its own. Capture and persistence only matter after the editor run can be initiated reliably.

**Independent Test**: With the harness addon enabled in the example project and agent assets already deployed once, request an automated inspection run for a scenario whose harness configuration declares a target scene and verify the run produces a machine-readable status flow that reaches a connected runtime session without requiring the operator to click play, capture, persist, or stop controls.

**Acceptance Scenarios**:

1. **Given** the target project is open in the Godot editor with the harness enabled and the requested scenario declares a valid target scene, **When** an agent requests an automated inspection run for that scenario, **Then** the system starts an editor playtest session for that declared scene and reports when the runtime harness session is attached and ready.
2. **Given** the editor is open but the harness plugin, autoload wiring, or target project state is not ready for an automated run, **When** the agent requests the run, **Then** the system returns a machine-readable blocked result that identifies the missing prerequisite instead of pretending the run started.
3. **Given** an automated run is already active for the same project, **When** another run is requested, **Then** the system rejects the second request with a machine-readable blocked result and reports that decision to the agent.

---

### User Story 2 - Capture, Persist, And Validate Evidence Without Dock Clicks (Priority: P2)

As a coding agent operator, I want the agent-run playtest to drive capture, bundle persistence, evidence validation, and orderly session shutdown automatically so the agent can inspect the resulting manifest and artifacts directly from the workspace.

**Why this priority**: The current plugin already captures and persists evidence once a debugger session exists, but the loop still breaks if a human must click dock buttons during or after the run.

**Independent Test**: Execute a seeded editor run for the example project, let the automation request or rely on the configured capture policy, persist the latest bundle, validate the manifest and referenced artifacts, terminate the play session, and confirm the agent can locate the final evidence files from the reported output path alone.

**Acceptance Scenarios**:

1. **Given** an automated editor run reaches an attached runtime session, **When** the capture point defined for the run is reached, **Then** the system triggers snapshot capture without requiring a manual dock interaction.
2. **Given** a snapshot and diagnostics are available for the active run, **When** the automated run reaches its persistence step, **Then** the system writes a manifest-centered evidence bundle and returns the manifest path and output directory to the agent.
3. **Given** the bundle has been written, **When** the agent checks the evidence, **Then** the system verifies that the manifest and referenced files exist before reporting the run as successful and ending the play session.

---

### User Story 3 - Expose The Supported Automation Options Clearly (Priority: P3)

As a harness maintainer, I want the agent-facing workflow to state which editor automation surfaces are supported, which one is the default, and when additional plugin hooks are required so future work can extend the loop without ambiguity.

**Why this priority**: The user request explicitly asks whether the current plugin is sufficient or whether new methods, events, or hooks are needed. That decision must become part of the supported workflow instead of remaining tribal knowledge.

**Independent Test**: Review the agent-facing run workflow for the feature and verify it reports whether the current environment can launch a run, request capture, persist the bundle, and validate output using existing surfaces or whether a richer editor control surface is unavailable and must fall back to a documented blocked state.

**Acceptance Scenarios**:

1. **Given** the project environment supports the chosen automation path, **When** an agent asks how the run loop will execute, **Then** the system reports the supported control path, required prerequisites, and expected lifecycle states.
2. **Given** the current plugin can capture and persist evidence but cannot fully launch the editor playtest on its own, **When** the agent performs a pre-run capability check, **Then** the system reports that gap explicitly instead of masking it behind capture or persistence errors.
3. **Given** a future iteration adds new plugin commands, hooks, or events for editor-run control, **When** an agent inspects the automation capability for a project, **Then** it can distinguish between launch control, capture control, persistence control, validation support, and session shutdown support.

### Edge Cases

- The Godot editor is open, but the requested scenario or harness configuration does not resolve to a valid target scene for the automated run.
- More than one eligible open project or editor session exists, making the target ambiguous for the first release.
- A playtest launch is requested, but the runtime debugger session never attaches, leaving capture commands with no active session.
- Capture or persistence is requested for the current run after a previous run has already left evidence files in the same output directory.
- The playtest crashes or exits before the configured capture point, leaving only partial runtime evidence.
- Manifest writing succeeds, but one or more referenced evidence files are missing or stale by the time the agent validates the bundle.
- The agent requests an automated run while source changes are still being written, creating a race between code edits and the launched playtest.
- Repeated rapid run requests must not start a second concurrent run and must return a machine-readable blocked result instead.

## References *(mandatory)*

### Internal References

- README.md
- AGENTS.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/AGENT_TOOLING_FOUNDATION.md
- docs/AI_TOOLING_BEST_PRACTICES.md
- docs/GODOT_PLUGIN_REFERENCES.md
- specs/002-inspect-scene-tree/spec.md
- specs/002-inspect-scene-tree/quickstart.md
- addons/agent_runtime_harness/plugin.gd
- addons/agent_runtime_harness/editor/scenegraph_dock.gd
- addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd
- addons/agent_runtime_harness/runtime/scenegraph_runtime.gd
- addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd
- addons/agent_runtime_harness/shared/inspection_constants.gd

### External References

- Godot editor plugins overview: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- Godot EditorPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- Godot EditorDebuggerPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EditorDebuggerSession class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggersession.html
- Godot EngineDebugger class reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html
- Godot autoload singletons guide: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
- Godot scene tree basics: https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html

### Source References

- No `../godot` source files were inspected for this specification; the current scope is grounded in repository docs plus the plugin, debugger, and runtime harness surfaces already present in this repo.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow an agent operating from the workspace to request an automated evidence run against a Godot project that is already open in the editor after the one-time asset deployment step has been completed.
- **FR-002**: System MUST perform a pre-run capability check that determines whether editor-run launch control, runtime session attachment, capture control, persistence control, evidence validation, and session shutdown control are available for the requested project state.
- **FR-003**: System MUST return a machine-readable blocked result when a requested automated run cannot start because prerequisites are missing, including at minimum editor availability, harness availability, active project availability, or run concurrency conflicts.
- **FR-004**: System MUST represent the automated run lifecycle in machine-readable states that cover request receipt, launch attempt, runtime session attachment, capture, persistence, validation, completion, and failure.
- **FR-005**: System MUST associate each automated run with explicit run metadata before launch, including scenario identity, run identity, intended output location, and any expectation inputs that govern diagnostics.
- **FR-005a**: System MUST resolve the playtest launch target from the requested scenario or harness configuration and MUST not depend on whichever editor scene happens to be active when the request is issued.
- **FR-005b**: System MUST support request-scoped overrides for per-run settings and MUST not require rewriting shared harness configuration files in order to launch an autonomous run.
- **FR-006**: System MUST autonomously start an editor playtest session for the requested project without requiring a human to click the Godot dock or play button after the run request is issued.
- **FR-007**: System MUST autonomously terminate the playtest session after the required evidence has been captured and validation has completed, unless the run has already ended because of a crash or other failure.
- **FR-008**: System MUST support at least one agent-invoked path that triggers snapshot capture for the active run without manual dock interaction, either by relying on configured automatic capture policy or by issuing an explicit capture request during the run.
- **FR-009**: System MUST persist the latest capture bundle for the active run without requiring a manual dock interaction once the run reaches its persistence step.
- **FR-010**: System MUST preserve the existing manifest-centered scenegraph evidence contract so agents can continue to read the manifest first and then inspect only the referenced raw artifacts as needed.
- **FR-011**: System MUST return the persisted manifest path, evidence output directory, run identity, lifecycle status, and session termination status to the requesting agent when an automated run completes or fails.
- **FR-012**: System MUST validate the persisted manifest and its referenced scenegraph artifacts as part of every automated run before reporting success.
- **FR-013**: System MUST distinguish between launch-control failures, runtime-session attachment failures, capture failures, persistence failures, validation failures, session-shutdown failures, and gameplay or expectation failures in its machine-readable run outcome.
- **FR-014**: System MUST prevent stale evidence from a prior run from being misreported as the result of the current automated run.
- **FR-015**: System MUST support exactly one eligible open Godot project or editor session in the first release and MUST return a blocked result instead of guessing when multiple possible targets are available.
- **FR-016**: System MUST reject concurrent or overlapping run requests for that single supported project with a machine-readable blocked result so agents do not issue capture or persistence commands against the wrong playtest session.
- **FR-017**: System MUST keep the first release scoped to projects opened in the Godot editor and MUST not require launching packaged or compiled game builds.
- **FR-018**: System MUST describe the supported automation options for closing the edit-run-capture-persist-inspect loop, identify the default path for the first release, and document the blocked behavior when full editor launch control is unavailable.
- **FR-019**: System MUST explicitly identify which plugin-first extension points are sufficient for the chosen automation path and MUST justify any newly introduced plugin commands, events, or hooks before considering escalation beyond addon, autoload, debugger, or GDExtension layers.
- **FR-020**: System MUST allow agents to inspect the completed evidence bundle directly from workspace-accessible files without relying on a human-written summary of the run outcome.
- **FR-021**: System MUST preserve the existing scenegraph snapshot, diagnostics, and summary semantics so the automated loop remains compatible with the current evidence triage workflow.

### Key Entities *(include if feature involves data)*

- **Automated Run Request**: The machine-readable instruction that tells the harness to launch an in-editor playtest, apply run metadata, and execute the evidence loop for one scenario.
- **Automation Capability Result**: A machine-readable report of which parts of the loop are available for the current project and editor state, including launch, session attachment, capture, persistence, validation, and shutdown readiness.
- **Editor Playtest Session**: The specific Godot editor run instance that the harness binds to for capture and persistence.
- **Run Lifecycle Record**: The machine-readable progression of states and timestamps for one automated evidence run from request through completion or failure.
- **Evidence Bundle**: The persisted manifest-centered set of scenegraph snapshot, diagnostics, and summary artifacts produced by the automated run.
- **Run Validation Result**: The machine-readable outcome that confirms whether the expected evidence files for the run were written correctly, are safe for the agent to inspect, and were secured before the play session ended.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the one-time asset deployment step, an agent can complete the edit-run-capture-persist-validate-stop loop for the seeded example project without further human input in at least 90% of validation runs.
- **SC-002**: In 100% of successful automated runs, the reported manifest path resolves to a manifest whose referenced scenegraph snapshot, diagnostics, and summary files are present at validation time.
- **SC-003**: In seeded blocked or failure cases, an agent can determine within 2 minutes whether the loop failed at launch control, runtime-session attachment, capture, persistence, validation, session shutdown, or gameplay expectation evaluation by reading the machine-readable run output alone.
- **SC-004**: For the example project under normal validation conditions, the time from automated run request to a validated persisted evidence bundle and a stopped play session is under 3 minutes.
- **SC-005**: Successful automated runs require zero manual dock interactions after the run request is issued.
- **SC-006**: In 100% of validation runs, the pre-run capability check returns a decisive ready or blocked result before the system attempts playtest launch, including a blocked result when multiple possible editor targets are open.

## Assumptions

- The game project is already open in the Godot editor on the same machine as the agent workspace when an automated run is requested.
- A one-time manual click on `Deploy Agent Assets` is acceptable before the autonomous run loop is used.
- The harness addon, project wiring, and runtime autoload are already installed in the target project before autonomous runs are attempted.
- The requested scenario or harness configuration can declare the scene that the autonomous run should launch.
- Shared harness configuration can remain stable while autonomous runs provide temporary per-run overrides.
- The first release only needs to support one eligible open Godot project and one active automated inspection run at a time; ambiguous multi-project conditions are blocked.
- Agents can read the persisted evidence files from the project workspace once the harness reports their paths.
- The current scenegraph snapshot, diagnostics, summary, and evidence-manifest contract remains the base evidence handoff model for the automated loop.
- The automated run is responsible for ending the play session once required evidence is captured and validated.
- Packaged executable launches remain out of scope for this feature.