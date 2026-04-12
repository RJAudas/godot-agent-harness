# Feature Specification: Agent Tooling Foundation

**Feature Branch**: `[001-godot-agent-tooling]`  
**Created**: 2026-04-11  
**Status**: Draft  
**Input**: User description: "Create agentic tooling in preparation for building this application, including agents, instruction files, skills, and guidance for feeding Godot plugin and runtime data into agents so they can drive code changes with less churn. Reference docs/AI_TOOLING_BEST_PRACTICES.md."

## Clarifications

### Session 2026-04-11

- Q: Which deliverables should this feature's first release be required to ship? → A: Ship a thorough set of tooling artifacts, including concrete guidance and automation artifacts, and use testing to determine which ones are useful.
- Q: What should be the primary shape of an agent-consumable evidence bundle? → A: Use a manifest JSON file as the primary entry point, with normalized summary fields and references to separate raw artifacts.
- Q: What should be the primary platform target for these tooling artifacts? → A: Target GitHub Copilot first, while keeping artifacts portable where practical for other agents later.
- Q: What write authority should first-release automation have? → A: Allow autonomous edits in expected repository paths without prior approval, using explicit scope and safety guardrails instead of approval gates.
- Q: Which GitHub Copilot surfaces should first-release tooling optimize for when generic compatibility is uncertain? → A: Optimize for VS Code Copilot Chat and Copilot CLI first, and prefer patterns proven there over generic tooling of uncertain compatibility.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Layered Agent Guidance (Priority: P1)

As a maintainer, I want a layered guidance system for this repository so a coding agent can understand the harness goal, Godot plugin constraints, and validation expectations before it edits code.

**Why this priority**: Repeated repo rediscovery is the current source of churn. Reducing orientation cost is the fastest way to improve every later implementation task.

**Independent Test**: Run a fresh-session evaluation against a representative addon or tooling task and verify the resulting machine-readable evaluation record shows the agent selected the correct project guidance, cited the plugin-first boundaries, and identified the expected validation loop without human correction.

**Acceptance Scenarios**:

1. **Given** a new agent session assigned a Godot harness task, **When** the session starts, **Then** it is directed to the stable repository guidance, curated Godot references, and evidence-first validation rules using GitHub Copilot's documented instruction model as the default entry point for VS Code Copilot Chat and Copilot CLI.
2. **Given** a task that touches a specific subtree, **When** the agent resolves applicable guidance, **Then** repo-wide rules and narrower task guidance remain clearly separated and non-conflicting.
3. **Given** a tooling artifact could depend on a platform-specific behavior, **When** it is designed for first release, **Then** it prefers Copilot-supported placement and precedence rules while keeping reusable content portable where practical.

---

### User Story 2 - Agent-Consumable Evidence Bundles (Priority: P2)

As a maintainer, I want runtime traces, scenario outputs, and diagnostics packaged into agent-consumable evidence bundles so an agent can reason from structured facts instead of raw logs or human summaries.

**Why this priority**: The harness only accelerates development if its outputs can be consumed directly by agents in a repeatable format.

**Independent Test**: Use a representative scenario run with at least one failure and verify a machine-readable bundle validation result shows the package contains scenario identity, run metadata, invariant results, a concise summary, and references to the underlying raw artifacts needed for deeper inspection.

**Acceptance Scenarios**:

1. **Given** a deterministic scenario run completes, **When** its evidence is prepared for agent use, **Then** a manifest JSON file exposes the run identity, scenario identity, summarized outcome, invariant status, and references to raw artifacts in a consistent structure.
2. **Given** a scenario produces large or noisy outputs, **When** the evidence bundle is generated, **Then** the manifest provides a condensed, ordered summary for the agent while preserving traceable links to the full evidence files.

---

### User Story 3 - Reusable Automation Decisions (Priority: P3)

As a maintainer, I want clear rules for when to create instructions, fixed workflows, agents, or skills so the repository gains only the amount of autonomy that repeated work actually justifies.

**Why this priority**: Adding autonomy too early creates maintenance overhead. This story keeps future tooling deliberate and evidence-backed.

**Independent Test**: Evaluate a set of recurring repository tasks against the shipped tooling artifacts and verify the resulting classification report consistently maps each task to the right delivery form, the required safety boundaries, and the validation gate needed to keep or discard an artifact based on observed usefulness.

**Acceptance Scenarios**:

1. **Given** a newly proposed automation need, **When** it is assessed against the decision rules, **Then** the team can determine whether it belongs in stable instructions, a fixed workflow, an agent, or a reusable skill.
2. **Given** a proposal for a higher-autonomy agent or skill, **When** it is approved for creation, **Then** its scope, allowed write boundaries, stop conditions, rollback expectations, and validation method are explicitly defined.
3. **Given** a tooling artifact has been shipped experimentally, **When** evaluation tasks show it does not improve correctness, speed, or evidence quality, **Then** the team can remove, narrow, or replace that artifact based on test results.

---

### Edge Cases

- Guidance layers drift out of sync and give conflicting directions for the same task.
- Runtime evidence from multiple scenario runs is mixed together without a unique run identity.
- Large traces exceed practical agent context limits and need summarization without hiding root-cause evidence.
- A proposed agent task is actually deterministic enough to be handled by a simpler workflow.
- An evidence bundle omits links back to the raw artifacts, making the summary unverifiable.
- Repo guidance includes unvalidated commands that send agents down failing paths.

## References *(mandatory)*

### Internal References

- README.md
- docs/AGENT_RUNTIME_HARNESS.md
- docs/AI_TOOLING_BEST_PRACTICES.md
- docs/GODOT_PLUGIN_REFERENCES.md
- .specify/memory/constitution.md

### External References

- Godot editor plugin overview: https://docs.godotengine.org/en/stable/tutorials/plugins/editor/index.html
- Godot EditorPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editorplugin.html
- Godot EditorDebuggerPlugin class reference: https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html
- Godot EngineDebugger class reference: https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html
- Godot Autoload singletons guide: https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html
- Godot GDExtension overview: https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/what_is_gdextension.html

### Source References

- No `../godot` source files were inspected for this specification; the current scope is defined by curated repository guidance and official plugin-layer documentation rather than engine internals.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST define a layered agent tooling model that distinguishes durable repository guidance, agent operating guidance, scoped instructions, reusable workflows, and skill-style capability bundles.
- **FR-001A**: System MUST ship concrete tooling artifacts in the first release, including repository-wide guidance, agent operating guidance, scoped guidance where justified, and at least one concrete automation artifact whose usefulness can be evaluated.
- **FR-001B**: System MUST treat GitHub Copilot's documented instruction and file-placement model as the primary delivery target for first-release guidance artifacts, with VS Code Copilot Chat and Copilot CLI as the first compatibility targets while keeping reusable content portable where practical for other agent runtimes.
- **FR-002**: System MUST provide a minimal onboarding path that directs agents to the repository purpose, plugin-first extension strategy, validated references, and expected validation loop before code changes begin.
- **FR-003**: System MUST define decision rules for when work should be solved with a direct prompt, a fixed workflow, a routed or specialist agent, or a reusable skill, favoring the least autonomous option that reliably solves the task.
- **FR-004**: System MUST define a manifest-centered evidence bundle contract in which a primary JSON manifest preserves scenario metadata, normalized summaries, invariant results, and references to the underlying raw artifacts.
- **FR-005**: System MUST ensure every agent-facing artifact states its intended trigger conditions, required inputs, expected outputs, and stop or escalation conditions.
- **FR-005A**: System MUST define which first-release automation artifacts may apply edits autonomously, the repository paths they may modify, and the conditions that force them to stop or escalate.
- **FR-006**: System MUST preserve the supported Godot extension hierarchy and justify any proposed escalation beyond addon, autoload, debugger integration, or GDExtension layers.
- **FR-007**: System MUST identify the machine-readable artifacts agents inspect to validate behavior, including the primary evidence manifest, normalized summary fields, scenario metadata, invariant outcomes, and references to raw traces or scene snapshots.
- **FR-008**: System MUST separate durable instructions from task-specific requests so one layer does not silently override or duplicate another.
- **FR-009**: System MUST define evaluation checks that measure whether the tooling reduces agent discovery churn, improves correct guidance selection, and increases first-pass evidence-backed task completion.
- **FR-010**: System MUST support broad but testable adoption by shipping a thorough initial set of candidate tooling artifacts and using evaluations to keep, narrow, or remove artifacts based on observed value.
- **FR-011**: System MUST define how large or noisy runtime outputs are condensed for agent use without losing traceability back to the full evidence set.
- **FR-012**: System MUST enforce explicit guardrails for destructive actions, out-of-scope writes, and autonomous edit loops, with automatic escalation when work falls outside expected repository paths or validation signals turn negative.

### Key Entities *(include if feature involves data)*

- **Guidance Layer**: A stable layer of instructions or workflow rules with a defined scope, precedence, and intended audience.
- **Primary Agent Platform**: The agent runtime whose documented file model and instruction precedence define the default placement and consumption rules for first-release tooling artifacts.
- **Tooling Artifact**: A concrete repo asset such as an instruction file, AGENTS guidance, workflow definition, agent prompt, evaluation fixture, or skill bundle that is shipped for agent use and measured for usefulness.
- **Agent Workflow**: A repeatable sequence of agent actions with a clear goal, entry conditions, stopping conditions, and validation path.
- **Write Boundary**: The explicitly allowed set of repository paths and edit types an autonomous tooling artifact may modify without prior human approval.
- **Evidence Bundle**: A structured package whose primary entry point is a JSON manifest containing normalized summary fields and references to the raw artifacts that support those findings.
- **Evidence Manifest**: The canonical machine-readable handoff file an agent reads first to discover run metadata, summary outcomes, invariant results, and pointers to detailed evidence files.
- **Evaluation Scenario**: A representative task or failure case used to measure whether the agent tooling selects the right guidance and produces the expected result.
- **Run Evidence Reference**: The identifying metadata that ties a summary back to a specific scenario run, artifact set, and validation outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new agent-facing coding task can be oriented using no more than three core guidance artifacts and reach the correct project area and validation expectations without human redirection.
- **SC-002**: In evaluation tasks spanning addon, docs, scenarios, and tools work, at least 90% of tasks are routed to the correct guidance layer or automation pattern on the first attempt.
- **SC-003**: For representative runtime-failure cases, maintainers can assemble an agent-consumable evidence bundle in under 5 minutes without manually rewriting raw logs into prose.
- **SC-004**: At least 80% of seeded evaluation tasks result in an evidence-backed next action or change plan on the agent's first pass.
- **SC-005**: Every validated evidence bundle includes a primary manifest file with scenario identity, run identity, outcome summary, invariant status, and references to the underlying raw artifacts.
- **SC-006**: Every shipped tooling artifact is covered by at least one evaluation scenario that can justify retaining, narrowing, or removing the artifact based on measured usefulness.
- **SC-007**: Any tooling artifact permitted to edit files autonomously stays within its declared write boundaries in 100% of validation runs and emits a machine-readable record when it stops or escalates.

## Assumptions

- The first release of this feature serves repository contributors and coding agents working on the harness, not external end users of a finished plugin.
- The initial scope includes a thorough set of tooling artifacts, but each artifact must remain testable and removable if evaluations show it is not useful.
- GitHub Copilot is the primary target for first-release instruction placement and precedence, while reusable guidance should remain portable enough to support other agents later where practical.
- When a generic artifact design conflicts with proven VS Code Copilot Chat or Copilot CLI compatibility, the first release should prefer the Copilot-compatible design and defer broader portability until it can be validated.
- First-release automation may apply edits autonomously inside declared repository boundaries, provided those boundaries, stop conditions, and validation checks are explicit and machine-verifiable.
- Existing and future deterministic scenario outputs from the harness can be referenced by this feature rather than redefined from scratch here.
- Raw runtime artifacts such as traces, scene snapshots, and event files will remain separate files referenced by the evidence manifest rather than being embedded wholesale into a single summary document.
- Official Godot documentation and the curated local reference documents remain the primary source of truth for supported extension points.
- The sibling `../godot` checkout will be consulted during planning or implementation only if plugin-layer references are insufficient for a specific design decision.
- Commands or workflows called out by the resulting tooling will be documented only after local validation.