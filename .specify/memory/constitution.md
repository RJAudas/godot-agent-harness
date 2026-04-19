<!--
Sync Impact Report
Version change: 1.1.0 -> 1.2.0
Modified principles:
- III. Test-Backed Agent Loops (expanded: mandates headless GDScript parse check after addon edits)
Added sections:
- None
Removed sections:
- None
Templates requiring updates:
- ✅ updated: .specify/memory/constitution.md
- ✅ updated: .specify/templates/plan-template.md (Constitution Check gate adds parse-check row)
- ✅ updated: .specify/templates/tasks-template.md (Polish phase lists parse-check task)
- ✅ updated: AGENTS.md (Validation expectations call out check-addon-parse.ps1)
- ✅ updated: .github/copilot-instructions.md (Validation commands list check-addon-parse.ps1)
- ⚠ pending: .specify/templates/spec-template.md (no constitution-bound section needed; revisit if scope expands)
- ⚠ pending: .specify/templates/commands/ (directory still absent in this checkout)
Follow-up TODOs:
- None
-->
# Godot Agent Harness Constitution

## Core Principles

### I. Plugin-First Interop
All feature work MUST begin with Godot-supported extension points in this order:
editor plugin, runtime addon with autoload, debugger integration, then GDExtension.
Engine changes MAY be proposed only after the plan documents why those layers cannot
meet the requirement. This keeps the harness aligned with Godot's intended extension
model and avoids paying engine-fork maintenance costs before a real blocker exists.

### II. Reference-Driven Design
Every specification, plan, and implementation task MUST cite the internal project
documents and external Godot references used to make design decisions. Relevant work
MUST consult docs/GODOT_PLUGIN_REFERENCES.md, related local docs, and the sibling
reference checkout at ../godot relative to the repository root when engine behavior
or integration details are unclear.
This project exists to interoperate with Godot correctly, so design work is invalid
if it guesses at APIs or recreates behavior that existing engine/plugin facilities
already provide.

### III. Test-Backed Agent Loops
Every user story MUST define an executable verification path before implementation is
considered complete. At minimum, each story MUST specify deterministic scenario runs,
runtime assertions, or automated tests that produce machine-readable pass/fail output.
Manual observation MAY supplement these checks but MUST NOT be the only proof. The
rationale is simple: agents improve fastest when code changes can be closed against a
repeatable test loop rather than a human narrative.

Any change that adds, removes, or edits GDScript files under
`addons/agent_runtime_harness/` MUST be validated with
`pwsh ./tools/check-addon-parse.ps1` before the change is considered complete.
The script opens a minimal headless Godot project and surfaces parse, compile, or
script-load errors that would otherwise only appear after a manual deploy and editor
reload. Contributors MUST run it locally (and MAY wire it into pre-commit or CI) and
MUST treat any non-zero exit as a blocking failure. The rationale is that addon
GDScript breakage is invisible to PowerShell unit tests but renders the harness
unusable for downstream agents the moment they enable the plugin.

### IV. Runtime Evidence as the Product Surface
Features MUST produce structured runtime artifacts that agents can consume directly,
including summaries, traces, scene snapshots, events, or invariant results as needed
for the story. Human-readable UI is important, but it MUST be backed by durable,
machine-readable evidence that explains what happened at runtime. The harness is only
useful if agents can inspect real execution data without waiting for a human to
translate behavior into prose.

### V. Reuse Before Reinvention
Plans and implementations MUST prefer existing Godot capabilities, documented plugin
APIs, and lightweight harness-specific glue over custom frameworks or parallel engine
abstractions. Any new subsystem MUST explain why available Godot functionality,
project tooling, or reference patterns were insufficient. This project is about
surfacing and packaging Godot runtime information for agents, not rebuilding broad
engine-adjacent infrastructure from scratch.

### VI. Documentation Synchronization
Any change that adds, removes, or alters an agent-observable feature, contract,
artifact, capability flag, command, prompt, skill, or workflow MUST land together
with the corresponding updates to the agent-facing surfaces that teach game-coding
agents how to use it. In the same change set, contributors MUST update, at minimum,
the affected entries under: docs/ (notably docs/AGENT_RUNTIME_HARNESS.md and
docs/AI_TOOLING_AUTOMATION_MATRIX.md when routing or runtime behavior is touched),
.github/copilot-instructions.md and the relevant .github/instructions/*.md path
scopes, .github/prompts/ and .github/agents/ assets that mention the feature, the
deployable templates under addons/agent_runtime_harness/templates/project_root/, and
the feature's own quickstart.md. Schemas, fixtures, capability advertisements, and
rejection codes MUST be linked from the prose rather than duplicated. A change is
not complete while a downstream agent could discover the new behavior only by
reading source code, and reviews MUST reject feature work whose docs, instructions,
prompts, or skills still describe the prior contract. The rationale is that this
repository's product is the agent's ability to operate the harness correctly;
runtime evidence is wasted if the agent cannot find out the feature exists or how
to invoke it.

## Engineering Boundaries

The repository scope is constrained to a Godot plugin-first harness that helps agents
observe, test, and diagnose runtime behavior. Work MUST prioritize the three product
pillars: understanding useful runtime/debug data inside Godot, interoperating with
that data safely through supported extension points, and presenting the resulting
evidence in formats agents can use to guide further edits.

Repository-local documentation MUST stay curated and lightweight. The repo MUST keep
architecture notes, implementation decisions, scenario definitions, and links to
official documentation; it MUST NOT vendor large copies of upstream Godot docs unless
offline use becomes an explicit requirement. The checkout at ../godot relative to
the repository root is the reference source tree for reading engine behavior and
integration patterns and MUST be treated as external reference material, not as part
of this repository.

## Workflow and Quality Gates

Each feature spec MUST identify the internal docs, external docs, and source
references used during discovery. Each implementation plan MUST include a
Constitution Check that confirms plugin-first scope, cites the relevant references,
documents the planned runtime artifacts, explains any escalation to GDExtension or
engine changes, and enumerates the agent-facing documentation, instructions,
prompts, skills, and deployable templates that will be updated alongside the code.

Implementation tasks MUST remain traceable to independently testable user stories.
Tasks for a story MUST include the scenario execution or automated verification needed
to prove the story with runtime evidence, and the task set MUST contain explicit
documentation-synchronization tasks for every agent-facing surface affected by the
change. Tasks that touch addon GDScript MUST also include a parse-check task
(`pwsh ./tools/check-addon-parse.ps1`) and MUST NOT be marked complete while the
script reports parse, compile, or script-load errors. Reviews MUST reject work that
lacks cited references, bypasses supported Godot extension layers without written
justification, depends on manual-only validation for behavior agents are expected to
diagnose, ships a behavior change without the matching updates to docs, instructions,
prompts, skills, or deployable agent assets, or merges addon GDScript edits without a
clean parse-check run.

## Governance

This constitution overrides conflicting local habits, templates, and planning norms.
Amendments MUST be documented in the constitution itself, include an updated Sync
Impact Report, and propagate any required changes to affected templates or guidance
documents before the amendment is considered complete.

Versioning follows semantic versioning for governance changes. MAJOR increments apply
to principle removals or incompatible reinterpretations, MINOR increments apply to
new principles or materially expanded obligations, and PATCH increments apply to
clarifications that do not change expected behavior. Compliance review is mandatory
for every spec, plan, and task set: reviewers MUST confirm reference coverage,
plugin-first justification, test-backed validation, machine-readable runtime
evidence, and documentation-synchronization coverage before approval.

**Version**: 1.2.0 | **Ratified**: 2026-04-11 | **Last Amended**: 2026-04-19
