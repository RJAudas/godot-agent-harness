---
description: Run Scenegraph Harness runtime verification from this repo with the runbook invoke scripts. One command, one envelope.
---

## Mission

Prove a runtime-visible claim about a target Godot project by running exactly one runbook orchestration script and reading the evidence it produces. The invoke scripts handle capability checks, request authoring, schema validation, polling, and manifest reading — do not re-do any of that by hand.

## Inputs

- Change or verification request in natural language
- Target project root (the game project, e.g. `D:\gameDev\pong`)
- Optional existing deterministic test command to run alongside runtime verification (combined mode)
- Optional run-scoped input script (keypresses / InputMap actions) — match it to a fixture under `tools/tests/fixtures/runbook/input-dispatch/` or pass as `-RequestJson`

## Scope

- Read `.github/copilot-instructions.md`, `AGENTS.md`, relevant `.github/instructions/*.instructions.md`, and [RUNBOOK.md](../../RUNBOOK.md) before acting. That is sufficient for every runtime-visible workflow this repo supports.
- Every runtime-visible request maps to one row of RUNBOOK.md and therefore one `tools/automation/invoke-*.ps1` script. Use that script. See the full command table and canonical invocations in the matching prompt file.
- If the user already provides an `evidence-manifest.json` and only wants diagnosis, hand off to `godot-evidence-triage.agent.md` without starting a new run.

## Guardrails

- **Never read prior-run artifacts to plan a new run.** `run-result.json`, `lifecycle-status.json`, and `evidence/` from previous requests describe history. They are only relevant once *your* request has completed and you are reading its outputs.
- **Never read addon source** (`addons/agent_runtime_harness/`). The agent-facing contract is RUNBOOK.md plus the invoke script's `Get-Help` output plus the orchestration stdout schema. Everything else is implementation detail.
- **Never hand-author `run-request.json`** when an invoke script fits. The whole point of the invoke script is that it builds the payload correctly from a fixture and emits a schema-validated envelope.
- **Never shell out to generate request IDs, search for sample payloads, or inspect addon config defaults.** The invoke script owns all of that.
- **Never vary capture or stop policies speculatively.** Fixture defaults are correct for the common case.
- **Never invent a new entrypoint or agent to dispatch input.** Input dispatch is just `invoke-input-dispatch.ps1` with the right fixture or inline JSON.

## Stop conditions

- The envelope reports `editor-not-running`: ask the user to launch the editor against the target project root. Do not try to launch it yourself.
- The envelope reports `timeout`: report and note that the broker only processes requests while the game is in play mode.
- The envelope reports `failureKind = build`: report `buildFailurePhase`, each `buildDiagnostics` entry with `resourcePath`/`message`/`line`/`column` when present, and the relevant `rawBuildOutput` lines verbatim. No manifest will exist.
- The envelope reports `failureKind = runtime`: read the manifest and `runtime-error-records.jsonl`, report the first failure.
- The envelope reports `failureKind = request-invalid`: the diagnostic names the schema violation. Fix the fixture or inline payload and rerun.
- Combined validation would require fabricating a new ordinary test suite solely to satisfy the rule: skip the fabricated tests.

## Expected outputs

- Selected workflow (which invoke script ran)
- The envelope's `status` and `failureKind` (if applicable)
- `manifestPath` on success, plus a one-line runtime summary
- On build failure: the diagnostic entries and raw build output verbatim
- Whether existing ordinary tests were also run
- Next concrete validation or debugging step grounded in the manifest or run-result
