## Runtime Harness

This project has the `agent_runtime_harness` addon installed. When the user asks to run the game, press keys, verify at runtime, inspect the scene, or watch for errors, delegate to the `godot-runtime-verification` subagent (`.claude/agents/godot-runtime-verification.md`) or follow the fast path below directly.

## Fast path — one invoke script, one envelope

The runtime invokers all assume a Godot editor is running against the project. Pass `-EnsureEditor` to have them auto-launch one (idempotent: reuses an existing editor when capability.json is fresh).

```powershell
# Scene inspection (no input). -EnsureEditor spawns the editor if needed.
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor

# Input dispatch (keypresses / InputMap actions)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"

# Runtime error triage
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot "<absolute path to this project>" -EnsureEditor `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json"

# When you're done with this project, stop the editor:
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-stop-editor.ps1 `
  -ProjectRoot "<absolute path to this project>"
```

Parse stdout JSON: `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`. On success read `manifestPath`, then the one artifact the manifest references.

Key identifiers: bare Godot names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — not `KEY_ENTER`. InputMap actions: `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Build errors

For build errors, try the CLI first (run from the project root, or pass `--path <project>`):

- `godot --check-only` — GDScript parse errors
- `godot --import` — asset import / `.tres` / scene-load errors
- `godot --headless --quit-after 1` — autoload `_ready` failures

Use `{{HARNESS_REPO_ROOT}}/tools/automation/invoke-build-error-triage.ps1` as a fallback when the CLI doesn't reproduce the error or doesn't surface enough detail (engine crashes, multi-file dependency error threading, structured JSON output for downstream consumption). If you find yourself reaching for it routinely, file an issue describing what the CLI missed.

## Do not

- **Do not hand-author `run-request.json`** — the invoke scripts own the broker loop.
- **Do not manually delete files** under `harness/automation/results/` or `evidence/automation/` — scripts clear the transient zone automatically before every run.
- **Do not read prior-run artifacts** to plan a new run — the transient zone is wiped before every invocation.
- **Do not read addon source** (`addons/agent_runtime_harness/`).
- **Do not vary capture or stop policies speculatively** — fixture defaults are correct.

## Subagents

- `godot-runtime-verification` — drives a fresh run (see `.claude/agents/godot-runtime-verification.md`).
- `godot-evidence-triage` — interprets an existing manifest without starting a new run.
