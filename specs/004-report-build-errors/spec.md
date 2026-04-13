# Feature Specification: Report Build Errors On Run

**Feature Branch**: `[004-report-build-errors]`  
**Created**: 2026-04-12  
**Status**: Draft  
**Input**: User description: "Reporting build errors on run. We encountered build errors when testing the agent loop where the agent made changes that resulted in compile errors. Update the plugin to provide build error output if the build/run failed. The agent should have the build error information so it can fix the issues and retry the run."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Return Build Errors For Failed Runs (Priority: P1)

As a coding agent operator, I want an automated run that fails during editor-reported build, parse, or blocking resource loading before runtime attachment to return machine-readable build error details so the agent can fix the code without waiting for a human to restate the failure.

**Why this priority**: The autonomous loop breaks as soon as the editor cannot start the run. If the agent cannot see the build failure directly, it cannot repair the change or retry the loop on its own.

**Independent Test**: Submit an autonomous run request against a seeded project state with a known compile, parse, or resource-load error and verify the run ends with a failed machine-readable result that identifies the current run, reports the build-failure phase, and includes both normalized diagnostics and the raw reported build output needed to locate the broken file or resource.

**Acceptance Scenarios**:

1. **Given** an autonomous run request targets a project with a script compile, parse, or blocking resource-load error, **When** the editor attempts to start the run, **Then** the system returns a failed run result that includes the current run identity and the reported build error details instead of waiting for runtime evidence that will never arrive.
2. **Given** the build fails before the runtime harness attaches, **When** the agent reads the run outcome, **Then** it can tell that the failure happened before capture or evidence persistence began.
3. **Given** more than one build error is reported for the same failed run, **When** the run result is written, **Then** the system includes all reported diagnostics for that run instead of collapsing them into a single generic message.

---

### User Story 2 - Keep Failure Reporting Actionable And Safe (Priority: P2)

As a coding agent, I want the failed run output to distinguish build failures from other automation failures and to avoid reusing stale evidence so I can decide whether to edit code and retry or investigate a different problem.

**Why this priority**: A generic launch failure is not enough. The agent needs to know whether it should fix source files, inspect harness configuration, or read persisted runtime evidence from a different failure mode.

**Independent Test**: Run seeded failure cases for build failure, blocked launch, and runtime attachment failure, then verify the machine-readable status and final result clearly separate those outcomes and never point to an older manifest as the evidence for the current build-failed request.

**Acceptance Scenarios**:

1. **Given** a previous autonomous run produced a valid evidence bundle, **When** the next run fails during build, **Then** the system does not report the older manifest as if it belonged to the build-failed run.
2. **Given** the editor reports a build failure without full line or column metadata, **When** the failed result is generated, **Then** the system still preserves the available normalized details and the raw build output snippet instead of discarding the diagnostic.
3. **Given** a run is blocked for a reason unrelated to compilation, **When** the agent reads the result, **Then** the system keeps that blocked outcome distinct from build-failure reporting.

---

### User Story 3 - Preserve The Existing Automation Path (Priority: P3)

As a harness maintainer, I want build-error reporting to fit into the existing plugin-owned automation broker and agent workflow so the fix stays plugin-first and does not introduce a second diagnostics channel for the same run lifecycle.

**Why this priority**: The repository already has a machine-readable capability, lifecycle, and run-result flow. Extending that path is lower risk and easier for agents to consume than inventing a parallel error-reporting mechanism.

**Independent Test**: Review the documented autonomous run contract and confirm it describes where build-failure information appears, how it relates to lifecycle and final-result artifacts, and how agents should use it before deciding to retry.

**Acceptance Scenarios**:

1. **Given** the plugin-owned broker remains the supported first-release control path, **When** a build failure occurs, **Then** the agent receives the diagnostics through the same workspace-visible automation artifacts it already uses for capability and run outcomes.
2. **Given** a run builds successfully and reaches runtime capture, **When** the agent reads the result, **Then** the existing manifest-centered evidence flow remains unchanged.
3. **Given** the chosen design needs additional plugin hooks or editor signals to observe build failures reliably, **When** the feature is documented, **Then** those additions are justified within the plugin-first stack before any escalation beyond addon, debugger, autoload, or GDExtension layers is considered.

---

### Edge Cases

- The editor reports several compile, parse, or blocking resource-load errors across different files for the same requested run.
- The build fails after launch is requested but before the runtime debugger session attaches.
- The editor surfaces only partial diagnostics, such as a message without an exact column.
- A prior successful run left a valid manifest in the output directory, and the current run fails before any new evidence bundle is created.
- A non-build launch problem occurs at the same time as stale source changes, and the result must not misclassify the outcome as a compile failure.
- The agent fixes one error and retries, but a different build error becomes the next blocking failure.

## References *(mandatory)*

### Internal References

- README.md
- AGENTS.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/AGENT_TOOLING_FOUNDATION.md
- docs/GODOT_PLUGIN_REFERENCES.md
- specs/003-editor-evidence-loop/spec.md
- specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md
- addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd
- addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd
- addons/agent_runtime_harness/shared/inspection_constants.gd

### External References

- Godot editor plugins overview: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- Godot EditorPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- Godot EditorDebuggerPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EditorDebuggerSession class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggersession.html

### Source References

- No `../godot` source files were inspected for this specification; the feature is grounded in the repository's current editor-automation contract and plugin-first guidance.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect when an autonomous editor run fails because the editor reports a build, parse, or blocking resource-load problem before the requested play session reaches runtime attachment.
- **FR-002**: System MUST return a machine-readable failed run outcome for build or compile failures instead of reducing them to an undifferentiated launch failure.
- **FR-003**: System MUST include normalized build diagnostics for the failed run with enough detail for an agent to identify the affected file, scene, or resource and understand the reported error message.
- **FR-004**: System MUST preserve multiple build diagnostics for the same failed run when the editor reports more than one error.
- **FR-005**: System MUST distinguish build or compile failures from blocked prerequisites, launch-control failures, runtime-attachment failures, capture failures, persistence failures, validation failures, shutdown failures, and gameplay failures.
- **FR-006**: System MUST associate every reported build diagnostic with the active request and run identity so stale diagnostics are not attributed to a new run.
- **FR-007**: System MUST expose the build-failure phase through the observable automation lifecycle before or alongside the final failed result so the agent can tell that runtime evidence capture did not start.
- **FR-008**: System MUST report that no new evidence manifest is available when a run fails during build before runtime capture or persistence occurs.
- **FR-009**: System MUST prevent a manifest or summary from a prior successful run from being presented as the evidence for a build-failed run.
- **FR-010**: System MUST preserve whatever location and severity metadata the editor provides for each build diagnostic, and when exact coordinates are unavailable it MUST still report the remaining normalized diagnostic context.
- **FR-011**: System MUST include the raw editor-reported build output snippet that produced the failed run diagnostics so the agent can inspect the original wording alongside the normalized fields.
- **FR-012**: System MUST provide enough machine-readable information for an agent to decide whether the appropriate next action is to edit code and retry rather than waiting for human narration, without requiring the plugin to trigger an automatic retry.
- **FR-013**: System MUST keep build-error reporting within the existing plugin-owned automation broker and workspace-visible result artifacts for the first release.
- **FR-014**: System MUST keep the successful-build path compatible with the existing manifest-centered evidence flow for runs that reach capture and persistence.
- **FR-015**: System MUST describe which supported Godot extension points are used to observe and report build failures and justify any new plugin hooks before considering escalation beyond addon, autoload, debugger, or GDExtension layers.
- **FR-016**: System MUST emit or identify the machine-readable artifacts agents inspect to confirm that a run failed during build and to read the associated diagnostics and raw build output.

### Key Entities *(include if feature involves data)*

- **Build Failure Report**: The machine-readable description of a run that could not start successfully because the editor reported a build, parse, or blocking resource-load failure before runtime attachment, including run identity, failure phase, normalized diagnostic entries, and the raw reported build output.
- **Build Diagnostic Entry**: One reported error or warning from the failed run, including the affected resource, the editor-provided message, and any available location or severity metadata.
- **Automation Lifecycle Status**: The observable state record that tells the agent whether the run was blocked, failed during build, reached runtime, or completed with persisted evidence.
- **Automation Run Result**: The final machine-readable outcome for one requested run, including whether a manifest exists, which failure kind applies, and whether build diagnostics are available.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of seeded build-failure validation runs, the agent can identify at least one affected resource, one reported build message, and the associated raw build-output snippet from the machine-readable run output alone.
- **SC-002**: In 100% of seeded build-failure validation runs, the system reports the failed outcome and associated diagnostics within 30 seconds of the run request instead of remaining indefinitely in a launch or waiting state.
- **SC-003**: In 100% of validation runs where the current request fails during build, the system does not report a stale evidence manifest from an earlier run as the current run output.
- **SC-004**: In at least 90% of seeded repair-and-retry validation cycles, the returned build diagnostics are sufficient for an agent to make a corrective edit and reach the next retry attempt without human restatement of the error.
- **SC-005**: In 100% of seeded successful-build validation runs, the existing manifest-centered runtime evidence handoff remains available and unchanged.

## Assumptions

- The target project is already open in the Godot editor and reachable through the existing plugin-owned automation broker.
- The first release is focused on editor-reported build, parse, or blocking resource-load failures surfaced by Godot while starting the requested play session, not on external packaging pipelines.
- The editor can expose at least a message and affected resource for build failures, even when richer location data is not always available.
- Agents continue to read workspace-visible automation artifacts and, when available, the persisted evidence manifest as their primary sources of truth.
- One autonomous run is processed at a time for the first release, so reported build diagnostics can be safely associated with a single active run.