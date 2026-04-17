## Runtime Harness
- This project includes the `agent_runtime_harness` addon for machine-readable runtime scenegraph evidence.
- `project.godot` should enable `res://addons/agent_runtime_harness/plugin.cfg` and register the `ScenegraphHarness` autoload at `res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd`.
- Both the editor plugin and runtime autoload default to `res://harness/inspection-run-config.json` for session configuration.
- Persisted evidence goes to `res://evidence/scenegraph/latest` by default and consists of `evidence-manifest.json`, `scenegraph-summary.json`, `scenegraph-diagnostics.json`, and `scenegraph-snapshot.json`.

## Runtime Evidence Workflow
- Use **ordinary tests** for unit, contract, framework, and other non-runtime checks.
- Use **Scenegraph Harness runtime verification** for requests such as "verify at runtime," "test the running code," "make sure the node appears in game," "confirm the node exists while playing," or other runtime-visible outcomes.
- Use **combined validation** when a change affects runtime-visible behavior and there is already a direct deterministic test surface. Run the existing tests plus the harness flow, but do not invent new ordinary tests only to satisfy the rule.
- If the user already points to a scenegraph evidence manifest and only wants diagnosis, keep the task in `godot-evidence-triage` mode instead of starting a fresh run.
- When runtime evidence exists, read `evidence/scenegraph/latest/evidence-manifest.json` first and inspect raw artifacts only when the manifest points to them.
- The default read order is: `evidence-manifest.json`, then `scenegraph-summary.json`, then `scenegraph-diagnostics.json` if the run is partial or fail, then `scenegraph-snapshot.json` for detailed tree inspection.
- For runtime verification requests, prefer proving behavior from the persisted scenegraph artifacts instead of relying on a human description of what happened in the editor.
- For end-to-end runtime verification, read `harness/automation/results/capability.json` first, request or inspect a brokered run under `harness/automation/requests/` and `harness/automation/results/`, then inspect the persisted bundle manifest.
- When asked whether a runtime node exists, report the manifest status first, then the node path if found, and then any diagnostic or capture limitation that affects confidence.
- Report harness bugs or automation-contract defects at `https://github.com/RJAudas/godot-agent-harness/issues`.
