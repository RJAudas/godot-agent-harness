# AGENTS.md

## Purpose

Use this file as the agent-facing operating guide for work in this repository.

## Working order

1. Read `README.md` for scope and layout.
2. Read `.github/copilot-instructions.md` for durable repo-wide rules.
3. Read the nearest matching `.github/instructions/*.instructions.md` file before editing a subtree.
4. Use `docs/AGENT_RUNTIME_HARNESS.md` and `docs/GODOT_PLUGIN_REFERENCES.md` before proposing engine-level changes.

## Core rules

- Prefer plugin-first solutions. Addon, autoload, debugger, and GDExtension layers come before any engine fork discussion.
- Treat machine-readable evidence as ground truth. If a manifest exists, read it before opening raw trace, event, or scene files.
- Keep agent-tooling assets inside the established Copilot-first surfaces: `.github/copilot-instructions.md`, `.github/instructions/`, `.github/prompts/`, and `.github/agents/`.
- Do not duplicate large guidance blocks across files. Link or point to the canonical layer instead.
- Treat `../godot` as reference-only unless the task explicitly asks for engine investigation.
- For any work that requires a real running Godot editor (manual feature validation, broker smoke tests, evidence reproduction, input-dispatch verification, "test the plugin", "test key input"), follow the sandbox flow in `docs/INTEGRATION_TESTING.md` and the "End-to-end plugin testing" section of `tools/README.md`: scaffold under `integration-testing/<name>/`, deploy with `tools/deploy-game-harness.ps1`, parse-check, then run the broker loop. Resolve the Godot binary the same way `tools/check-addon-parse.ps1` does (`$env:GODOT_BIN`, then `godot`/`godot4`/`Godot*` on `PATH`); if neither resolves in the current shell, check the User-scope environment before concluding Godot is missing. Never download a Godot binary into the repo and never hard-code an install path in checked-in scripts.

## Validation routing

- Use **ordinary tests** for unit, contract, framework, and other non-runtime checks.
- Use **Scenegraph Harness runtime verification** for requests such as "verify at runtime," "test the running code," "make sure the node appears in game," "confirm the node exists while playing," "start the app and press <key>," or other runtime-visible outcomes.
- Use **combined validation** when a change affects runtime-visible behavior and there is already a deterministic direct test surface. Run the existing tests and the runtime harness flow together, but do not fabricate new ordinary tests only to satisfy the combined rule.
- If the user already supplies an evidence manifest and wants diagnosis, stay in manifest-centered evidence triage instead of launching a fresh runtime-verification run.
- Auto-delegate to the matching custom agent rather than handling runtime work inline. Delegate to `godot-runtime-verification` for any fresh harness run (runtime-visible checks, starting the game, dispatching keys or `InputMap` actions via `overrides.inputDispatchScript`, reproducing a runtime crash). Delegate to `godot-evidence-triage` when an evidence manifest already exists and only diagnosis is required. Do not ask the user to pick the agent when the routing rule is unambiguous.
- For runtime verification in this repository, prefer `pwsh ./tools/automation/get-editor-evidence-capability.ps1` and `pwsh ./tools/automation/request-editor-evidence-run.ps1`, then inspect the persisted bundle manifest first.
- Treat blocked capability artifacts, blocked run results, or missing persisted bundles as explicit stop conditions. Report them plainly instead of guessing around the editor.

## Validation expectations

- Validate repository JSON outputs with `pwsh ./tools/validate-json.ps1` and the matching schema.
- Validate manifests with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`.
- Validate autonomous write requests with `pwsh ./tools/automation/validate-write-boundary.ps1` before recording a run as compliant.
- Submit pause-on-error decisions with `pwsh ./tools/automation/submit-pause-decision.ps1 -ProjectRoot <path> -RunId <id> -PauseId <n> -Decision continue|stop -SubmittedBy <agent>`.
- After editing any GDScript under `addons/agent_runtime_harness/`, run `pwsh ./tools/check-addon-parse.ps1`. A non-zero exit is a blocking failure that MUST be resolved before the change is considered complete.
- Record story-level eval results in `tools/evals/001-agent-tooling-foundation/` as machine-readable JSON.

## Path defaults

- Safe default write targets for agent-tooling work are `.github/`, `docs/`, `tools/`, and `specs/001-agent-tooling-foundation/`.
- Avoid casual edits under `addons/agent_runtime_harness/` and `scenarios/` unless the task needs runtime-facing behavior or deterministic fixture changes. The git-ignored `integration-testing/` sandbox is yours to use freely; tracked test fixtures live under `tools/tests/fixtures/`.

## Autonomous artifacts

- First-release autonomous artifacts may write only inside paths declared by `tools/automation/write-boundaries.json`.
- If a requested change falls outside the declared boundary, stop and escalate instead of improvising broader edits.
