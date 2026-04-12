# Data Model: Inspect Scene Tree

## Entities

### Inspection Session

- **Purpose**: Represents one editor-launched playtest session that can exchange scenegraph data between the editor and the running game.
- **Fields**:
  - `session_id`: Stable session identifier for one editor play session.
  - `run_id`: Persisted evidence run identifier.
  - `scenario_id`: Scenario or validation target identifier.
  - `capture_policy`: Enabled capture triggers for the session.
  - `status`: Initializing, connected, capturing, persisted, closed, or error.
  - `started_at`: Session start timestamp.
  - `ended_at`: Optional end timestamp.
- **Relationships**:
  - One Inspection Session can produce many Scenegraph Snapshots.
  - One Inspection Session can emit many Diagnostics.
  - One Inspection Session persists to one Inspection Manifest.

### Capture Trigger

- **Purpose**: Identifies why a snapshot was taken.
- **Fields**:
  - `trigger_type`: `startup`, `manual`, or `failure`.
  - `requested_by`: Editor plugin, runtime failure handler, or user action.
  - `reason`: Short machine-readable explanation.
  - `frame`: Optional frame number.
  - `timestamp`: Trigger timestamp.

### Scenegraph Snapshot

- **Purpose**: Point-in-time record of the runtime scene hierarchy.
- **Fields**:
  - `snapshot_id`: Stable identifier for the capture.
  - `session_id`: Parent Inspection Session identifier.
  - `run_id`: Persisted evidence run identifier.
  - `trigger`: Capture Trigger object.
  - `root_scene`: Active root scene name or path.
  - `frame`: Optional frame number.
  - `captured_at`: Timestamp.
  - `node_count`: Total serialized node count.
  - `nodes`: Array of Scenegraph Node records.
  - `capture_status`: Complete, partial, or error.
- **Relationships**:
  - One Scenegraph Snapshot contains many Scenegraph Nodes.
  - One Scenegraph Snapshot can be referenced by many Diagnostics.

### Scenegraph Node

- **Purpose**: Bounded serialized view of one runtime node.
- **Fields**:
  - `path`: Runtime node path.
  - `type`: Godot node type.
  - `parent_path`: Parent node path.
  - `owner_path`: Optional owner path.
  - `groups`: Optional array of groups.
  - `script_class`: Script path or class identifier when available.
  - `visibility_state`: Visible or hidden state when meaningful.
  - `processing_state`: Process and physics-process enabled state when available.
  - `transform_state`: Bounded transform fields relevant to the node type.
  - `properties`: Additional bounded core inspection properties.

### Scenario Expectation

- **Purpose**: Declares a node or hierarchy condition that should hold during a scenario.
- **Fields**:
  - `expectation_id`: Stable identifier.
  - `required`: Whether the expectation is mandatory.
  - `matching_mode`: Hybrid matching mode.
  - `exact_path`: Optional stable runtime path.
  - `selectors`: Optional selector list for dynamic matching.
  - `required_parent`: Optional expected parent path or selector.
  - `required_properties`: Optional bounded property expectations.
  - `failure_message`: Default diagnostic wording.
- **Relationships**:
  - One Scenario Expectation can produce zero or more Diagnostics.

### Node Selector

- **Purpose**: Selector-based identity rule for matching dynamic nodes.
- **Fields**:
  - `selector_type`: `name`, `group`, `type`, or `script_class`.
  - `value`: Selector value.
  - `priority`: Match precedence when multiple selectors exist.

### Missing-Node Diagnostic

- **Purpose**: Records that a required expectation could not be matched in a snapshot.
- **Fields**:
  - `diagnostic_id`: Stable identifier.
  - `expectation_id`: Related Scenario Expectation identifier.
  - `snapshot_id`: Snapshot where the failure was observed.
  - `status`: Fail.
  - `message`: Machine-readable summary.
  - `expected_identity`: Exact path or selector summary.

### Hierarchy Mismatch Diagnostic

- **Purpose**: Records that a node was found but attached under the wrong branch or with incomplete identity.
- **Fields**:
  - `diagnostic_id`: Stable identifier.
  - `expectation_id`: Related Scenario Expectation identifier.
  - `snapshot_id`: Snapshot where the mismatch was observed.
  - `observed_path`: Actual matched node path.
  - `expected_parent`: Expected parent identity.
  - `message`: Machine-readable summary.
  - `mismatch_fields`: Which hierarchy or identity fields failed.

### Inspection Manifest

- **Purpose**: Persisted entry point for post-run agent consumption.
- **Fields**:
  - `manifest_id`: Stable manifest identifier.
  - `run_id`: Run identifier.
  - `scenario_id`: Scenario identifier.
  - `status`: Pass, fail, error, or unknown.
  - `summary`: Headline, outcome, and key findings.
  - `artifact_refs`: References to scenegraph snapshots, diagnostics, and supporting artifacts.
  - `validation`: Bundle validation status.
  - `created_at`: Timestamp.
- **Relationships**:
  - One Inspection Manifest references many Scenegraph Snapshots and Diagnostics.

## State Transitions

### Inspection Session Lifecycle

1. `initializing` → editor plugin prepares the play session and capture policy.
2. `connected` → debugger transport is available and runtime collector is reachable.
3. `capturing` → startup, manual, or failure-triggered snapshot work is in progress.
4. `persisted` → manifest and artifact files are written successfully.
5. `closed` → session ended cleanly.
6. `error` → transport or persistence failed and diagnostics explain the failure mode.

### Snapshot Lifecycle

1. `triggered` → a startup, manual, or failure event requests capture.
2. `collected` → runtime collector enumerates nodes and properties.
3. `evaluated` → hybrid expectations are checked against the snapshot.
4. `published` → snapshot is returned to the editor UI.
5. `persisted` → snapshot and diagnostics are written to the evidence bundle.

### Diagnostic Outcome Flow

1. `pending` → expectation has not yet been evaluated for a snapshot.
2. `pass` → expectation matched successfully.
3. `fail_missing` → required node could not be matched.
4. `fail_mismatch` → node matched but hierarchy or identity constraints failed.
5. `error` → capture transport or serialization prevented a reliable result.