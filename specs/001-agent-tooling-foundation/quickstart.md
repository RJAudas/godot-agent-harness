# Quickstart: Agent Tooling Foundation

## Goal

Validate that the first-release tooling works in VS Code Copilot Chat and Copilot CLI before optimizing for broader portability.

## 1. Orientation Validation

1. Open the repository in VS Code.
2. Start a Copilot Chat task that asks for a change touching docs or addon scaffolding.
3. Verify the agent reaches the correct guidance entry points without broad repo rediscovery.
4. Record whether it cites plugin-first constraints and the expected validation loop.

## 2. Copilot CLI Validation

1. Run a seeded Copilot CLI task against the same repository context.
2. Confirm the CLI flow uses the same durable guidance and does not depend on VS Code-only assumptions.
3. Compare the guidance selection and resulting output against the expected eval fixture.

## 3. Evidence Manifest Validation

1. Prepare a sample runtime output set from a deterministic scenario.
2. Assemble an evidence manifest that references the raw artifacts.
3. Validate the manifest against `contracts/evidence-manifest.schema.json`.
4. Confirm an agent can determine the run outcome and relevant artifacts from the manifest without reading every raw file first.

## 4. Autonomous Boundary Validation

1. Run a tooling artifact that is permitted to edit in-scope repository paths.
2. Verify it logs changed paths, validation outcomes, and stop or escalation reasons in a machine-readable record.
3. Confirm it refuses or escalates when the requested work falls outside its declared write boundary.

## Exit Criteria

- Copilot Chat and Copilot CLI both consume the planned guidance stack successfully.
- Evidence manifests validate and point cleanly to raw runtime artifacts.
- At least one autonomous artifact stays fully within its declared write boundary during seeded evals.
- Evaluation results are concrete enough to retain, narrow, or remove shipped tooling artifacts.