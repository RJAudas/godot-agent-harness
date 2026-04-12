# Implementation Plan: Inspect Scene Tree

**Branch**: `[002-inspect-scene-tree]` | **Date**: 2026-04-11 | **Spec**: [specs/002-inspect-scene-tree/spec.md](specs/002-inspect-scene-tree/spec.md)
**Input**: Feature specification from `/specs/002-inspect-scene-tree/spec.md`

## Summary

Deliver the lowest-complexity editor-first scenegraph inspection flow for Godot playtesting by combining a dock-first editor plugin, debugger-backed message transport, and a minimal runtime autoload collector that emits bounded scenegraph snapshots and diagnostics. The feature will capture startup, on-demand, and failure-triggered scenegraph data during editor play sessions, surface the latest results in the editor, and persist a manifest-centered evidence bundle that Copilot Chat or GitHub CLI can inspect after the run. Standalone packaged-executable support remains deferred, but the scenegraph and diagnostic payloads will avoid editor-only assumptions so the same contract can be reused by a later runtime-only harness.

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon and runtime scripts, Markdown planning artifacts, JSON evidence artifacts, and existing PowerShell validation helpers  
**Primary Dependencies**: Godot `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, addon autoload patterns, existing evidence-manifest tooling under `tools/evidence/`, and the evidence bundle schema under `specs/001-agent-tooling-foundation/contracts/`  
**Storage**: Machine-readable JSON artifacts written per editor play session, fixture outputs under `tools/evals/fixtures/001-agent-tooling-foundation/`, and deterministic validation assets under `examples/pong-testbed/` and feature docs under `specs/002-inspect-scene-tree/`  
**Testing**: Deterministic editor-run validation in `examples/pong-testbed/`, manifest validation with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`, JSON validation with `pwsh ./tools/validate-json.ps1`, and seeded scenegraph fixtures that cover healthy, missing-node, and hierarchy-mismatch outcomes  
**Target Platform**: Godot 4.x editor play sessions on Windows first, with repository-hosted evidence validation that remains CI-friendly  
**Project Type**: Editor addon plus minimal runtime instrumentation with debugger integration and persisted evidence contract  
**Performance Goals**: Capture startup, manual, and failure-triggered scenegraph snapshots without requiring per-frame polling; keep snapshot payloads bounded to the clarified core inspection set; avoid editor UI stalls during normal playtesting  
**Constraints**: Plugin-first constitution, no engine fork, packaged executable support deferred, persisted evidence required for every validation path, hybrid matching for runtime expectations, and reuse of the manifest-centered contract before inventing new bundle formats  
**Scale/Scope**: Adds Godot addon scaffolding under `addons/agent_runtime_harness/`, deterministic validation assets under `examples/pong-testbed/`, feature-level contracts and quickstart docs under `specs/002-inspect-scene-tree/`, and only the minimum tooling updates needed to recognize new artifact kinds in existing evidence flows

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `docs/AI_TOOLING_BEST_PRACTICES.md`, `.specify/memory/constitution.md`, `.github/instructions/addons.instructions.md`, `specs/002-inspect-scene-tree/spec.md`, `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`, `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/scene-snapshot.json`
- **External Docs**: Godot editor plugins overview, `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, scene tree basics, and autoload singletons documentation
- **Source References**: No `../godot` source files were inspected for this plan. Official Godot plugin references and existing repository contracts were sufficient for this architecture.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the architecture stays within editor plugin, runtime autoload, and debugger integration layers, with no engine changes planned.
- [x] Reference coverage complete: internal docs, addon-specific guidance, external Godot references, and existing evidence-contract surfaces are cited for the key decisions.
- [x] Runtime evidence defined: the plan names persisted scenegraph snapshots, structured diagnostics, and manifest entries as the machine-readable outputs agents consume.
- [x] Test loop defined: each story maps to deterministic editor-run validation in the example project plus manifest or fixture verification.
- [x] Reuse justified: the plan extends the existing evidence-manifest contract and fixture patterns instead of creating a parallel scene-inspection bundle format.

## Project Structure

### Documentation (this feature)

```text
specs/002-inspect-scene-tree/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── scenegraph-inspection-contract.md
└── tasks.md
```

### Source Code (repository root)

```text
addons/
└── agent_runtime_harness/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AI_TOOLING_BEST_PRACTICES.md
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

tools/
├── evidence/
└── evals/
```

**Structure Decision**: Put the implementation under `addons/agent_runtime_harness/` with four focused layers: editor plugin bootstrap, dock UI, debugger bridge, and runtime scenegraph collector. Use `examples/pong-testbed/` for deterministic validation scenes and expected-node fixtures. Keep machine-readable contract details in `specs/002-inspect-scene-tree/contracts/` until implementation stabilizes, and only touch `tools/evidence/` if the existing manifest helpers need minimal changes to recognize scenegraph-specific artifact kinds.

## Phase 0: Research Focus

1. Confirm the lowest-complexity editor surface: use a dock-first experience for capture controls and latest results, with debugger integration serving primarily as message transport.
2. Confirm the runtime instrumentation boundary: one autoload-backed collector that serializes the clarified core inspection set and evaluates hybrid expectations without introducing per-frame tracing.
3. Confirm how scenegraph snapshots and diagnostics fit into the existing evidence-manifest schema through additional artifact references instead of a new top-level bundle type.
4. Confirm a deterministic example-project validation flow that exercises healthy, missing-node, and hierarchy-mismatch outcomes during editor play.
5. Confirm which packaged-runtime compatibility choices are effectively free now, such as runtime-neutral field names and trigger reasons, and defer the rest.

## Phase 1: Design Focus

1. Define the editor plugin architecture: plugin entrypoint, dock state flow, debugger session hookup, and capture request lifecycle.
2. Define the runtime data contract: snapshot payload, node record shape, trigger metadata, scenario expectation schema, and structured diagnostics.
3. Define the persisted artifact bundle: manifest usage, artifact kinds, output directory expectations, and how live captures map to post-run evidence.
4. Define the deterministic validation setup in `examples/pong-testbed/`, including at least one normal scene and one intentionally broken expectation path.
5. Define minimal tooling touchpoints required to validate scenegraph artifacts with existing JSON and manifest scripts.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the solution still relies only on editor plugin, runtime autoload, and debugger integration layers.
- [x] Reference coverage remains complete after design: contract and validation decisions still map back to cited internal and external references.
- [x] Runtime evidence remains the product surface: live captures produce persisted scenegraph snapshots, diagnostics, and manifest-linked summaries.
- [x] Test loop remains defined after design: example-project runs and evidence validation still prove each story deterministically.
- [x] Reuse remains justified after design: the plan still extends the existing evidence bundle contract and avoids a parallel scene-inspection packaging model.

## Phase 2 Preview

Expected tasks will group into:

1. Addon scaffolding: create the editor plugin entrypoint, dock UI, debugger bridge, and runtime collector/autoload registration surfaces.
2. Scenegraph contract and serialization: implement snapshot generation, bounded property extraction, hybrid expectation matching, and structured diagnostic payloads.
3. Evidence persistence: write scenegraph snapshots and diagnostics into a manifest-centered bundle with stable artifact kinds.
4. Example-project validation: add deterministic scenes or fixtures in `examples/pong-testbed/` that prove healthy and failing inspection cases.
5. Tooling and docs: add minimal fixture updates, contract docs, and validation guidance needed for agents to consume the resulting artifacts.

## Complexity Tracking

No constitution violations are expected. The selected architecture is intentionally conservative: a dock-first editor UI, debugger-backed transport, and one lightweight runtime collector are sufficient for the first release. A custom debugger tab, broader runtime telemetry, or packaged-build transport path should be considered only if the dock-first approach fails to expose enough useful evidence.

# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement, targeted Godot integration points,
and the runtime evidence this feature must produce]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with concrete project details.
  Plans in this repository are expected to stay Godot/plugin focused.
-->

**Language/Version**: [e.g., GDScript for Godot 4.x, optional C++ for GDExtension, or NEEDS CLARIFICATION]  
**Primary Dependencies**: [e.g., EditorPlugin, EditorDebuggerPlugin, EngineDebugger, test framework, or NEEDS CLARIFICATION]  
**Storage**: [e.g., JSON artifacts in project output directories, fixtures in scenarios/, or N/A]  
**Testing**: [e.g., headless Godot scenario run, invariant checks, GdUnit4, or NEEDS CLARIFICATION]  
**Target Platform**: [e.g., Godot editor on Windows/macOS/Linux, headless CI runner, or NEEDS CLARIFICATION]
**Project Type**: [e.g., editor addon, runtime addon, debugger integration, GDExtension, or NEEDS CLARIFICATION]  
**Performance Goals**: [domain-specific, e.g., capture traces without breaking target frame budget]  
**Constraints**: [e.g., plugin-first, machine-readable outputs required, no engine fork without justification]  
**Scale/Scope**: [e.g., feature affects addon UI, runtime instrumentation, example Pong scenario]

## Reference Inputs

- **Internal Docs**: [List the repo docs consulted, including docs/GODOT_PLUGIN_REFERENCES.md]
- **External Docs**: [List the official Godot docs, class refs, or other authoritative references used]
- **Source References**: [List relevant files or subsystems inspected in ../godot relative to the repository root when engine behavior mattered]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [ ] Plugin-first approach preserved: the plan starts with addon, autoload, debugger,
      or GDExtension layers and does not escalate to engine changes without written proof.
- [ ] Reference coverage complete: internal docs, external docs, and source references
      are cited for each important technical decision.
- [ ] Runtime evidence defined: the feature names the machine-readable artifacts,
      summaries, or debugger payloads it will emit for agents.
- [ ] Test loop defined: each user story has a deterministic scenario, automated test,
      or invariant-driven validation path.
- [ ] Reuse justified: any new abstraction explains why existing Godot/plugin behavior
      was insufficient.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
addons/
└── agent_runtime_harness/

docs/
├── AGENT_RUNTIME_HARNESS.md
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

scenarios/

tools/
```

**Structure Decision**: [Document which of the existing repository areas this feature
touches and why those paths are sufficient]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., Introduce GDExtension] | [specific runtime or API limitation] | [why addon/debugger APIs were insufficient] |
| [e.g., Engine patch investigation] | [verified blocker] | [which supported extension points were tried first] |
