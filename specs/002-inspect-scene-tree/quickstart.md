# Quickstart: Inspect Scene Tree

## Goal

Validate the editor-first scenegraph inspection loop in a deterministic example project and confirm the resulting evidence bundle is usable by agents after the run.

## 1. Prepare the Example Project

1. Open `examples/pong-testbed/` in the Godot editor once the feature implementation is present.
2. Confirm the project references `harness/inspection-run-config.json` and the example scenes under `scenes/`.
3. Enable the harness addon from the project plugin settings and confirm the editor exposes the Scenegraph Harness dock.

## 2. Validate Startup And Manual Capture

1. Start a play session from `scenes/main.tscn` in the Godot editor.
2. Confirm the harness captures an automatic startup snapshot that matches the structure in `harness/expected-live-scenegraph.json`.
3. Trigger a manual capture from the dock while the session is still running.
4. Confirm the latest scenegraph summary includes the active root, bounded node details, and the `manual` trigger reason.

## 3. Validate Diagnostic Capture

1. Run `scenes/missing_node_case.tscn` or `scenes/mismatch_node_case.tscn` in the Godot editor.
2. Swap the active expectation file in `harness/inspection-run-config.json` to `harness/expectations/missing-node.json` or `harness/expectations/mismatch-node.json` for the case you are exercising.
3. Confirm the harness records a missing-node or hierarchy-mismatch diagnostic and takes a failure-triggered snapshot.
4. Confirm the editor surface distinguishes a valid diagnostic result from a transport or capture failure.

## 4. Validate Persisted Evidence

1. End the play session and inspect the generated evidence bundle for the run.
2. Confirm the bundle contains a manifest plus referenced scenegraph snapshot and diagnostic artifacts.
3. Validate the manifest with `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath examples/pong-testbed/harness/expected-evidence-manifest.json` or the generated run manifest.
4. Validate the snapshot and diagnostics with `pwsh ./tools/validate-json.ps1 -InputPath examples/pong-testbed/harness/expected-live-scenegraph.json -SchemaPath specs/002-inspect-scene-tree/contracts/scenegraph-snapshot.schema.json` and `pwsh ./tools/validate-json.ps1 -InputPath examples/pong-testbed/evidence/scenegraph-diagnostics.json -SchemaPath specs/002-inspect-scene-tree/contracts/scenegraph-diagnostics.schema.json`.

## 5. Validate Agent Consumption

1. Open the manifest in VS Code Copilot Chat or point GitHub CLI-based workflows at the run bundle.
2. Confirm the agent can identify whether the run was healthy, missing required nodes, or failed due to capture transport issues by reading the manifest before opening raw artifacts.
3. Confirm the agent can locate the most relevant snapshot and diagnostic files from the artifact references alone.

## Exit Criteria

- The editor plugin exposes useful live scenegraph visibility during playtesting without requiring a custom engine build.
- Startup, manual, and failure-triggered captures all produce bounded scenegraph snapshots.
- Persisted evidence bundles validate and reference the expected snapshot and diagnostic artifacts.
- Agents can understand the run outcome from the manifest-centered contract without relying on a human-written explanation.