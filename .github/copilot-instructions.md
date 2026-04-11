# Godot Agent Harness Copilot Instructions

## Repository purpose

This repository builds a plugin-first Godot harness that gives coding agents machine-readable runtime evidence instead of relying on human retellings of gameplay behavior.

## Read in this order

1. `README.md` for repository purpose and layout.
2. `AGENTS.md` for agent-facing workflow rules.
3. Relevant path-specific files under `.github/instructions/`.
4. `docs/AGENT_RUNTIME_HARNESS.md` for harness architecture and evidence expectations.
5. `docs/AI_TOOLING_BEST_PRACTICES.md` when adding or changing agent tooling assets.

## Durable rules

- Stay plugin-first: prefer addon, autoload, debugger, and GDExtension layers before considering engine changes.
- Treat `../godot` as a read-only reference checkout when engine behavior needs confirmation.
- When runtime evidence exists, read the manifest first and inspect raw artifacts only as needed.
- Keep repo-wide guidance concise. Put durable rules here, agent operating workflow in `AGENTS.md`, and subtree-specific constraints in `.github/instructions/`.
- For the current agent-tooling foundation work, prefer changes in `.github/`, `docs/`, `tools/`, and `specs/001-agent-tooling-foundation/` unless the task explicitly requires addon or scenario edits.

## Validation commands

- `pwsh ./tools/validate-json.ps1 -InputPath <json-path> -SchemaPath <schema-path>` validates repository JSON assets against a schema.
- `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>` validates an evidence bundle manifest and confirms referenced artifacts exist.
- `pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId <artifact-id> -RequestedPath <path> -RequestedEditType <edit-type>` checks whether an autonomous action stays inside the declared write boundary.

## Output locations

- Place seeded eval prompts and result files under `tools/evals/001-agent-tooling-foundation/`.
- Place reusable fixture inputs under `tools/evals/fixtures/001-agent-tooling-foundation/`.
- Place evidence helper scripts under `tools/evidence/`.
- Place autonomous boundary contracts and run logs under `tools/automation/`.
