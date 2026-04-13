# Data Model: Autonomous Editor Evidence Loop

## Entities

### Automation Capability Result

- **Purpose**: Describes whether the current open-editor project can accept an autonomous run request safely.
- **Fields**:
  - `checked_at`: Timestamp for the capability evaluation.
  - `project_identifier`: Canonical identifier for the eligible open project.
  - `single_target_ready`: Whether exactly one eligible project or editor session was found.
  - `launch_control_available`: Whether the plugin can start playtesting.
  - `runtime_bridge_available`: Whether debugger-backed runtime coordination is available.
  - `capture_control_available`: Whether capture can be triggered for the active project.
  - `persistence_available`: Whether bundle persistence is wired and writable.
  - `validation_available`: Whether the manifest and artifact validation path is available.
  - `shutdown_control_available`: Whether the plugin can stop the play session after validation.
  - `blocked_reasons`: Array of machine-readable reasons when the run cannot proceed.
  - `recommended_control_path`: Preferred automation path for the environment.

### Automated Run Request

- **Purpose**: The machine-readable request an agent submits to start one autonomous evidence run.
- **Fields**:
  - `request_id`: Stable identifier for the request artifact.
  - `scenario_id`: Scenario or validation target identifier.
  - `run_id`: Intended evidence run identifier.
  - `output_directory`: Target directory for the evidence bundle.
  - `artifact_root`: Artifact root to use in the persisted manifest.
  - `expectation_files`: Optional expectation file list.
  - `capture_policy`: Startup, explicit, or failure-triggered capture preferences.
  - `stop_policy`: Whether the session should end automatically after validation.
  - `requested_by`: Request origin such as VS Code agent or workflow helper.
  - `created_at`: Request timestamp.

### Automation Control Path

- **Purpose**: Identifies which cross-tool orchestration pattern is active for a run.
- **Fields**:
  - `path_kind`: `file_broker`, `editor_script_forwarder`, or `local_ipc`.
  - `default_for_v1`: Whether this path is the first-release default.
  - `supports_launch`: Whether the path can trigger play start.
  - `supports_shutdown`: Whether the path can stop the session after validation.
  - `supports_status_updates`: Whether the path can expose incremental lifecycle state.
  - `notes`: Short explanation of assumptions or limits.

### Automated Run Session

- **Purpose**: Represents one end-to-end autonomous run managed by the editor plugin.
- **Fields**:
  - `request_id`: Source Automated Run Request identifier.
  - `session_id`: Editor-side session identifier.
  - `run_id`: Persisted evidence run identifier.
  - `scenario_id`: Scenario identifier.
  - `status`: Current lifecycle status.
  - `play_state`: Editor play session state.
  - `started_at`: Run start timestamp.
  - `ended_at`: Run end timestamp when available.
  - `control_path`: Automation Control Path record.
  - `manifest_path`: Final manifest path when available.
  - `validation_result`: Final Run Validation Result when available.
  - `termination_status`: How play ended.
- **Relationships**:
  - One Automated Run Session is created from one Automated Run Request.
  - One Automated Run Session produces one final Automated Run Result.
  - One Automated Run Session may emit many Lifecycle Status records.

### Lifecycle Status Record

- **Purpose**: Captures a point-in-time machine-readable state transition for the autonomous run.
- **Fields**:
  - `request_id`: Parent request identifier.
  - `run_id`: Parent run identifier.
  - `status`: `received`, `blocked`, `launching`, `awaiting_runtime`, `capturing`, `persisting`, `validating`, `stopping`, `completed`, or `failed`.
  - `details`: Short human-readable explanation.
  - `timestamp`: Status timestamp.
  - `evidence_refs`: Optional manifest or artifact references already known at that point.

### Automated Run Result

- **Purpose**: Final machine-readable outcome returned to the agent after the run finishes or fails.
- **Fields**:
  - `request_id`: Source request identifier.
  - `run_id`: Final run identifier.
  - `final_status`: Completed, blocked, or failed.
  - `failure_kind`: Launch, attachment, capture, persistence, validation, shutdown, or gameplay failure when relevant.
  - `manifest_path`: Final manifest path when available.
  - `output_directory`: Final evidence directory.
  - `validation_result`: Final validation details.
  - `termination_status`: Whether play stopped cleanly, crashed, or was already closed.
  - `completed_at`: Completion timestamp.

### Run Validation Result

- **Purpose**: Confirms whether the evidence bundle produced by the run is safe for agent consumption.
- **Fields**:
  - `manifest_exists`: Whether the manifest file exists.
  - `artifact_refs_checked`: Number of referenced artifacts checked.
  - `missing_artifacts`: List of missing artifact paths.
  - `bundle_valid`: Whether the bundle passed validation.
  - `notes`: Validation notes for the agent.
  - `validated_at`: Validation timestamp.

### Persisted Evidence Bundle

- **Purpose**: Existing manifest-centered scenegraph evidence package produced by the autonomous run.
- **Fields**:
  - `manifest`: Persisted manifest dictionary.
  - `snapshot_artifact`: Scenegraph snapshot artifact.
  - `diagnostics_artifact`: Scenegraph diagnostics artifact.
  - `summary_artifact`: Scenegraph summary artifact.
- **Relationships**:
  - One Persisted Evidence Bundle belongs to one Automated Run Session.

## State Transitions

### Capability Flow

1. `unknown` → project has not been checked yet.
2. `ready` → exactly one eligible project exists and all required control surfaces are available.
3. `blocked` → ambiguity or a prerequisite gap prevents autonomous execution.

### Automated Run Lifecycle

1. `received` → request artifact accepted.
2. `launching` → plugin initiates the editor play session.
3. `awaiting_runtime` → waiting for debugger-backed runtime attachment.
4. `capturing` → startup or explicit capture occurs.
5. `persisting` → latest bundle is being written.
6. `validating` → manifest and referenced artifacts are being checked.
7. `stopping` → plugin ends the play session after validation.
8. `completed` → result artifact written successfully.
9. `blocked` → prerequisites or target selection prevented execution.
10. `failed` → a lifecycle stage failed and the result records the failure kind.

### Termination Flow

1. `not_started` → no play session exists yet.
2. `running` → editor play session is active.
3. `stopping` → plugin requested shutdown.
4. `stopped_cleanly` → play ended as intended.
5. `already_closed` → runtime ended before requested shutdown.
6. `crashed` → runtime exited unexpectedly.
7. `shutdown_failed` → stop request did not complete as expected.

## Invariants

- Only one eligible open project may be targeted in the first release.
- Only one active Automated Run Session may be in progress for that project at a time.
- Overlapping run requests must be rejected with a blocked result rather than queued.
- A run cannot report `completed` unless `bundle_valid` is true.
- A run cannot report success if `termination_status` is unknown after validation.
- A final result must always identify the failure kind when `final_status` is `failed`.
- Evidence reported for a run must match the run’s `run_id` and output directory.