# Quickstart: Agent Tooling Foundation

## Goal

Validate that the first-release tooling works in VS Code Copilot Chat and Copilot CLI before optimizing for broader portability.

## 1. Orientation Validation

1. Open the repository in VS Code.
2. Use the seeded prompts at `tools/evals/001-agent-tooling-foundation/us1-copilot-chat-orientation.md` and `tools/evals/001-agent-tooling-foundation/us1-copilot-cli-orientation.md` for the Chat and CLI flows.
3. Compare the agent behavior against `tools/evals/001-agent-tooling-foundation/us1-guidance-selection.expected.json`.
4. Record the machine-readable result in `tools/evals/001-agent-tooling-foundation/us1-orientation-results.json`.
5. Validate the recorded result with `pwsh ./tools/validate-json.ps1 -InputPath 'tools/evals/001-agent-tooling-foundation/us1-orientation-results.json' -SchemaPath 'tools/evals/agent-eval-result.schema.json'`.

## 2. Copilot CLI Validation

1. Run the seeded Copilot CLI task from `tools/evals/001-agent-tooling-foundation/us1-copilot-cli-orientation.md` against the same repository context.
2. Confirm the CLI flow uses the same durable guidance and does not depend on VS Code-only assumptions.
3. Compare the guidance selection and resulting output against `tools/evals/001-agent-tooling-foundation/us1-guidance-selection.expected.json`.

## 3. Evidence Manifest Validation

1. Start with the seeded runtime artifact set under `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/`.
2. Assemble or review the manifest at `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json`.
3. Generate a sample manifest with `pwsh ./tools/evidence/new-evidence-manifest.ps1`.
4. Validate the valid manifest with `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json'`.
5. Confirm the invalid fixture is rejected with `pwsh ./tools/validate-json.ps1 -InputPath 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json' -SchemaPath 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json' -AllowInvalid`.
6. Record the flow in `tools/evals/001-agent-tooling-foundation/us2-bundle-results.json` and validate it with `pwsh ./tools/validate-json.ps1 -InputPath 'tools/evals/001-agent-tooling-foundation/us2-bundle-results.json' -SchemaPath 'tools/evals/agent-eval-result.schema.json'`.
7. Confirm an agent can determine the run outcome and relevant artifacts from the manifest before reading the raw files referenced in the bundle.

## 4. Autonomous Boundary Validation

1. Use `tools/automation/write-boundaries.json` as the declared boundary contract and `tools/automation/validate-write-boundary.ps1` as the enforcement check.
2. Validate an allowed request with `pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId 'godot-evidence-triage.agent' -RequestedPath 'tools/evals/001-agent-tooling-foundation/us3-validation-results.json' -RequestedEditType 'update'`.
3. Inspect a rejected request with `pwsh ./tools/automation/validate-write-boundary.ps1 -ArtifactId 'godot-evidence-triage.agent' -RequestedPath 'addons/agent_runtime_harness/plugin.gd' -RequestedEditType 'update' -AllowViolation`.
4. Emit the machine-readable run log with `pwsh ./tools/automation/new-autonomous-run-record.ps1 -ArtifactId 'godot-evidence-triage.agent' -WriteBoundaryId 'godot-evidence-triage-first-release' -RequestSummary 'Validate in-scope eval result output for manifest-centered evidence triage.' -OperationPath 'tools/evals/001-agent-tooling-foundation/us3-validation-results.json' -OperationEditType 'update' -OperationStatus 'performed' -OperationNote 'Eval result file updated inside the declared boundary.' -ValidationName 'write-boundary-check' -ValidationStatus 'pass' -ValidationDetails 'Requested eval result path is allowed by the boundary contract.' -OutputPath 'tools/automation/run-records/godot-evidence-triage-validation.json'`.
5. Record the validation result in `tools/evals/001-agent-tooling-foundation/us3-validation-results.json` and validate it with `pwsh ./tools/validate-json.ps1 -InputPath 'tools/evals/001-agent-tooling-foundation/us3-validation-results.json' -SchemaPath 'tools/evals/agent-eval-result.schema.json'`.

## 5. Final Validation

1. Confirm the story result files exist in `tools/evals/001-agent-tooling-foundation/`.
2. Validate `tools/evals/001-agent-tooling-foundation/final-validation-results.json` with `pwsh ./tools/validate-json.ps1 -InputPath 'tools/evals/001-agent-tooling-foundation/final-validation-results.json' -SchemaPath 'tools/evals/agent-eval-result.schema.json'`.

## Exit Criteria

- Copilot Chat and Copilot CLI both consume the planned guidance stack successfully.
- Evidence manifests validate and point cleanly to raw runtime artifacts.
- At least one autonomous artifact stays fully within its declared write boundary during seeded evals.
- Evaluation results are concrete enough to retain, narrow, or remove shipped tooling artifacts.