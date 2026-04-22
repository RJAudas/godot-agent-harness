---
description: Verify a runtime-visible Godot change with the Scenegraph Harness and combine existing tests when they also apply.
---

## User Input

```text
$ARGUMENTS
```

## Goal

Choose the correct validation mode for a Godot task and use the Scenegraph Harness when the request is about proving what happens in the running game.

## Routing rules

1. Use ordinary tests only for unit, contract, framework, or schema checks that do not ask about the running game.
2. Use Scenegraph Harness runtime verification for requests such as "verify at runtime," "test the running code," "make sure the node appears in game," "confirm the node exists while playing," or other runtime-visible outcomes.
3. Use combined validation when the change affects runtime-visible behavior and there is already a direct deterministic test surface. Run the existing tests plus the harness flow, but do not invent new ordinary tests solely to satisfy the combined rule.
4. If the user already provides `evidence/scenegraph/latest/evidence-manifest.json` and only wants diagnosis, hand the task to `godot-evidence-triage.prompt.md`.

## Runtime verification workflow

1. Read `harness/automation/results/capability.json` first to confirm whether the open project can accept a brokered evidence request.
<!-- runbook:do-not-read-addon-source -->
2. Do **not** read addon source files (`addons/agent_runtime_harness/`) to understand the harness protocol. All agent-facing contracts are in `specs/` and `docs/` in the harness repository.
<!-- /runbook:do-not-read-addon-source -->
3. If capability is blocked, missing, or stale, report that blocked state explicitly instead of guessing around the editor.
4. Write or inspect the brokered request under `harness/automation/requests/run-request.json`.
5. Wait for the final result under `harness/automation/results/`. If it reports `failureKind = build`, stop there, do not expect a manifest, and read `details`, `buildFailurePhase`, `buildDiagnostics`, and `rawBuildOutput`.
6. For build-failed runs, report each diagnostic with `resourcePath`, `message`, and `line`/`column` when available, and include the relevant raw build-output lines verbatim instead of paraphrasing them away.
7. If the run completed with a manifest, read `evidence/scenegraph/latest/evidence-manifest.json` first, then the summary, then diagnostics or snapshot only if needed.
8. Separate gameplay failures from harness wiring or automation failures such as missing autoload setup, blocked capability, no persisted bundle, or build-failed runs that ended before runtime capture.

## Output

- Selected validation mode
- Runtime evidence result or blocked reason, or the build-failure result with its diagnostic details and raw output
- Whether ordinary tests were also required
- Next concrete validation or debugging step
