## Runtime Harness
- This project includes the `agent_runtime_harness` addon for machine-readable runtime scenegraph evidence.
- `project.godot` should enable `res://addons/agent_runtime_harness/plugin.cfg` and register the `ScenegraphHarness` autoload at `res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd`.
- Both the editor plugin and runtime autoload default to `res://harness/inspection-run-config.json` for session configuration.
- Persisted evidence goes to `res://evidence/scenegraph/latest` by default and consists of `evidence-manifest.json`, `scenegraph-summary.json`, `scenegraph-diagnostics.json`, and `scenegraph-snapshot.json`.

## Runtime Evidence Workflow
- When runtime evidence exists, read `evidence/scenegraph/latest/evidence-manifest.json` first and inspect raw artifacts only when the manifest points to them.
- The default read order is: `evidence-manifest.json`, then `scenegraph-summary.json`, then `scenegraph-diagnostics.json` if the run is partial or fail, then `scenegraph-snapshot.json` for detailed tree inspection.
- For runtime verification requests, prefer proving behavior from the persisted scenegraph artifacts instead of relying on a human description of what happened in the editor.
- When asked whether a runtime node exists, report the manifest status first, then the node path if found, and then any diagnostic or capture limitation that affects confidence.