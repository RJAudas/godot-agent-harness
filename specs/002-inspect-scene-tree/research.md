# Research: Inspect Scene Tree

## Decision 1: Use a dock-first editor plugin with debugger-backed transport

- **Decision**: Make an `EditorPlugin` dock the primary operator surface for starting captures, inspecting the latest snapshot summary, and reviewing diagnostics, while using `EditorDebuggerPlugin` and `EditorDebuggerSession` mainly as the transport layer between the editor and the running game.
- **Rationale**: A dock is the lowest-complexity editor surface that still gives agents and maintainers a stable place to trigger captures and review results. It avoids the extra complexity of building a full custom debugger tab before the core transport and persistence loop is proven.
- **Alternatives considered**: A debugger-tab-first UI was rejected for the first release because it adds integration complexity without improving the core persisted evidence contract. A pure file-only workflow was rejected because the feature explicitly needs useful live scenegraph visibility during editor play sessions.

## Decision 2: Keep runtime instrumentation to a single autoload-backed collector

- **Decision**: Add one minimal runtime collector that can enumerate the live scene tree, serialize the clarified core inspection set, evaluate hybrid expectations, and respond to start, manual, and failure-triggered capture requests.
- **Rationale**: This matches the plugin-first constitution and gives the editor enough structured data without introducing broad runtime tracing or a parallel instrumentation framework. It also creates the cleanest later migration path to a runtime-only harness.
- **Alternatives considered**: Per-node instrumentation helpers were rejected as unnecessary for the first release. Engine-level hooks were rejected because addon and debugger layers are sufficient for scenegraph inspection.

## Decision 3: Reuse the manifest-centered evidence bundle instead of inventing a live-only contract

- **Decision**: Persist scenegraph snapshots and diagnostics as artifact references within the existing evidence-manifest shape and add scene-inspection-specific kinds rather than creating a separate inspection bundle format.
- **Rationale**: Agents already have one stable bundle entry point in this repository. Reusing that pattern reduces cognitive load and makes post-run inspection work the same way as other runtime evidence consumption flows.
- **Alternatives considered**: A separate scene-inspection manifest was rejected because it would duplicate summary and artifact-link logic. Embedding all scenegraph data directly into the manifest was rejected because snapshots can grow large and should stay as referenced artifacts.

## Decision 4: Use hybrid expectation matching as the default diagnostic model

- **Decision**: Model scenario expectations so they can match nodes by exact path when stable and by selector-based identity when dynamic runtime instancing makes paths unreliable.
- **Rationale**: This preserves determinism for static scenes while avoiding brittle failures in cases where nodes are created or attached dynamically. It is also the cleanest way to keep the diagnostic model reusable in a future runtime-only harness.
- **Alternatives considered**: Exact-path-only matching was rejected as too fragile for dynamic scene trees. Selector-only matching was rejected because it weakens deterministic checks where stable paths are known.

## Decision 5: Validate the feature through deterministic example-project runs before optimizing portability

- **Decision**: Use `examples/pong-testbed/` as the first validation target and plan at least one healthy scenegraph capture case plus one deliberately broken expectation case that proves missing-node or hierarchy-mismatch diagnostics.
- **Rationale**: The constitution requires test-backed agent loops. A deterministic example project gives a concrete proof path for live capture, persisted artifacts, and post-run agent consumption.
- **Alternatives considered**: Planning only abstract contract tests was rejected because the feature is about editor-run behavior. Prioritizing packaged executable support was rejected because it expands transport and launch concerns before the editor-first loop is proven.

## Decision 6: Defer packaged executable support but keep contract fields runtime-neutral

- **Decision**: Treat standalone packaged builds as explicitly out of scope for the first release while naming capture triggers, session metadata, and artifact payloads so they do not depend on editor-only semantics.
- **Rationale**: This preserves a low-complexity first implementation and keeps open a low-cost compatibility path for a later runtime-only harness.
- **Alternatives considered**: Designing separate editor and packaged contracts now was rejected because it adds premature abstraction. Treating the editor session as the only possible producer was rejected because it would make later reuse unnecessarily expensive.

## Implementation Notes

- Added repo-local scenegraph snapshot and diagnostics schemas under `specs/002-inspect-scene-tree/contracts/` and validated them with `tools/validate-json.ps1`.
- Added deterministic example fixtures under `examples/pong-testbed/` for healthy, missing-node, and hierarchy-mismatch cases, plus a persisted manifest fixture that validates through `tools/evidence/validate-evidence-manifest.ps1`.
- Extended `tools/evidence/new-evidence-manifest.ps1` and `tools/evidence/validate-evidence-manifest.ps1` so the existing manifest-centered flow explicitly recognizes `scenegraph-snapshot`, `scenegraph-diagnostics`, and `scenegraph-summary` artifact kinds.
- Reviewed the seeded `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/scene-snapshot.json` contract and kept it unchanged because the new scenegraph artifacts extend the manifest bundle without changing the existing sample snapshot shape.
- Local validation covered all PowerShell tests and machine-readable fixtures. End-to-end editor execution from the Godot runtime remains pending because no Godot executable was available in the current environment.