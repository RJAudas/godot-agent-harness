# Research: Autonomous Editor Evidence Loop

## Decision 1: Make the open Godot editor the automation owner

- **Decision**: Keep orchestration inside the Godot editor plugin and treat the already-open editor as the single owner of launch, capture, persist, validate, and stop actions for one project.
- **Rationale**: The user workflow is explicitly “game open in the designer, VS Code open in the directory.” The editor already owns the plugin lifecycle, debugger session awareness, and access to existing dock and bridge state, so it is the lowest-complexity place to coordinate the run.
- **Alternatives considered**: A second Godot process or standalone runner was deferred because it breaks the open-editor assumption. OS-level UI automation was rejected because it is brittle and hard to validate.

## Decision 2: Use workspace-visible request and result artifacts as the default cross-tool handoff

- **Decision**: Let the VS Code side trigger autonomous runs by writing a machine-readable request artifact into the project workspace and let the plugin answer with capability, status, and final result artifacts in the same workspace-visible surface.
- **Rationale**: Agents already know how to read and write files deterministically. This matches the repo’s automation matrix, avoids hidden side channels, and keeps the handoff inspectable after the run.
- **Alternatives considered**: A local IPC server is viable but deferred because it adds lifecycle and security complexity. A one-shot editor-script entrypoint is viable as a fallback if the file-driven broker proves too slow or too awkward, but it should still invoke the same plugin-owned orchestration path.

## Decision 3: Reuse the existing scenegraph harness for runtime capture and persistence

- **Decision**: Treat current runtime capture, debugger transport, and evidence persistence as the base system and add automation coordination around them rather than redesigning the scenegraph bundle.
- **Rationale**: The existing plugin already supports `configure_session`, startup capture, explicit capture requests, and `persist_latest_bundle`. The missing piece is editor automation and lifecycle control, not a new evidence format.
- **Alternatives considered**: A separate automation-only evidence bundle was rejected because it would duplicate manifest routing and increase agent complexity. Replacing the debugger transport was rejected because current repo guidance already prefers debugger-backed messaging for editor-runtime coordination.

## Decision 4: Require a capability check before every autonomous run

- **Decision**: The automation layer must emit a capability result before attempting launch so blocked states are explicit and deterministic.
- **Rationale**: The spec requires a blocked result when prerequisites are missing or the target is ambiguous. A capability check is the cleanest place to detect missing addon wiring, missing runtime configuration, multiple candidate sessions, or unavailable launch control before any side effects occur.
- **Alternatives considered**: Optimistically trying the run first and classifying failures later was rejected because it hides prerequisite problems behind noisier runtime errors. Manual operator confirmation was rejected because the first release requires zero manual intervention after the request is issued.

## Decision 5: Use a single run coordinator with explicit state transitions

- **Decision**: Introduce one plugin-side coordinator that owns the run lifecycle from request receipt through completion or failure and emits machine-readable state updates.
- **Rationale**: Today, the dock triggers capture and persist as isolated actions. Autonomous runs need stronger sequencing: prepare session metadata, launch playtest, await debugger attachment, capture, persist, validate, stop, and report. One coordinator reduces race conditions and makes stale-evidence protection easier.
- **Alternatives considered**: Wiring separate subsystems directly to request artifacts was rejected because it would make state ownership and failure classification ambiguous.

## Decision 6: Protect against stale evidence with per-run identity and validation-aware completion

- **Decision**: Every autonomous run must generate or confirm a unique run identity, ensure evidence paths map to that identity, and validate the final manifest before reporting success.
- **Rationale**: The spec explicitly calls out stale evidence risk. Reusing the manifest contract is only safe if the run coordinator can prove the output belongs to the current request.
- **Alternatives considered**: Reusing a fixed latest directory without run-specific verification was rejected because it allows false positives when prior artifacts linger. Relying only on timestamps without run identifiers was rejected because it is harder to reason about across rapid repeated runs.

## Decision 7: Keep v1 single-project and block ambiguity rather than inventing target selection logic

- **Decision**: Support exactly one eligible open Godot project for the first release and block when the target is ambiguous.
- **Rationale**: The clarified spec prefers a blocked result over guessing. This keeps the first release focused on a reliable single-project loop instead of fragile editor-window discovery heuristics.
- **Alternatives considered**: Picking the active editor window automatically was rejected because it is too implicit. User-specified target identifiers are a reasonable future extension, but they are unnecessary if the first release can safely block ambiguity.

## Decision 7a: Reject overlapping run requests in v1

- **Decision**: Reject overlapping autonomous run requests with a machine-readable blocked result instead of queueing them.
- **Rationale**: The first release already limits the system to one eligible open project and one active run. Rejecting overlap keeps state ownership clear and makes it easier for agents to reason about failures without guessing which request owns the active session.
- **Alternatives considered**: Queueing was rejected for v1 because it complicates lifecycle ownership, stale-artifact protection, and timeout reasoning before the core single-run broker is proven.

## Decision 8: Capture implementation options explicitly instead of pretending the run-control path is already proven

- **Decision**: Document a preferred path and viable alternatives in the planning package so implementation can validate the actual editor control surfaces without reopening the product requirements.
- **Rationale**: The user explicitly asked for alternatives where the build path is not obvious. Capturing them in planning artifacts preserves a clean implementation-agnostic spec while still giving maintainers concrete choices to discuss.
- **Alternatives considered**: Encoding implementation alternatives directly in the feature spec was rejected because it would blur product requirements and design decisions.

## Options To Validate During Implementation

### Option A: File-based automation broker inside the plugin

- **Shape**: The plugin watches a project-local request path, processes one request at a time, and writes capability and result artifacts back to the workspace.
- **Why it fits**: It is inspectable, deterministic, and easy for VS Code agents to use.
- **Primary risk**: The editor-side file watch or polling loop must remain lightweight and must handle partial writes safely.

### Option B: Secondary editor-script trigger that forwards into the same broker

- **Shape**: A deterministic workspace-side command invokes a Godot editor script or similar entrypoint, which forwards the run request into plugin-owned orchestration.
- **Why it fits**: It could bootstrap automation before a persistent listener is trusted.
- **Primary risk**: It may create another editor lifecycle path and complicate the “already open project” model.

### Option C: Local IPC server owned by the plugin

- **Shape**: The plugin exposes a loopback-only command surface for run requests and status reporting.
- **Why it fits**: It could provide lower-latency control and streaming updates.
- **Primary risk**: It introduces avoidable security, lifecycle, and cleanup complexity for v1.

### Rejected Option: External GUI automation

- **Why rejected**: It bypasses machine-readable editor state, is platform-fragile, and does not align with the plugin-first constitution.

## Implementation Notes

- The current plan assumes the scenegraph runtime and bridge remain the evidence-producing core; no new runtime evidence family is needed.
- No `../godot` source inspection was required for planning. If editor-owned run control proves ambiguous during implementation, inspect `../godot` only to confirm plugin-layer limitations before considering deeper escalation.
- If workspace-side helper scripts are added, they should remain deterministic and should integrate with existing automation boundary and run-log expectations rather than inventing a parallel safety model.