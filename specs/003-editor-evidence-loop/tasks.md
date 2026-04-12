# Tasks: Autonomous Editor Evidence Loop

**Input**: Design documents from `/specs/003-editor-evidence-loop/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Every user story includes executable validation tasks using deterministic example-project runs, contract validation, or PowerShell-based automation checks that produce machine-readable evidence.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently once the shared automation contracts and broker plumbing exist.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story the task belongs to (`US1`, `US2`, `US3`)
- All tasks include exact repository paths in the description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the fixture, template, and test locations that every story depends on.

- [ ] T001 Create automation fixture directories under `examples/pong-testbed/harness/automation/requests/` and `examples/pong-testbed/harness/automation/results/`
- [ ] T002 [P] Create template automation directories under `addons/agent_runtime_harness/templates/project_root/harness/automation/requests/` and `addons/agent_runtime_harness/templates/project_root/harness/automation/results/`
- [ ] T003 [P] Add the new task-level test suite file `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and register it from `tools/tests/run-tool-tests.ps1`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared automation contracts, artifact plumbing, and configuration defaults that block all user stories.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [ ] T004 Create contract schemas in `specs/003-editor-evidence-loop/contracts/automation-capability.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json`, and `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`
- [ ] T005 [P] Add shared automation constants, artifact names, and lifecycle states in `addons/agent_runtime_harness/shared/inspection_constants.gd`
- [ ] T006 [P] Implement shared request and result file handling in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`
- [ ] T007 [P] Extend `examples/pong-testbed/harness/inspection-run-config.json` and `addons/agent_runtime_harness/templates/project_root/harness/inspection-run-config.json` with scenario-declared target-scene fields, automation paths, and default request-scoped override support
- [ ] T008 Extend `tools/tests/ScenegraphAutomationLoop.Tests.ps1` to validate the new automation schemas with `tools/validate-json.ps1`

**Checkpoint**: Shared automation contracts and artifact plumbing are ready; story work can begin.

---

## Phase 3: User Story 1 - Start An Editor Run Autonomously (Priority: P1) 🎯 MVP

**Goal**: Allow a workspace-side agent to submit an autonomous run request, resolve the scenario-declared scene target, and start a single-project editor play session or return a blocked result deterministically.

**Independent Test**: Submit healthy and blocked request fixtures for `examples/pong-testbed/`, confirm the plugin reports capability correctly, resolves the scene from scenario or harness config rather than the active editor tab, emits lifecycle status through runtime attachment, and either launches the run or emits a blocked result with no hidden manual fallback.

### Validation for User Story 1 ⚠️

- [ ] T009 [P] [US1] Add capability fixtures at `examples/pong-testbed/harness/automation/results/capability-ready.expected.json` and `examples/pong-testbed/harness/automation/results/capability-blocked.expected.json`
- [ ] T010 [P] [US1] Add request fixtures at `examples/pong-testbed/harness/automation/requests/run-request.healthy.json` and `examples/pong-testbed/harness/automation/requests/run-request.blocked.json`
- [ ] T011 [P] [US1] Add capability, single-project, scene-target, shutdown-readiness, and runtime-attachment lifecycle validation coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` against `specs/003-editor-evidence-loop/contracts/automation-capability.schema.json` and `specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json`

### Implementation for User Story 1

- [ ] T012 [US1] Implement the plugin-owned automation broker in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and wire it from `addons/agent_runtime_harness/plugin.gd`
- [ ] T013 [P] [US1] Implement request intake, single-run locking, and request-scoped override parsing in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`
- [ ] T014 [P] [US1] Implement scenario-declared target-scene resolution and play-start control in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`
- [ ] T015 [US1] Emit capability results, lifecycle-status artifacts through runtime attachment, and blocked run results from `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`
- [ ] T016 [US1] Add example-project wiring for automation request and result paths in `examples/pong-testbed/project.godot` and `examples/pong-testbed/harness/inspection-run-config.json`

**Checkpoint**: User Story 1 is complete when a healthy request can start the declared scene and report attached-runtime status, and blocked requests return deterministic machine-readable results without touching the dock.

---

## Phase 4: User Story 2 - Capture, Persist, And Validate Evidence Without Dock Clicks (Priority: P2)

**Goal**: Extend the autonomous run from launch into capture, manifest-centered persistence, evidence validation, stale-artifact protection, and orderly session shutdown.

**Independent Test**: Run the healthy example request end to end, confirm the autonomous loop captures scenegraph evidence, persists the bundle, validates the manifest and artifact refs, stops the play session, and emits a final run result that points to the current run’s evidence only.

### Validation for User Story 2 ⚠️

- [ ] T017 [P] [US2] Add autonomous run result fixtures at `examples/pong-testbed/harness/automation/results/run-result.success.expected.json`, `examples/pong-testbed/harness/automation/results/run-result.attachment-failure.expected.json`, `examples/pong-testbed/harness/automation/results/run-result.capture-failure.expected.json`, `examples/pong-testbed/harness/automation/results/run-result.validation-failure.expected.json`, `examples/pong-testbed/harness/automation/results/run-result.shutdown-failure.expected.json`, and `examples/pong-testbed/harness/automation/results/run-result.gameplay-failure.expected.json`
- [ ] T018 [P] [US2] Add manifest-backed automated run validation and failure-kind matrix coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` using `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json` and `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`

### Implementation for User Story 2

- [ ] T019 [P] [US2] Implement end-to-end run lifecycle sequencing in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [ ] T020 [P] [US2] Extend `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd` and `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` with automation-aware session configuration and completion signaling
- [ ] T021 [US2] Implement lifecycle-status and final run-result artifact writing in `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd` and `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`
- [ ] T022 [US2] Wire validated capture, persistence, and shutdown sequencing in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` and `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`
- [ ] T023 [US2] Implement run-id-based stale-artifact protection in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, `addons/agent_runtime_harness/editor/scenegraph_automation_artifact_store.gd`, and `examples/pong-testbed/harness/automation/results/`
- [ ] T024 [US2] Extend template and example-project automation output settings in `addons/agent_runtime_harness/templates/project_root/harness/inspection-run-config.json` and `examples/pong-testbed/harness/inspection-run-config.json`

**Checkpoint**: User Story 2 is complete when the autonomous loop can run end to end and the final result always points to a validated, current evidence bundle.

---

## Phase 5: User Story 3 - Expose The Supported Automation Options Clearly (Priority: P3)

**Goal**: Make the default automation path, blocked behaviors, helper surfaces, and fallback options explicit for agents and maintainers.

**Independent Test**: Inspect capability results, helper outputs, and agent-facing docs to confirm the implemented flow reports the preferred path, distinguishes blocked states cleanly, and documents the deferred alternatives without implying hidden support.

### Validation for User Story 3 ⚠️

- [ ] T025 [P] [US3] Add control-path and blocked-behavior fixtures at `examples/pong-testbed/harness/automation/results/capability-options.expected.json` and `examples/pong-testbed/harness/automation/results/run-result.blocked.expected.json`
- [ ] T026 [P] [US3] Add helper and control-path validation coverage in `tools/tests/ScenegraphAutomationLoop.Tests.ps1` and `tools/tests/AutomationTools.Tests.ps1`

### Implementation for User Story 3

- [ ] T027 [P] [US3] Finalize contract docs and align schemas in `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/contracts/automation-capability.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json`, and `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`
- [ ] T028 [P] [US3] Update `addons/agent_runtime_harness/templates/project_root/AGENTS.runtime-harness.md` with the preferred file-broker path, blocked conditions, and manifest-first evidence workflow for autonomous runs
- [ ] T029 [P] [US3] Implement deterministic workspace helpers in `tools/automation/get-editor-evidence-capability.ps1` and `tools/automation/request-editor-evidence-run.ps1`
- [ ] T030 [US3] Add helper-script coverage in `tools/tests/AutomationTools.Tests.ps1` and document the supported automation surfaces in `docs/AGENT_TOOLING_FOUNDATION.md`
- [ ] T031 [US3] Update `specs/003-editor-evidence-loop/quickstart.md` and `specs/003-editor-evidence-loop/research.md` with the implemented default path and any validated fallback findings

**Checkpoint**: User Story 3 is complete when agents and maintainers can see exactly what path is supported, what is blocked, and what alternatives remain deferred.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final synchronization, end-to-end validation, and documentation cleanup across stories.

- [ ] T032 [P] Update `README.md` and `docs/AGENT_RUNTIME_HARNESS.md` with the implemented autonomous editor evidence loop entry points, constraints, and validation flow
- [ ] T033 [P] Run `pwsh ./tools/tests/run-tool-tests.ps1` and fix regressions in `tools/tests/ScenegraphAutomationLoop.Tests.ps1`, `tools/tests/AutomationTools.Tests.ps1`, and any touched automation helpers
- [ ] T034 Run the full validation flow in `specs/003-editor-evidence-loop/quickstart.md` against `examples/pong-testbed/` and record implementation notes in `specs/003-editor-evidence-loop/research.md`
- [ ] T035 [P] Run repeated seeded autonomous runs for `examples/pong-testbed/` and record machine-readable reliability results in `examples/pong-testbed/harness/automation/results/reliability-summary.json`
- [ ] T036 [P] Measure end-to-end request-to-stop timing for the seeded healthy flow and record the result in `examples/pong-testbed/harness/automation/results/performance-summary.json`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies
- **Phase 2: Foundational**: Depends on Phase 1 and blocks all user stories
- **Phase 3: User Story 1**: Depends on Phase 2 and is the MVP
- **Phase 4: User Story 2**: Depends on Phase 2 and the launch broker established in User Story 1 because it extends the same autonomous run lifecycle
- **Phase 5: User Story 3**: Depends on Phase 2 and can begin once contract names and helper surfaces are stable
- **Phase 6: Polish**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1**: No dependency on other user stories after Phase 2
- **US2**: Builds on the autonomous launch path from US1 because capture, persistence, validation, and shutdown happen within that same broker-owned run
- **US3**: Reuses shared contracts from Phase 2 and can overlap with late US1 or US2 work as long as file ownership stays coordinated

### Within Each User Story

- Validation fixtures and contract checks should land before implementation tasks
- Runtime artifact production must land with the feature, not as a later cleanup
- Story-specific validation should run before moving to the next priority if working sequentially

### Parallel Opportunities

- T002 and T003 can run in parallel after T001
- T005, T006, and T007 can run in parallel after T004 starts defining the shared contract shapes
- In US1, T009, T010, and T011 can run in parallel; T013 and T014 can run in parallel after T012 defines the broker entrypoint
- In US2, T017 and T018 can run in parallel; T019 and T020 can run in parallel once the broker contract is stable
- In US3, T025 and T026 can run in parallel; T027, T028, and T029 can run in parallel once the implemented contract surface is known
- In Phase 6, T035 and T036 can run in parallel after T034 establishes the end-to-end validation flow

---

## Parallel Example: User Story 1

```text
T009 Add capability fixtures at examples/pong-testbed/harness/automation/results/capability-ready.expected.json and capability-blocked.expected.json
T010 Add request fixtures at examples/pong-testbed/harness/automation/requests/run-request.healthy.json and run-request.blocked.json
T011 Add capability, scene-target, shutdown-readiness, and lifecycle validation coverage in tools/tests/ScenegraphAutomationLoop.Tests.ps1
```

```text
T013 Implement request intake, single-run locking, and request-scoped override parsing in addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd
T014 Implement scenario-declared target-scene resolution and play-start control in addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate healthy and blocked launch behavior plus runtime-attachment status in `examples/pong-testbed/`
5. Stop and confirm the autonomous launch path works before extending it into persistence and shutdown

### Incremental Delivery

1. Deliver shared contracts, artifact storage, and configuration defaults
2. Deliver autonomous launch and blocked-result handling and validate it
3. Deliver capture, persistence, validation, and shutdown sequencing and validate it
4. Deliver helper surfaces and documentation for the supported automation path and alternatives
5. Run the full quickstart, repeated-run reliability check, and timing validation, then sync docs and fixtures

### Parallel Team Strategy

1. One contributor handles shared contracts and artifact-store plumbing in Phase 2
2. After Phase 2, one contributor can focus on US1 broker behavior while another prepares US3 docs and helper scaffolding that depend only on stable contract names
3. US2 starts once US1 fixes the broker entrypoint and launch semantics

---

## Notes

- `[P]` means the task is safe to parallelize only if file ownership does not overlap
- All validation outputs should stay machine-readable and point back to the example project’s evidence and automation artifacts
- The clarified spec requires scenario-declared launch targets and request-scoped overrides; tasks above assume those decisions are not optional
- The preferred v1 path is the plugin-owned file broker; script forwarding and local IPC remain documented alternatives, not first-release commitments