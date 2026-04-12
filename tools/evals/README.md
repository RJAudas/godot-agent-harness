# Evaluation Assets

Use `tools/evals/` for seeded evaluation prompts, expected outputs, and machine-readable results that measure whether repository tooling improves agent behavior.

## Naming

- Feature-specific eval prompts live under `tools/evals/<feature-id>/`.
- Reusable fixture inputs live under `tools/evals/fixtures/<feature-id>/`.
- Expected JSON outputs use `<story>-<purpose>.expected.json`.
- Recorded run results use `<story>-<purpose>-results.json` when multiple outputs exist, or `<story>-<purpose>.json` when one file is sufficient.

## Coverage

- Add at least one fixture for VS Code Copilot Chat and one fixture for Copilot CLI when the story changes durable guidance or workflows.
- Keep each fixture deterministic: name the entry files, required inputs, and the expected machine-readable output.
- When a story depends on runtime evidence, store a portable sample bundle under `tools/evals/fixtures/<feature-id>/` instead of depending on ad hoc scenario output.

## Result Locations

- Store story-specific result files beside the feature prompts in `tools/evals/001-agent-tooling-foundation/`.
- Store raw evidence fixtures, sample manifests, and expected-output references under `tools/evals/fixtures/001-agent-tooling-foundation/`.
- Use `tools/automation/` only for autonomous boundary contracts and run logs, not as a general eval output location.

## Validation Rule

Every JSON result or fixture added here should validate against a repository schema by using `tools/validate-json.ps1` before the task is considered complete.