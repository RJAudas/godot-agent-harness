---
description: Run Scenegraph Harness runtime verification by writing one brokered run-request and reading its evidence. Stay on the fast path.
---

## Mission

Prove a runtime-visible claim about the running Godot project by delivering exactly one brokered run-request and reading the evidence it produces. Do not spelunk; the fast path below is sufficient for every standard run-game, press-key, or observe-state request.

## Inputs

- Change or verification request in natural language
- Optional expected runtime node, hierarchy, or gameplay symptom
- Optional input script (keypresses, `InputMap` actions) to drive the running game

## Fast path

Every "run the game / press keys / verify at runtime" request resolves to these four steps. See `godot-runtime-verification.prompt.md` for the full run-request template and the explicit don'ts.

1. Verify `harness/automation/results/capability.json` exists and is fresh (<5 min). If not, report `editor-not-running`.
2. Write `harness/automation/requests/run-request.json` using the canonical template in the prompt file. One file.
3. Poll `harness/automation/results/run-result.json` for a matching `requestId` + non-empty `completedAt` (up to 60s).
4. Read `manifestPath` from the fresh run-result, then the manifest, then the relevant summary artifact.

## Guardrails

- **Never read prior-run artifacts to plan a new run.** `run-result.json`, `lifecycle-status.json`, and `evidence/` from past requests describe history — they do not tell you what payload to write now.
- **Never read addon source** (`addons/agent_runtime_harness/`). The agent-facing contract is the prompt file plus the capability artifact.
- **Never vary `capturePolicy` or `stopPolicy` speculatively.** The canonical template values are correct for the common case.
- **Never invent helper scripts or alternate broker paths.** The only input is `run-request.json`; the only outputs are `run-result.json` and the manifest.
- **Never invent a new agent** to dispatch input. Input dispatch is an `inputDispatchScript` field on the standard run-request. Key identifiers are bare names (`ENTER`, `SPACE`, `LEFT`), not `KEY_*` constants.

## Stop conditions

- `capability.json` is missing, stale (>5 min), or reports `supported=false` for the kind of run you need.
- The fresh `run-result.json` reports `failureKind = build`. Report the build diagnostics and stop; no manifest will exist.
- No matching `run-result.json` appears within 60s. Report `timeout` and note that the editor broker only processes requests while the game is in play mode.
- Task is evidence triage on an existing manifest: route to `godot-evidence-triage.agent.md`.

## Expected outputs

- `status` + `failureKind` (if applicable)
- Manifest path and one-line runtime summary on success
- On build failure, the `buildFailurePhase`, each `buildDiagnostics` entry with line/column when present, and the relevant raw build-output lines verbatim
- The next concrete debugging step grounded in the manifest or run-result
