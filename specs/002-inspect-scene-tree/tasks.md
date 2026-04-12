# Tasks: Inspect Scene Tree

**Input**: Design documents from `/specs/002-inspect-scene-tree/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Every user story includes executable validation tasks using deterministic example-project runs plus PowerShell validation for snapshot, diagnostic, and manifest artifacts.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently once the shared capture infrastructure is in place.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story the task belongs to (`US1`, `US2`, `US3`)
- All tasks include exact repository paths in the description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the addon, example-project, and test scaffolding that every story depends on.

- [X] T001 Create the addon implementation layout under `addons/agent_runtime_harness/plugin.cfg`, `addons/agent_runtime_harness/plugin.gd`, `addons/agent_runtime_harness/editor/`, `addons/agent_runtime_harness/runtime/`, and `addons/agent_runtime_harness/shared/`
- [X] T002 [P] Create deterministic example-project directories under `examples/pong-testbed/scenes/`, `examples/pong-testbed/harness/expectations/`, and `examples/pong-testbed/evidence/`
- [X] T003 [P] Add feature test coverage placeholders in `tools/tests/ScenegraphInspection.Tests.ps1` and register the suite from `tools/tests/run-tool-tests.ps1`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared capture, schema, and evidence plumbing that blocks all user stories.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [X] T004 Implement shared capture channel and artifact constants in `addons/agent_runtime_harness/shared/inspection_constants.gd`
- [X] T005 [P] Implement shared snapshot capture and serialization services in `addons/agent_runtime_harness/runtime/scenegraph_capture_service.gd` and `addons/agent_runtime_harness/shared/scenegraph_serializer.gd`
- [X] T006 [P] Create artifact schemas in `specs/002-inspect-scene-tree/contracts/scenegraph-snapshot.schema.json` and `specs/002-inspect-scene-tree/contracts/scenegraph-diagnostics.schema.json`
- [X] T007 [P] Extend `tools/evidence/new-evidence-manifest.ps1` and `tools/evidence/validate-evidence-manifest.ps1` to recognize `scenegraph-snapshot`, `scenegraph-diagnostics`, and `scenegraph-summary` artifact kinds
- [X] T008 Create shared example-project harness settings in `examples/pong-testbed/harness/inspection-run-config.json` and `examples/pong-testbed/harness/expectations/common.json`

**Checkpoint**: Shared capture and evidence infrastructure is ready; user stories can now proceed independently.

---

## Phase 3: User Story 1 - Inspect Live Scene Hierarchy (Priority: P1) 🎯 MVP

**Goal**: Expose the live runtime hierarchy in the Godot editor through a dock-first workflow with startup and manual captures.

**Independent Test**: Launch `examples/pong-testbed/` from the editor, verify startup and manual captures produce scenegraph JSON that matches the healthy fixture and validates against the snapshot schema.

### Validation for User Story 1 ⚠️

- [X] T009 [P] [US1] Add the healthy snapshot expectation fixture at `examples/pong-testbed/harness/expected-live-scenegraph.json`
- [X] T010 [P] [US1] Add startup and manual snapshot validation coverage in `tools/tests/ScenegraphInspection.Tests.ps1` against `specs/002-inspect-scene-tree/contracts/scenegraph-snapshot.schema.json`

### Implementation for User Story 1

- [X] T011 [US1] Implement the editor plugin bootstrap in `addons/agent_runtime_harness/plugin.cfg` and `addons/agent_runtime_harness/plugin.gd`
- [X] T012 [P] [US1] Implement the dock UI for capture controls and latest snapshot summary in `addons/agent_runtime_harness/editor/scenegraph_dock.gd`
- [X] T013 [P] [US1] Implement the debugger session bridge in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`
- [X] T014 [P] [US1] Implement the runtime collector and autoload entrypoints in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` and `addons/agent_runtime_harness/runtime/scenegraph_autoload.gd`
- [X] T015 [US1] Wire startup and manual capture flow into `examples/pong-testbed/project.godot` and `examples/pong-testbed/scenes/main.tscn`
- [X] T016 [US1] Add capture-state and transport-error handling in `addons/agent_runtime_harness/editor/scenegraph_dock.gd` and `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`

**Checkpoint**: User Story 1 is complete when live startup and manual captures are visible in the dock and validate independently.

---

## Phase 4: User Story 2 - Preserve Agent-Readable Run Artifacts (Priority: P2)

**Goal**: Persist manifest-centered evidence bundles that preserve scenegraph captures and summaries after editor play sessions end.

**Independent Test**: End a play session in `examples/pong-testbed/`, validate the generated manifest and artifact references, and confirm the manifest alone identifies the relevant scenegraph output.

### Validation for User Story 2 ⚠️

- [X] T017 [P] [US2] Add the expected persisted manifest fixture at `examples/pong-testbed/harness/expected-evidence-manifest.json`
- [X] T018 [P] [US2] Add manifest and artifact-reference validation coverage in `tools/tests/ScenegraphInspection.Tests.ps1` using `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`

### Implementation for User Story 2

- [X] T019 [P] [US2] Implement scenegraph artifact writing in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- [X] T020 [P] [US2] Implement manifest summary generation in `addons/agent_runtime_harness/shared/scenegraph_summary_builder.gd`
- [X] T021 [US2] Wire post-run persistence and manifest generation in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd` and `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- [X] T022 [US2] Configure run output locations and bundle settings in `examples/pong-testbed/harness/inspection-run-config.json` and `examples/pong-testbed/project.godot`
- [X] T023 [US2] Update persisted-artifact validation guidance in `specs/002-inspect-scene-tree/quickstart.md`

**Checkpoint**: User Story 2 is complete when post-run scenegraph evidence validates and remains agent-readable without reopening raw live-session state.

---

## Phase 5: User Story 3 - Diagnose Missing Or Misplaced Nodes (Priority: P3)

**Goal**: Detect missing and hierarchy-mismatched nodes with hybrid expectation matching and failure-triggered captures.

**Independent Test**: Run broken `examples/pong-testbed/` cases, validate diagnostic JSON against the diagnostics schema, and confirm failure-triggered captures distinguish scenegraph problems from transport errors.

### Validation for User Story 3 ⚠️

- [X] T024 [P] [US3] Add broken expectation fixtures in `examples/pong-testbed/harness/expectations/missing-node.json` and `examples/pong-testbed/harness/expectations/mismatch-node.json`
- [X] T025 [P] [US3] Add missing-node and hierarchy-mismatch validation coverage in `tools/tests/ScenegraphInspection.Tests.ps1` against `specs/002-inspect-scene-tree/contracts/scenegraph-diagnostics.schema.json`

### Implementation for User Story 3

- [X] T026 [P] [US3] Implement hybrid expectation evaluation in `addons/agent_runtime_harness/runtime/scenegraph_expectation_evaluator.gd`
- [X] T027 [P] [US3] Implement diagnostic serialization in `addons/agent_runtime_harness/runtime/scenegraph_diagnostic_serializer.gd`
- [X] T028 [US3] Wire failure-triggered capture and diagnostic publication in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` and `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`
- [X] T029 [US3] Add deterministic broken validation scenes in `examples/pong-testbed/scenes/missing_node_case.tscn` and `examples/pong-testbed/scenes/mismatch_node_case.tscn`
- [X] T030 [US3] Surface missing-node, hierarchy-mismatch, and transport-error outcomes distinctly in `addons/agent_runtime_harness/editor/scenegraph_dock.gd`
- [X] T031 [US3] Update implemented diagnostic flow details in `specs/002-inspect-scene-tree/contracts/scenegraph-inspection-contract.md` and `specs/002-inspect-scene-tree/quickstart.md`

**Checkpoint**: User Story 3 is complete when diagnostic captures and persisted evidence clearly identify missing and misplaced runtime nodes.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final synchronization, fixture updates, and end-to-end validation across stories.

- [X] T032 [P] Update `docs/AGENT_RUNTIME_HARNESS.md` with the implemented editor-run scenegraph inspection flow, artifact kinds, and validation path
- [X] T033 [P] Update `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/scene-snapshot.json` and any paired manifest fixtures if the stabilized scenegraph contract changes the sample shape
- [X] T034 Run `pwsh ./tools/tests/run-tool-tests.ps1` and fix regressions in `tools/tests/ScenegraphInspection.Tests.ps1`, `tools/evidence/new-evidence-manifest.ps1`, and `tools/evidence/validate-evidence-manifest.ps1`
- [ ] T035 Run the full validation flow in `specs/002-inspect-scene-tree/quickstart.md` against `examples/pong-testbed/` and record implementation notes in `specs/002-inspect-scene-tree/research.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies
- **Phase 2: Foundational**: Depends on Phase 1 and blocks all user stories
- **Phase 3: User Story 1**: Depends on Phase 2 and is the MVP
- **Phase 4: User Story 2**: Depends on Phase 2 and reuses the shared capture service without depending on the dock UI being fully complete
- **Phase 5: User Story 3**: Depends on Phase 2 and reuses the shared capture service plus persisted artifact contract
- **Phase 6: Polish**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: No dependency on other user stories after Phase 2
- **US2**: No dependency on US1 after Phase 2; it consumes the shared snapshot outputs established in Foundational
- **US3**: No dependency on US1 or US2 after Phase 2; it consumes the shared snapshot outputs and manifest artifact kinds established in Foundational

### Within Each User Story

- Validation fixtures and executable checks should land before implementation tasks
- Runtime artifact production must land with the feature, not as a later cleanup step
- Story-specific validation should run before moving to the next priority if working sequentially

### Parallel Opportunities

- T002 and T003 can run in parallel after T001
- T005, T006, and T007 can run in parallel after T004 starts defining shared constants
- In US1, T009 and T010 can run in parallel; T012, T013, and T014 can run in parallel after the shared capture service exists
- In US2, T017 and T018 can run in parallel; T019 and T020 can run in parallel once shared artifact kinds are stable
- In US3, T024 and T025 can run in parallel; T026 and T027 can run in parallel once the diagnostics schema exists

---

## Parallel Example: User Story 1

```text
T009 Add the healthy snapshot expectation fixture at examples/pong-testbed/harness/expected-live-scenegraph.json
T010 Add startup and manual snapshot validation coverage in tools/tests/ScenegraphInspection.Tests.ps1
```

```text
T012 Implement the dock UI in addons/agent_runtime_harness/editor/scenegraph_dock.gd
T013 Implement the debugger session bridge in addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd
T014 Implement the runtime collector and autoload entrypoints in addons/agent_runtime_harness/runtime/scenegraph_runtime.gd and addons/agent_runtime_harness/runtime/scenegraph_autoload.gd
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate startup and manual capture behavior in `examples/pong-testbed/`
5. Stop and confirm the live editor workflow is useful before expanding persistence and diagnostics

### Incremental Delivery

1. Deliver shared capture, schema, and manifest plumbing
2. Deliver live dock-based scenegraph visibility and validate it
3. Deliver persisted evidence bundles and validate them
4. Deliver missing-node and hierarchy-mismatch diagnostics and validate them
5. Run the full quickstart and sync fixtures and docs

### Parallel Team Strategy

1. One contributor handles shared capture and schema work in Phase 2
2. After Phase 2, one contributor can focus on US1 editor surfaces while another prepares US2 artifact persistence
3. US3 can start once the diagnostics schema and shared capture outputs exist, provided coordination stays clear on `addons/agent_runtime_harness/runtime/`

---

## Notes

- `[P]` means the task is safe to parallelize only if file ownership does not overlap
- All validation outputs should stay machine-readable and point back to `examples/pong-testbed/` evidence artifacts
- Packaged executable support remains out of scope for these tasks unless implementation reveals a trivial compatibility path
- The current `specs/002-inspect-scene-tree/plan.md` contains a duplicated template appendix; task generation above follows the completed plan content at the top of that file