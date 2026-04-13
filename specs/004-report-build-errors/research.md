# Research: Report Build Errors On Run

## Decision 1: Reuse the existing broker artifacts as the only first-release reporting surface

- **Decision**: Extend the existing lifecycle status and final run-result artifacts instead of creating a separate build-error artifact.
- **Rationale**: `docs/AGENT_TOOLING_FOUNDATION.md` and `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md` already define the plugin-owned file broker as the workspace-visible control path for autonomous runs. Keeping build-error reporting inside those same artifacts preserves a single source of truth for the agent and matches the repository’s preference for deterministic local workflows from `docs/AI_TOOLING_AUTOMATION_MATRIX.md`.
- **Alternatives considered**:
  - Separate build-error JSON artifact: rejected because it would split one failed run across multiple primary result files.
  - External helper-only output capture: rejected because it would create a parallel path outside the plugin-owned evidence loop.

## Decision 2: Introduce an explicit build failure classification rather than overloading launch failure

- **Decision**: Treat editor-reported build, parse, and blocking resource-load failures as a distinct automation failure mode.
- **Rationale**: `specs/004-report-build-errors/spec.md` requires build failures to be distinguishable from blocked prerequisites, generic launch failures, and runtime attachment problems. The current `automation-run-result.schema.json` from `specs/003-editor-evidence-loop/contracts/` does not include a build-specific failure kind, so the plan needs a contract extension rather than a text-only note.
- **Alternatives considered**:
  - Reuse `launch` for build-failed runs: rejected because agents could not reliably tell whether they should fix code or inspect launch control.
  - Reuse `attachment` for failures before runtime exists: rejected because it would misclassify failures that occur before the harness can attach.

## Decision 3: Carry both normalized diagnostics and raw build output

- **Decision**: Include normalized diagnostic entries plus the raw editor-reported build-output snippet for the current run.
- **Rationale**: The clarified spec requires both formats. Normalized fields give the agent structured access to resource path, message, severity, and optional location data, while the raw snippet preserves the editor’s original wording when metadata is incomplete.
- **Alternatives considered**:
  - Normalized diagnostics only: rejected because partial editor metadata would lose useful original context.
  - Raw output only: rejected because agents would need to re-parse build output for every retry loop.

## Decision 4: Treat manifest absence as an explicit part of the build-failed result

- **Decision**: A build-failed run should report `manifestPath` as absent and clearly state that no new evidence bundle was produced.
- **Rationale**: `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md` already requires evidence to be traceable to the current `runId`, and the current run coordinator keeps manifest validation as the success gate. For build-failed runs, preserving manifest absence is safer than trying to clean or reinterpret a previous evidence directory.
- **Alternatives considered**:
  - Reuse the most recent manifest if it still exists: rejected because it would violate run attribution and stale-artifact safety.
  - Always delete prior evidence before launch: rejected because it adds destructive behavior that is not required to satisfy the spec.

## Decision 5: Validate the feature with seeded broken-project cases plus contract checks

- **Decision**: Use deterministic example-project failure fixtures together with schema validation and existing regression surfaces.
- **Rationale**: The constitution requires test-backed agent loops and machine-readable evidence. For this feature, the relevant proof is a seeded compile, parse, or resource-load failure that results in deterministic run-result artifacts, plus validation that successful runs still preserve the current manifest-centered path.
- **Alternatives considered**:
  - Manual editor checks only: rejected because they do not provide repeatable proof for agents.
  - Tool-only schema validation without runtime failure fixtures: rejected because it would not prove the broker can attribute real build failures correctly.