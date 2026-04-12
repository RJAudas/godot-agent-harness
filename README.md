# Godot Agent Harness

Godot Agent Harness is a plugin-first project for improving **agent-driven game development** in Godot.

The core goal is to give agents **structured runtime feedback** instead of relying on a human to repeatedly run the game and describe what went wrong in natural language.

## Project goal

Build a Godot-compatible harness that helps agents:

- run deterministic gameplay scenarios
- inspect the runtime scene tree / node graph
- capture machine-readable frame traces
- collect structured gameplay events and logs
- evaluate invariants automatically
- diagnose runtime failures from evidence

This project is intentionally starting as a **plugin/addon**, not an engine fork.

## Why this exists

The current feedback loop for agent-built games is weak:

1. Agent changes code.
2. Human runs the game.
3. Human explains behavior.
4. Agent guesses.

That breaks down on bugs like:

- incorrect Pong bounce physics
- objects not instancing
- collisions behaving incorrectly
- infinite gameplay loops

The harness is meant to become the missing observability layer.

## Approach

Start with the least invasive path:

1. **Editor plugin / addon**
2. **Runtime addon + autoload singleton**
3. **Debugger integration**
4. **GDExtension if needed**
5. **Engine fork only as a last resort**

## Repository layout

```text
addons/
  agent_runtime_harness/   # plugin/addon implementation
docs/
  AGENT_RUNTIME_HARNESS.md # requirements and architecture
  GODOT_PLUGIN_REFERENCES.md
examples/
  pong-testbed/            # minimal validation project
scenarios/                 # deterministic scenario definitions
tools/                     # helper scripts and runner utilities
```

## Documentation

- Requirements and implementation direction: `docs/AGENT_RUNTIME_HARNESS.md`
- Curated Godot extension references: `docs/GODOT_PLUGIN_REFERENCES.md`
- AI agent tooling guidance: `docs/AI_TOOLING_BEST_PRACTICES.md`
- Agent tooling overview and manual usage: `docs/AGENT_TOOLING_FOUNDATION.md`
- Project constitution and delivery rules: `.specify/memory/constitution.md`

## Plugin deployment

The harness now supports two deployment paths for a target Godot game project.

### Preferred path: plugin-driven deployment

1. Copy `addons/agent_runtime_harness/` into the target project under `addons/`.
2. Enable the addon from Godot project plugin settings.
3. Use the `Deploy Agent Assets` action in the Scenegraph Harness dock.

That plugin action installs the project-level assets the agent needs:

- `.github/copilot-instructions.md` managed runtime-harness block
- `AGENTS.md` managed runtime-harness block
- `.github/prompts/godot-evidence-triage.prompt.md`
- `.github/agents/godot-evidence-triage.agent.md`
- `harness/inspection-run-config.json`
- `project.godot` wiring for the harness autoload and config path

The deployable templates live inside the addon under `addons/agent_runtime_harness/templates/project_root/`, so the plugin can install them without depending on the source repository layout.

### Optional path: source-repo deployment script

If you are deploying from this repository into another local game project, you can also use:

```powershell
pwsh ./tools/deploy-game-harness.ps1 -GameRoot <game-root>
```

That script copies the addon and installs the same project-level assets from the addon template directory. It is primarily useful for source-driven setup and testing; the plugin-driven path is the intended day-to-day installation flow.

## Agent tooling entry points

The repository uses a Copilot-first guidance stack for agent work:

- `.github/copilot-instructions.md` for durable repo-wide guidance
- `AGENTS.md` for agent-facing workflow rules and validation expectations
- `.github/instructions/` for subtree-specific constraints
- `.github/prompts/` and `.github/agents/` for reusable Copilot-native workflows
- `tools/evals/001-agent-tooling-foundation/` for seeded eval prompts and machine-readable result files

## Development discipline

Feature work in this repository follows a plugin-first constitution:

- consult internal docs and official Godot references before designing or implementing
- use `../godot` relative to the repository root as the reference checkout when engine behavior needs verification
- prefer addon, autoload, debugger, and GDExtension layers before considering engine changes
- require deterministic scenario runs or other automated validation that produces machine-readable runtime evidence for agents

## Security scanning

This repository uses Gitleaks in GitHub Actions to scan git history and current changes for committed secrets.

- Workflow: `.github/workflows/gitleaks.yml`
- Configuration: `.gitleaks.toml`
- Local hook config: `.pre-commit-config.yaml`

To enable local pre-commit scanning:

1. Install pre-commit using the instructions at https://pre-commit.com/#install
2. Run `pre-commit install`
3. Optionally run `pre-commit run --all-files` to scan the repository immediately

If you intentionally need a test secret in the repository, prefer a fake value that does not match real credential formats. If Gitleaks still flags it, use a targeted allowlist approach rather than disabling the scan broadly.

## Reference strategy

This repository should **not vendor the full Godot documentation**.

Instead, it should keep:

- concise local design notes
- curated links to official docs
- implementation-specific notes learned while building the harness

That keeps the repo lightweight while still giving agents enough context to work effectively.
