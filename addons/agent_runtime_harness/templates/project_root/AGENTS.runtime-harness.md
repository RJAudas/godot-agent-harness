## Runtime Harness Workflow

This project has the `agent_runtime_harness` addon installed. When the user asks to run the game, press keys, verify at runtime, inspect the scene, or watch for errors, use the Scenegraph Harness. The full prompt is at [`.github/prompts/godot-runtime-verification.prompt.md`](.github/prompts/godot-runtime-verification.prompt.md); the matching subagent for Claude Code is at [`.claude/agents/godot-runtime-verification.md`](.claude/agents/godot-runtime-verification.md).

## Fast path (every run-game + optional input request)

1. Verify `harness/automation/results/capability.json` exists and is fresher than 5 minutes. Otherwise report `editor-not-running` and ask the user to launch the editor against this project.
2. Write **one** file at `harness/automation/requests/run-request.json` using the canonical payload template in the runtime-verification prompt. Fill the `<CHANGE>` fields, leave the rest verbatim.
3. Poll `harness/automation/results/run-result.json` for up to 60 seconds, waiting for a `requestId` that matches the one you wrote **and** a non-empty `completedAt`.
4. Read the `manifestPath` from that run-result, then the manifest, then the relevant summary artifact (e.g. `input-dispatch-outcomes.jsonl`, `scenegraph-summary.json`).

Key identifiers in `inputDispatchScript` are bare Godot logical names — `ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`, etc. — **not** `KEY_ENTER`. For InputMap actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Do not

These behaviours burn 5–10 minutes per run for no gain:

- **Do not read prior-run artifacts to plan a new run.** `run-result.json` from earlier requests, `lifecycle-status.json`, previous `run-request*.json` files, and anything under `evidence/` describe the past. They do not tell you what payload to write now.
- **Do not read addon source** (`addons/agent_runtime_harness/`) to understand the protocol. Everything you need is in the runtime-verification prompt and this file.
- **Do not vary `capturePolicy` or `stopPolicy` speculatively.** The template defaults are correct for the common case.
- **Do not shell out to generate request IDs, search for sample payloads, or build requests from config defaults.** Use the template verbatim.
- **Do not invent new broker entrypoints or helper scripts.** One file in (`run-request.json`), one file out (`run-result.json`), one manifest to read.

## Routing

- **Runtime-visible request** (run game, press key, verify at runtime): delegate to `godot-runtime-verification` (Claude subagent in `.claude/agents/` or Copilot agent in `.github/agents/`).
- **Existing manifest + diagnosis only**: delegate to `godot-evidence-triage`.
- **Pure unit / contract / schema test**: run ordinary tests; the harness is not involved.

## Stop conditions

- Capability artifact is missing, stale, or reports `supported=false` for the kind of run you need.
- `run-result.json` reports `failureKind = build`: report `buildFailurePhase`, each `buildDiagnostics` entry with `resourcePath`/`message`/`line`/`column`, and the relevant `rawBuildOutput` lines verbatim. No manifest will exist.
- No matching `run-result.json` appears within 60 seconds: the broker only processes requests while the game is in play mode — the user may need to press Play.
- The task requires changes outside the declared autonomous write boundaries.

Report harness bugs or automation-contract defects at <https://github.com/RJAudas/godot-agent-harness/issues>.
