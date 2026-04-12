# Fixture Layout

This directory holds deterministic inputs for the Agent Tooling Foundation feature.

## Runtime Sample Bundle

Store the seeded runtime evidence under `runtime-sample/` with these portable files:

- `summary.json`: normalized scenario outcome and key findings
- `invariants.json`: invariant results with messages and any artifact references
- `trace.jsonl`: line-delimited per-frame trace events
- `events.json`: structured gameplay or harness events
- `scene-snapshot.json`: scene tree or node snapshot for the relevant window

## Eval Prompt Files

Feature prompt fixtures live in `tools/evals/001-agent-tooling-foundation/` and reference this fixture directory when they need runtime evidence or expected JSON outputs.

## Expected Outputs

- `evidence-manifest.valid.json` is the canonical valid manifest fixture.
- `evidence-manifest.invalid.json` exercises schema rejection and missing required fields.
- Story-level expected outputs stay next to their eval prompts unless they are reused by multiple stories.

## Validation

Validate each JSON fixture with `tools/validate-json.ps1` and the appropriate schema before relying on it in quickstart or regression work.