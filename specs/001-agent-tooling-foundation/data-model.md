# Data Model: Agent Tooling Foundation

## Entities

### Guidance Layer

- **Purpose**: Represents one scope of stable guidance consumed by agents.
- **Fields**:
  - `id`: Stable identifier.
  - `name`: Human-readable layer name.
  - `scope`: Repo-wide, subtree-specific, workflow-specific, or planning-specific.
  - `primary_consumer`: VS Code Copilot Chat, Copilot CLI, or portable.
  - `precedence_rule`: How this layer interacts with broader or narrower layers.
  - `artifact_paths`: Files that implement the layer.
- **Relationships**:
  - One Guidance Layer can be implemented by many Tooling Artifacts.

### Tooling Artifact

- **Purpose**: Represents a concrete shipped asset used by agents.
- **Fields**:
  - `id`: Stable artifact identifier.
  - `type`: Instruction file, AGENTS guidance, prompt, agent definition, helper script, eval fixture, or skill bundle.
  - `platform_target`: Primary Agent Platform value.
  - `location`: Repository path.
  - `trigger_conditions`: When the artifact should be used.
  - `required_inputs`: Inputs the artifact assumes.
  - `expected_outputs`: Outputs or side effects the artifact produces.
  - `write_boundary_id`: Optional pointer to the write boundary that governs autonomous edits.
  - `evaluation_status`: Proposed, active, retained, narrowed, or removed.
- **Relationships**:
  - Belongs to one Guidance Layer.
  - Can have zero or one Write Boundary.
  - Must be covered by one or more Evaluation Scenarios.

### Primary Agent Platform

- **Purpose**: Captures the platform whose behavior defines first-release compatibility.
- **Fields**:
  - `name`: Platform name.
  - `priority_rank`: Relative priority among supported consumers.
  - `supported_surfaces`: VS Code Copilot Chat, Copilot CLI.
  - `portability_policy`: Rules for keeping artifacts reusable elsewhere.

### Write Boundary

- **Purpose**: Defines the autonomous edit scope for a tooling artifact.
- **Fields**:
  - `id`: Stable boundary identifier.
  - `artifact_id`: Owning tooling artifact.
  - `allowed_paths`: Repository paths the artifact may modify.
  - `allowed_edit_types`: Create, update, delete, or read-only.
  - `stop_conditions`: Signals that force the artifact to stop.
  - `escalation_conditions`: Signals that require human review or fallback behavior.
  - `log_output_path`: Where autonomous run records are written.

### Evidence Manifest

- **Purpose**: Canonical machine-readable handoff file for runtime evidence.
- **Fields**:
  - `schema_version`: Contract version.
  - `manifest_id`: Unique manifest identifier.
  - `run_id`: Runtime execution identifier.
  - `scenario_id`: Scenario identity.
  - `status`: Pass, fail, error, or unknown.
  - `summary`: Normalized summary object.
  - `invariants`: Array of invariant outcomes.
  - `artifact_refs`: Array of referenced raw evidence artifacts.
  - `producer`: Metadata about the tool or workflow that assembled the bundle.
  - `validation`: Contract validation result.
  - `created_at`: Timestamp.
- **Relationships**:
  - One Evidence Manifest references many Run Evidence References.

### Run Evidence Reference

- **Purpose**: Locates a raw evidence file behind the manifest.
- **Fields**:
  - `kind`: Trace, events, scene snapshot, stdout summary, invariant report, or autonomous-run record.
  - `path`: Relative artifact path.
  - `media_type`: JSON, JSONL, text, or other supported type.
  - `description`: Short explanation of what the artifact contains.
  - `relevance_window`: Optional frame or time range.

### Evaluation Scenario

- **Purpose**: Measures whether a tooling artifact improves real agent work.
- **Fields**:
  - `id`: Stable scenario identifier.
  - `goal`: Task the agent must complete.
  - `target_surface`: VS Code Copilot Chat or Copilot CLI.
  - `input_assets`: Guidance files, prompts, evidence manifests, or code context supplied.
  - `expected_behavior`: Required guidance selection, output form, or change proposal.
  - `success_metrics`: Measured outcomes.
  - `failure_signals`: Observable regressions or misroutes.

## State Transitions

### Tooling Artifact Lifecycle

1. `proposed` → artifact is defined but not yet evaluated.
2. `active` → artifact is shipped and under active evaluation.
3. `retained` → artifact passed usefulness thresholds.
4. `narrowed` → artifact remains but with reduced scope after evaluation.
5. `removed` → artifact failed usefulness or safety evaluation.

### Evidence Manifest Validation

1. `assembled` → manifest created with referenced raw artifacts.
2. `validated` → schema and required-field checks passed.
3. `consumed` → agent used the manifest in an eval or workflow.
4. `archived` → retained for replay, diffing, or regression use.