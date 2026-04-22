# Godot Agent Harness Copilot Instructions

## Repository purpose

This repository builds a plugin-first Godot harness that gives coding agents machine-readable runtime evidence instead of relying on human retellings of gameplay behavior.

## Read in this order

1. `README.md` for repository purpose and layout.
2. `AGENTS.md` for agent-facing workflow rules.
3. Relevant path-specific files under `.github/instructions/`.
4. `docs/AGENT_RUNTIME_HARNESS.md` for harness architecture and evidence expectations.
5. `docs/AI_TOOLING_BEST_PRACTICES.md` when adding or changing agent tooling assets.
6. `docs/INTEGRATION_TESTING.md` and the "End-to-end plugin testing" section of `tools/README.md` BEFORE doing anything that involves a real Godot editor, real playtest, or real input dispatch.

## Durable rules

- Stay plugin-first: prefer addon, autoload, debugger, and GDExtension layers before considering engine changes.
- Treat `../godot` as a read-only reference checkout when engine behavior needs confirmation.
- When runtime evidence exists, read the manifest first and inspect raw artifacts only as needed.
- Use three validation modes consistently: ordinary tests, Scenegraph Harness runtime verification, and combined validation.
- Choose Scenegraph Harness runtime verification for requests about runtime-visible behavior, what appears in game, node presence, hierarchy, or other outcomes that must be proven from a running project.
- Choose combined validation when a change affects runtime-visible behavior and there is already an existing deterministic test surface; run the existing tests plus the runtime harness flow, but do not invent new ordinary tests solely to satisfy the rule.
- When routing to runtime verification from this repository checkout, prefer the workspace-side helper flow: check capability, request a brokered run, then read the persisted evidence manifest first. Treat blocked or missing capability and run-result artifacts as explicit unsupported states.
- Auto-delegate runtime work to the matching custom agent instead of handling it inline. Invoke `godot-runtime-verification` whenever a fresh harness run is needed (runtime-visible verification, starting the game, dispatching keys or `InputMap` actions, reproducing a runtime crash). Invoke `godot-evidence-triage` when an evidence manifest already exists and the user only wants diagnosis. Do not ask the user which agent to pick when the routing rule is unambiguous.
- Keep repo-wide guidance concise. Put durable rules here, agent operating workflow in `AGENTS.md`, and subtree-specific constraints in `.github/instructions/`.
- For the current agent-tooling foundation work, prefer changes in `.github/`, `docs/`, `tools/`, and `specs/001-agent-tooling-foundation/` unless the task explicitly requires addon or scenario edits.
- For any task that requires running the harness against a real Godot editor (manual feature validation, broker smoke tests, evidence reproduction, input-dispatch verification), use the `integration-testing/<name>` sandbox flow documented in `docs/INTEGRATION_TESTING.md` and `tools/README.md`. Do NOT scaffold ad-hoc projects elsewhere, do NOT download or extract a Godot binary into the repo, and do NOT hard-code an absolute path to a Godot install. Resolve the binary the same way `tools/check-addon-parse.ps1` does: `$env:GODOT_BIN` first, then `godot`/`godot4`/`Godot*` on `PATH`. If neither resolves in the current shell, check the user-level environment (`[System.Environment]::GetEnvironmentVariable('GODOT_BIN','User')` and the `User` `Path` for a `Godot*` directory) before concluding Godot is missing.

## Validation commands

- `pwsh ./tools/validate-json.ps1 -InputPath <json-path> -SchemaPath <schema-path>` validates repository JSON assets against a schema.
- `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest-path>` validates an evidence bundle manifest and confirms referenced artifacts exist.
- `pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId <artifact-id> -RequestedPath <path> -RequestedEditType <edit-type>` checks whether an autonomous action stays inside the declared write boundary.
- `pwsh ./tools/automation/submit-pause-decision.ps1 -ProjectRoot <path> -RunId <id> -PauseId <n> -Decision continue|stop -SubmittedBy <agent>` submits a pause-on-error decision during an active harness run.
- `pwsh ./tools/check-addon-parse.ps1` opens a minimal headless Godot project and surfaces GDScript parse, compile, or script-load errors in the addon. Run it after any edit under `addons/agent_runtime_harness/`; a non-zero exit is a blocking failure.

## Output locations

- Place seeded eval prompts and result files under `tools/evals/001-agent-tooling-foundation/`.
- Place reusable fixture inputs under `tools/evals/fixtures/001-agent-tooling-foundation/`.
- Place evidence helper scripts under `tools/evidence/`.
- Place autonomous boundary contracts and run logs under `tools/automation/`.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at `specs/008-agent-runbook/plan.md`. Companion artifacts:
`specs/008-agent-runbook/spec.md`, `research.md`, `data-model.md`,
`contracts/`, and `quickstart.md`.
<!-- SPECKIT END -->
