---
description: Use for multi-step Godot runtime flows that chain multiple harness invocations. Single-step runtime checks (inspect, press, watch) go directly to the matching `invoke-*.ps1` script or `/godot-*` slash command — not here.
---

## When to use this agent

Every single-step runtime workflow has a `/godot-*` slash command (Claude Code) or a direct `invoke-*.ps1` script (other tools): `/godot-inspect`, `/godot-press`, `/godot-debug-runtime`, `/godot-debug-build`, `/godot-watch`, `/godot-pin`, `/godot-unpin`, `/godot-pins`. Delegate to this agent ONLY when the request requires **multiple such invocations chained together** and the orchestration between them needs planning.

Examples of correct delegation:

- "Repro the crash, pin the run, compare it against the baseline from last week."
- "Sweep a batch of input fixtures against this build and summarize which ones trigger the bug."
- "Run build-error triage, apply the fix, re-run to confirm clean, then capture the scene tree."

Do NOT delegate here for:

- Single-step runtime workflows — use the matching slash command or `invoke-*.ps1` directly.
- Evidence triage on an existing manifest — use `godot-evidence-triage.agent.md`.

## Mission (for multi-step flows only)

Plan and execute a sequence of harness invocations, coordinate their evidence, and report a single consolidated outcome. Each constituent invocation still goes through an `invoke-*.ps1` script — this agent orchestrates the sequence.

## Inputs

- Multi-step request in natural language
- Target project root (the game project, e.g. `D:\gameDev\pong`)
- Optional existing deterministic test command to run alongside runtime verification (combined mode)

## Scope

- Read `.github/copilot-instructions.md`, `AGENTS.md`, relevant `.github/instructions/*.instructions.md`, and [RUNBOOK.md](../../RUNBOOK.md) before planning.
- Every individual step still maps to one row of RUNBOOK.md → one `tools/automation/invoke-*.ps1` script. Use those scripts; do not invent new entry points.
- If the user already provides an `evidence-manifest.json` and only wants diagnosis, hand off to `godot-evidence-triage.agent.md` without starting a new run.

## Guardrails

- **Never read prior-run artifacts to plan a new run.** `run-result.json`, `lifecycle-status.json`, and `evidence/` from previous requests describe history. They are only relevant once *your* request has completed and you are reading its outputs. Use `invoke-list-pinned-runs.ps1` to locate a prior run's evidence when comparing across runs.
- **Never read addon source** (`addons/agent_runtime_harness/`). The agent-facing contract is RUNBOOK.md plus the invoke script's `Get-Help` output plus the orchestration stdout schema.
- **Never hand-author `run-request.json`** when an invoke script fits.
- **Never shell out to generate request IDs, search for sample payloads, or inspect addon config defaults.** The invoke script owns all of that.
- **Never vary capture or stop policies speculatively.** Fixture defaults are correct for the common case.
- **Never invent a new entrypoint to dispatch input.** Input dispatch is `invoke-input-dispatch.ps1` with the right fixture or inline JSON.

## Stop conditions

- The envelope reports `editor-not-running`: ask the user to launch the editor against the target project root. Do not try to launch it yourself.
- The envelope reports `timeout`: report and note that the broker only processes requests while the game is in play mode.
- The envelope reports `failureKind = build`: report `buildFailurePhase`, each `buildDiagnostics` entry with `resourcePath`/`message`/`line`/`column` when present, and the relevant `rawBuildOutput` lines verbatim. No manifest will exist.
- The envelope reports `failureKind = runtime`: read the manifest and `runtime-error-records.jsonl`, report the first failure.
- The envelope reports `failureKind = request-invalid`: the diagnostic names the schema violation. Fix the fixture or inline payload and rerun.
- Combined validation would require fabricating a new ordinary test suite solely to satisfy the rule: skip the fabricated tests.

## Expected outputs

- The sequence of workflows that ran (which invoke scripts, in what order)
- For each step: `status` and (on failure) `failureKind` + `manifestPath`
- Consolidated outcome across all steps
- Whether existing ordinary tests were also run
- Next concrete action grounded in the aggregated evidence
