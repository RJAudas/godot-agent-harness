# Quickstart: Report Build Errors On Run

## Goal

Implement build-failure reporting as a narrow extension of the existing autonomous editor evidence loop so an agent can fix compile-time problems and retry without human narration.

## Implementation Outline

1. Extend the plugin-owned automation broker path in `addons/agent_runtime_harness/editor/` rather than creating a new diagnostics transport.
2. Add a distinct `build` failure classification and the supporting payload fields needed for normalized diagnostics and raw build output.
3. Keep successful runs on the current manifest-centered path with no behavior change beyond backward-compatible contract additions.
4. Add deterministic validation assets that prove build-failed, blocked, stale-manifest, and successful-run outcomes.

## Primary Source Areas

- `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`
- `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`
- `addons/agent_runtime_harness/shared/inspection_constants.gd`
- `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`
- `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`

## Recommended Validation Flow

1. Create or seed a broken example-project case in `examples/pong-testbed/` that produces a compile, parse, or blocking resource-load error during launch.
2. Request an autonomous run through the existing editor-evidence workflow and confirm the final run result reports `failureKind = build` with diagnostics for the active `runId`.
3. Confirm the run result leaves `manifestPath = null`, includes validation notes that no new bundle was produced, and does not point to a stale manifest from a previous successful run.
4. Re-run the healthy example-project flow and confirm the existing manifest-centered evidence bundle still validates successfully with no build payload fields added.
5. Measure request-to-failed-result timing for the seeded build-failure path and confirm it stays within the 30-second target.
6. Validate any updated JSON contracts and related PowerShell test surfaces.

## Validation Commands

```powershell
pwsh ./tools/validate-json.ps1 -InputPath <run-result-json> -SchemaPath specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json
pwsh ./tools/tests/run-tool-tests.ps1
```

## Expected Outcomes

- Build-failed runs expose normalized diagnostics and raw build-output text through the existing result contract.
- Build-failed runs are routed from `run-result.json` directly and do not require a manifest lookup.
- Successful runs continue to expose `evidence-manifest.json` through the current manifest-centered workflow.
- Agents can decide to repair code and retry from the reported artifacts alone.
