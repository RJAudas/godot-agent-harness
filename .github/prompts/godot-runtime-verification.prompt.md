---
description: Verify a Godot runtime-visible change with the Scenegraph Harness, combine existing tests when needed, and prove the outcome from persisted evidence.
---

## User Input

```text
$ARGUMENTS
```

## Goal

Choose the correct validation mode for a Godot change, perform Scenegraph Harness runtime verification when the request is about running-game behavior, and keep ordinary tests in scope when the change also has an existing deterministic test surface.

## Routing rules

1. Use ordinary tests only for unit, contract, framework, or schema checks that do not ask about the running game.
2. Use Scenegraph Harness runtime verification for requests such as "verify at runtime," "test the running code," "make sure the node appears in game," "confirm the node exists while playing," or other runtime-visible outcomes.
3. Use combined validation when the change affects runtime-visible behavior and there is already a direct deterministic test surface. Run the existing tests plus the runtime harness flow, but do not invent new ordinary tests solely to satisfy the combined rule.
4. If the user already provides an evidence manifest and only wants diagnosis, hand the task to `godot-evidence-triage.prompt.md` instead of starting a fresh run.

## Runtime verification workflow

1. Read `RUNBOOK.md` first to identify the correct `invoke-*.ps1` script, fixture template, and recipe doc for the requested workflow.
<!-- runbook:do-not-read-addon-source -->
2. Do **not** read addon source files (`addons/agent_runtime_harness/`) to understand the harness protocol. All agent-facing contracts are in `RUNBOOK.md`, `docs/runbook/`, `specs/008-agent-runbook/contracts/`, and the existing `specs/` and `tools/` trees.
<!-- /runbook:do-not-read-addon-source -->
3. Confirm harness availability and read the latest capability artifact first. From this repository checkout, use the matching invoke script: `pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot <game-root>`, or `invoke-input-dispatch.ps1`, etc. The script checks capability internally and returns a JSON stdout envelope.
4. If capability is blocked, missing, or schema-invalid, report that blocked state explicitly instead of guessing around the editor.
5. Submit a brokered run request through the invoke script. Parse the JSON stdout envelope (conforming to `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`) for `status`, `manifestPath`, and `diagnostics`.
6. Wait for the final run result. If it reports `failureKind = build`, stop there, do not expect a manifest, and read `details`, `buildFailurePhase`, `buildDiagnostics`, and `rawBuildOutput`.
7. For build-failed runs, report each diagnostic with `resourcePath`, `message`, and `line`/`column` when available, and include the relevant raw build-output lines verbatim instead of paraphrasing them away.
8. If the run completed with a manifest, read the evidence manifest first, then the summary, then diagnostics or snapshot only if needed.
9. Separate gameplay failures from harness wiring or automation failures such as missing autoload setup, blocked capability, no persisted bundle, or build-failed runs that ended before runtime capture.

## Output

- Selected validation mode
- Runtime evidence result or blocked reason, or the build-failure result with its diagnostic details and raw output
- Whether ordinary tests were also required
- Next concrete validation or debugging step
