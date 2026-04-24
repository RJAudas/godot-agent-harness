# Godot Agent Harness Copilot Instructions

## Repository purpose

This repository builds a plugin-first Godot harness that gives coding agents machine-readable runtime evidence instead of relying on human retellings of gameplay behavior.

## Read in this order

1. `README.md` for repository purpose and layout.
2. `AGENTS.md` for agent-facing workflow rules.
3. `RUNBOOK.md` as the five-row quick-reference index before running any runtime workflow (scene inspection, input dispatch, behavior watch, build-error triage, runtime-error triage).
4. Relevant path-specific files under `.github/instructions/`.
5. `docs/AGENT_RUNTIME_HARNESS.md` for harness architecture and evidence expectations.
6. `docs/AI_TOOLING_BEST_PRACTICES.md` when adding or changing agent tooling assets.
7. `docs/INTEGRATION_TESTING.md` and the "End-to-end plugin testing" section of `tools/README.md` BEFORE doing anything that involves a real Godot editor, real playtest, or real input dispatch.

## Durable rules

- Stay plugin-first: prefer addon, autoload, debugger, and GDExtension layers before considering engine changes.
- Treat `../godot` as a read-only reference checkout when engine behavior needs confirmation.
- When runtime evidence exists, read the manifest first and inspect raw artifacts only as needed.
- Use three validation modes consistently: ordinary tests, Scenegraph Harness runtime verification, and combined validation.
- Choose Scenegraph Harness runtime verification for requests about runtime-visible behavior, what appears in game, node presence, hierarchy, or other outcomes that must be proven from a running project.
- Choose combined validation when a change affects runtime-visible behavior and there is already an existing deterministic test surface; run the existing tests plus the runtime harness flow, but do not invent new ordinary tests solely to satisfy the rule.
- When routing to runtime verification from this repository checkout, prefer the parameterized orchestration scripts (`tools/automation/invoke-*.ps1`); consult `RUNBOOK.md` for the right script, fixture template, and recipe doc for each workflow. Fall back to the raw helper flow only when the invoke script cannot satisfy the need. Treat blocked or missing capability and run-result artifacts as explicit unsupported states.
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
- `pwsh ./tools/automation/invoke-input-dispatch.ps1 -ProjectRoot <game-root> [-RequestFixturePath <path> | -RequestJson <json>]` runs an input-dispatch workflow end-to-end and emits a JSON stdout envelope.
- `pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot <game-root>` runs a startup scene-tree capture and emits a JSON stdout envelope.
- `pwsh ./tools/automation/invoke-build-error-triage.ps1 -ProjectRoot <game-root> [-RequestFixturePath <path> | -RequestJson <json>] [-IncludeRawBuildOutput]` runs a build-error triage workflow and emits a JSON stdout envelope.
- `pwsh ./tools/automation/invoke-runtime-error-triage.ps1 -ProjectRoot <game-root> [-RequestFixturePath <path> | -RequestJson <json>] [-IncludeFullStack]` runs a runtime-error triage workflow and emits a JSON stdout envelope.
- `pwsh ./tools/automation/invoke-behavior-watch.ps1 -ProjectRoot <game-root> [-RequestFixturePath <path> | -RequestJson <json>]` runs a behavior-watch workflow and emits a JSON stdout envelope.
- `pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot <game-root> -PinName <name> [-Force] [-DryRun]` pins the current transient run to a stable named slot and emits a lifecycle envelope.
- `pwsh ./tools/automation/invoke-unpin-run.ps1 -ProjectRoot <game-root> -PinName <name> [-DryRun]` removes a named pin and emits a lifecycle envelope.
- `pwsh ./tools/automation/invoke-list-pinned-runs.ps1 -ProjectRoot <game-root>` lists all named pins and emits a lifecycle envelope with `pinnedRunIndex[]`.

The transient zone (`harness/automation/results/` and `evidence/automation/`) is cleared automatically before every runtime run. Pin a run with `invoke-pin-run.ps1` before running again when you need to compare or preserve it. Never delete transient-zone files manually.

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
