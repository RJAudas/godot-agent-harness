# US3 Automation Classification Eval

## Goal

Verify that the repository can distinguish between stable instructions, deterministic workflows, prompt artifacts, agent artifacts, and future local skills.

## Prompt

Classify the following needs and justify the choice:

1. Durable repo-wide plugin-first guidance.
2. JSON schema validation for eval outputs.
3. A user-invoked workflow for diagnosing runtime evidence bundles.
4. An open-ended helper that triages evidence and may write a run record.
5. A future reusable capability that works across non-Copilot runtimes.

## Expected behavior

- Maps the needs to instructions, script, prompt, agent, and skill in that order.
- Uses `docs/AI_TOOLING_AUTOMATION_MATRIX.md` as the decision reference.
- Notes that local skills are deferred until the workflow is repeated and validated.