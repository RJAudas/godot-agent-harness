# Tasks: Report Build Errors On Run

**Input**: Design documents from `/specs/004-report-build-errors/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Every user story includes executable validation tasks using deterministic broken-project fixtures, shared contract validation, and existing automation regression surfaces that produce machine-readable results.

**Organization**: Tasks are grouped by user story so the build-failure path, the safety and edge-case path, and the contract-preservation path can each be implemented and validated independently once the shared result contract is in place.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story the task belongs to (`US1`, `US2`, `US3`)
- All tasks include exact repository paths in the description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add shared test scaffolding for build-failed runs before contract and broker changes begin.

- [X] T001 Add shared build-diagnostic assertion helpers in `tools/tests/TestHelpers.ps1`
- [X] T002 [P] Add a build-failure test grouping scaffold in `tools/tests/ScenegraphAutomationLoop.Tests.ps1`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared run-result contract and reusable payload plumbing that all stories depend on.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [X] T004 Extend `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json` and `specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json` with the `build` failure kind and the build-failure payload fields required by the 004 spec
- [X] T005 [P] Align `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md` and `specs/004-report-build-errors/contracts/build-error-run-result-contract.md` on lifecycle, result, and no-manifest semantics for build-failed runs
- [X] T006 [P] Add shared build-failure constants and payload semantics in `addons/agent_runtime_harness/shared/inspection_constants.gd`
- [X] T007 [P] Extend reusable result-writing helpers in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd` and test assertions in `tools/tests/TestHelpers.ps1` for build diagnostics and raw build output

**Checkpoint**: Shared contract and payload plumbing are ready; story work can begin.

---

## Phase 3: User Story 1 - Return Build Errors For Failed Runs (Priority: P1) 🎯 MVP

**Goal**: Detect build-failed runs before runtime attachment and return a failed run result with normalized diagnostics and raw build output.

**Independent Test**: Submit a seeded broken-project request and confirm the final run result reports `failureKind = build`, identifies the active `runId`, includes normalized diagnostics plus raw build output, and does not wait for runtime evidence that will never exist.

### Validation for User Story 1 ⚠️

- [X] T008 [P] [US1] Add deterministic build-failure request, lifecycle, and expected result fixtures in `examples/pong-testbed/harness/automation/requests/run-request.build-failure.json`, `examples/pong-testbed/harness/automation/results/lifecycle-status.build-failure.expected.json`, and `examples/pong-testbed/harness/automation/results/run-result.build-failure.expected.json`
- [X] T009 [P] [US1] Add schema and regression coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` for lifecycle-status `failureKind = build`, `buildFailurePhase`, and `buildDiagnosticCount`, plus run-result `buildDiagnostics` and `rawBuildOutput`

### Implementation for User Story 1

- [X] T010 [US1] Implement build-failure detection and lifecycle classification in the launch-to-attach boundary in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [X] T011 [P] [US1] Wire any required broker-side observation and signal handling in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and `addons/agent_runtime_harness/plugin.gd`
- [X] T012 [P] [US1] Extend lifecycle-status and final result writing in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd` and `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` to emit normalized diagnostics and raw build output for the active run
- [X] T013 [US1] Preserve healthy successful-run behavior in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` so build payloads appear only on build-failed runs

**Checkpoint**: User Story 1 is complete when a broken run returns actionable build diagnostics through the existing final run-result artifact.

---

## Phase 4: User Story 2 - Keep Failure Reporting Actionable And Safe (Priority: P2)

**Goal**: Prevent stale evidence reuse, preserve multiple diagnostics and partial metadata, and keep build-failed runs distinct from other failure modes.

**Independent Test**: Run seeded stale-manifest, multi-error, resource-load, partial-metadata, and blocked-nonbuild cases and confirm the broker returns the correct failure classification without reusing old evidence.

### Validation for User Story 2 ⚠️

- [X] T014 [P] [US2] Add stale-manifest, multi-error, blocking resource-load, partial-metadata, and blocked-nonbuild expected results under `examples/pong-testbed/harness/automation/results/`
- [X] T015 [P] [US2] Add regression coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` for stale-manifest prevention, multi-diagnostic preservation, blocking resource-load handling, partial metadata retention, and blocked-vs-build distinctions

### Implementation for User Story 2

- [X] T016 [US2] Implement explicit no-manifest validation notes and stale-artifact protection for build-failed runs in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [X] T017 [P] [US2] Preserve multiple diagnostics and partial metadata in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd` and `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [X] T018 [US2] Keep blocked prerequisite outcomes distinct from build-failed outcomes in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [X] T019 [US2] Align result fixtures in `examples/pong-testbed/harness/automation/results/` so previous manifests are never treated as the output of a build-failed run

**Checkpoint**: User Story 2 is complete when build-failed runs stay actionable and safe even under stale-output and multi-error conditions.

---

## Phase 5: User Story 3 - Preserve The Existing Automation Path (Priority: P3)

**Goal**: Keep the file-broker path authoritative, keep successful runs on the manifest-centered path, and document the shared contract extension clearly.

**Independent Test**: Validate a healthy success fixture and the updated contract docs so agents can distinguish build-failed runs from successful manifest-backed runs without learning a new transport or workflow.

### Validation for User Story 3 ⚠️

- [X] T020 [P] [US3] Add healthy-run regression coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `examples/pong-testbed/harness/automation/results/run-result.success.expected.json` to confirm manifest-centered success behavior remains unchanged
- [X] T021 [P] [US3] Add helper or consumer regression coverage in `tools/tests/AutomationTools.Tests.ps1` if updated contract fields affect schema-consuming scripts or result readers

### Implementation for User Story 3

- [X] T022 [P] [US3] Update `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/quickstart.md`, and `specs/004-report-build-errors/contracts/build-error-run-result-contract.md` to document the shared contract extension without introducing a new diagnostics channel
- [X] T023 [P] [US3] Update `docs/AGENT_TOOLING_FOUNDATION.md` and `specs/004-report-build-errors/quickstart.md` so agents read the final run result first for build-failed runs and the manifest first for successful runs
- [X] T024 [US3] Update `addons/agent_runtime_harness/templates/project_root/AGENTS.runtime-harness.md` and any related deployed guidance templates so the build-failure path is described in the same plugin-owned workflow
- [X] T025 [US3] Confirm result-contract compatibility across `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`, `tools/tests/AutomationTools.Tests.ps1`, and any touched helper expectations

**Checkpoint**: User Story 3 is complete when the build-failure extension is documented as part of the same broker workflow and successful runs still use the manifest-centered path unchanged.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Run full regression coverage, verify quickstart behavior, and synchronize high-level docs.

- [X] T026 [P] Update `README.md` and `docs/AGENT_RUNTIME_HARNESS.md` if the build-failure extension changes the documented autonomous-run outcome flow
- [X] T027 Run `pwsh ./tools/tests/run-tool-tests.ps1` and fix regressions in `tools/tests/ScenegraphAutomationLoop.Tests.ps1`, `tools/tests/AutomationTools.Tests.ps1`, and any touched contract files
- [X] T028 [P] Execute the validation flow in `specs/004-report-build-errors/quickstart.md` against `examples/pong-testbed/` and record any implementation notes in `specs/004-report-build-errors/research.md`
- [ ] T029 [P] Measure request-to-failed-result timing for seeded build-failure runs against the 30-second target and record the result in `specs/004-report-build-errors/research.md`
- [ ] T030 [P] Run seeded repair-and-retry validation cycles for the build-failure fixtures and record the observed pass-rate evidence in `specs/004-report-build-errors/research.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies
- **Phase 2: Foundational**: Depends on Phase 1 and blocks all user stories
- **Phase 3: User Story 1**: Depends on Phase 2 and delivers the MVP build-failure path
- **Phase 4: User Story 2**: Depends on Phase 2 and builds on the shared build-failure payload introduced in User Story 1
- **Phase 5: User Story 3**: Depends on Phase 2 and can overlap with late User Story 2 work once contract names are stable
- **Phase 6: Polish**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: No dependency on other user stories after Phase 2
- **US2**: Builds on US1 because stale-manifest and edge-case handling extend the build-failed result path introduced there
- **US3**: Depends on the stable contract surface from Phases 2 and 3, but should remain independently testable through healthy-run regressions and documentation checks

### Within Each User Story

- Validation fixtures and regression checks should land before implementation tasks
- Shared contract and payload changes must land before story-specific broker behavior
- A story is not complete until its machine-readable outputs and validation surfaces are updated together

### Parallel Opportunities

- T001 and T002 can run in parallel at the start of Phase 1
- T005, T006, and T007 can run in parallel once T004 defines the shared schema changes
- In US1, T008 and T009 can run in parallel; T011 and T012 can run in parallel after T010 starts the build-failure detection path
- In US2, T014 and T015 can run in parallel; T016 and T017 can run in parallel once the build-failure payload exists
- In US3, T020 and T021 can run in parallel; T022 and T023 can run in parallel once the final contract fields are stable
- In Phase 6, T028, T029, and T030 can run in parallel after the implementation is stable enough for end-to-end measurement

---

## Parallel Example: User Story 1

```text
T008 Add deterministic build-failure request, lifecycle, and expected result fixtures in examples/pong-testbed/harness/automation/requests/run-request.build-failure.json, examples/pong-testbed/harness/automation/results/lifecycle-status.build-failure.expected.json, and examples/pong-testbed/harness/automation/results/run-result.build-failure.expected.json
T009 Add schema and regression coverage in tools/tests/ScenegraphAutomationLoop.Tests.ps1 for failureKind = build, buildFailurePhase, buildDiagnosticCount, buildDiagnostics, and rawBuildOutput
```

```text
T011 Wire any required broker-side observation and signal handling in addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd and addons/agent_runtime_harness/plugin.gd
T012 Extend final result writing in addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd and addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd to emit normalized diagnostics and raw build output for the active run
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate the build-failure fixture independently through the shared run-result artifact
5. Stop and confirm the agent has enough information to repair and retry before expanding into safety and documentation work

### Incremental Delivery

1. Deliver shared contract and payload changes
2. Deliver build-failure detection and final result emission and validate it
3. Deliver stale-evidence safety and edge-case handling and validate it
4. Deliver documentation and success-path preservation work and validate it
5. Run the full tool-test and quickstart flow, then sync any remaining docs

### Parallel Team Strategy

1. One contributor handles shared contract and payload plumbing in Phase 2
2. After Phase 2, one contributor can focus on broker detection while another prepares stale-manifest fixtures and regression coverage
3. Documentation and guidance updates can proceed once the final contract fields are stable

---

## Notes

- `[P]` means a task is safe to parallelize only if file ownership does not overlap
- The clarified spec requires normalized diagnostics, raw build output, explicit no-manifest semantics, and no automatic retry behavior
- The preferred v1 path remains the plugin-owned file broker; do not add a second diagnostics transport while implementing these tasks
