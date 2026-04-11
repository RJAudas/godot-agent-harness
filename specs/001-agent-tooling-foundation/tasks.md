# Tasks: Agent Tooling Foundation

**Input**: Design documents from `/specs/001-agent-tooling-foundation/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md, contracts/

**Tests**: Every user story includes executable validation tasks using seeded Copilot Chat or Copilot CLI eval fixtures, manifest validation, or autonomous-boundary checks that produce machine-readable evidence.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when file ownership does not overlap
- **[Story]**: Which user story the task belongs to (`US1`, `US2`, `US3`)
- All tasks include exact repository paths in the description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory structure and shared eval locations that every story depends on.

- [x] T001 Create implementation directories `.github/instructions/`, `tools/evals/001-agent-tooling-foundation/`, `tools/evals/fixtures/001-agent-tooling-foundation/`, `tools/evidence/`, and `tools/automation/`
- [x] T002 [P] Add a shared eval usage note to `tools/evals/README.md` describing fixture naming, result locations, and Copilot Chat versus Copilot CLI coverage for this feature
- [x] T003 [P] Update `specs/001-agent-tooling-foundation/quickstart.md` with the concrete evaluation artifact paths that implementation tasks will populate

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared schemas and validation helpers that block all story work.

**⚠️ CRITICAL**: No user story work should begin until this phase is complete.

- [x] T004 Create `tools/evals/agent-eval-result.schema.json` to standardize machine-readable results for seeded Copilot Chat and Copilot CLI evaluations
- [x] T005 [P] Create `tools/automation/autonomous-run-record.schema.json` for machine-readable logs emitted by autonomous tooling runs
- [x] T006 [P] Create `tools/automation/write-boundaries.schema.json` to define the allowed path and edit-type contract for autonomous artifacts
- [x] T007 Implement `tools/validate-json.ps1` to validate JSON fixtures and run records against repository schemas, including `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`
- [x] T008 Create `tools/evals/fixtures/001-agent-tooling-foundation/README.md` documenting the sample runtime artifacts, eval prompts, and expected-output fixture layout

**Checkpoint**: Shared validation infrastructure is ready; user stories can now proceed independently.

---

## Phase 3: User Story 1 - Layered Agent Guidance (Priority: P1) 🎯 MVP

**Goal**: Deliver a Copilot-first guidance stack that gets agents oriented to the Godot harness, plugin-first constraints, and validation workflow with minimal rediscovery.

**Independent Test**: Run seeded orientation evals for VS Code Copilot Chat and Copilot CLI and verify machine-readable results show the agent selected the correct guidance stack, cited plugin-first constraints, and used the expected validation loop.

### Validation for User Story 1 ⚠️

- [x] T009 [P] [US1] Add the VS Code Copilot Chat orientation eval fixture at `tools/evals/001-agent-tooling-foundation/us1-copilot-chat-orientation.md`
- [x] T010 [P] [US1] Add the Copilot CLI orientation eval fixture at `tools/evals/001-agent-tooling-foundation/us1-copilot-cli-orientation.md`
- [x] T011 [P] [US1] Add expected guidance-selection results at `tools/evals/001-agent-tooling-foundation/us1-guidance-selection.expected.json`

### Implementation for User Story 1

- [x] T012 [US1] Update `.github/copilot-instructions.md` with the durable repo-wide guidance for Godot plugin work, evidence-first validation, and approved repository paths
- [x] T013 [P] [US1] Create `AGENTS.md` with agent-facing operating rules, validation expectations, and repository navigation guidance for this harness
- [x] T014 [P] [US1] Create `.github/instructions/addons.instructions.md` for addon-specific guidance that narrows behavior under `addons/agent_runtime_harness/`
- [x] T015 [P] [US1] Create `.github/instructions/scenarios.instructions.md` for deterministic scenario, fixture, and runtime evidence handling under `scenarios/`
- [x] T016 [P] [US1] Create `.github/instructions/tools.instructions.md` for helper scripts, eval assets, and evidence tooling under `tools/`
- [x] T017 [US1] Update `README.md` and `docs/AI_TOOLING_BEST_PRACTICES.md` to point to the adopted Copilot-first guidance stack without duplicating repo instructions
- [x] T018 [US1] Run the orientation flow from `specs/001-agent-tooling-foundation/quickstart.md` and record machine-readable results in `tools/evals/001-agent-tooling-foundation/us1-orientation-results.json`

**Checkpoint**: User Story 1 is complete when Copilot Chat and Copilot CLI can both orient correctly using the new guidance stack.

---

## Phase 4: User Story 2 - Agent-Consumable Evidence Bundles (Priority: P2)

**Goal**: Deliver a manifest-centered evidence bundle contract and helper tooling that turns Godot runtime outputs into a stable handoff format agents can consume directly.

**Independent Test**: Assemble a sample evidence bundle from seeded runtime artifacts, validate it against the manifest schema, and confirm a seeded agent task can determine outcome and next actions from the manifest without reading every raw file first.

### Validation for User Story 2 ⚠️

- [x] T019 [P] [US2] Add a valid manifest fixture at `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json`
- [x] T020 [P] [US2] Add an invalid manifest fixture at `tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json`
- [x] T021 [P] [US2] Add an evidence-consumption eval fixture at `tools/evals/001-agent-tooling-foundation/us2-evidence-consumption.md`

### Implementation for User Story 2

- [x] T022 [US2] Implement `tools/evidence/validate-evidence-manifest.ps1` to validate manifests against `specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json`
- [x] T023 [P] [US2] Implement `tools/evidence/new-evidence-manifest.ps1` to assemble a manifest from seeded raw runtime artifacts and normalized summary fields
- [x] T024 [P] [US2] Add a sample runtime artifact fixture set under `tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/` including trace, event, and scene-snapshot references
- [x] T025 [US2] Update `docs/AGENT_RUNTIME_HARNESS.md` with the evidence bundle flow, manifest contract, and how agents should consume the manifest before raw files
- [x] T026 [US2] Run the evidence bundle flow from `specs/001-agent-tooling-foundation/quickstart.md` and record results in `tools/evals/001-agent-tooling-foundation/us2-bundle-results.json`

**Checkpoint**: User Story 2 is complete when manifests validate, reference raw artifacts correctly, and seeded tasks can use them as the primary entry point.

---

## Phase 5: User Story 3 - Reusable Automation Decisions (Priority: P3)

**Goal**: Deliver the decision rules, autonomous write-boundary contracts, and at least one concrete Copilot-first automation artifact that can be kept or removed based on evaluation results.

**Independent Test**: Run seeded classification and boundary evals to verify the repo can distinguish between instructions, workflows, agents, and skills, and that autonomous tooling stays within declared write boundaries while logging machine-readable stop or escalation records.

### Validation for User Story 3 ⚠️

- [x] T027 [P] [US3] Add the automation-classification eval fixture at `tools/evals/001-agent-tooling-foundation/us3-automation-classification.md`
- [x] T028 [P] [US3] Add the write-boundary eval fixture at `tools/evals/001-agent-tooling-foundation/us3-write-boundary.md`
- [x] T029 [P] [US3] Add expected lifecycle and boundary outcomes at `tools/evals/001-agent-tooling-foundation/us3-expected-results.json`

### Implementation for User Story 3

- [x] T030 [US3] Create `docs/AI_TOOLING_AUTOMATION_MATRIX.md` describing when the repo should use instructions, fixed workflows, Copilot-native agents or prompts, or local skills
- [x] T031 [P] [US3] Create the Copilot-first prompt artifact `.github/prompts/godot-evidence-triage.prompt.md` for diagnosing Godot runtime evidence from a manifest-centered bundle
- [x] T032 [P] [US3] Create the paired agent artifact `.github/agents/godot-evidence-triage.agent.md` with explicit scope, inputs, stop conditions, and expected outputs
- [x] T033 [P] [US3] Implement `tools/automation/validate-write-boundary.ps1` to enforce autonomous path and edit-type limits using `tools/automation/write-boundaries.schema.json`
- [x] T034 [P] [US3] Add `tools/automation/write-boundaries.json` declaring allowed write scopes for first-release autonomous artifacts
- [x] T035 [P] [US3] Implement `tools/automation/new-autonomous-run-record.ps1` to emit machine-readable run logs that conform to `tools/automation/autonomous-run-record.schema.json`
- [x] T036 [US3] Run the automation classification and write-boundary flows from `specs/001-agent-tooling-foundation/quickstart.md` and record results in `tools/evals/001-agent-tooling-foundation/us3-validation-results.json`

**Checkpoint**: User Story 3 is complete when the repo has concrete decision rules, one evaluable Copilot-first automation artifact, and validated autonomous boundary enforcement.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final synchronization, documentation cleanup, and end-to-end validation across stories.

- [x] T037 [P] Update `README.md` with the final agent tooling entry points, evidence bundle helpers, and eval result locations
- [x] T038 [P] Sync `specs/001-agent-tooling-foundation/quickstart.md` with the implemented commands, result files, and validation flow
- [x] T039 Run the full quickstart across VS Code Copilot Chat and Copilot CLI and record final machine-readable results in `tools/evals/001-agent-tooling-foundation/final-validation-results.json`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1: Setup**: No dependencies
- **Phase 2: Foundational**: Depends on Phase 1 and blocks all story work
- **Phase 3: User Story 1**: Depends on Phase 2 and is the MVP
- **Phase 4: User Story 2**: Depends on Phase 2; can proceed independently of User Story 1 once shared validation infrastructure is in place
- **Phase 5: User Story 3**: Depends on Phase 2; can proceed independently of User Story 1 and User Story 2 once shared validation infrastructure is in place
- **Phase 6: Polish**: Depends on the desired user stories being complete

### User Story Dependencies

- **US1**: No dependency on other user stories after Phase 2
- **US2**: No dependency on other user stories after Phase 2, but it reuses the shared validation helper from `tools/validate-json.ps1`
- **US3**: No dependency on other user stories after Phase 2, but it reuses shared eval and automation schemas from Phase 2

### Within Each User Story

- Validation fixtures and expected results should land before implementation tasks
- Implementation tasks must emit machine-readable artifacts as part of the story, not as a later cleanup
- Story-specific validation runs should happen before moving to the next priority if working sequentially

### Parallel Opportunities

- T002 and T003 can run in parallel after T001
- T005 and T006 can run in parallel; T004 and T007 can overlap once directory setup is complete
- In US1, T009, T010, and T011 can run in parallel; T013 through T016 can run in parallel after the eval fixtures exist
- In US2, T019, T020, and T021 can run in parallel; T023 and T024 can run in parallel after T022 starts defining the contract flow
- In US3, T027, T028, and T029 can run in parallel; T031 through T035 can run in parallel once T030 fixes the automation decision rules

---

## Parallel Example: User Story 1

```text
T009 Add the VS Code Copilot Chat orientation eval fixture at tools/evals/001-agent-tooling-foundation/us1-copilot-chat-orientation.md
T010 Add the Copilot CLI orientation eval fixture at tools/evals/001-agent-tooling-foundation/us1-copilot-cli-orientation.md
T011 Add expected guidance-selection results at tools/evals/001-agent-tooling-foundation/us1-guidance-selection.expected.json
```

```text
T013 Create AGENTS.md
T014 Create .github/instructions/addons.instructions.md
T015 Create .github/instructions/scenarios.instructions.md
T016 Create .github/instructions/tools.instructions.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1
4. Validate orientation behavior in VS Code Copilot Chat and Copilot CLI
5. Stop and confirm the guidance stack reduces repo rediscovery before expanding scope

### Incremental Delivery

1. Deliver shared validation infrastructure
2. Deliver Copilot-first guidance stack and validate it
3. Deliver evidence manifest tooling and validate it
4. Deliver automation decision tooling and write-boundary enforcement
5. Run the full quickstart and decide which artifacts to retain, narrow, or remove

### Parallel Team Strategy

1. One contributor handles shared validation infrastructure in Phase 2
2. One contributor can implement US1 guidance assets while another prepares US2 evidence fixtures after Phase 2
3. US3 can start once the shared automation schemas exist, provided the owner coordinates on shared helper scripts

---

## Notes

- `[P]` means the task is safe to parallelize only if file ownership does not overlap
- All evaluation outputs should be machine-readable and saved under `tools/evals/001-agent-tooling-foundation/`
- Prefer Copilot Chat and Copilot CLI compatibility over generic abstractions when the two conflict
- Keep autonomous write scopes explicit and narrow even though first-release automation is approval-free inside those boundaries