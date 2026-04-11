<!--
Sync Impact Report
Version change: unversioned template -> 1.0.0
Modified principles:
- Template principle 1 -> I. Plugin-First Interop
- Template principle 2 -> II. Reference-Driven Design
- Template principle 3 -> III. Test-Backed Agent Loops
- Template principle 4 -> IV. Runtime Evidence as the Product Surface
- Template principle 5 -> V. Reuse Before Reinvention
Added sections:
- Engineering Boundaries
- Workflow and Quality Gates
Removed sections:
- None
Templates requiring updates:
- ✅ updated: .specify/templates/plan-template.md
- ✅ updated: .specify/templates/spec-template.md
- ✅ updated: .specify/templates/tasks-template.md
- ✅ updated: README.md
- ✅ updated: docs/AGENT_RUNTIME_HARNESS.md
- ⚠ pending: .specify/templates/commands/ (directory not present; no command templates were available to validate)
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
documents the planned runtime artifacts, and explains any escalation to GDExtension
or engine changes.

Implementation tasks MUST remain traceable to independently testable user stories.
Tasks for a story MUST include the scenario execution or automated verification needed
to prove the story with runtime evidence. Reviews MUST reject work that lacks cited
references, bypasses supported Godot extension layers without written justification,
or depends on manual-only validation for behavior agents are expected to diagnose.

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
plugin-first justification, test-backed validation, and machine-readable runtime
evidence before approval.

**Version**: 1.0.0 | **Ratified**: 2026-04-11 | **Last Amended**: 2026-04-11
