# Feature Specification: Behavior Watch Sampling

**Feature Branch**: `[005-add-behavior-capture]`  
**Created**: 2026-04-14  
**Status**: Draft  
**Input**: User description: "Build a plugin-first runtime behavior capture feature for the Godot Agent Harness that lets an agent request bounded watch sampling for specific runtime nodes and properties during an editor-launched playtest. Record a low-overhead time-series trace for selected targets such as the Pong ball, capturing fields like position, velocity, collision state, and related movement data every frame or every N frames over a defined window instead of logging the whole scene continuously. Persist the output as a stable machine-readable trace artifact that fits into the existing manifest-centered evidence bundle. Use docs\BEHAVIOR_CAPTURE_SLICES.md as a reference and focus on slice 1 and slice 2 only."

## Clarifications

### Session 2026-04-14

- Q: Which watch-target selector shape should the first release support? → A: Absolute runtime node paths only.
- Q: What should the first-release persisted trace artifact contract be? → A: A fixed `trace.jsonl` artifact referenced from the manifest.
- Q: How should the bounded watch window be defined in the first release? → A: Use an explicit start-frame offset plus a bounded frame count.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declare A Bounded Watch Request (Priority: P1)

As a coding agent, I want to declare exactly which runtime nodes, properties, sampling cadence, and capture window to observe so the harness records only the behavior evidence relevant to my debugging question.

**Why this priority**: The targeted trace cannot be trusted or kept low-overhead unless the request contract is explicit, normalized, and rejected decisively when it asks for unsupported scope.

**Independent Test**: Validate one seeded Pong watch request and one invalid request without starting a playtest. Confirm the valid request is normalized into explicit defaults for cadence, start-frame offset, and bounded frame count, and the invalid request fails with a machine-readable reason that identifies the unsupported selector, property, or unbounded request field.

**Acceptance Scenarios**:

1. **Given** a valid watch request for `/root/Main/Ball` with selected movement properties, **When** the harness prepares the next editor-launched playtest, **Then** it records an explicit normalized request that names the watched targets, watched properties, cadence, start-frame offset, and bounded frame count for that run.
2. **Given** a request omits optional cadence or watch-window values, **When** the request is normalized, **Then** the harness fills in explicit bounded defaults for the start-frame offset and bounded frame count instead of relying on implicit runtime behavior.
3. **Given** a request asks for an unsupported selector, property, trigger, invariant, or unbounded full-scene capture mode, **When** the request is validated, **Then** the harness rejects it before the run begins with a machine-readable unsupported reason.

---

### User Story 2 - Persist A Targeted Time-Series Trace (Priority: P2)

As a coding agent, I want the harness to sample only the selected properties for selected runtime nodes over a bounded frame window so I can inspect time-based behavior such as sticking, sliding, or failed bounce reversal without paying the cost of continuous whole-scene logging.

**Why this priority**: The trace artifact is the first runtime evidence that can explain motion bugs over time. Without it, the harness still depends on coarse snapshots or human retellings of how gameplay evolved.

**Independent Test**: Run a deterministic Pong wall-bounce playtest with a watch request for `/root/Main/Ball` that samples position, velocity, collision state, last collider, and related movement data at every frame and at every N frames in separate runs. Confirm the persisted trace artifact contains only the selected target and fields, stays within the requested start-frame offset and bounded frame-count window, and is referenced from the current evidence bundle.

**Acceptance Scenarios**:

1. **Given** a valid watch request is attached to an editor-launched playtest, **When** the configured capture window runs, **Then** the harness writes a machine-readable time-series trace containing frame, timestamp, target identity, and the requested watched properties for the selected nodes only.
2. **Given** a watch request uses every N frames sampling, **When** the run completes, **Then** the trace rows reflect the requested cadence and do not exceed the configured start-frame offset and bounded frame count.
3. **Given** a requested node never becomes available or produces no samples during the configured window, **When** the run completes, **Then** the outcome reports that gap explicitly instead of silently expanding to unrelated nodes or producing a misleading full-scene trace.

---

### User Story 3 - Keep Evidence Manifest-Centered (Priority: P3)

As a harness maintainer, I want targeted behavior sampling to fit the existing manifest-centered evidence bundle so agents can read the manifest first and then open the trace artifact directly instead of learning a second post-run evidence path.

**Why this priority**: The repository already treats the manifest as the machine-readable handoff contract. Preserving that flow keeps behavior capture additive and easier for agents to consume.

**Independent Test**: Persist a completed watch-sampling run and verify the resulting evidence bundle exposes the current trace artifact as a first-class manifest entry, points to the applied watch scope, and does not report a stale trace from an earlier run as the result of the current playtest.

**Acceptance Scenarios**:

1. **Given** a targeted watch run completes successfully, **When** the evidence bundle is written, **Then** the manifest references the trace artifact and provides enough summary context for an agent to identify it as the next file to inspect.
2. **Given** a targeted watch run fails before persistence, **When** the agent reads the run outcome, **Then** the missing current trace artifact is reported explicitly instead of implying that one was written.
3. **Given** an earlier run already left a trace artifact in the output location, **When** a new watched run executes, **Then** the harness reports only the trace produced for the current run and never attributes stale trace output to the new run.

### Edge Cases

- A request mixes valid and invalid watch targets or properties; the harness should reject the entire request rather than apply a partial watch set that changes the debugging question.
- A request defines a sampling interval or watch window that yields zero eligible samples; the harness should reject the request as invalid instead of writing an empty success artifact.
- A watched node is instanced after the playtest starts; the trace should begin when the node first becomes available and still respect the configured end boundary.
- A watched property is unavailable on a selected node for the entire run; the outcome should identify that unsupported property explicitly.
- The configured watch window ends before the behavior of interest happens; the run should still produce a bounded trace that makes the missing evidence clear.
- A prior run already wrote `trace.jsonl`; the new run must not reuse that older file as the current run's evidence.

## References *(mandatory)*

### Internal References

- README.md
- AGENTS.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/AGENT_TOOLING_FOUNDATION.md
- docs/GODOT_PLUGIN_REFERENCES.md
- docs/BEHAVIOR_CAPTURE_SLICES.md
- specs/003-editor-evidence-loop/spec.md
- specs/004-report-build-errors/spec.md
- addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd
- addons/agent_runtime_harness/shared/inspection_constants.gd
- tools/evidence/artifact-registry.ps1

### External References

- Godot editor plugins overview: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- Godot EditorPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- Godot EditorDebuggerPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EditorDebuggerSession class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggersession.html
- Godot EngineDebugger class reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html
- Godot autoload singletons guide: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
- Godot scene tree basics: https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html

### Source References

- No `../godot` source files were inspected for this specification; the current scope is grounded in repository documentation plus the existing plugin-first runtime transport and evidence bundle contracts already present in this repository.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow an agent to submit a machine-readable behavior watch request as session configuration or per-run override data for an editor-launched playtest.
- **FR-002**: System MUST allow a behavior watch request to identify one or more runtime watch targets by absolute runtime node path and the explicit property list to sample for each target.
- **FR-003**: System MUST allow a behavior watch request to define a bounded sampling cadence using either every-frame sampling or every-N-frames sampling.
- **FR-004**: System MUST allow a behavior watch request to define a bounded watch window using an explicit start-frame offset plus a bounded frame count for the run.
- **FR-005**: System MUST normalize every valid behavior watch request before capture begins so default cadence, start-frame offset, bounded frame count, and persistence values are explicit in run metadata.
- **FR-006**: System MUST persist or expose an applied-watch summary that tells the agent which normalized request the harness actually used for the run.
- **FR-007**: System MUST reject unsupported selectors, including any selector form other than an absolute runtime node path, properties, cadences, zero-sample windows, or other invalid request fields with explicit machine-readable errors before the playtest begins.
- **FR-008**: System MUST reject request fields that belong to later behavior-capture slices, including trigger-driven persistence, invariant evaluation, script probes, or open-ended full-scene capture, with a machine-readable unsupported reason instead of partially executing them.
- **FR-009**: System MUST sample only the requested targets and requested properties during the active watch window and MUST NOT silently expand capture to unrelated nodes or unrelated fields.
- **FR-010**: System MUST support watched movement-oriented fields needed for Pong-style bounce diagnosis, including position, velocity, collision state, and related movement data when those fields are available on the selected target.
- **FR-011**: System MUST record each captured sample with stable machine-readable fields that include at minimum the current run identity, frame number, timestamp, watched target identity, and the requested property values for that row.
- **FR-012**: System MUST persist the sampled output as a fixed `trace.jsonl` artifact for the run using an agent-readable row format suitable for post-run inspection.
- **FR-013**: System MUST keep watch sampling low-overhead and bounded by honoring the configured cadence and end boundary instead of recording continuous full-scene per-frame data.
- **FR-014**: System MUST report when a requested target or property produced no samples so the agent can distinguish missing evidence from a clean behavior run.
- **FR-015**: System MUST fit the targeted watch trace into the existing manifest-centered evidence bundle and MUST reference the current run's `trace.jsonl` artifact from the persisted manifest.
- **FR-016**: System MUST prevent stale trace output from an earlier run from being reported as the evidence for the current run.
- **FR-017**: System MUST keep the first release explicitly scoped to slice 1 and slice 2 of `docs/BEHAVIOR_CAPTURE_SLICES.md`.
- **FR-018**: System MUST keep the first release scoped to editor-launched playtests with the harness already installed and MUST NOT require packaged builds or engine-fork changes.
- **FR-019**: System MUST describe and justify the supported plugin-first extension points used for this feature, with the first release staying inside the editor plugin or addon, runtime addon plus autoload, and debugger messaging layers unless those surfaces cannot satisfy the bounded watch outcomes.
- **FR-020**: System MUST emit or identify the machine-readable artifacts agents inspect to validate the feature, including the normalized watch scope, the persisted `trace.jsonl` artifact, and the manifest entry that points to that trace for the current run.

### Key Entities *(include if feature involves data)*

- **Behavior Watch Request**: The run-scoped machine-readable request that declares watch targets, watched properties, cadence, explicit start-frame offset, bounded frame count, and other in-scope options for slices 1 and 2.
- **Watch Target**: One selected runtime node identified by an absolute runtime node path plus the explicit list of properties to sample for that target.
- **Applied Watch Summary**: The normalized representation of the watch request that the harness associates with the run and exposes to the agent before or with the resulting evidence.
- **Trace Sample Row**: One machine-readable time-series entry containing run identity, frame number, timestamp, target identity, and the watched property values collected at that point.
- **Behavior Trace Artifact**: The persisted bounded `trace.jsonl` file for the current run plus its manifest reference within the evidence bundle.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of seeded valid watch-request fixtures, the harness produces an explicit applied-watch summary before the playtest begins, and in 100% of invalid fixtures it returns a machine-readable rejection without starting capture.
- **SC-002**: In 100% of seeded Pong wall-bounce validation runs for this feature, the current run produces a bounded trace artifact linked from the current evidence bundle within 60 seconds of the playtest ending.
- **SC-003**: In 100% of targeted watch validation runs, every persisted trace row includes frame number, timestamp, target identity, and only the explicitly requested watched fields.
- **SC-004**: In 100% of every-N-frames validation runs, the trace never exceeds the configured bounded frame count or configured end boundary for the current request.
- **SC-005**: In at least 90% of seeded sticky, sliding, or failed-reversal diagnostic exercises for Pong, an agent can identify the relevant behavior window from the manifest plus the targeted trace artifact within 5 minutes without opening a continuous whole-scene log.

## Assumptions

- This specification intentionally covers only slice 1 and slice 2 from `docs/BEHAVIOR_CAPTURE_SLICES.md`; triggered persistence windows, invariants, and script probes remain future work.
- The first release targets a harness-enabled project that is already open in the Godot editor and can accept editor-launched playtest requests.
- The watch request is run-scoped and can be supplied through existing session configuration or per-run override mechanisms rather than requiring a new manual editing step.
- The first release supports absolute runtime node paths as the only watch-target selector form; relative-name and group-based selectors remain out of scope.
- The first release always persists targeted sampling output as `trace.jsonl` and does not negotiate alternative trace file formats per request.
- The first release defines the watch window relative to playtest frame 0 by using an explicit start-frame offset plus a bounded frame count; target appearance does not redefine the window.
- If any requested target, property, or slice-later field is unsupported, the harness rejects the full request instead of silently downgrading to a partial watch set.
- The first release only needs to capture node-state and related movement data that the harness can observe through existing plugin-first runtime surfaces; custom script-local decision variables remain out of scope until a later slice adds probe support.
- The manifest-centered evidence bundle remains the primary post-run handoff, and the new trace artifact is additive to that existing contract rather than a replacement for it.
