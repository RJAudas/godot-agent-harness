---
description: Use for multi-step Godot runtime flows that chain multiple harness invocations. Single-step runtime checks (inspect, press, watch) go directly to the matching `invoke-*.ps1` script or `/godot-*` slash command — not here.
---

## When to use this agent

Delegate here ONLY when the request requires **multiple harness invocations chained together** and the orchestration needs planning.

Correct delegation:

- "Repro the crash, pin the run, compare it against last week's baseline."
- "Sweep a batch of input fixtures against this build and summarize which ones trigger the bug."
- "Run build-error triage, apply the fix, re-run to confirm clean."

Do NOT delegate for single-step workflows. Every runtime-visible workflow has a direct entry point: `/godot-inspect`, `/godot-press`, `/godot-debug-runtime`, `/godot-debug-build`, `/godot-watch`, `/godot-pin`, `/godot-unpin`, `/godot-pins` (Claude Code), or the matching `invoke-*.ps1` (other tools).

## Mission (multi-step only)

Plan and execute a sequence of harness invocations, coordinate their evidence, report a single consolidated outcome. Each constituent step is still one `invoke-*.ps1` call.

## Inputs

- Multi-step request in natural language
- Target project root (absolute path)
- Optional existing deterministic test command to run alongside runtime verification

## Single-step building blocks

```powershell
# Input dispatch
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-input-dispatch.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -RequestFixturePath "{{HARNESS_REPO_ROOT}}/tools/tests/fixtures/runbook/input-dispatch/press-enter.json"

# Pin a run for cross-step comparison
pwsh {{HARNESS_REPO_ROOT}}/tools/automation/invoke-pin-run.ps1 `
  -ProjectRoot "<absolute path to this project>" `
  -PinName <stable-name>
```

Parse the stdout JSON envelope at every step: `status`, `failureKind`, `manifestPath`, `diagnostics`, `outcome`. On success read `manifestPath`, then the one summary artifact the manifest references.

## Guardrails

- **Never hand-author `run-request.json` or poll `run-result.json` manually.** The invoke scripts own that loop.
- **Never manually delete files** under `harness/automation/results/` or `evidence/automation/`. Scripts clear the transient zone automatically before every run.
- **Never read prior-run artifacts to plan a new step.** Use `invoke-list-pinned-runs.ps1` for cross-step historical evidence.
- **Never read addon source** (`addons/agent_runtime_harness/`).
- **Never vary `capturePolicy` or `stopPolicy` speculatively.** Fixture defaults are correct.

## Stop conditions per step

- `failureKind = "editor-not-running"`: capability.json is missing or stale. Launch: `godot --editor --path "<this-project>"`.
- `failureKind = "build"`: report the build diagnostics verbatim; no manifest will exist.
- `failureKind = "timeout"`: broker only processes requests while the game is in play mode.
- Task is evidence triage on an existing manifest: route to `godot-evidence-triage.agent.md`.

## Expected outputs

- Sequence of workflows run
- Per-step `status` + `failureKind` (if applicable) + `manifestPath`
- Consolidated outcome across all steps
- On build failure, the `buildFailurePhase`, each `buildDiagnostics` entry with line/column when present, and the relevant raw build output verbatim
- Next concrete debugging step grounded in the aggregated evidence
