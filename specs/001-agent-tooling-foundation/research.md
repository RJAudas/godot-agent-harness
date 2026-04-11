# Research: Agent Tooling Foundation

## Decision 1: Use Copilot-first guidance artifacts as the primary delivery surface

- **Decision**: Build first-release guidance around `.github/copilot-instructions.md`, `AGENTS.md`, and the existing `.github/agents/` and `.github/prompts/` scaffolding, with VS Code Copilot Chat and Copilot CLI as the first compatibility targets.
- **Rationale**: `docs/AI_TOOLING_BEST_PRACTICES.md` explicitly recommends Copilot-first placement and warns against assuming a hosted skill runtime inside Copilot. The repository already contains `.github/agents/`, `.github/prompts/`, and `.specify/`, so extending those surfaces is lower-risk than inventing a parallel system.
- **Alternatives considered**: A generic cross-agent layout from day one was rejected because it risks placing artifacts in patterns that are portable in theory but unproven in VS Code Copilot Chat or Copilot CLI.

## Decision 2: Use a manifest-centered evidence bundle

- **Decision**: Define a primary JSON evidence manifest that summarizes the run and points to raw traces, event logs, scene snapshots, invariant results, and future diagnostics.
- **Rationale**: A single manifest gives agents one stable entry point and reduces context churn, while referenced raw artifacts remain inspectable and do not need to be embedded into one oversized summary document.
- **Alternatives considered**: A single all-in-one JSON file was rejected because large runtime data would become unwieldy. JSONL-first output was rejected because it pushes too much summarization burden onto the consuming agent.

## Decision 3: Treat evaluations as a first-class product artifact

- **Decision**: Ship seeded evaluation scenarios that measure orientation quality, guidance selection, evidence consumption, and autonomous write-boundary compliance for both Copilot Chat and Copilot CLI.
- **Rationale**: The point of the feature is to reduce LLM churn. That cannot be proven from documentation quality alone; it needs reproducible checks that show whether the tooling helps or hurts.
- **Alternatives considered**: Manual review of prompt quality was rejected as insufficient because it does not reveal how the artifacts behave when the agent is operating under real constraints.

## Decision 4: Allow autonomous edits only inside explicit write boundaries

- **Decision**: First-release automation may write autonomously inside declared repository paths, but each artifact must declare allowed paths, stop conditions, validation signals, and machine-readable run logs.
- **Rationale**: The user prefers autonomy over approvals, but the repo still needs objective signals that an automation artifact stayed in scope and knew when to stop.
- **Alternatives considered**: Mandatory human approval before edits was rejected because it reduces the value of first-release autonomy. Fully unconstrained autonomy was rejected because it removes the safety signal needed to evaluate the tooling objectively.

## Decision 5: Keep engine internals out of scope for this feature

- **Decision**: Planning and implementation stay at the repository-guidance, evidence-contract, and helper-tooling layers, using Godot plugin references as the architectural ceiling for this feature.
- **Rationale**: This work is about making agents more effective at using the harness, not expanding the harness with new runtime capture mechanisms. Existing and future runtime artifacts are inputs to the contract design.
- **Alternatives considered**: Investigating `../godot` or planning new addon instrumentation as part of this feature was rejected because it would dilute the scope and violate the plugin-first, reuse-before-reinvention constraints.