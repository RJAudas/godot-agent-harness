# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Start here. This file is the fast-path summary; the full agent-facing operating guide is [AGENTS.md](AGENTS.md), and repo-wide durable rules live in [.github/copilot-instructions.md](.github/copilot-instructions.md).

## Architecture (one-pager)

Plugin-first Godot harness that gives agents machine-readable runtime evidence instead of human retellings. Two sides talk via a file broker:

- **Editor side** ([addons/agent_runtime_harness/editor/](addons/agent_runtime_harness/editor/)): dock UI, automation broker, run coordinator, artifact store. Watches `harness/automation/requests/` in the target project and writes to `harness/automation/results/`.
- **Runtime side** ([addons/agent_runtime_harness/runtime/](addons/agent_runtime_harness/runtime/)): autoload singleton loaded into the *playtest* game — scene capture, input dispatch, behavior-watch sampler, artifact writer.
- **Evidence is manifest-centered**: every run produces `evidence-manifest.json` that references the workflow-specific artifact (e.g. `input-dispatch-outcomes.jsonl`, `scene-tree.json`). Read the manifest, not raw artifacts.
- **Agent-facing contracts** live in [specs/008-agent-runbook/contracts/](specs/008-agent-runbook/contracts/) (schemas) and [docs/runbook/](docs/runbook/) (recipes). The `invoke-*.ps1` scripts wrap the full capability-check → request → poll → manifest-read loop so agents never hand-author `run-request.json`.
- **Evidence lifecycle**: the transient zone (`harness/automation/results/` + `evidence/automation/`) is wiped automatically before every run. To keep a run, use `invoke-pin-run.ps1` — do not delete or copy files by hand. Zone classification is the single source of truth in `Get-RunZoneClassification` ([data-model](specs/009-evidence-lifecycle/data-model.md)). Pinned runs live in `harness/automation/pinned/<name>/`.
- **Integration testing** uses git-ignored sandboxes at `integration-testing/<name>/`. Never scaffold ad-hoc projects elsewhere, never commit a Godot binary, never hard-code an install path.

## Common commands

- `pwsh ./tools/tests/run-tool-tests.ps1` — Pester suite for all PowerShell scripts; no live editor needed.
- `pwsh ./tools/check-addon-parse.ps1` — headless GDScript parse/compile check. **Run after every edit under `addons/agent_runtime_harness/`**; non-zero exit is a blocking failure.
- `pwsh ./tools/validate-json.ps1 -InputPath <json> -SchemaPath <schema>` — JSON-schema validation for fixtures, requests, config.
- `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <path>` — validates an evidence manifest and confirms referenced artifacts exist.
- `pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId <id> -RequestedPath <path> -RequestedEditType <type>` — run before recording an autonomous write as compliant.
- Godot binary resolution (for any script that needs it): `$env:GODOT_BIN` first, then `godot`/`godot4`/`Godot*` on PATH. If neither resolves, check the User-scope environment before concluding Godot is missing.

## Safe edit targets

Default write zones: `.github/`, `docs/`, `tools/`, `specs/`. Avoid casual edits under `addons/agent_runtime_harness/` and `scenarios/` unless the task requires runtime-facing behavior or deterministic fixture changes. `integration-testing/` is git-ignored and yours to use freely. First-release autonomous artifacts must stay inside the paths declared in [tools/automation/write-boundaries.json](tools/automation/write-boundaries.json).

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

- **Do not read prior-run artifacts to plan a new run.** The transient zone is wiped automatically before each new run, so any file you read there belongs to the *current* run or is a stale artefact you should not trust. If you need a prior run's evidence, it must have been pinned first — use `invoke-list-pinned-runs.ps1` to find it, not a directory scan.
- **Do not read addon source to understand the agent protocol.** Every agent-facing contract is in `RUNBOOK.md`, `docs/runbook/`, `specs/008-agent-runbook/contracts/`, or an invoke script's `Get-Help` output. (When the *task itself* is editing the addon to fix a bug, reading it is expected — then run `tools/check-addon-parse.ps1`.)
- **Do not hand-author `run-request.json`** when an invoke script exists for the workflow.
- **Do not generate request IDs via shell, search for sample payloads, or build requests from raw config.** The invoke script owns all of that.
- **Do not vary capture or stop policies speculatively.** Fixture defaults are correct for the common case.

## Where to look for more

- [AGENTS.md](AGENTS.md) — full operating guide, validation routing, write boundaries
- [RUNBOOK.md](RUNBOOK.md) — workflow-to-script mapping
- [docs/runbook/](docs/runbook/) — recipe docs for each workflow
- [specs/008-agent-runbook/contracts/](specs/008-agent-runbook/contracts/) — schemas
- `.claude/agents/` — subagents to delegate to

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
at [specs/009-evidence-lifecycle/plan.md](specs/009-evidence-lifecycle/plan.md).
<!-- SPECKIT END -->
