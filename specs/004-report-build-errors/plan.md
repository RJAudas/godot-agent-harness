
# Implementation Plan: Report Build Errors On Run

**Branch**: `[004-report-build-errors]` | **Date**: 2026-04-12 | **Spec**: [specs/004-report-build-errors/spec.md](specs/004-report-build-errors/spec.md)
**Input**: Feature specification from `/specs/004-report-build-errors/spec.md`

## Summary

Extend the existing autonomous editor evidence loop so a run that fails before runtime attachment because of an editor-reported build, parse, or blocking resource-load error returns actionable machine-readable diagnostics through the same plugin-owned broker artifacts the agent already reads today. The plan keeps the file-broker control path, lifecycle status artifact, and final run-result artifact as the only first-release reporting surfaces, adds normalized build diagnostics plus the raw editor build-output snippet to that contract, prevents stale manifests from being misreported on build-failed runs, and preserves the successful manifest-centered evidence flow unchanged.

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon scripts, Markdown planning artifacts, JSON automation contracts, and existing PowerShell validation scripts where contract or fixture changes require them  
**Primary Dependencies**: Godot `EditorPlugin`-owned control surfaces, the existing automation broker in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`, run coordination in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, artifact writing in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`, shared automation constants in `addons/agent_runtime_harness/shared/inspection_constants.gd`, the current editor-evidence loop contracts under `specs/003-editor-evidence-loop/contracts/`, and JSON validation support under `tools/validate-json.ps1`  
**Storage**: Machine-readable lifecycle and run-result JSON artifacts under project-local harness automation result paths; existing manifest-centered runtime evidence under project evidence directories; feature planning artifacts under `specs/004-report-build-errors/`  
**Testing**: Deterministic example-project validation in `examples/pong-testbed/` with seeded compile, parse, or resource-load failures; JSON schema validation for any run-result contract changes; existing PowerShell tool tests if helper scripts or schemas are extended; combined validation when contract changes affect both plugin behavior and existing deterministic tooling  
**Target Platform**: Godot 4.x editor with the project already open on the same machine as VS Code, Windows first with choices that remain portable where practical  
**Project Type**: Editor addon and debugger-aware automation contract extension layered onto the current plugin-owned file broker  
**Performance Goals**: Report build-failed runs with diagnostics inside the spec target of 30 seconds; keep automation polling and failure classification lightweight enough not to degrade normal editor playtesting; preserve current successful-run timing and evidence publication behavior  
**Constraints**: Plugin-first, no engine fork, no automatic retry behavior in the plugin, no parallel diagnostics channel outside the existing broker artifacts, no stale manifest reuse, preserve successful manifest-centered evidence flow, keep packaged build pipelines out of scope for v1  
**Scale/Scope**: Primarily touches `addons/agent_runtime_harness/editor/`, `addons/agent_runtime_harness/shared/`, `specs/003-editor-evidence-loop/contracts/`, feature docs under `specs/004-report-build-errors/`, deterministic validation assets under `examples/pong-testbed/`, and only minimal updates under `tools/` if schema or validation helpers need narrow extensions

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AGENT_TOOLING_FOUNDATION.md`, `docs/AI_TOOLING_AUTOMATION_MATRIX.md`, `docs/AI_TOOLING_BEST_PRACTICES.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `specs/003-editor-evidence-loop/spec.md`, `specs/003-editor-evidence-loop/plan.md`, `specs/003-editor-evidence-loop/data-model.md`, `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`, `specs/004-report-build-errors/spec.md`, `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`, `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`, `addons/agent_runtime_harness/shared/inspection_constants.gd`
- **External Docs**: Godot editor plugins overview, `EditorPlugin`, `EditorDebuggerPlugin`, and `EditorDebuggerSession` references as cited in the spec and `docs/GODOT_PLUGIN_REFERENCES.md`
- **Source References**: No `../godot` source files were inspected for this plan. Current repository docs, contracts, and addon surfaces were sufficient to define a plugin-first implementation path.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays within editor plugin, current automation broker, existing artifact-writing surfaces, and documented Godot extension points, with no engine changes planned.
- [x] Reference coverage complete: internal docs, external Godot references, and current repo source surfaces are cited for each key design decision.
- [x] Runtime evidence defined: the plan keeps lifecycle status and final run-result artifacts as the machine-readable product surface and explicitly defines build diagnostics as part of that evidence.
- [x] Test loop defined: each user story maps to deterministic seeded build-failure, stale-evidence, and successful-run validation paths in the example project.
- [x] Reuse justified: the plan extends the existing editor-evidence loop contract and broker instead of introducing a second diagnostics transport or new automation subsystem.

## Project Structure

### Documentation (this feature)

```text
specs/004-report-build-errors/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Source Code (repository root)

```text
addons/
└── agent_runtime_harness/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AGENT_TOOLING_FOUNDATION.md
├── AI_TOOLING_AUTOMATION_MATRIX.md
├── AI_TOOLING_BEST_PRACTICES.md
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

specs/
└── 003-editor-evidence-loop/

tools/
├── automation/
└── tests/
```

**Structure Decision**: Keep implementation centered in `addons/agent_runtime_harness/editor/` because build-failure detection and reporting belong to the same open-editor broker that already owns lifecycle and run-result publication. Extend `addons/agent_runtime_harness/shared/inspection_constants.gd` only as needed for new failure-kind or payload semantics. Update the existing editor-evidence loop contracts under `specs/003-editor-evidence-loop/contracts/` where the current run-result schema is the authoritative shared contract, and use `specs/004-report-build-errors/` for feature-specific design artifacts that explain the extension. Use `examples/pong-testbed/` for deterministic broken-project fixtures and touch `tools/` only where schema validation or existing regression coverage needs narrow updates.

## Implementation Alternatives

### Preferred V1 Path: Extend the current lifecycle and run-result artifacts with build-failure details

- Detect editor-reported build, parse, or blocking resource-load failures during the existing launch and runtime-attachment boundary.
- Keep the current file-broker control path and artifact locations unchanged.
- Add normalized build diagnostics and a raw build-output snippet to the existing machine-readable result surface instead of creating a new artifact type.
- Preserve `manifestPath = null` and explicit failure metadata when no runtime evidence bundle was produced.

### Alternative 1: Separate build-error artifact alongside the run result

- A dedicated build-error JSON artifact could isolate diagnostics from the final run result.
- This is rejected for v1 because it would split the agent’s source of truth across multiple files for the same failed run and weaken the current single-result contract.

### Alternative 2: Treat build problems as generic launch failures with better text only

- The broker could keep the existing failure kinds unchanged and only add richer launch-failure notes.
- This is rejected because the spec requires build or compile failures to be distinguishable from other launch, blocked, or runtime failures.

### Alternative 3: Scrape editor output outside the broker and report it as an external helper result

- A workspace helper could try to collect build output independently and merge it after the fact.
- This is rejected for v1 because it creates a second reporting path, complicates run attribution, and cuts against the plugin-owned evidence surface already established in the repo.

### Escalation Paths Not Planned For V1

- GDExtension is not planned unless the editor plugin surfaces prove unable to observe the required build-failure signals with acceptable fidelity.
- Engine changes remain out of scope unless addon, debugger, and editor surfaces are shown insufficient with cited evidence.

## Phase 0: Research Focus

1. Confirm which editor-observable surfaces can reliably identify build, parse, and blocking resource-load failures before runtime attachment.
2. Confirm where in the current broker lifecycle a build failure should be classified so it remains distinct from blocked, launch, attachment, and gameplay failures.
3. Confirm the smallest contract extension needed for normalized diagnostics and raw build-output snippets while preserving backward compatibility for successful runs.
4. Confirm how stale-manifest prevention should behave when a run fails before any new evidence bundle is produced.
5. Confirm the deterministic validation shape for seeded broken-project cases in `examples/pong-testbed/`, including multi-error and partial-metadata scenarios.

## Phase 1: Design Focus

1. Design the build-failure detection path in the current automation broker and run coordinator, including when the failure is emitted into lifecycle status and final run result.
2. Design the build-failure data model for normalized diagnostic entries, raw build-output snippets, failure attribution to the active request and run, and manifest absence semantics.
3. Design the contract changes needed in the current automation run-result schema and any supporting contract documentation so agents can consume the new payload deterministically.
4. Design deterministic validation flows for a successful run, a seeded build-failed run, a stale-manifest regression case, and a blocked non-build case.
5. Design any narrow docs or quickstart updates needed so agents and maintainers know how the feature extends the existing editor-evidence workflow.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the preferred path still relies on the current editor addon, shared constants, broker artifacts, and documented Godot plugin surfaces only.
- [x] Reference coverage remains complete after design: plan decisions continue to map back to repo docs, adjacent editor-evidence-loop artifacts, and cited Godot references.
- [x] Runtime evidence remains the product surface: agents still read lifecycle and final run-result artifacts first, with the manifest-centered bundle remaining authoritative when a run reaches capture and persistence.
- [x] Test loop remains defined after design: deterministic validation continues to cover successful, blocked, and build-failed runs with machine-readable outcomes.
- [x] Reuse remains justified after design: the feature stays an incremental extension of the current broker and contract rather than a new automation subsystem.

## Phase 2 Preview

Expected tasks will group into:

1. Broker and coordinator behavior: classify build-failed runs in the launch-to-attach window, capture the current run’s diagnostics, and publish them through lifecycle and final-result artifacts.
2. Shared contract and constant updates: extend failure-kind semantics, payload fields, and schema documentation without regressing current successful-run consumers.
3. Artifact and evidence safety: ensure `manifestPath`, validation notes, and stale-artifact behavior remain correct when no new bundle is produced.
4. Example-project and regression validation: add deterministic broken-project fixtures and regression coverage for multi-error, partial-metadata, stale-manifest, and successful-run paths.
5. Supporting docs and validation assets: update feature-local design artifacts and only the narrow tool or test surfaces needed to validate the contract extension.

## Complexity Tracking

No constitution violations are expected. The preferred path deliberately stays narrow: reuse the existing automation broker, extend the current run-result contract, and validate the new failure mode with deterministic fixtures. If implementation proves the editor surfaces cannot reliably expose build-failure information, the first fallback to evaluate is a documented plugin-level observation enhancement inside the same broker path, not a new external helper, IPC layer, GDExtension, or engine change.
