## Runtime Harness

- This project includes the `agent_runtime_harness` addon for machine-readable runtime scenegraph evidence.
- `project.godot` should enable `res://addons/agent_runtime_harness/plugin.cfg` and register the `ScenegraphHarness` autoload at `res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd`.
- Both the editor plugin and runtime autoload default to `res://harness/inspection-run-config.json` for session configuration.
- Persisted evidence goes to the path declared by `artifactRoot` / `outputDirectory` in each run-request.

## Runtime Evidence Workflow — fast path

For every "run the game", "press Enter past the menu", "verify at runtime", "inspect the scene", or "watch for errors" request, call one invoke script:

```powershell
# Scene inspection (no input)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1 `
  -ProjectRoot "<absolute path to this project>"

# Input dispatch (keypresses / InputMap actions)
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"
```

Each script handles capability check, request authoring, polling, and manifest lookup automatically and emits a single JSON envelope to stdout. Parse the envelope: `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`. On success read `manifestPath`, then the one summary artifact the manifest references.

Key identifiers in `inputDispatchScript` are bare Godot logical names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — **not** `KEY_ENTER`. Actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Don'ts

- **Do not hand-author `run-request.json` or poll `run-result.json` manually.** The invoke scripts own that loop.
- **Do not manually delete files** under `harness/automation/results/` or `evidence/automation/`. The scripts clear the transient zone automatically before every run.
- **Do not read prior-run artifacts** (`lifecycle-status.json`, previous run artifacts, or files under `evidence/` not produced by the current run). They describe the past, not what you need to do now.
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the protocol. The prompt file has everything.
- **Do not vary capture or stop policies speculatively.** Fixture defaults are correct for the common case.
- **Do not stop and restart the editor speculatively.** `capability.json` reflects current state, and stale editor state is rarely the cause of failures. Read `harness/automation/results/capability.json`, `run-result.json`, or `lifecycle-status.json` first. Restart only when you've confirmed the issue is editor-cached, not config-driven (or when running a CLI tool that needs exclusive project access, e.g. `godot --headless --import`).

## Routing

- **Runtime-visible request**: delegate to `godot-runtime-verification` (available as a Claude subagent under `.claude/agents/` and as a Copilot agent under `.github/agents/`).
- **Existing manifest, diagnosis only**: delegate to `godot-evidence-triage`.
- **Pure unit / contract / schema tests**: use ordinary tests; the harness is not involved.

## Read order after a successful run

- `evidence-manifest.json` (from the envelope's `manifestPath`)
- The one summary artifact named in the manifest's `artifactRefs` for your workflow (`scenegraph-summary.json`, `input-dispatch-outcomes.jsonl`, `behavior-watch-sample.jsonl`, etc.)
- Diagnostics or raw snapshots only if the summary points to a problem

## Failure handling

| `failureKind` | Meaning | Next step |
|---|---|---|
| `editor-not-running` | Capability artifact missing or stale | Launch: `godot --editor --path "<this-project>"` |
| `build` | GDScript compile error | Report `diagnostics[0]` verbatim; no manifest |
| `runtime` | Runtime error captured | Read `outcome.latestErrorSummary` or `outcome.firstFailureSummary` |
| `timeout` | Run did not complete | Broker only runs while game is in play mode |

Report harness bugs or automation-contract defects at <https://github.com/RJAudas/godot-agent-harness/issues>.
