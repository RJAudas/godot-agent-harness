## Runtime Harness Workflow

This project has the `agent_runtime_harness` addon installed. When the user asks to run the game, press keys, verify at runtime, inspect the scene, or watch for errors, use the Scenegraph Harness. The full prompt is at [`.github/prompts/godot-runtime-verification.prompt.md`](.github/prompts/godot-runtime-verification.prompt.md); the matching subagent for Claude Code is at [`.claude/agents/godot-runtime-verification.md`](.claude/agents/godot-runtime-verification.md).

## Fast path — one invoke script call

Use a harness invoke script — it handles capability check, request authoring, polling, and manifest lookup automatically and emits a single JSON envelope to stdout. `-ProjectRoot` is the absolute path to this game project.

```powershell
# Scene inspection (no input)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot "<absolute path to this project>"

# Input dispatch (keypresses / InputMap actions)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"

# Runtime error triage
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json"
```

Parse the stdout JSON envelope — `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome` — for the result. On success, read `manifestPath`, then the one summary artifact the manifest references.

Key identifiers in `inputDispatchScript` are bare Godot logical names — `ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE` — **not** `KEY_ENTER`. For InputMap actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Failure handling

| `failureKind` | Meaning | Next step |
|---|---|---|
| `editor-not-running` | Capability artifact missing or stale | Launch: `godot --editor --path "<this-project>"` |
| `build` | GDScript compile error | Report `diagnostics[0]` verbatim; no manifest |
| `runtime` | Runtime error captured | Read `outcome.latestErrorSummary` or `outcome.firstFailureSummary` |
| `timeout` | Run did not complete | Broker only runs while game is in play mode |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not hand-author `run-request.json` or poll `run-result.json` manually.** The invoke scripts own that loop.
- **Do not manually delete files** under `harness/automation/results/` or `evidence/automation/`. The invoke scripts clear the transient zone automatically before every run.
- **Do not read prior-run artifacts to plan a new run.** The transient zone is wiped before each invocation; any file you read there belongs to the current run or is stale.
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the protocol. Everything you need is in this file and the runtime-verification prompt.
- **Do not vary `capturePolicy` or `stopPolicy` speculatively.** Fixture defaults are correct for the common case.

## Routing

- **Runtime-visible request** (run game, press key, verify at runtime): delegate to `godot-runtime-verification` (Claude subagent in `.claude/agents/` or Copilot agent in `.github/agents/`).
- **Existing manifest + diagnosis only**: delegate to `godot-evidence-triage`.
- **Pure unit / contract / schema test**: run ordinary tests; the harness is not involved.

## Stop conditions

- Capability artifact is missing, stale, or reports `supported=false` for the kind of run you need. Launch the editor: `godot --editor --path "<this-project>"`.
- Envelope `failureKind = build`: report `buildFailurePhase`, `buildDiagnostics` entries verbatim, no manifest will exist.
- Envelope `failureKind = timeout`: the broker only processes requests while the game is in play mode.
- The task requires changes outside the declared autonomous write boundaries.

Report harness bugs or automation-contract defects at <https://github.com/RJAudas/godot-agent-harness/issues>.
