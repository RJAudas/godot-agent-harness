---
description: Drive a Godot runtime verification with the Scenegraph Harness using invoke scripts. One call, one JSON envelope.
---

## User Input

```text
$ARGUMENTS
```

> **Claude Code users**: every workflow below is also a `/godot-*` slash command (`/godot-inspect`, `/godot-press`, `/godot-debug-runtime`, `/godot-debug-build`, `/godot-watch`, `/godot-pin`, `/godot-unpin`, `/godot-pins`). The skill auto-invocation is the preferred path. This prompt remains the canonical guidance for Copilot and other non-Claude tools.

## Fast path — one invoke script call

Run the matching invoke script; it handles capability check, request authoring, polling, and manifest lookup in one call and emits a single JSON envelope to stdout.

### Input dispatch (keypresses / InputMap actions)

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestJson '{
  "requestId": "placeholder",
  "scenarioId": "agent-runtime-verification",
  "runId": "agent-runtime-verification",
  "targetScene": "<CHANGE: e.g. res://scenes/main.tscn>",
  "outputDirectory": "res://evidence/automation/agent",
  "artifactRoot": "evidence/automation/agent",
  "capturePolicy": { "startup": true, "manual": true, "failure": true },
  "stopPolicy": { "stopAfterValidation": true },
  "requestedBy": "agent",
  "createdAt": "<CHANGE: current UTC ISO-8601, e.g. 2026-04-23T15:30:00Z>",
  "inputDispatchScript": {
    "events": [
      { "kind": "key", "identifier": "ENTER", "phase": "press",   "frame": 30 },
      { "kind": "key", "identifier": "ENTER", "phase": "release", "frame": 32 }
    ]
  }
}'
```

The `requestId` in the JSON is always overridden by the script with a fresh value. Key identifiers are bare Godot logical names — `ENTER`, `SPACE`, `LEFT`, `RIGHT`, `UP`, `DOWN`, `ESCAPE` — **not** `KEY_ENTER`. For InputMap actions use `{ "kind": "action", "identifier": "ui_accept", ... }`. For runs with no input, call `{{HARNESS_REPO_ROOT}}/tools/automation/invoke-scene-inspection.ps1` directly (or `/godot-inspect` in Claude Code).

### Runtime error triage

```powershell
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-runtime-error-triage.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json"
```

## Reading the envelope

Parse stdout as JSON:

| Field | Meaning |
|---|---|
| `status` | `"success"` or `"failure"` |
| `failureKind` | `null` on success; see table below on failure |
| `manifestPath` | Absolute path to `evidence-manifest.json` (success only) |
| `diagnostics` | Human-readable messages; `diagnostics[0]` is the actionable one |
| `outcome` | Workflow-specific summary (node count, dispatched events, error summary) |

On success: read `manifestPath`, then the one summary artifact the manifest references (`input-dispatch-outcomes.jsonl` for keypresses, `runtime-error-records.jsonl` for error triage).

## Failure handling

| `failureKind` | Meaning | Next step |
|---|---|---|
| `editor-not-running` | Capability artifact missing or stale | Launch: `godot --editor --path "<this-project>"` |
| `build` | GDScript compile error | Report `diagnostics[0]` verbatim; no manifest |
| `runtime` | Runtime error captured | Read `outcome.latestErrorSummary` or `outcome.firstFailureSummary` |
| `timeout` | Run did not complete | Broker only runs while game is in play mode |
| `internal` | Harness-internal error | Report `diagnostics[0]`; file a bug |

## Do not

- **Do not hand-author `run-request.json` or poll `run-result.json`.** The invoke scripts own that loop.
- **Do not manually delete files** under `harness/automation/results/` or `evidence/automation/`. Scripts clear the transient zone automatically before every run.
- **Do not read prior-run artifacts.** The transient zone is wiped before every invocation.
- **Do not read addon source** (`addons/agent_runtime_harness/`). Everything you need is in this prompt.
- **Do not vary `capturePolicy` or `stopPolicy` speculatively.** Fixture defaults are correct.
- **Do not invent new broker entrypoints.** Use the invoke scripts.

## Routing away from this prompt

- Existing manifest + diagnosis only: hand off to `godot-evidence-triage.prompt.md` instead of starting a new run.
- Pure unit / contract / schema test with no runtime behaviour: use ordinary tests.

## Output

- `status`: `success` or `failure`
- `failureKind` on failure (`editor-not-running`, `timeout`, `build`, `runtime`, `request-invalid`)
- `manifestPath` on success
- One-line summary of what happened at runtime (nodes captured, input events dispatched, scene transition observed, etc.)
