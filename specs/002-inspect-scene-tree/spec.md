# Feature Specification: Inspect Scene Tree

**Feature Branch**: `[002-inspect-scene-tree]`  
**Created**: 2026-04-11  
**Status**: Draft  
**Input**: User description: "Create a feature specification for a Godot editor-first agent harness that helps a coding agent inspect the live scene tree while the game is launched from the Godot editor. The first release should focus on an editor plugin plus debugger integration that can request or receive structured runtime scenegraph data during playtesting, while still writing stable machine-readable artifacts that Copilot Chat or GitHub CLI can inspect after the run. Treat support for packaged executables as out of scope for the first release, but design the data contract so a later runtime-only harness can reuse it. Keep the solution plugin-first and centered on how the editor experience exposes scene hierarchy, key node properties, and missing-node diagnostics to an agent without relying on human descriptions."

## Clarifications

### Session 2026-04-11

- Q: Which per-node property set should the first release guarantee in each scenegraph capture? → A: Core inspection set: include identity plus transform, visibility, processing state, and script/class identifiers where available.
- Q: How should scenario expectations identify required runtime nodes in the first release? → A: Hybrid matching: support exact path when stable, plus selector-based matching when paths are dynamic.
- Q: When should the first release capture scenegraph snapshots automatically? → A: Hybrid checkpoints: capture on explicit request plus automatic start and failure-triggered snapshots.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Inspect Live Scene Hierarchy (Priority: P1)

As a coding agent operator, I want the editor-launched game session to expose the active runtime scene hierarchy in a structured form so I can confirm what nodes exist during playtesting without relying on a human to describe the tree.

**Why this priority**: Live visibility into the runtime hierarchy is the core missing capability. Without it, the agent still depends on natural-language retellings for missing instances, wrong parents, or unexpected scene composition.

**Independent Test**: Launch a deterministic playtest from the Godot editor, request a runtime scenegraph snapshot during the session, and verify the resulting evidence bundle contains a machine-readable scenegraph artifact and summary fields that identify the active root, tracked nodes, and snapshot timestamp.

**Acceptance Scenarios**:

1. **Given** a game is launched from the Godot editor with the harness enabled, **When** an agent requests the current runtime scenegraph during playtesting, **Then** the harness returns a structured scene hierarchy that includes node paths, node types, parent-child relationships, and snapshot metadata for the active session.
2. **Given** a playtest session is already running, **When** the runtime scenegraph changes because nodes are instanced or freed, **Then** the harness can provide an updated structured snapshot without requiring the user to restart the session.
3. **Given** the requested scenegraph contains many nodes, **When** the harness returns the snapshot, **Then** the evidence remains machine-readable and ordered so an agent can locate gameplay-relevant branches without relying on prose interpretation.

---

### User Story 2 - Preserve Agent-Readable Run Artifacts (Priority: P2)

As a coding agent operator, I want each inspection-capable playtest run to persist stable machine-readable artifacts so Copilot Chat or GitHub CLI can inspect the session outcome after the editor run ends.

**Why this priority**: Live inspection is useful during playtesting, but the debugging loop still breaks if the resulting evidence disappears when the session stops or cannot be consumed consistently by agent tooling later.

**Independent Test**: Complete a deterministic editor-launched playtest run that performs at least one scenegraph capture and verify the output directory contains a manifest-centered evidence bundle whose summary references the persisted scenegraph artifact and any related diagnostics.

**Acceptance Scenarios**:

1. **Given** a playtest session ends normally, **When** the harness writes its run outputs, **Then** it persists a stable evidence bundle whose primary manifest points to the captured scenegraph data and summarizes the inspection outcome.
2. **Given** an agent opens the run artifacts after the playtest, **When** it reads the manifest first, **Then** it can determine what snapshots and diagnostics were captured without opening every raw artifact.
3. **Given** multiple editor playtest runs occur for the same project, **When** their artifacts are written, **Then** each run is identifiable by unique run metadata so agents do not confuse scenegraph outputs across sessions.

---

### User Story 3 - Diagnose Missing Or Misplaced Nodes (Priority: P3)

As a coding agent operator, I want the harness to highlight missing expected nodes and suspicious hierarchy mismatches so the agent can identify likely root causes for scene setup failures directly from structured evidence.

**Why this priority**: Agents need more than a raw tree dump. They need machine-readable diagnostics that point to absent or misplaced nodes when expected gameplay objects are missing at runtime.

**Independent Test**: Run a deterministic playtest fixture where an expected gameplay node is intentionally absent or attached under the wrong parent and verify the evidence bundle records a structured diagnostic that names the missing or mismatched node expectation and links it to the relevant scenegraph snapshot.

**Acceptance Scenarios**:

1. **Given** the harness is configured with required runtime node expectations for a scenario, **When** an expected node is missing during playtesting, **Then** the harness records a machine-readable missing-node diagnostic that identifies the missing path or role and the snapshot in which the failure was observed.
2. **Given** a node exists but is attached under an unexpected branch or lacks key identifying metadata, **When** the harness evaluates the runtime hierarchy, **Then** it records a structured hierarchy mismatch diagnostic instead of reporting the run as fully healthy.
3. **Given** an agent reviews a failed run after playtesting, **When** it reads the manifest and linked diagnostics, **Then** it can distinguish between a complete capture failure and a valid capture that exposed missing or misplaced nodes.

### Edge Cases

- The playtest ends before a requested scenegraph capture completes.
- The runtime hierarchy changes while a snapshot is being collected, producing partial or stale data.
- A scene contains a large number of nodes, making raw snapshots too verbose for direct agent consumption without summarized entry points.
- Expected nodes are optional for one scenario but required for another, so diagnostics must preserve scenario context.
- A node exists at runtime but its identifying properties are empty or inconsistent, making path-only diagnostics insufficient.
- The editor session loses live communication with the running game while still needing to preserve whatever evidence was already captured.

## References *(mandatory)*

### Internal References

- README.md
- AGENTS.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/GODOT_PLUGIN_REFERENCES.md
- docs/AI_TOOLING_BEST_PRACTICES.md

### External References

- Godot editor plugins overview: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- Godot EditorPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- Godot EditorDebuggerPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EditorDebuggerSession class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggersession.html
- Godot EngineDebugger class reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html
- Godot scene tree basics: https://docs.godotengine.org/en/stable/tutorials/scripting/scene_tree.html
- Godot autoload singletons guide: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html

### Source References

- No `../godot` source files were inspected for this specification; the current scope is defined by repository guidance and official plugin-layer documentation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support live runtime scenegraph inspection for games launched from the Godot editor during playtesting.
- **FR-002**: System MUST let the editor-side inspection workflow request a current scenegraph snapshot from the running game and MUST also support automatic scenegraph capture at session start and on failure-triggered checkpoints without a manual request.
- **FR-003**: System MUST represent each captured scenegraph in a machine-readable structure that includes node identity, hierarchy relationships, and snapshot metadata.
- **FR-004**: System MUST include a core inspection property set in each capture so an agent can reason about hierarchy and gameplay setup, including node path, node type, parent path, ownership or grouping metadata when present, transform state, visibility state, processing state, and script or class identifiers where available.
- **FR-005**: System MUST preserve captured scenegraph data as stable machine-readable run artifacts that remain inspectable after the playtest session ends.
- **FR-006**: System MUST write a manifest-centered evidence bundle in which the primary manifest summarizes the inspection session and references the persisted scenegraph artifacts and related diagnostics.
- **FR-007**: System MUST record run identity, session identity, and capture timestamps so agents can distinguish outputs from separate playtest runs.
- **FR-008**: System MUST detect and record missing-node diagnostics for required runtime nodes defined by the active scenario or inspection request, using hybrid matching that supports exact paths when stable and selector-based matching when runtime paths are dynamic.
- **FR-009**: System MUST detect and record hierarchy mismatch diagnostics when a node exists but appears under an unexpected branch or lacks required identifying metadata.
- **FR-010**: System MUST distinguish between capture transport failures, incomplete captures, and valid captures that reveal scenegraph problems so agents can assign the correct next action.
- **FR-011**: System MUST keep the first release scoped to editor-launched playtests and MUST not require support for packaged executables.
- **FR-012**: System MUST define the scenegraph data contract so a later runtime-only harness can reuse the same artifact shape and diagnostic model without requiring human translation.
- **FR-013**: System MUST preserve the plugin-first extension order and explicitly justify any need to escalate beyond addon, autoload, debugger integration, or GDExtension layers.
- **FR-014**: System MUST provide an agent-readable summary entry point that helps Copilot Chat or GitHub CLI locate the relevant snapshot and diagnostic artifacts without scanning every raw file.
- **FR-015**: System MUST ensure scenario-specific expectations and diagnostics stay associated with the scenario that produced them.

### Key Entities *(include if feature involves data)*

- **Inspection Session**: The editor-launched playtest interaction in which the harness can request, receive, and persist runtime scenegraph data for one run.
- **Scenegraph Snapshot**: A point-in-time machine-readable representation of the active runtime hierarchy, including node relationships, selected properties, and capture metadata.
- **Scenegraph Artifact**: The persisted file or files that store one or more scenegraph snapshots for later agent inspection.
- **Missing-Node Diagnostic**: A structured record that identifies a required runtime node that was absent when the scenegraph was evaluated.
- **Hierarchy Mismatch Diagnostic**: A structured record that identifies a node that existed but appeared under the wrong branch or with incomplete identifying metadata.
- **Inspection Manifest**: The primary machine-readable summary file that identifies the run, lists capture results, summarizes diagnostic status, and links to raw artifacts.
- **Scenario Expectation**: A machine-readable declaration of which nodes or hierarchy conditions should hold for a given scenario or inspection request, with hybrid matching rules that can use exact paths or selector-based identity depending on runtime stability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In at least 90% of seeded editor playtest evaluations, an agent can identify the active gameplay branch and required nodes from the provided evidence bundle without relying on a human-written scene description.
- **SC-002**: A deterministic editor-launched playtest that captures runtime hierarchy evidence produces a manifest and linked scenegraph artifacts in 100% of successful validation runs.
- **SC-003**: For seeded missing-node or misplaced-node fixtures, at least 90% of runs produce a diagnostic that correctly identifies the missing or mismatched runtime expectation.
- **SC-004**: An agent reviewing the persisted artifacts after a playtest can determine within 2 minutes whether the run failed because of missing nodes, hierarchy mismatches, or capture-transport issues.
- **SC-005**: The first release supports post-run inspection through the same persisted contract for every editor-launched scenario in scope, without requiring packaged executable support.
- **SC-006**: The scenegraph contract used by persisted artifacts can be reused unchanged by at least one documented follow-on runtime-only harness design during planning validation.

## Assumptions

- The primary users are coding agents and maintainers debugging Godot projects through editor-launched playtests rather than players of packaged builds.
- The first release can rely on editor-side control plus runtime communication during playtesting, provided the resulting evidence survives as persisted artifacts after the session ends.
- Packaged executable support is intentionally out of scope for the first release, but the persisted artifact contract should avoid editor-only semantics where a reusable runtime-neutral field would work.
- Scenegraph inspection will focus on hierarchy, identity, and a bounded set of high-value properties rather than attempting to serialize every property on every node.
- Scenario definitions or inspection requests can declare required nodes or hierarchy expectations that the harness uses to produce diagnostics.
- Official Godot plugin and debugger documentation are sufficient for specification work at this stage; engine-source inspection in `../godot` can wait until planning or implementation if gaps remain.