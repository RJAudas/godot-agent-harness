# Tasks: Behavior Watch Sampling

**Input**: Design documents from `/specs/005-behavior-watch-sampling/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Every user story includes executable validation tasks using deterministic request fixtures, seeded Pong automation runs, manifest validation, and existing PowerShell regression surfaces that produce machine-readable results.

**Organization**: Tasks are grouped by user story so the request-contract path, bounded trace-sampling path, and manifest-integration path can each be implemented and validated independently once the shared behavior-watch plumbing is ready.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story the task belongs to (`US1`, `US2`, `US3`)
- All tasks include exact repository paths in the description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the deterministic fixture and regression scaffolding needed for behavior-watch implementation work.

- [X] T001 Create behavior-watch request fixture scaffolding in `examples/pong-testbed/harness/automation/requests/behavior-watch-valid.json` and `examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-selector.json`
- [X] T002 [P] Add behavior-watch regression grouping scaffolds in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `tools/tests/AutomationTools.Tests.ps1`
- [X] T003 [P] Create behavior-watch expected-output scaffolding in `examples/pong-testbed/evidence/automation/` and `examples/pong-testbed/harness/automation/results/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish shared request, runtime, and artifact plumbing that all user stories depend on.

**CRITICAL**: No user story work should begin until this phase is complete.

- [X] T004 Extend `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` and `tools/automation/request-editor-evidence-run.ps1` to accept `overrides.behaviorWatchRequest`
- [X] T005 [P] Add shared behavior-watch constants and artifact metadata in `addons/agent_runtime_harness/shared/inspection_constants.gd` and `tools/evidence/artifact-registry.ps1`
- [X] T006 [P] Create the shared request-validation helper in `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`
- [X] T007 [P] Add run-scoped watch-session plumbing in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`, and `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`

**Checkpoint**: Shared behavior-watch plumbing is ready; story work can now proceed.

---

## Phase 3: User Story 1 - Declare A Bounded Watch Request (Priority: P1) MVP

**Goal**: Let an agent submit a bounded behavior watch request that is normalized or rejected before a playtest begins.

**Independent Test**: Validate one seeded Pong watch request and one invalid request without launching a playtest, and confirm the valid request produces explicit defaults while the invalid request returns a machine-readable rejection.

### Validation for User Story 1

- [X] T008 [P] [US1] Add valid and invalid request fixtures in `examples/pong-testbed/harness/automation/requests/behavior-watch-valid.json`, `examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-selector.json`, and `examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-window.json`
- [X] T009 [P] [US1] Add normalization and rejection coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `tools/tests/AutomationTools.Tests.ps1` for unsupported selectors, later-slice fields, and zero-sample windows

### Implementation for User Story 1

- [X] T010 [US1] Implement watch-request normalization defaults and rejection rules in `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`
- [X] T011 [P] [US1] Publish invalid watch-request failures before playtest launch in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`
- [X] T012 [P] [US1] Expose the normalized applied-watch summary in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` and `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`
- [X] T013 [US1] Align request-contract documentation and examples in `specs/005-behavior-watch-sampling/contracts/behavior-watch-contract.md` and `specs/005-behavior-watch-sampling/quickstart.md`

**Checkpoint**: User Story 1 is complete when behavior-watch requests are deterministically normalized or rejected before runtime sampling starts.

---

## Phase 4: User Story 2 - Persist A Targeted Time-Series Trace (Priority: P2)

**Goal**: Sample only the requested node paths and fields within the configured watch window and persist a bounded `trace.jsonl` artifact.

**Independent Test**: Run deterministic Pong wall-bounce fixtures for every-frame and every-N-frame sampling and confirm the resulting trace contains only the requested Ball fields within the configured start-frame offset and bounded frame count.

### Validation for User Story 2

- [X] T014 [P] [US2] Add deterministic Pong watch-run fixtures in `examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-frame.json` and `examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-n.json`
- [X] T015 [P] [US2] Add bounded-trace sampling coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `tools/tests/AutomationTools.Tests.ps1` for cadence, frame-window enforcement, requested-fields-only rows, and no-sample outcomes

### Implementation for User Story 2

- [X] T016 [P] [US2] Implement bounded watch-sampling state in `addons/agent_runtime_harness/runtime/behavior_watch_sampler.gd`
- [X] T017 [US2] Wire start-frame offset and cadence enforcement into `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`
- [X] T018 [P] [US2] Implement flat `trace.jsonl` row serialization in `addons/agent_runtime_harness/runtime/behavior_trace_writer.gd`
- [X] T019 [US2] Persist the current run's `trace.jsonl` artifact through `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd` and `addons/agent_runtime_harness/runtime/behavior_trace_writer.gd`
- [X] T020 [US2] Report missing-target, missing-property, and no-sample outcomes in `addons/agent_runtime_harness/runtime/behavior_watch_sampler.gd` and `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`

**Checkpoint**: User Story 2 is complete when a deterministic Pong run produces a bounded `trace.jsonl` artifact for the requested watch scope only.

---

## Phase 5: User Story 3 - Keep Evidence Manifest-Centered (Priority: P3)

**Goal**: Keep behavior-watch output on the existing manifest-first evidence path and prevent stale traces from being misattributed to the current run.

**Independent Test**: Persist a completed behavior-watch run and confirm the current manifest references the current run's `trace.jsonl`, exposes the applied-watch summary, and never points to stale trace output from a previous run.

### Validation for User Story 3

- [X] T021 [P] [US3] Add expected manifest and result fixtures for behavior-watch runs in `examples/pong-testbed/evidence/automation/` and `examples/pong-testbed/harness/automation/results/`
- [X] T022 [P] [US3] Add manifest-reference and stale-trace regression coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `tools/tests/AutomationTools.Tests.ps1`

### Implementation for User Story 3

- [X] T023 [US3] Register behavior-watch trace artifact metadata in `tools/evidence/artifact-registry.ps1` and `addons/agent_runtime_harness/shared/inspection_constants.gd`
- [X] T024 [US3] Add `trace.jsonl` artifact references and applied-watch summary output in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- [X] T025 [P] [US3] Align run-result-to-manifest handoff behavior in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd` and `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [X] T026 [US3] Document manifest-first trace consumption in `docs/AGENT_TOOLING_FOUNDATION.md` and `specs/005-behavior-watch-sampling/contracts/behavior-watch-contract.md`

**Checkpoint**: User Story 3 is complete when behavior-watch traces are consumed through the same manifest-centered evidence flow as the rest of the harness.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Finish shared documentation, run full validation, and capture follow-up notes from the quickstart flow.

- [X] T027 [P] Update slice-1 and slice-2 guidance in `docs/BEHAVIOR_CAPTURE_SLICES.md` and `docs/AGENT_RUNTIME_HARNESS.md`
- [X] T028 Run `pwsh ./tools/tests/run-tool-tests.ps1` and fix regressions in `tools/tests/ScenegraphAutomationLoop.Tests.ps1`, `tools/tests/AutomationTools.Tests.ps1`, and any touched contracts
- [X] T029 [P] Run `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <generated-manifest>` against the behavior-watch fixture output and record notes in `specs/005-behavior-watch-sampling/research.md`
- [X] T030 [P] Execute the validation flow in `specs/005-behavior-watch-sampling/quickstart.md` against `examples/pong-testbed/` and record follow-up notes in `specs/005-behavior-watch-sampling/research.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies
- **Phase 2: Foundational**: Depends on Phase 1 and blocks all user-story work
- **Phase 3: User Story 1**: Depends on Phase 2 and delivers the MVP request-contract path
- **Phase 4: User Story 2**: Depends on Phase 2 and can proceed independently once shared request and session plumbing exist
- **Phase 5: User Story 3**: Depends on User Story 2 because manifest integration needs the trace artifact path to exist
- **Phase 6: Polish**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: No dependency on other user stories after Phase 2
- **US2**: No dependency on US1 once the shared request schema, validator helper, and session plumbing from Phase 2 are in place
- **US3**: Depends on US2 because manifest integration and stale-trace protection require the trace artifact produced there

### Within Each User Story

- Validation fixtures and regression checks should land before implementation tasks
- Runtime artifact production must land with the story, not as a later cleanup step
- A story is not complete until its machine-readable outputs and validation surfaces are updated together

### Parallel Opportunities

- T002 and T003 can run in parallel after T001 starts the fixture structure
- T005, T006, and T007 can run in parallel after T004 defines the shared request extension
- In US1, T008 and T009 can run in parallel; T011 and T012 can run in parallel after T010 begins the validator logic
- In US2, T014 and T015 can run in parallel; T016 and T018 can run in parallel before T017 and T019 integrate them
- In US3, T021 and T022 can run in parallel; T025 and T026 can run in parallel after T023 and T024 stabilize the artifact path
- In Phase 6, T027, T029, and T030 can run in parallel after implementation stabilizes

---

## Parallel Example: User Story 1

```text
T008 Add valid and invalid request fixtures in examples/pong-testbed/harness/automation/requests/behavior-watch-valid.json, examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-selector.json, and examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-window.json
T009 Add normalization and rejection coverage in tools/tests/ScenegraphAutomationLoop.Tests.ps1 and tools/tests/AutomationTools.Tests.ps1 for unsupported selectors, later-slice fields, and zero-sample windows
```

```text
T011 Publish invalid watch-request failures before playtest launch in addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd and addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd
T012 Expose the normalized applied-watch summary in addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd and addons/agent_runtime_harness/runtime/scenegraph_runtime.gd
```

## Parallel Example: User Story 2

```text
T014 Add deterministic Pong watch-run fixtures in examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-frame.json and examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-n.json
T015 Add bounded-trace sampling coverage in tools/tests/ScenegraphAutomationLoop.Tests.ps1 and tools/tests/AutomationTools.Tests.ps1 for cadence, frame-window enforcement, requested-fields-only rows, and no-sample outcomes
```

```text
T016 Implement bounded watch-sampling state in addons/agent_runtime_harness/runtime/behavior_watch_sampler.gd
T018 Implement flat trace.jsonl row serialization in addons/agent_runtime_harness/runtime/behavior_trace_writer.gd
```

## Parallel Example: User Story 3

```text
T021 Add expected manifest and result fixtures for behavior-watch runs in examples/pong-testbed/evidence/automation/ and examples/pong-testbed/harness/automation/results/
T022 Add manifest-reference and stale-trace regression coverage in tools/tests/ScenegraphAutomationLoop.Tests.ps1 and tools/tests/AutomationTools.Tests.ps1
```

```text
T025 Align run-result-to-manifest handoff behavior in addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd and addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd
T026 Document manifest-first trace consumption in docs/AGENT_TOOLING_FOUNDATION.md and specs/005-behavior-watch-sampling/contracts/behavior-watch-contract.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate request normalization and rejection independently without launching a playtest
5. Stop and confirm the agent can author a deterministic bounded watch contract before building runtime sampling

### Incremental Delivery

1. Deliver the shared request and session plumbing
2. Deliver User Story 1 and validate request normalization and rejection
3. Deliver User Story 2 and validate bounded trace sampling
4. Deliver User Story 3 and validate manifest-centered handoff and stale-trace protection
5. Run polish validations and sync any remaining documentation

### Parallel Team Strategy

1. One contributor handles the shared request extension and validator scaffolding in Phase 2
2. After Phase 2, one contributor can focus on request-validation UX while another prepares trace sampling fixtures
3. Once trace persistence stabilizes, another contributor can complete manifest integration and guidance updates in parallel

---

## Notes

- `[P]` means a task is safe to parallelize only when file ownership does not overlap
- The clarified spec fixes the first release to absolute runtime node paths, explicit start-frame offset plus bounded frame count, and a fixed `trace.jsonl` artifact
- Do not introduce later-slice trigger windows, invariants, probes, or full-scene continuous logging while implementing these tasks
