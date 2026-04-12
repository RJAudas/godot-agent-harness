# Contract: Editor Evidence Loop

## Purpose

Define the planned machine-readable contract between a workspace-side agent and the open Godot editor for autonomous scenegraph evidence runs.

## Contract Surfaces

### Capability Result

- **Role**: Reports whether the current open-editor environment is safe to target.
- **Produced by**: Editor-owned automation broker.
- **Consumed by**: VS Code agent or deterministic helper workflow.
- **Minimum fields**:
  - `singleTargetReady`
  - `launchControlAvailable`
  - `runtimeBridgeAvailable`
  - `captureControlAvailable`
  - `persistenceAvailable`
  - `validationAvailable`
  - `shutdownControlAvailable`
  - `blockedReasons`
  - `recommendedControlPath`

### Automated Run Request

- **Role**: Tells the editor broker to perform one end-to-end autonomous run.
- **Produced by**: VS Code agent or deterministic helper workflow.
- **Consumed by**: Editor-owned automation broker.
- **Minimum fields**:
  - `requestId`
  - `scenarioId`
  - `runId`
  - `outputDirectory`
  - `artifactRoot`
  - `expectationFiles`
  - `capturePolicy`
  - `stopPolicy`
  - `requestedBy`
  - `createdAt`

### Lifecycle Status

- **Role**: Exposes observable progress without requiring the agent to infer state from raw evidence files.
- **Produced by**: Editor-owned automation broker.
- **Consumed by**: VS Code agent or deterministic helper workflow.
- **Expected states**:
  - `received`
  - `blocked`
  - `launching`
  - `awaiting_runtime`
  - `capturing`
  - `persisting`
  - `validating`
  - `stopping`
  - `completed`
  - `failed`

### Automated Run Result

- **Role**: Final machine-readable outcome for the autonomous run.
- **Produced by**: Editor-owned automation broker.
- **Consumed by**: VS Code agent.
- **Minimum fields**:
  - `requestId`
  - `runId`
  - `finalStatus`
  - `failureKind`
  - `manifestPath`
  - `outputDirectory`
  - `validationResult`
  - `terminationStatus`
  - `completedAt`

## Evidence Requirements

- The run result must reference the manifest-centered evidence bundle rather than embedding all raw runtime artifacts inline.
- The manifest remains the primary handoff surface for scenegraph snapshot, diagnostics, and summary artifacts.
- A run cannot report success until the manifest and referenced artifacts have been validated.
- The evidence bundle must be traceable to the current `runId` so stale outputs cannot satisfy a new request accidentally.

## Control Path Options

| Option | Status | Summary | Why | Risk |
|--------|--------|---------|-----|------|
| Plugin-owned file broker | Preferred for v1 | Workspace-visible request and result artifacts are exchanged with the open editor plugin. | Deterministic, inspectable, and aligned with plugin-first design. | Requires safe file polling or ingestion semantics. |
| Editor-script forwarder | Viable fallback | A deterministic command forwards the request into the same plugin-owned orchestration path. | Could bootstrap automation if a persistent broker is not ready. | May complicate the already-open-editor assumption. |
| Local IPC broker | Deferred | Plugin exposes a loopback command surface. | Richer control and progress streaming. | More security and lifecycle complexity than v1 needs. |
| External GUI automation | Rejected | Simulate user interaction to press play and stop. | No plugin changes required. | Brittle, opaque, and contrary to repo guidance. |

## Safety Requirements

- The broker must block when more than one eligible open project or session could satisfy the request.
- The broker must process at most one autonomous run at a time for the first release and reject overlap with a machine-readable blocked result.
- Any workspace-side helper that writes request artifacts should integrate with the repository’s existing automation boundary and run-log guidance when those helpers are added.
- Launch, validation, and shutdown failures must be distinguishable in machine-readable form.