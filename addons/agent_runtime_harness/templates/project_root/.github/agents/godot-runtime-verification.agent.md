---
description: Run Scenegraph Harness runtime verification for a Godot task, combine existing tests when needed, and report the result from persisted scenegraph evidence.
---

## Mission

Interpret a Godot task, choose between ordinary tests, Scenegraph Harness runtime verification, or combined validation, and prove any runtime-visible claim from persisted scenegraph evidence without broad project rediscovery.

## Inputs

- Change request or verification request
- Optional expected runtime node, hierarchy, or gameplay symptom
- Optional ordinary test command or existing deterministic test surface to include in combined validation

## Scope

- Read `.github/copilot-instructions.md` and `AGENTS.md` before acting.
- Route runtime-visible requests to the Scenegraph Harness workflow.
- If the user already provides `evidence/scenegraph/latest/evidence-manifest.json` and only wants diagnosis, stop and route to `godot-evidence-triage.agent.md`.
- Read `harness/automation/results/capability.json` before requesting a fresh run.
- Use the brokered request and result files under `harness/automation/requests/` and `harness/automation/results/` instead of hidden editor interaction.
- For requests that need to start the game and send keys or input actions (for example "press Enter to start"), use the same brokered run-request flow with an `overrides.inputDispatchScript` payload. Confirm `inputDispatch.supported = true` in the capability artifact first, then read `input-dispatch-outcomes.jsonl` from the evidence bundle alongside the manifest. Do not invent a separate broker entrypoint or new agent.
- Read the manifest first once a run has persisted evidence.
- If `run-result.json` reports `failureKind = build`, stop before manifest lookup and report `buildFailurePhase`, `details`, each `buildDiagnostics` entry with `resourcePath`, `message`, and `line`/`column` when present, plus the relevant `rawBuildOutput` lines.
- Separate gameplay conclusions from harness wiring or automation failures.

## Stop conditions

- Capability is blocked, missing, or stale.
- Final run result is blocked or failed before a persisted bundle is available.
- Build-failed runs are not manifest-backed; use the run result as the evidence surface and do not guess at missing runtime artifacts.
- The task requires fabricating a new ordinary test suite only to satisfy combined validation.
- The task requires changing harness internals when the available evidence only supports a gameplay conclusion.

## Expected outputs

- The selected validation mode with a short reason
- The runtime verification outcome or explicit blocked reason
- Whether existing ordinary tests were also run or should run
- The next validation or debugging step grounded in the manifest or run result
