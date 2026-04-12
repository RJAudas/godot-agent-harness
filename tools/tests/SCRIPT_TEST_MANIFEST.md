# Script Test Manifest

This manifest records how each PowerShell script under `tools/` is exercised by the automated test suite.

## tools/validate-json.ps1

- Purpose: validate repo-local or absolute JSON files against a JSON schema and return a machine-readable result.
- Primary fixtures: `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json`, `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json`, `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`.
- Success cases: valid relative paths, valid absolute paths, `-PassThru` object output.
- Failure cases: schema-invalid fixture without `-AllowInvalid`, malformed JSON with `-AllowInvalid`.
- Assertions: correct `valid` flag, non-zero exit semantics on failure, surfaced error text.

## tools/evidence/new-evidence-manifest.ps1

- Purpose: generate an evidence manifest from a runtime artifact directory.
- Primary fixtures: `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/summary.json`, `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/invariants.json`, other files under `runtime-sample/`.
- Success cases: seeded default generation, explicit `ScenarioId`/`RunId`/`Status` overrides, nested output path creation, reduced artifact count when optional inputs are removed.
- Failure cases: missing `summary.json`, invalid `Status` argument.
- Assertions: manifest fields copied from summary, invariant propagation, artifact count, output path creation, validation notes remain `bundleValid = false` until validator runs.

## tools/evidence/validate-evidence-manifest.ps1

- Purpose: validate a manifest against schema and confirm referenced artifacts exist within the repo boundary.
- Primary fixtures: `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json`, `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json`.
- Success cases: canonical valid manifest.
- Failure cases: schema-invalid manifest, missing artifact paths, artifact paths resolving outside the repository root.
- Assertions: `schemaValid`, `bundleValid`, `missingArtifactPaths`, and non-zero exit semantics for invalid bundles.

## tools/automation/validate-write-boundary.ps1

- Purpose: confirm autonomous write requests stay inside the declared boundary contract.
- Primary fixtures: `tools/automation/write-boundaries.json`, `tools/automation/write-boundaries.schema.json`.
- Success cases: allowed relative path, allowed absolute path.
- Failure cases: out-of-bound path with and without `-AllowViolation`, unknown `ArtifactId`, mismatched `RequestedPath`/`RequestedEditType` counts, absolute path outside the repo.
- Assertions: `requestAllowed`, violation details, path normalization, and non-zero exit semantics when violations are not allowed.

## tools/automation/new-autonomous-run-record.ps1

- Purpose: emit a schema-valid autonomous run record and self-validate it.
- Primary fixtures: `tools/automation/autonomous-run-record.schema.json`.
- Success cases: minimal record generation, nested output path creation, default operation and validation field values.
- Failure cases: mismatched `OperationEditType`, `OperationStatus`, `OperationNote`, `ValidationStatus`, and `ValidationDetails` counts.
- Assertions: output record shape, generated defaults, schema-valid JSON emission, and terminating errors for inconsistent parameter arrays.