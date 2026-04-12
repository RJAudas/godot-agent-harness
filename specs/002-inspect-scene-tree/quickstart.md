# Quickstart: Inspect Scene Tree

## Goal

Validate the editor-first scenegraph inspection loop in a deterministic example project and confirm the resulting evidence bundle is usable by agents after the run.

## 1. Prepare the Example Project

1. Open `examples/pong-testbed/` in the Godot editor once the feature implementation is present.
2. Enable the harness addon from the project plugin settings.
3. Confirm the editor exposes the harness dock and that the project can enter a normal play session.

## 2. Validate Startup And Manual Capture

1. Start a play session from the Godot editor.
2. Confirm the harness captures an automatic startup snapshot and shows a concise summary in the dock.
3. Trigger a manual capture from the dock while the session is still running.
4. Confirm the latest scenegraph summary includes the active root, bounded node details, and the capture trigger reason.

## 3. Validate Diagnostic Capture

1. Run the deterministic validation case in `examples/pong-testbed/` that omits or misplaces an expected node.
2. Confirm the harness records a missing-node or hierarchy-mismatch diagnostic and takes a failure-triggered snapshot.
3. Confirm the editor surface distinguishes a valid diagnostic result from a transport or capture failure.

## 4. Validate Persisted Evidence

1. End the play session and inspect the generated evidence bundle for the run.
2. Confirm the bundle contains a manifest plus referenced scenegraph snapshot and diagnostic artifacts.
3. Validate the manifest with `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>`.
4. If the snapshot or diagnostics adopt a dedicated schema, validate those JSON files with `pwsh ./tools/validate-json.ps1 -InputPath <json-path> -SchemaPath <schema-path>`.

## 5. Validate Agent Consumption

1. Open the manifest in VS Code Copilot Chat or point GitHub CLI-based workflows at the run bundle.
2. Confirm the agent can identify whether the run was healthy, missing required nodes, or failed due to capture transport issues by reading the manifest before opening raw artifacts.
3. Confirm the agent can locate the most relevant snapshot and diagnostic files from the artifact references alone.

## Exit Criteria

- The editor plugin exposes useful live scenegraph visibility during playtesting without requiring a custom engine build.
- Startup, manual, and failure-triggered captures all produce bounded scenegraph snapshots.
- Persisted evidence bundles validate and reference the expected snapshot and diagnostic artifacts.
- Agents can understand the run outcome from the manifest-centered contract without relying on a human-written explanation.