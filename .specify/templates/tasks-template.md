---

description: "Task list template for feature implementation"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Every user story MUST include executable validation tasks. At minimum,
include deterministic scenario runs, invariant checks, or automated tests that
produce machine-readable evidence for agents.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Single project**: `src/`, `tests/` at repository root
- **Web app**: `backend/src/`, `frontend/src/`
- **Mobile**: `api/src/`, `ios/src/` or `android/src/`
- Paths shown below assume single project - adjust based on plan.md structure

<!-- 
  ============================================================================
  IMPORTANT: The tasks below are SAMPLE TASKS for illustration purposes only.
  
  The /speckit.tasks command MUST replace these with actual tasks based on:
  - User stories from spec.md (with their priorities P1, P2, P3...)
  - Feature requirements from plan.md
  - Entities from data-model.md
  - Endpoints from contracts/
  
  Tasks MUST be organized by user story so each story can be:
  - Implemented independently
  - Tested independently
  - Delivered as an MVP increment
  
  DO NOT keep these sample tasks in the generated tasks.md file.
  ============================================================================
-->

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, reference capture, and basic structure

- [ ] T001 Create project structure per implementation plan
- [ ] T002 Capture internal and external references in specs/[###-feature-name]/research.md
- [ ] T003 [P] Confirm the intended Godot integration points against docs/GODOT_PLUGIN_REFERENCES.md and any inspected ../godot sources relative to the repository root
- [ ] T004 [P] Configure formatting, linting, or editor tooling needed for the selected implementation path

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

Examples of foundational tasks (adjust based on your project):

- [ ] T005 Establish shared runtime artifact locations and naming conventions
- [ ] T006 [P] Implement baseline tracing, event, or summary plumbing needed across stories
- [ ] T007 [P] Create shared scenario fixtures, test helpers, or invariant utilities
- [ ] T008 Configure error handling and structured logging infrastructure
- [ ] T009 Document any approved escalation beyond addon/debugger layers in the plan

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - [Title] (Priority: P1) 🎯 MVP

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Validation for User Story 1 ⚠️

> **NOTE: Define these checks before implementation and confirm they fail or are incomplete first**

- [ ] T010 [P] [US1] Add deterministic scenario or automated test covering the story
- [ ] T011 [P] [US1] Add invariant or artifact validation for the expected runtime evidence

### Implementation for User Story 1

- [ ] T012 [P] [US1] Implement the story in the appropriate addon, runtime, or tool file
- [ ] T013 [P] [US1] Emit the machine-readable runtime artifacts the story requires
- [ ] T014 [US1] Wire the feature into the selected Godot extension point or scenario flow
- [ ] T015 [US1] Add validation and error handling
- [ ] T016 [US1] Document any new references or engine findings discovered during implementation

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - [Title] (Priority: P2)

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Validation for User Story 2 ⚠️

- [ ] T017 [P] [US2] Add deterministic scenario or automated test covering the story
- [ ] T018 [P] [US2] Add invariant or artifact validation for the expected runtime evidence

### Implementation for User Story 2

- [ ] T019 [P] [US2] Implement the story in the appropriate addon, runtime, or tool file
- [ ] T020 [P] [US2] Emit the machine-readable runtime artifacts the story requires
- [ ] T021 [US2] Integrate with existing scenario, debugger, or editor plugin flows as needed
- [ ] T022 [US2] Document any new references or engine findings discovered during implementation

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - [Title] (Priority: P3)

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Validation for User Story 3 ⚠️

- [ ] T023 [P] [US3] Add deterministic scenario or automated test covering the story
- [ ] T024 [P] [US3] Add invariant or artifact validation for the expected runtime evidence

### Implementation for User Story 3

- [ ] T025 [P] [US3] Implement the story in the appropriate addon, runtime, or tool file
- [ ] T026 [P] [US3] Emit the machine-readable runtime artifacts the story requires
- [ ] T027 [US3] Integrate with existing scenario, debugger, or editor plugin flows as needed
- [ ] T028 [US3] Document any new references or engine findings discovered during implementation

**Checkpoint**: All user stories should now be independently functional

---

[Add more user story phases as needed, following the same pattern]

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] TXXX [P] Documentation updates in docs/
- [ ] TXXX Code cleanup and refactoring
- [ ] TXXX Performance optimization across all stories
- [ ] TXXX [P] Extend automated coverage or scenario depth where evidence is still weak
- [ ] TXXX Security hardening
- [ ] TXXX Run quickstart.md validation

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - May integrate with US1/US2 but should be independently testable

### Within Each User Story

- Validation tasks MUST be defined and shown failing or incomplete before implementation
- Runtime artifact production must land with the feature, not as a later cleanup step
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- All validation tasks for a user story marked [P] can run in parallel
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Launch validation for User Story 1 together:
Task: "Add deterministic scenario or automated test covering the story"
Task: "Add invariant or artifact validation for the expected runtime evidence"

# Launch implementation for User Story 1 together when file ownership allows:
Task: "Implement the story in the appropriate addon, runtime, or tool file"
Task: "Emit the machine-readable runtime artifacts the story requires"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify validation fails or is incomplete before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
