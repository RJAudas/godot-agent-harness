
# Implementation Plan: Autonomous Editor Evidence Loop

**Branch**: `[003-create-feature-branch]` | **Date**: 2026-04-12 | **Spec**: [specs/003-editor-evidence-loop/spec.md](specs/003-editor-evidence-loop/spec.md)
**Input**: Feature specification from `/specs/003-editor-evidence-loop/spec.md`

## Summary

Close the edit-run-capture-persist-validate-stop loop for a Godot project that is already open in the editor by adding an editor-owned automation path on top of the existing scenegraph harness. The plan keeps the current runtime capture, debugger transport, and manifest-centered evidence bundle as the core product surface, then layers in a deterministic automation broker that can accept a machine-readable run request, start the editor play session, coordinate capture and persistence, validate the resulting evidence bundle, stop the session, and return a machine-readable run result. Where the implementation path is not fully proven yet, the plan captures concrete alternatives and explicitly defers the ones that add more complexity than the first release can justify.

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon and runtime scripts, Markdown planning artifacts, JSON request and result contracts, and optional PowerShell support scripts for deterministic local workflows  
**Primary Dependencies**: Godot `EditorPlugin`, editor-owned run-control surfaces, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, existing harness runtime scripts under `addons/agent_runtime_harness/`, evidence helpers under `tools/evidence/`, and automation guardrails under `tools/automation/`  
**Storage**: Machine-readable JSON request, capability, status, and result artifacts under project-local harness directories; manifest-centered scenegraph evidence under project evidence output directories; feature docs under `specs/003-editor-evidence-loop/`  
**Testing**: Deterministic Godot editor validation in `examples/pong-testbed/`, manifest validation with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`, JSON validation with `pwsh ./tools/validate-json.ps1` where applicable, and existing PowerShell test coverage if new helper scripts are introduced  
**Target Platform**: Godot 4.x editor with the project already open on the same machine as VS Code, Windows first with design choices that remain portable where practical  
**Project Type**: Editor addon plus runtime addon and debugger integration, with a local automation broker contract for agent-driven playtest control  
**Performance Goals**: Reach a validated persisted evidence bundle and stopped play session within the spec target of 3 minutes; keep automation polling or coordination light enough to avoid noticeable editor stalls during normal playtesting; avoid stale-artifact confusion across repeated runs  
**Constraints**: Plugin-first, no engine fork, packaged executable launches out of scope, mandatory evidence validation before success, single eligible open project in v1, machine-readable blocked results instead of hidden manual fallback, reuse the existing manifest-centered evidence contract before inventing new bundle formats  
**Scale/Scope**: Primarily touches `addons/agent_runtime_harness/`, addon template assets under `addons/agent_runtime_harness/templates/project_root/`, deterministic validation assets under `examples/pong-testbed/`, feature docs under `specs/003-editor-evidence-loop/`, and only minimal helper tooling under `tools/` if deterministic submission or validation helpers are justified

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AGENT_TOOLING_FOUNDATION.md`, `docs/AI_TOOLING_AUTOMATION_MATRIX.md`, `docs/AI_TOOLING_BEST_PRACTICES.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `specs/002-inspect-scene-tree/spec.md`, `specs/002-inspect-scene-tree/plan.md`, `specs/002-inspect-scene-tree/research.md`, `specs/002-inspect-scene-tree/data-model.md`, `specs/002-inspect-scene-tree/quickstart.md`, `addons/agent_runtime_harness/plugin.gd`, `addons/agent_runtime_harness/editor/scenegraph_dock.gd`, `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`, `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`, `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`, `addons/agent_runtime_harness/shared/inspection_constants.gd`
- **External Docs**: Godot editor plugins overview, `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, autoload singletons, and scene tree documentation as cited in the spec
- **Source References**: No `../godot` source files were inspected for this plan. Current repo docs plus the existing addon, debugger, and runtime harness surfaces were sufficient to define a plugin-first implementation path.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays within editor plugin, runtime addon, debugger transport, and project-local automation artifacts, with no engine changes planned.
- [x] Reference coverage complete: internal docs, external Godot references, and current repo source surfaces are cited for the key technical decisions.
- [x] Runtime evidence defined: the plan names the capability report, run lifecycle record, manifest-centered evidence bundle, and validation result as machine-readable outputs.
- [x] Test loop defined: each story maps to a deterministic editor-run validation path in the example project, including blocked, healthy, and failure outcomes.
- [x] Reuse justified: the plan extends the existing scenegraph harness, manifest bundle, and automation safety guidance instead of creating a separate runtime-evidence system.

## Project Structure

### Documentation (this feature)

```text
specs/003-editor-evidence-loop/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── editor-evidence-loop-contract.md
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
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

tools/
├── automation/
└── evidence/
```

**Structure Decision**: Keep the implementation centered in `addons/agent_runtime_harness/` because the open-editor control loop belongs to the plugin and its existing debugger bridge. Extend the addon’s project-root templates so a target game can receive any new automation request or result paths during the existing one-time deployment step. Use `examples/pong-testbed/` for deterministic validation scenes and expected artifacts. Touch `tools/evidence/` only if the existing manifest validators need narrow updates, and touch `tools/automation/` only if a deterministic workspace-side helper or run-log contract is needed to support approval-free automation safely.

## Implementation Alternatives

### Preferred V1 Path: Editor-owned automation broker plus workspace-visible request and result artifacts

- The Godot plugin owns launch, capture, persist, validate, and stop orchestration inside the open editor session.
- A VS Code agent triggers that flow by writing a machine-readable run request into a project-local harness path the plugin watches or polls.
- The plugin writes capability and result artifacts back into the workspace so the agent can inspect them deterministically.
- This path fits the repo’s automation matrix: the cross-tool handoff is a deterministic local operation, while the agent remains responsible for open-ended reasoning over the result.

### Alternative 1: Editor script or secondary Godot command entrypoint that invokes the same broker

- This remains viable if a lightweight workspace-side trigger is needed before a persistent in-editor listener is trusted.
- It is not the preferred first path because it risks starting a second editor context or drifting away from the “already open in the designer” assumption.

### Alternative 2: Local IPC server exposed by the plugin

- A local HTTP, socket, or named-pipe broker could provide lower-latency command handling and richer progress streaming.
- It is deferred because it adds security, lifecycle, and cleanup complexity that the first release does not need if file-based request and result artifacts are sufficient.

### Alternative 3: External UI automation

- Simulated keystrokes or window automation could trigger the editor play button without plugin changes.
- This is rejected for v1 because it is brittle, platform-specific, hard to validate, and violates the repo’s preference for machine-readable plugin-level control over hidden human-like behavior.

### Escalation Paths Not Planned For V1

- GDExtension remains unnecessary unless editor-side or scripting-level control surfaces prove insufficient during implementation.
- Engine changes remain out of scope unless supported addon and debugger layers are proven inadequate with cited evidence.

## Phase 0: Research Focus

1. Confirm the lowest-complexity editor-owned control path for a project that is already open in Godot and determine whether the plugin can own both play start and play stop directly.
2. Confirm the best workspace-to-editor request channel for the first release, comparing file-based command ingestion against script-invocation and IPC alternatives.
3. Define the machine-readable capability report, run request, lifecycle status, and final result contracts that agents will rely on before and after the run.
4. Confirm how the existing scenegraph runtime and debugger bridge should be extended so launch control and post-validation shutdown integrate cleanly with today’s capture and persistence flow.
5. Confirm stale-evidence prevention, single-project targeting, and blocked-result semantics so the first release cannot silently operate on the wrong editor session.

## Phase 1: Design Focus

1. Design the editor automation broker, including request intake, capability checks, run lifecycle coordination, and session shutdown behavior.
2. Design the machine-readable contracts for capability results, run requests, lifecycle events or status snapshots, and final run results, including explicit shutdown readiness and blocked concurrency results.
3. Design the bridge and runtime changes needed to reuse existing capture and persistence behavior while adding automation-aware state transitions.
4. Design the deterministic validation flow in `examples/pong-testbed/`, covering a healthy autonomous run, a blocked prerequisite case, and at least one expectation-driven failure case.
5. Design any minimal workspace-side helper surfaces, deployment-template changes, or automation run-log integration needed to make the loop reliable and auditable.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the proposed default path still relies on addon, runtime autoload, debugger transport, and project-local artifacts only.
- [x] Reference coverage remains complete after design: plan decisions still map back to repo docs, existing addon code, and cited Godot plugin references.
- [x] Runtime evidence remains the product surface: the new automation layer routes agents to capability reports, run results, and the existing manifest-centered evidence bundle.
- [x] Test loop remains defined after design: deterministic example-project validation still proves ready, blocked, successful, and failed runs.
- [x] Reuse remains justified after design: the plan reuses the scenegraph harness, evidence manifest, and automation-safety patterns instead of introducing a parallel runtime control stack.

## Phase 2 Preview

Expected tasks will group into:

1. Editor automation broker: add plugin-side request intake, capability checks, lifecycle coordination, and play start and stop control.
2. Bridge and runtime integration: extend the existing debugger bridge and runtime coordinator to support automation states without breaking current capture and persistence behavior.
3. Contracts and deployment assets: add request, capability, and result contract docs plus any project-root template assets required during one-time deployment.
4. Example-project validation: add deterministic fixtures and evidence expectations in `examples/pong-testbed/` that prove healthy, blocked, and failing autonomous runs.
5. Minimal helper tooling and docs: add only the scripts or guidance needed to submit requests deterministically, validate outputs, measure repeated-run reliability and timing, and keep autonomous actions within declared boundaries.

## Complexity Tracking

No constitution violations are expected. The preferred path intentionally stays conservative: an editor-owned automation broker layered over the existing scenegraph harness is sufficient unless implementation proves that the open editor cannot expose stable run-control surfaces. If that blocker appears, the first fallback to evaluate is a secondary script-invocation path that still routes through the same plugin-owned orchestration rather than jumping directly to IPC, GDExtension, or engine changes.
