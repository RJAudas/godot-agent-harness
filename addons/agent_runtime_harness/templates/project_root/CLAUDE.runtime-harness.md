## Runtime Harness

This project has the `agent_runtime_harness` addon installed. When the user asks to run the game, press keys, verify at runtime, inspect the scene, or watch for errors, delegate to the `godot-runtime-verification` subagent (`.claude/agents/godot-runtime-verification.md`) or follow the fast path below directly.

## Fast path (4 steps — do not read any other files first)

1. Check `harness/automation/results/capability.json` exists and mtime < 5 min. Otherwise report `editor-not-running` — ask the user to launch the editor against this project.
2. Write **one** file at `harness/automation/requests/run-request.json` using the canonical payload template in [`.github/prompts/godot-runtime-verification.prompt.md`](.github/prompts/godot-runtime-verification.prompt.md). Fill only `<CHANGE>` fields.
3. Poll `harness/automation/results/run-result.json` for up to 60s, waiting for a matching `requestId` + non-empty `completedAt`.
4. Read `manifestPath` from that run-result, then the manifest, then the summary artifact the manifest references.

Key identifiers in `inputDispatchScript` are bare Godot logical names (`ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE`) — **not** `KEY_ENTER`. Actions use `{ "kind": "action", "identifier": "ui_accept", ... }`.

## Do not

- **Do not read prior-run artifacts** (`run-result.json` from earlier requests, `lifecycle-status.json`, previous `run-request*.json`, or `evidence/` files not produced by *your* request).
- **Do not read addon source** (`addons/agent_runtime_harness/`).
- **Do not hand-author multiple requests, shell-generate request IDs, or search for sample payloads.** Use the template verbatim.
- **Do not vary capture or stop policies speculatively.** Template defaults are correct for the common case.
- **Do not invent new broker entrypoints.** One file in, one file out, one manifest.

## Subagents

- `godot-runtime-verification` — drives a fresh run (see `.claude/agents/godot-runtime-verification.md`).
- `godot-evidence-triage` — interprets an existing manifest without starting a new run.
