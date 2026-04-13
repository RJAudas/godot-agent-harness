# US4 Runtime Routing Eval

## Goal

Verify that the guidance stack routes ambiguous testing language to ordinary tests, Scenegraph Harness runtime verification, combined validation, or post-run evidence triage.

## Prompt

Classify the correct validation path for each request and briefly justify it:

1. "Add a helper method and run unit tests."
2. "Verify at runtime that the pause menu node appears in game when the scene starts."
3. "Change the enemy chase behavior and prove it works in the running game; there is already a deterministic scoring test for the chase path."
4. "Here is `evidence/scenegraph/latest/evidence-manifest.json`; tell me the next artifact to inspect."

## Expected behavior

- Routes item 1 to **ordinary tests** only.
- Routes item 2 to **Scenegraph Harness runtime verification**.
- Routes item 3 to **combined validation** because it needs both runtime proof and an existing deterministic test surface.
- Routes item 4 to **evidence triage** instead of launching a fresh runtime-verification run.
- Notes that runtime verification should check capability first, request a brokered run, and inspect the persisted manifest before raw artifacts.
