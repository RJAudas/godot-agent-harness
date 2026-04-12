# Implementation Plan: Agent Tooling Foundation

**Branch**: `[001-godot-agent-tooling]` | **Date**: 2026-04-11 | **Spec**: [specs/001-agent-tooling-foundation/spec.md](specs/001-agent-tooling-foundation/spec.md)
**Input**: Feature specification from `/specs/001-agent-tooling-foundation/spec.md`

## Summary

Establish a Copilot-first agent tooling foundation for the Godot Agent Harness that works directly with VS Code Copilot Chat and Copilot CLI, while remaining portable to other harnesses where that does not reduce first-release compatibility. The feature will deliver layered repository guidance, a manifest-centered runtime evidence contract, evaluation fixtures that measure whether tooling artifacts actually reduce churn, and autonomous automation guardrails for in-scope repository edits. The work stays plugin-first: it does not change Godot engine internals and treats runtime traces, events, scene snapshots, and invariant results as inputs consumed through agent-facing contracts rather than as a reason to escalate beyond addon, autoload, debugger, or GDExtension layers.

## Technical Context

**Language/Version**: Markdown guidance assets, JSON and JSON Schema contracts, PowerShell helper scripts for deterministic local workflows, and existing Godot 4.x runtime artifact formats consumed by the tooling  
**Primary Dependencies**: GitHub Copilot repository instructions and prompt/agent file model, VS Code Copilot Chat, Copilot CLI, existing Speckit scaffolding under `.github/agents`, `.github/prompts`, and `.specify`, plus JSON validation tooling that can be run locally  
**Storage**: Repository-hosted Markdown and JSON assets under `.github/`, repo root guidance files, `specs/001-agent-tooling-foundation/`, and future evaluation or helper outputs under `tools/` and scenario output directories  
**Testing**: Deterministic evaluation fixtures for Copilot Chat and Copilot CLI tasks, manifest contract validation, scenario-backed evidence bundle checks, and autonomous write-boundary validation with machine-readable run records  
**Target Platform**: VS Code Copilot Chat and Copilot CLI on Windows first, with portable artifact content for other harnesses where practical  
**Project Type**: Repository-level agent tooling foundation spanning Copilot instructions, agent prompts, evaluation fixtures, helper scripts, and evidence contracts for a Godot plugin-first harness  
**Performance Goals**: Orient new tasks with no more than three core guidance artifacts, achieve at least 90% first-pass routing accuracy in seeded evals, assemble an evidence bundle in under 5 minutes from existing runtime artifacts, and keep autonomous tooling within declared write boundaries in 100% of validation runs  
**Constraints**: Copilot-first when compatibility is uncertain, plugin-first and no engine fork, machine-readable evidence required, reuse existing `.github/agents` and `.github/prompts` before creating parallel systems, do not assume hosted Copilot skills, document commands only after local validation, and allow autonomous edits only inside explicit write boundaries  
**Scale/Scope**: Touches `.github/`, repo-root agent guidance, planning artifacts in `specs/001-agent-tooling-foundation/`, selected docs, helper tooling under `tools/`, and evaluation inputs that reference `scenarios/`; `addons/agent_runtime_harness/` remains primarily a producer and consumer boundary for future runtime evidence rather than the focus of this feature

## Reference Inputs

- **Internal Docs**: `README.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AI_TOOLING_BEST_PRACTICES.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `.specify/memory/constitution.md`, `.github/agents/`, `.github/prompts/`
- **External Docs**: Godot editor plugin overview, `EditorPlugin`, `EditorDebuggerPlugin`, `EngineDebugger`, Autoload singletons, GDExtension overview, GitHub Copilot repository custom instructions docs, GitHub Copilot path-specific instruction guidance, AGENTS.md guidance referenced by `docs/AI_TOOLING_BEST_PRACTICES.md`
- **Source References**: No `../godot` source files were required for this plan. Existing repository scaffolding under `.github/agents/`, `.github/prompts/`, and `.specify/` is the operative reference surface for Copilot-facing behavior in this feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays in repository guidance, addon-facing evidence contracts, and helper tooling without escalating to engine changes.
- [x] Reference coverage complete: internal docs, external docs, and current source surfaces are cited for the key technical decisions.
- [x] Runtime evidence defined: the plan centers a machine-readable evidence manifest plus references to raw traces, events, scene snapshots, and evaluation run records.
- [x] Test loop defined: each story maps to deterministic eval fixtures, evidence bundle validation, or autonomous-boundary checks.
- [x] Reuse justified: the plan extends existing `.github/agents`, `.github/prompts`, and `.specify` scaffolding before considering new parallel tooling systems.

## Project Structure

### Documentation (this feature)

```text
specs/001-agent-tooling-foundation/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── evidence-manifest.schema.json
└── tasks.md
```

### Source Code (repository root)

```text
.github/
├── agents/
├── prompts/
└── copilot-instructions.md        # planned

AGENTS.md                          # planned

addons/
└── agent_runtime_harness/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AI_TOOLING_BEST_PRACTICES.md
└── GODOT_PLUGIN_REFERENCES.md

scenarios/

tools/
```

**Structure Decision**: Use `.github/copilot-instructions.md` and `AGENTS.md` as the primary layered guidance entry points for VS Code Copilot Chat and Copilot CLI. Reuse the existing `.github/agents/` and `.github/prompts/` structure for Copilot-native workflow assets, add `.github/instructions/` only if a subtree genuinely needs narrower rules, keep evidence contracts and eval design artifacts inside the feature spec folder during planning, and place reusable validation helpers or eval runners in `tools/`. Avoid inventing a parallel generic agent runtime unless Copilot-native placement is proven insufficient.

## Phase 0: Research Focus

1. Confirm the exact Copilot-first guidance stack for this repo: `.github/copilot-instructions.md`, `AGENTS.md`, existing `.github/agents/`, existing `.github/prompts/`, and any narrowly justified `.github/instructions/` files.
2. Define the manifest-centered evidence bundle as the canonical handoff between Godot runtime outputs and coding agents.
3. Establish eval strategy for both VS Code Copilot Chat and Copilot CLI so tooling usefulness is measured instead of assumed.
4. Define autonomous write-boundary and stop-condition rules for any first-release automation artifact.
5. Identify which portability decisions can safely be deferred until after Copilot-first validation.

## Phase 1: Design Focus

1. Design the layered guidance model and precedence rules across repo-wide instructions, AGENTS guidance, scoped instructions, prompts, and agent artifacts.
2. Model the entities that tie together tooling artifacts, evidence manifests, write boundaries, and evaluation scenarios.
3. Define the evidence manifest schema and the minimum required artifact reference set.
4. Draft a quickstart flow that validates the tooling through VS Code Copilot Chat and Copilot CLI using repository-local tasks.
5. Keep all outputs portable where practical, but never at the expense of working reliably inside the primary Copilot surfaces.

## Phase 2 Preview

Expected tasks will group into:

1. Core guidance assets: repo-wide Copilot instructions, root AGENTS guidance, and any justified scoped instructions.
2. Copilot-native automation assets: prompt or agent files that help with Godot harness work and evidence interpretation.
3. Evidence contracts and helper tooling: manifest validation, bundle assembly helpers, and machine-readable autonomous-run logs.
4. Evaluation fixtures: seeded tasks and expected outcomes for Copilot Chat and Copilot CLI.
5. Documentation updates: minimal docs that explain how to use and validate the tooling without duplicating repo instructions.

## Complexity Tracking

No constitution violations are expected. The plan intentionally avoids new engine-facing abstractions, GDExtension escalation, or non-Copilot-first runtime assumptions.