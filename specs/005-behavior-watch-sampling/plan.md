
# Implementation Plan: Behavior Watch Sampling

**Branch**: `[005-add-behavior-capture]` | **Date**: 2026-04-14 | **Spec**: [specs/005-behavior-watch-sampling/spec.md](specs/005-behavior-watch-sampling/spec.md)
**Input**: Feature specification from `/specs/005-behavior-watch-sampling/spec.md`

## Summary

Extend the existing editor-launched evidence loop so an autonomous run can carry a bounded `behaviorWatchRequest` for absolute runtime node paths, normalize that request before capture begins, sample only the requested properties at every-frame or every-N-frames cadence within an explicit start-frame offset plus bounded frame-count window, and persist the result as a fixed `trace.jsonl` artifact referenced from the current run's manifest-centered evidence bundle. The preferred v1 path reuses the current automation run request, debugger-backed session configuration, runtime addon, and manifest-writing flow rather than creating a second broker, a live-only stream, or a separate evidence handoff.

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon and runtime scripts, JSON schemas and fixtures for contract surfaces, Markdown design artifacts, and existing PowerShell helpers for request writing and validation  
**Primary Dependencies**: Godot `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, and `EngineDebugger`; the existing automation run request contract in `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`; editor bridge flow in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`; runtime session handling in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`; manifest persistence in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`; artifact registry support in `tools/evidence/artifact-registry.ps1`  
**Storage**: Run-scoped automation request and result JSON under project-local `harness/automation/`; run-scoped evidence bundles under project `res://evidence/...` output directories; fixed `trace.jsonl` colocated with the current run's manifest and related artifacts; feature planning artifacts under `specs/005-behavior-watch-sampling/`  
**Testing**: Contract-fixture validation for request normalization and rejection without launching the game; deterministic Pong editor-evidence runs through the existing automation broker for bounded trace persistence; manifest validation with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`; existing PowerShell regression suite with `pwsh ./tools/tests/run-tool-tests.ps1` when tool or schema helpers change; combined validation because the feature changes runtime-visible behavior and existing deterministic tool surfaces  
**Target Platform**: Godot 4.x editor with the example project already open on the same machine as VS Code; Windows first, while keeping file and contract choices portable across normal editor platforms  
**Project Type**: Editor addon plus runtime addon plus debugger-integration contract extension layered onto the current plugin-owned file broker  
**Performance Goals**: Keep v1 bounded to selected targets and properties only, avoid full-scene continuous logging, support every-frame and every-N-frame sampling for a single Pong ball watch window without materially changing the deterministic playtest flow, and emit the final trace artifact and manifest reference within the spec target of 60 seconds after run completion  
**Constraints**: Plugin-first only; no engine fork; no GDExtension unless addon and debugger surfaces prove insufficient; slice 1 and slice 2 only; absolute runtime node path selectors only; explicit start-frame offset plus bounded frame count; fixed `trace.jsonl`; no trigger windows, invariants, script probes, or always-on full-scene logging in v1; machine-readable outputs required; no stale artifact reuse across runs  
**Scale/Scope**: Primarily touches `addons/agent_runtime_harness/editor/`, `addons/agent_runtime_harness/runtime/`, `addons/agent_runtime_harness/shared/`, `specs/003-editor-evidence-loop/contracts/`, feature-local contracts and design artifacts under `specs/005-behavior-watch-sampling/`, deterministic Pong fixtures under `examples/pong-testbed/`, and narrow evidence or test helpers under `tools/` if the manifest or request-validation surface needs extension

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AGENT_TOOLING_FOUNDATION.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `docs/BEHAVIOR_CAPTURE_SLICES.md`, `specs/003-editor-evidence-loop/spec.md`, `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`, `specs/004-report-build-errors/plan.md`, `specs/005-behavior-watch-sampling/spec.md`, `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`, `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`, `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`, `addons/agent_runtime_harness/shared/inspection_constants.gd`, `tools/evidence/artifact-registry.ps1`, `tools/automation/request-editor-evidence-run.ps1`, `examples/pong-testbed/harness/inspection-run-config.json`, `examples/pong-testbed/harness/automation/requests/run-request.healthy.json`, `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/trace.jsonl`
- **External Docs**: Godot editor plugins overview, `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, autoload singleton guidance, and scene tree basics as cited in the feature spec and `docs/GODOT_PLUGIN_REFERENCES.md`
- **Source References**: No `../godot` source files were inspected for this plan. The current repository docs, contracts, fixtures, and addon surfaces were sufficient to define a plugin-first implementation path.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays inside the editor addon, runtime addon, debugger transport, and existing manifest workflow with no engine changes or native layer planned.
- [x] Reference coverage complete: internal docs, external Godot references, and current repo source surfaces are cited for all key design decisions.
- [x] Runtime evidence defined: the plan names the normalized applied-watch summary, fixed `trace.jsonl` artifact, and manifest artifact reference as the machine-readable product surface.
- [x] Test loop defined: the plan uses deterministic request-fixture validation plus deterministic Pong editor-evidence runs and manifest validation.
- [x] Reuse justified: the preferred path extends the existing automation request, session configuration, and manifest writer instead of creating a new broker or second evidence path.

## Project Structure

### Documentation (this feature)

```text
specs/005-behavior-watch-sampling/
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
    ├── editor/
    ├── runtime/
    └── shared/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AGENT_TOOLING_FOUNDATION.md
├── BEHAVIOR_CAPTURE_SLICES.md
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

specs/
└── 003-editor-evidence-loop/

tools/
├── automation/
├── evidence/
└── tests/
```

**Structure Decision**: Keep the implementation centered in `addons/agent_runtime_harness/` because request normalization, runtime sampling, and manifest persistence all belong to the same plugin-first control path already used for scenegraph capture. Extend `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` for run-request integration, add slice-specific request and trace-row contracts under `specs/005-behavior-watch-sampling/contracts/`, use `examples/pong-testbed/` for deterministic watch-request fixtures and expected outputs, and touch `tools/evidence/` or `tools/tests/` only where manifest or schema validation needs narrow updates.

## Implementation Alternatives

### Preferred V1 Path: Extend the current automation request, session configuration, and manifest flow

- Carry `behaviorWatchRequest` through the existing automation run request as a run-scoped override.
- Normalize the watch request before capture begins and expose the applied-watch summary in run metadata and the persisted evidence bundle.
- Sample only requested targets and properties inside the runtime addon during the configured watch window.
- Persist a fixed `trace.jsonl` next to the current run's manifest and add a `trace` artifact reference to that manifest.

### Alternative 1: Create a separate behavior-capture broker or second request path

- A dedicated request file or IPC path could isolate behavior capture from scenegraph automation.
- This is rejected for v1 because it would split the autonomous run contract and create a second evidence entrypoint for the agent.

### Alternative 2: Record full-scene per-frame state and filter later

- Buffering the whole scene each frame would delay target selection to persistence time.
- This is rejected for v1 because it breaks the low-overhead requirement and broadens capture far beyond slice 1 and slice 2.

### Alternative 3: Stream watch samples live to the editor and treat the stream as the primary surface

- A live-only debugger stream could avoid local runtime buffering.
- This is rejected for v1 because it weakens deterministic bounded capture and makes persisted post-run evidence secondary instead of primary.

### Escalation Paths Not Planned For V1

- GDExtension is not planned unless addon and debugger surfaces prove unable to sample the bounded watch set with acceptable overhead.
- Engine changes remain out of scope unless documented addon, autoload, debugger, and GDExtension options are shown insufficient with cited evidence.

## Phase 0: Research Focus

1. Confirm the smallest extension to the existing automation run request that can carry a behavior watch request without inventing a new command surface.
2. Confirm where normalization should occur so unsupported selectors, fields, and zero-sample windows fail before capture begins.
3. Confirm how `trace.jsonl` should be persisted and referenced from the current manifest-centered evidence bundle with no stale-output ambiguity.
4. Confirm the flat trace-row contract by reusing the existing runtime-sample `trace.jsonl` fixture shape where it already fits.
5. Confirm the deterministic validation shape for valid and invalid watch requests plus bounded Pong watch runs through the current automation flow.

## Phase 1: Design Focus

1. Design the `behaviorWatchRequest` contract, including absolute runtime node paths, watched property lists, cadence, start-frame offset, bounded frame count, and rejected later-slice fields.
2. Design the normalized applied-watch summary and the validation rules that make defaults and unsupported-field failures explicit.
3. Design the runtime sampler and the flat `trace.jsonl` row contract, including frame, timestamp, node path, and watched movement fields.
4. Design the manifest integration, artifact registration, and stale-artifact protections needed so the current run's manifest points to the current run's trace only.
5. Design deterministic request fixtures, Pong runtime verification fixtures, and quickstart instructions that prove slice 1 and slice 2 without depending on later-slice trigger or invariant machinery.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the preferred path still relies on the current editor addon, runtime addon, debugger bridge, and manifest writer only.
- [x] Reference coverage remains complete after design: plan decisions continue to map back to repo docs, contracts, fixtures, and cited Godot references.
- [x] Runtime evidence remains the product surface: agents still read the run result and persisted manifest first, then open `trace.jsonl` from the manifest reference.
- [x] Test loop remains defined after design: deterministic request-fixture validation and deterministic Pong watch runs remain the proof path.
- [x] Reuse remains justified after design: the feature stays an incremental extension of the current automation request and evidence bundle instead of a parallel subsystem.

## Phase 2 Preview

Expected tasks will group into:

1. Request contract and normalization: extend the run-request schema, add the slice-specific watch contract, and implement normalization plus rejection rules.
2. Runtime sampling: add the bounded sampler, track watch-window progress, and collect flat per-sample rows for the requested node paths and fields only.
3. Artifact persistence: write `trace.jsonl`, update the manifest artifact references, and expose the applied-watch summary for the current run.
4. Deterministic validation: add valid and invalid request fixtures, add deterministic Pong watch-run fixtures, and verify bounded trace output plus manifest correctness.
5. Supporting docs and tooling: update feature-local contracts and quickstart material, and extend narrow evidence or test helpers only where validation requires it.

## Complexity Tracking

No constitution violations are expected. The preferred path deliberately stays narrow: reuse the current automation request surface, extend the current manifest-centered bundle, and add only the contract and runtime pieces required for bounded watch sampling in slices 1 and 2.
