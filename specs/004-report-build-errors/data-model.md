# Data Model: Report Build Errors On Run

## Entities

### Build Diagnostic Entry

- **Purpose**: Represents one editor-reported build, parse, or blocking resource-load problem associated with the active run.
- **Fields**:
  - `resourcePath`: Affected script, scene, or resource path when available.
  - `message`: Normalized error text for agent consumption.
  - `severity`: Reported severity such as `error`, `warning`, or `unknown`.
  - `line`: Source line when the editor reports it.
  - `column`: Source column when the editor reports it.
  - `sourceKind`: `script`, `scene`, `resource`, or `unknown`.
  - `code`: Optional diagnostic code or identifier when available.
  - `rawExcerpt`: The raw line or snippet from editor build output that corresponds to this diagnostic.

### Build Failure Report

- **Purpose**: Logical view of the final automation run result when `finalStatus = failed` and `failureKind = build`.
- **Fields**:
  - `requestId`: Source automation request identifier.
  - `runId`: Active run identifier.
  - `finalStatus`: Always `failed` for this entity.
  - `failureKind`: `build`.
  - `buildFailurePhase`: Whether the failure was detected during `launching` or `awaiting_runtime`.
  - `buildDiagnostics`: Array of Build Diagnostic Entry values.
  - `rawBuildOutput`: Ordered raw output lines or snippets attributed to the active run.
  - `manifestPath`: Always `null` when no new evidence bundle was produced.
  - `outputDirectory`: Intended evidence output directory for the run.
  - `validationResult`: Validation result confirming no new manifest was produced for this run.
  - `terminationStatus`: Whether play never started, was already closed, or exited unexpectedly.
  - `completedAt`: Final timestamp for the failed result.

### Lifecycle Status Record

- **Purpose**: Point-in-time machine-readable state update for the automation broker.
- **Fields**:
  - `requestId`: Parent request identifier.
  - `runId`: Parent run identifier.
  - `status`: Existing lifecycle state such as `launching`, `awaiting_runtime`, or `failed`.
  - `details`: Human-readable status summary.
  - `timestamp`: Status timestamp.
  - `failureKind`: Optional failure classification when the status represents failure.
  - `buildFailurePhase`: Whether the build failure was observed during `launching` or `awaiting_runtime`.
  - `buildDiagnosticCount`: Number of build diagnostics currently known.
  - `rawBuildOutputAvailable`: Whether raw build output is attached in the final result.

### Automation Run Result

- **Purpose**: Shared final machine-readable outcome for any automation run, including successful, blocked, and build-failed paths.
- **Fields**:
  - `requestId`: Source request identifier.
  - `runId`: Active run identifier.
  - `finalStatus`: `completed`, `blocked`, or `failed`.
  - `failureKind`: Existing failure kinds plus `build`.
  - `buildFailurePhase`: Optional phase for build-failed runs.
  - `buildDiagnostics`: Optional normalized diagnostic array for build-failed runs.
  - `rawBuildOutput`: Optional raw build-output lines or snippets for build-failed runs.
  - `manifestPath`: Manifest path for successful runs and `null` for build-failed runs.
  - `outputDirectory`: Run output directory.
  - `validationResult`: Validation details for successful or build-failed paths.
  - `terminationStatus`: Final play-session status.
  - `completedAt`: Final timestamp.

### Run Validation Result

- **Purpose**: Describes whether a run produced a valid evidence bundle or correctly reported its absence.
- **Fields**:
  - `manifestExists`: Whether a manifest exists for the active run.
  - `artifactRefsChecked`: Number of referenced artifacts checked.
  - `missingArtifacts`: Missing artifact list when a manifest was expected.
  - `bundleValid`: Whether the bundle is valid for agent consumption.
  - `notes`: Validation notes, including explicit no-manifest notes for build-failed runs.
  - `validatedAt`: Validation timestamp.

## State Transitions

### Build-Failed Run Lifecycle

1. `received` → request accepted.
2. `launching` → editor begins the playtest launch flow.
3. `failed` with `failureKind = build` → build, parse, or blocking resource-load diagnostics are observed before runtime attachment.

### Attachment-Boundary Failure Variant

1. `received` → request accepted.
2. `launching` → launch requested.
3. `awaiting_runtime` → plugin waits for runtime attachment.
4. `failed` with `failureKind = build` → editor surfaces build-related diagnostics before runtime attachment completes.

### Successful Run Lifecycle

1. `received` → `launching` → `awaiting_runtime`.
2. `capturing` → `persisting` → `validating` → `stopping`.
3. `completed` with a valid manifest-centered evidence bundle.

## Invariants

- A build-failed run must keep `failureKind = build` and must not be reported as blocked, attachment, or gameplay failure.
- A build-failed run must be attributable to exactly one `requestId` and `runId`.
- A build-failed run must not reuse a manifest from a previous run as its current evidence.
- When a build-failed run has `manifestPath = null`, validation notes must explain that no new evidence bundle was produced.
- A build-failed run should carry at least one normalized diagnostic entry or at least one raw build-output line so the result remains actionable.
- Successful runs must continue using the existing manifest-centered evidence flow without requiring build-failure payloads.