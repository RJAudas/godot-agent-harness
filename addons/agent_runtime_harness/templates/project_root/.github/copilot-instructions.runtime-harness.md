## Runtime Harness

- This project includes the `agent_runtime_harness` addon for machine-readable runtime scenegraph evidence.
- `project.godot` should enable `res://addons/agent_runtime_harness/plugin.cfg` and register the `ScenegraphHarness` autoload at `res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd`.
- Both the editor plugin and runtime autoload default to `res://harness/inspection-run-config.json` for session configuration.
- Persisted evidence goes to the path declared by `artifactRoot` / `outputDirectory` in each run-request.

## Runtime Evidence Workflow — fast path

For every "run the game", "press Enter past the menu", "verify at runtime", "inspect the scene", or "watch for errors" request:

1. Check `harness/automation/results/capability.json` — missing or stale (>5 min) means `editor-not-running`.
2. Write **one** file, `harness/automation/requests/run-request.json`, using the canonical payload template in [`.github/prompts/godot-runtime-verification.prompt.md`](prompts/godot-runtime-verification.prompt.md). Fill only the `<CHANGE>` fields.
3. Poll `harness/automation/results/run-result.json` up to 60s for a matching `requestId` + non-empty `completedAt`.
4. Read `manifestPath` from the fresh run-result, then the manifest, then the one summary artifact the manifest references. That is your evidence.

Key identifiers in `inputDispatchScript` are bare Godot logical names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — **not** `KEY_ENTER`. Actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Don'ts

- **Do not read prior-run artifacts** (`run-result.json` from earlier requests, `lifecycle-status.json`, previous `run-request*.json`, or files under `evidence/` not produced by *your* request). They describe the past, not what you need to do now.
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the protocol. The prompt file has everything.
- **Do not vary capture or stop policies speculatively.** Template defaults are correct for the common case.
- **Do not hand-author multiple requests, shell-generate IDs, or search for sample payloads.** Use the template verbatim.

## Routing

- **Runtime-visible request**: delegate to `godot-runtime-verification` (available as a Claude subagent under `.claude/agents/` and as a Copilot agent under `.github/agents/`).
- **Existing manifest, diagnosis only**: delegate to `godot-evidence-triage`.
- **Pure unit / contract / schema tests**: use ordinary tests; the harness is not involved.

## Read order after a successful run

- `evidence-manifest.json` (from the fresh run-result's `manifestPath`)
- The one summary artifact named in the manifest's `artifactRefs` for your workflow (`scenegraph-summary.json`, `input-dispatch-outcomes.jsonl`, `behavior-watch-sample.jsonl`, etc.)
- Diagnostics or raw snapshots only if the summary points to a problem

## Build and runtime failure handling

- `run-result.json` reports `failureKind = build`: report `buildFailurePhase`, each `buildDiagnostics` entry with `resourcePath`/`message`/`line`/`column`, and the relevant `rawBuildOutput` lines **verbatim**. Do not paraphrase. No manifest will exist.
- `failureKind = runtime`: read the manifest and `runtime-error-records.jsonl` for the first failure.
- `failureKind = timeout`: the broker did not pick up the request. The plugin only processes requests while the game is in play mode — the user may need to press Play.

Report harness bugs or automation-contract defects at <https://github.com/RJAudas/godot-agent-harness/issues>.
