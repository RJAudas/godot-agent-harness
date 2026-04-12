# Contract: Scenegraph Inspection

## Purpose

Define the first-release contract between the editor plugin, runtime collector, and persisted evidence bundle for editor-first scenegraph inspection.

## Live Capture Contract

The runtime collector must be able to publish a scenegraph snapshot to the editor for three trigger classes:

- `startup`: automatic capture taken when the editor play session becomes ready.
- `manual`: capture requested from the editor dock during an active session.
- `failure`: automatic capture taken when expectation evaluation or transport health signals a failed inspection outcome.

Each live capture result should include:

- Session and run identifiers.
- Trigger metadata.
- Snapshot status: complete, partial, or error.
- Root scene metadata.
- Array of bounded node records using the core inspection property set.
- Array of structured diagnostics linked to expectation identifiers when applicable.

## Node Record Contract

Each serialized node record should expose:

- `path`
- `type`
- `parent_path`
- `owner_path` when available
- `groups` when present
- `script_class` when available
- `visibility_state` when meaningful
- `processing_state` when available
- `transform_state` with node-type-appropriate transform fields
- `properties` for any additional bounded core inspection values

The first release should not attempt to serialize arbitrary inspector state outside the clarified core inspection set.

## Expectation And Diagnostic Contract

Scenario expectations should support hybrid matching:

- Exact path matching for stable runtime nodes.
- Selector-based matching for dynamic nodes using name, group, type, or script-class identity.

The first release should emit at least these diagnostic outcomes:

- `missing_node`
- `hierarchy_mismatch`
- `capture_error`

Each diagnostic should include the expectation identifier when one exists, the snapshot identifier, a machine-readable status, and a short explanation that an agent can quote or summarize.

## Persisted Artifact Contract

Post-run evidence should reuse the existing manifest-centered bundle pattern.

Recommended artifact kinds:

- `scenegraph-snapshot`
- `scenegraph-diagnostics`
- `scenegraph-summary`

The manifest summary should let an agent determine:

- whether capture succeeded,
- whether required nodes were missing or misplaced,
- which snapshot is the most relevant,
- and whether the run ended with a transport or persistence error.

## Reuse Constraint

Payload fields should be named so a future runtime-only harness can emit the same snapshot and diagnostic shapes without depending on editor-only concepts beyond optional producer metadata.