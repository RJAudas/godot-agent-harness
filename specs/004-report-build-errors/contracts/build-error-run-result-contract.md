# Contract: Build Error Reporting In The Editor Evidence Loop

## Purpose

Define how the `004-report-build-errors` feature extends the existing autonomous editor evidence loop contract when a run fails before runtime attachment because the editor reports a build, parse, or blocking resource-load problem.

## Reused Contract Surfaces

The first release reuses the existing plugin-owned file broker surfaces from `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`:

- `harness/automation/results/lifecycle-status.json`
- `harness/automation/results/run-result.json`

No separate build-error artifact is introduced for v1.

## Lifecycle Status Extension

When a build-related failure is detected before runtime attachment completes, the lifecycle status keeps the existing `failed` state and adds build-specific metadata.

### Additional lifecycle fields

- `failureKind`: `build`
- `buildDiagnosticCount`: Number of normalized diagnostics currently attributed to the run
- `buildFailurePhase`: `launching` or `awaiting_runtime`

### Expected behavior

- A build-related failure must be distinguishable from `blocked`, generic `launch`, and `attachment` failures.
- The lifecycle artifact should make it clear that runtime capture and persistence did not begin.

## Final Run Result Extension

The final run result remains the primary machine-readable outcome for the run and gains build-specific payload fields.

### Additional run-result fields

- `failureKind`: includes `build`
- `buildFailurePhase`: Phase in which the build failure was observed
- `buildDiagnostics`: Array of normalized diagnostic entries
- `rawBuildOutput`: Raw build-output lines or snippets attributed to the active run

### Build Diagnostic Entry shape

- `resourcePath`: Affected file or resource path when available
- `message`: Normalized error text
- `severity`: `error`, `warning`, or `unknown`
- `line`: Source line when available
- `column`: Source column when available
- `sourceKind`: `script`, `scene`, `resource`, or `unknown`
- `code`: Optional diagnostic identifier
- `rawExcerpt`: Raw build-output text associated with this entry

## Manifest Semantics

- `manifestPath` must remain `null` when a run fails before runtime attachment and no new evidence bundle is produced.
- `validationResult.manifestExists` must remain `false` for that build-failed run.
- Validation notes must explain that the absence of a manifest is expected for this failure mode.
- A prior successful manifest must not be reported as the evidence output for a build-failed run.

## Agent Consumption Rules

- Agents should read `run-result.json` first to determine whether the run failed during build.
- If `failureKind = build`, the agent should use `buildDiagnostics` as the structured fix surface and `rawBuildOutput` for additional context.
- Agents should not expect `evidence-manifest.json` to exist for build-failed runs.
- The plugin-owned broker may detect these failures during the editor plugin build callback or while the run is still waiting for runtime attachment, but the reporting surface remains the same lifecycle and final-result artifacts.

## Rejected V1 Alternatives

- Separate build-error result file: rejected because it splits the failed-run contract.
- Generic `launch` failure with richer notes only: rejected because it hides the distinction between code-fix and control-path problems.
- External log scraping outside the broker: rejected because it creates a second source of truth for the same run.
