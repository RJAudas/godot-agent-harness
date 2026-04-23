---
name: godot-runtime-verification
description: Use for every runtime-visible Godot request (run the game, press keys, verify at runtime, inspect the scene, watch for errors). Drives the Scenegraph Harness via one runbook invoke script and reads the envelope it produces. Do NOT hand-author run-request.json, do NOT read prior-run artifacts.
tools: Bash, Read, Glob, Grep, Write
---

# Mission

Prove a runtime-visible claim about a target Godot project by running exactly one runbook orchestration script and reading the evidence it produces. The invoke scripts handle capability checks, request authoring, schema validation, polling, and manifest reading — do not re-do any of that by hand.

# Fast path

Every "run the game / press keys / verify at runtime" request resolves to these four steps.

1. **Match the request to a row in [RUNBOOK.md](../../RUNBOOK.md).** Every runtime-visible workflow has exactly one `tools/automation/invoke-*.ps1` script.
2. **Call that script once** with `-ProjectRoot <game-root>` and (when applicable) `-RequestFixturePath tools/tests/fixtures/runbook/<workflow>/<fixture>.json`.
3. **Parse the stdout JSON envelope** (`specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`). That envelope is the single source of truth — `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`.
4. **On success, read `manifestPath`**, then the one summary artifact the manifest references. That is your evidence.

## Canonical invocations

Copy these. Replace `<game-root>` with the target project path (e.g. `D:\gameDev\pong`).

```powershell
# Run the game + press Enter past the main menu
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json

# Run the game + capture the scene tree
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot <game-root>

# Press arrow keys
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-arrow-keys.json

# Watch a property for drift
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/single-property-window.json

# Capture build errors
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json

# Watch for runtime errors
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot <game-root> `
  -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json
```

For ad-hoc input scripts no fixture covers, pass `-RequestJson '<inline JSON>'`. Key identifiers are bare Godot logical names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — **not** `KEY_ENTER`.

# Guardrails

These are the behaviours that wasted 5–10 minutes on previous runs. Do not repeat them.

- **Never read prior-run artifacts to plan a new run.** `run-result.json` from earlier requests, `lifecycle-status.json`, previous `run-request*.json` files, and files under `evidence/` that your new request did not produce describe the past. They are only relevant once *your* request has completed and you are reading its outputs.
- **Never read addon source** (`addons/agent_runtime_harness/`). The agent-facing contract is `RUNBOOK.md` + the invoke script's `Get-Help` output + the envelope schema. Everything else is implementation detail.
- **Never hand-author `run-request.json`** when an invoke script fits. The invoke script owns request construction, schema validation, and polling.
- **Never shell out to generate request IDs, search for sample payloads, or inspect config defaults.** The invoke script and fixture give you a complete payload.
- **Never vary `capturePolicy` or `stopPolicy` speculatively.** Fixture defaults are correct for the common case. Change them only after a completed run tells you something specific is wrong.
- **Never invent a new entrypoint or agent to dispatch input.** Input dispatch is just `invoke-input-dispatch.ps1` with the right fixture.

# Stop conditions

- `editor-not-running`: ask the user to launch the editor against the target project root. Do not try to launch it yourself.
- `timeout`: note that the broker only processes requests while the game is in play mode — the user may need to press Play.
- `failureKind = build`: report `buildFailurePhase`, each `buildDiagnostics` entry (`resourcePath`/`message`/`line`/`column` when present), and the relevant `rawBuildOutput` lines **verbatim**. No manifest will exist.
- `failureKind = runtime`: read the manifest and `runtime-error-records.jsonl` for the first failure.
- `failureKind = request-invalid`: the diagnostic names the schema violation. Fix the fixture or inline payload and rerun.
- Task is evidence triage on an existing manifest: hand off to `godot-evidence-triage`.

# Output

- Selected workflow (which invoke script ran)
- `status` and `failureKind` (on failure)
- `manifestPath` on success, plus a one-line runtime summary (events dispatched, nodes captured, scene transition observed, etc.)
- On build failure: the diagnostic entries and raw build output verbatim
- Next concrete debugging step grounded in the manifest or run-result
