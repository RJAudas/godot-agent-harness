
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
- [ ] Documentation synchronization planned: the plan enumerates the agent-facing
      surfaces (docs/, .github/copilot-instructions.md, .github/instructions/,
      .github/prompts/, .github/agents/, addons/agent_runtime_harness/templates/
      project_root/, and the feature quickstart) that will be updated alongside the
      code, or explains why a given surface is unaffected.
- [ ] Addon parse-check planned: any task touching GDScript under
      `addons/agent_runtime_harness/` includes a step to run
      `pwsh ./tools/check-addon-parse.ps1` and treats a non-zero exit as blocking.

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
