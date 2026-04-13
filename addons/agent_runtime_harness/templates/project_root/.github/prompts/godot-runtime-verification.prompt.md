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
2. If capability is blocked, missing, or stale, report that blocked state explicitly instead of guessing around the editor.
3. Write or inspect the brokered request under `harness/automation/requests/run-request.json`.
4. Wait for the final result under `harness/automation/results/` and confirm that the persisted bundle exists.
5. Read `evidence/scenegraph/latest/evidence-manifest.json` first, then the summary, then diagnostics or snapshot only if needed.
6. Separate gameplay failures from harness wiring or automation failures such as missing autoload setup, blocked capability, or no persisted bundle.

## Output

- Selected validation mode
- Runtime evidence result or blocked reason
- Whether ordinary tests were also required
- Next concrete validation or debugging step
