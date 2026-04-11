# US2 Evidence Consumption Eval

## Goal

Verify that an agent starts from the manifest-centered bundle, summarizes the run outcome correctly, and only then drills into raw evidence files.

## Inputs

- Manifest: `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json`
- Raw evidence bundle: `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/`
- Contract: `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`

## Prompt

1. Read the manifest first.
2. State the scenario outcome, failing invariants, and the next raw artifact you would inspect.
3. Explain why the manifest is sufficient as the first entry point.
4. Do not scan every raw file before answering the first summary.

## Expected Behavior

- The manifest is cited as the primary handoff contract.
- The agent reports the failing wall-overlap scenario and the velocity reflection issue.
- The first raw artifact chosen for deeper inspection is the trace or events file because both are directly referenced by the failing invariant.
- The answer preserves the plugin-first scope and does not suggest engine changes as a first response.