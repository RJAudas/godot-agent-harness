# Research: Behavior Watch Sampling

## Decision 1: Reuse the existing automation run request and debugger-backed session configuration

- **Decision**: Carry the v1 behavior watch request through the current automation run request as a run-scoped override and deliver it through the existing `configure_session` debugger message.
- **Rationale**: `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` already provides a stable run-scoped override surface, and `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd` plus `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` already exchange session context dictionaries over the debugger bridge. Extending that path keeps the watch request aligned with the current run identity and avoids creating a second control surface.
- **Alternatives considered**:
  - Separate behavior-capture broker or request file: rejected because it would split the autonomous run contract.
  - Standalone debugger command for watch setup: rejected because it separates normalization from the existing run-scoped session configuration.

## Decision 2: Normalize the watch request into an applied-watch summary before sampling starts

- **Decision**: Validate and normalize the watch request before sampling begins, producing an applied-watch summary with explicit defaults for cadence, start-frame offset, bounded frame count, and fixed output semantics.
- **Rationale**: The clarified spec requires invalid selectors, unsupported later-slice fields, and zero-sample windows to fail before capture. Normalizing once per run creates the machine-readable applied-watch summary the agent must be able to inspect and avoids hidden runtime defaults.
- **Alternatives considered**:
  - Editor-only normalization: rejected because runtime surfaces still need the normalized contract and would duplicate validation logic.
  - Partial acceptance of mixed valid and invalid fields: rejected because the spec requires the full request to fail decisively instead of changing the debugging question.

## Decision 3: Persist a fixed `trace.jsonl` in the current run's evidence bundle and reference it from the same manifest

- **Decision**: Write a fixed `trace.jsonl` file inside the current run's output directory and add a `trace` artifact reference to the same manifest-centered evidence bundle already used for runtime artifacts.
- **Rationale**: `tools/evidence/artifact-registry.ps1` already registers `trace` with `trace.jsonl`, and the existing runtime sample fixture under `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/trace.jsonl` shows the flat JSONL row shape the repo already expects. Reusing the current manifest path keeps the agent on one manifest-first workflow.
- **Alternatives considered**:
  - Separate behavior-only manifest or evidence directory: rejected because it would create a second post-run evidence path for the agent.
  - Configurable `trace.json` versus `trace.jsonl`: rejected because the clarified spec fixes the artifact contract to `trace.jsonl`.

## Decision 4: Keep the trace row format flat and agent-readable

- **Decision**: Plan around flat JSONL rows with `frame`, `timestampMs`, `nodePath`, and the watched fields at the top level rather than nesting sampled properties under opaque blobs.
- **Rationale**: The existing runtime sample trace fixture already uses this shape, and the spec explicitly prefers explicit fields over opaque blobs. Flat rows are easier for agents to inspect and for schemas or validators to reason about.
- **Alternatives considered**:
  - Nested `sampledProperties` objects: rejected because they add one more layer of indirection without helping bounded single-target diagnosis.
  - Full-scene frame snapshots filtered post-run: rejected because they violate the low-overhead bounded-watch goal.

## Decision 5: Validate the feature with contract fixtures plus deterministic Pong automation runs

- **Decision**: Use a two-layer validation path: fixture-driven request validation without a playtest for slice 1, then deterministic Pong automation runs through the existing editor-evidence loop for slice 2.
- **Rationale**: This preserves the constitution's test-backed loop while keeping validation aligned to the two feature slices. Valid and invalid watch-request fixtures prove normalization and rejection behavior, while deterministic Pong runs prove bounded sampling, manifest integration, and stale-artifact safety.
- **Alternatives considered**:
  - Manual editor checks only: rejected because they do not produce repeatable agent-readable proof.
  - Schema-only validation without runtime runs: rejected because it would not prove the sampler or manifest flow.

## Decision 6: Use run-scoped output directories and manifest validation to prevent stale trace reuse

- **Decision**: Treat run-scoped output directories and manifest validation as the primary stale-artifact safety mechanism for v1.
- **Rationale**: The existing automation request flow already uses per-run `outputDirectory` and `artifactRoot` values. Keeping `trace.jsonl` in that run-scoped output and validating the manifest against the current run keeps stale traces from satisfying a new request accidentally.
- **Alternatives considered**:
  - Reusing a shared `latest` trace file across runs: rejected because it risks misattributing stale output to the current run.
  - Destructive global cleanup before every run: rejected because run-scoped output directories already provide safer provenance.

## Implementation Notes

- The current automation request should remain the entrypoint; the new watch contract becomes an additive extension rather than a new command surface.
- `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` already owns session configuration and persistence handoff, making it the natural place to initialize and expose normalized watch state.
- `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd` already builds artifact references into `evidence-manifest.json`, so the trace artifact should be added there rather than through a second manifest writer for v1.
- The existing Pong testbed already provides stable `/root/Main/Ball` identity and run-request fixtures that make deterministic bounded sampling validation practical.

## Validation Notes

- `pwsh ./tools/tests/run-tool-tests.ps1` passed after the behavior-watch request schema, request helper, fixtures, manifests, and PowerShell regression coverage were updated.
- `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-frame/evidence-manifest.json` passed for the seeded behavior-watch bundle.
- `pwsh ./tools/automation/request-editor-evidence-run.ps1 -ProjectRoot examples/pong-testbed -RequestFixturePath examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-frame.json -PassThru` wrote a schema-valid broker request artifact for the example project.
- `pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot examples/pong-testbed` reported that no live `harness/automation/results/capability.json` artifact was present from this checkout, so full runtime verification stayed blocked until an editor session publishes capability and run-result artifacts.
