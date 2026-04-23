# Claude Code instructions

Start here. This file is the fast-path summary for Claude Code working in this repo. The full agent-facing operating guide is [AGENTS.md](AGENTS.md); read it once per session.

## Runtime verification (the common ask)

When the user asks to run the game, press keys, verify runtime behaviour, inspect a scene, or watch for errors:

1. **Match the request to a row in [RUNBOOK.md](RUNBOOK.md).** Every runtime-visible workflow has exactly one `tools/automation/invoke-*.ps1` script.
2. **Call that script once** with the target project root and a fixture from `tools/tests/fixtures/runbook/<workflow>/`. The script handles the capability check, request authoring, schema validation, polling, and manifest lookup.
3. **Parse the stdout JSON envelope** (`specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`). That envelope is the single source of truth — `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`.
4. **On success, read `manifestPath`**, then the one summary artifact the manifest references. That is your evidence.

For delegation, the `godot-runtime-verification` subagent in [.claude/agents/](.claude/agents/) is the canonical handler — invoke it via Task when the user's request is runtime-visible.

### Canonical invocations

```powershell
# Run the game + press Enter past the menu
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json

# Run the game + capture the scene tree
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot <game-root>
```

See the full list in [RUNBOOK.md](RUNBOOK.md).

## Do not

These are the behaviors that waste runs.

- **Do not read prior-run artifacts to plan a new run.** That includes earlier `run-result.json`, `lifecycle-status.json`, previous request files, or anything under `evidence/` that your new request did not produce.
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the protocol. Every agent-facing contract is in `RUNBOOK.md`, `docs/runbook/`, `specs/008-agent-runbook/contracts/`, or an invoke script's `Get-Help` output.
- **Do not hand-author `run-request.json`** when an invoke script exists for the workflow.
- **Do not generate request IDs via shell, search for sample payloads, or build requests from raw config.** The invoke script owns all of that.
- **Do not vary capture or stop policies speculatively.** Fixture defaults are correct for the common case.

## Where to look for more

- [AGENTS.md](AGENTS.md) — full operating guide, validation routing, write boundaries
- [RUNBOOK.md](RUNBOOK.md) — workflow-to-script mapping
- [docs/runbook/](docs/runbook/) — recipe docs for each workflow
- [specs/008-agent-runbook/contracts/](specs/008-agent-runbook/contracts/) — schemas
- `.claude/agents/` — subagents to delegate to
