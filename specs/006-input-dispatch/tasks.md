---

description: "Task list for feature 006-input-dispatch: Runtime Input Dispatch"
---

# Tasks: Runtime Input Dispatch

**Input**: Design documents from `/specs/006-input-dispatch/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Validation tasks produce machine-readable evidence (Pester regression coverage for the new validator and artifact registry entry, plus deterministic Pong editor-evidence runs for dispatch, persistence, and capability gating). Combined validation applies because the feature changes runtime-visible behavior and already has an existing deterministic tool-level test surface.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- File paths are repository-relative and absolute from repo root `D:\dev\godot-agent-harness\`

## Path Conventions

- Addon plugin-first surfaces: `addons/agent_runtime_harness/{shared,editor,runtime}/`
- Contract extension: `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`
- Feature-local contracts and fixtures: `specs/006-input-dispatch/` and `examples/pong-testbed/harness/automation/requests/`
- Evidence registry and capability helper: `tools/evidence/`, `tools/automation/`
- Pester regression coverage: `tools/tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm feature scaffolding and reference alignment before writing any addon, runtime, or contract code.

- [ ] T001 Confirm `specs/006-input-dispatch/` scaffolding is present (plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md) and that `.specify/feature.json` points at `specs/006-input-dispatch`.
- [ ] T002 [P] Confirm the intended Godot integration points (`Input.parse_input_event`, `InputEventKey`, `InputEventAction`, `InputMap`, `Engine.get_process_frames`) against `docs/GODOT_PLUGIN_REFERENCES.md` and record any clarifications inline in `specs/006-input-dispatch/research.md`.
- [ ] T003 [P] Cross-check the existing behavior-watch validator, debugger bridge, runtime session, artifact writer, and automation broker reference trail cited in `specs/006-input-dispatch/plan.md` by opening each file listed under Primary Dependencies to confirm no structural drift has occurred since 005.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the shared schema, artifact registry, capability entry, validator skeleton, and fixture directory layout that every user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Extend the existing automation run request schema at `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` to accept an additive `overrides.inputDispatchScript` property that `$ref`s `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json`, leaving every existing field untouched.
- [ ] T005 [P] Register the new evidence artifact kind in `tools/evidence/artifact-registry.ps1` with `kind = 'input-dispatch-outcomes'`, `file = 'input-dispatch-outcomes.jsonl'`, `mediaType = 'application/jsonl'`, and a description tying it to the input-dispatch feature.
- [ ] T006 [P] Add shared runtime constants for the input-dispatch feature (outcome filename, status enum values `dispatched | skipped_frame_unreached | skipped_run_ended | failed`, rejection reason codes, event-count cap of 256, and debugger message keys) in `addons/agent_runtime_harness/shared/inspection_constants.gd` without disturbing existing constants.
- [ ] T007 [P] Create the `InputDispatchRequestValidator` skeleton in `addons/agent_runtime_harness/shared/input_dispatch_request_validator.gd` with a `normalize_request(request)` entry point returning `{accepted: {...}, rejected: [...]}`, modeled on `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd` and following the literal-const / explicit RegEx typing conventions.
- [ ] T008 [P] Create the deterministic fixture directory `examples/pong-testbed/harness/automation/requests/input-dispatch/` with a placeholder README explaining which per-story fixtures will live there, so later fixture tasks have a stable home.
- [ ] T009 [P] Add a Pester test file `tools/tests/InputDispatchArtifactRegistry.Tests.ps1` that confirms `Get-EvidenceArtifactDefinitions` includes the new `input-dispatch-outcomes` kind with the expected file name and media type.

**Checkpoint**: Foundation ready — schema, registry, constants, validator skeleton, fixture directory, and registry regression coverage are in place; user-story phases can now proceed.

---

## Phase 3: User Story 1 — Declare A Deterministic Input Script (Priority: P1) 🎯 MVP

**Goal**: An agent can submit a deterministic input-dispatch script (keyboard `Key` enum events and declared `InputMap` action events, press/release phases, process-frame anchor, ≤256 events) as part of an automation run request and receive strict machine-readable acceptance or rejection before the playtest launches.

**Independent Test**: Running `pwsh ./tools/tests/run-tool-tests.ps1` exercises the validator against a valid Pong numpad-Enter script and invalid fixtures for each rejection code; all accepted scripts normalize into an applied-input-dispatch summary, and all invalid scripts reject with the correct code before any playtest is launched.

### Validation for User Story 1 ⚠️

> Define these checks before implementation and confirm they fail or are incomplete first.

- [ ] T010 [P] [US1] Add Pester coverage `tools/tests/InputDispatchRequestValidator.Tests.ps1` that invokes the validator (via the existing GDScript-invocation test harness pattern used by `BehaviorWatchRequestValidator` tests, or an equivalent fixture-driven contract check) against one valid Pong numpad-Enter fixture and one invalid fixture per rejection code (`missing_field`, `unsupported_field`, `later_slice_field`, `unsupported_identifier`, `unmatched_release`, `script_too_long`, `invalid_phase`, `invalid_frame`, `duplicate_event`).
- [ ] T011 [P] [US1] Add a JSON Schema validation test in the same Pester file that confirms every fixture under `examples/pong-testbed/harness/automation/requests/input-dispatch/` whose filename starts with `valid-` conforms to `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json` via `pwsh ./tools/validate-json.ps1`.

### Implementation for User Story 1

- [ ] T012 [P] [US1] Implement the full `InputDispatchRequestValidator` rules in `addons/agent_runtime_harness/shared/input_dispatch_request_validator.gd`: enforce required fields, the 256-event cap (`script_too_long`), logical `Key` enum whitelist for `kind = key` (`unsupported_identifier`), declared-`InputMap`-action check for `kind = action` (`unsupported_identifier`), `press|release` phase (`invalid_phase`), non-negative integer `frame` (`invalid_frame`), duplicate-event detection (`duplicate_event`), press/release matching (`unmatched_release`), and later-slice rejection of `mouse`, `touch`, `gamepad`, `recordedReplay`, `physicalKeycode`, and `physicsFrame` (`later_slice_field`).
- [ ] T013 [P] [US1] Add the valid Pong numpad-Enter fixture `examples/pong-testbed/harness/automation/requests/input-dispatch/valid-numpad-enter.json` matching the example shape in `specs/006-input-dispatch/quickstart.md` (press at frame 30, release at frame 32, `KP_ENTER`).
- [ ] T014 [P] [US1] Add one invalid fixture per rejection code in `examples/pong-testbed/harness/automation/requests/input-dispatch/` with filenames `invalid-<reason>.json` (`invalid-script-too-long.json`, `invalid-unsupported-identifier.json`, `invalid-unmatched-release.json`, `invalid-later-slice-mouse.json`, `invalid-invalid-phase.json`, `invalid-invalid-frame.json`, `invalid-duplicate-event.json`, `invalid-missing-field.json`, `invalid-unsupported-field.json`).
- [ ] T015 [US1] Extend the editor-side run coordinator in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` to load `overrides.inputDispatchScript` from the incoming automation request, invoke `InputDispatchRequestValidator.normalize_request(...)`, short-circuit the run with a machine-readable rejection payload on any rejection, and otherwise attach the normalized applied-input-dispatch summary to the run metadata.
- [ ] T016 [US1] Propagate the normalized applied-input-dispatch summary through the existing `configure_session` debugger message in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd` and store it on the runtime session in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` under a new `input_dispatch_script` field (snake_case in runtime context, camelCase in the debugger payload per repo naming convention).
- [ ] T017 [US1] Update `specs/006-input-dispatch/contracts/input-dispatch-contract.md` if any validator rejection code is renamed or added during implementation, so the contract stays authoritative.

**Checkpoint**: At this point, User Story 1 should be fully functional — valid scripts normalize and reach the runtime, invalid scripts reject with machine-readable codes before launch.

---

## Phase 4: User Story 2 — Dispatch Events Through The Real Input Pipeline (Priority: P1)

**Goal**: The runtime addon delivers each accepted event at its declared process frame through `Input.parse_input_event()` using `InputEventKey` or `InputEventAction`, so the game's `_input`, `_unhandled_input`, and `Input.is_action_*` handlers observe the event as a genuine keypress — including the Pong numpad-Enter `_unhandled_input` crash described in issue #12.

**Independent Test**: Running the Pong numpad-Enter fixture through `pwsh ./tools/automation/request-editor-evidence-run.ps1` reaches the `_unhandled_input` crash path from issue #12 (diagnostics capture the failure), and a synthetic non-crashing scene confirms `Input.is_action_pressed` observes the state change on the dispatched frame.

### Validation for User Story 2 ⚠️

- [ ] T018 [P] [US2] Add Pester coverage `tools/tests/InputDispatchRuntimeDispatcher.Tests.ps1` that (a) runs the Pong numpad-Enter fixture via the existing editor-evidence automation helper and asserts the resulting run-result JSON records a crash consistent with issue #12, and (b) runs a non-crashing fixture (to be added in T021) and asserts the diagnostics surface the expected action-pressed observation.
- [ ] T019 [P] [US2] Add a quickstart validation step in `specs/006-input-dispatch/quickstart.md` (if not already present) that describes how to manually confirm `_unhandled_input` was invoked by inspecting the diagnostics artifact after running the numpad-Enter fixture.

### Implementation for User Story 2

- [ ] T020 [P] [US2] Add a new runtime dispatcher script `addons/agent_runtime_harness/runtime/input_dispatch_runtime.gd` that: captures a process-frame baseline on its first `_process()` tick, maintains the normalized event queue sorted by `(frame, order, declaredIndex)`, drains every event whose effective frame `<= Engine.get_process_frames() - baseline` on each `_process()` tick, constructs the appropriate `InputEventKey` (setting `keycode` from the `Key` enum, `pressed` from phase, `echo = false`) or `InputEventAction` (setting `action` and `pressed`), calls `Input.parse_input_event(event)`, and records a per-event outcome via the artifact writer.
- [ ] T021 [P] [US2] Add a non-crashing Pong fixture `examples/pong-testbed/harness/automation/requests/input-dispatch/valid-action-accept.json` that dispatches a declared `ui_accept`-like action press/release pair a few frames into a scene that simply records `Input.is_action_pressed` into a diagnostics field, to prove the real-pipeline path without depending on the crash.
- [ ] T022 [US2] Wire `input_dispatch_runtime.gd` into the existing runtime autoload / session lifecycle in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` so it activates when the session configuration carries an applied input-dispatch summary, and tears down cleanly at run shutdown including release-on-shutdown safety accounting per FR-010.
- [ ] T023 [US2] Enforce FR-009 by forbidding any code path in the runtime dispatcher or the editor coordinator from invoking game signals, autoload methods, or OS-level key injection as a substitute for `Input.parse_input_event`; document the guardrail with a comment block that cites FR-008 and FR-009.

**Checkpoint**: Both US1 and US2 are functional — valid scripts reach the runtime and dispatch through the real input pipeline; the Pong numpad-Enter crash reproduces end-to-end.

---

## Phase 5: User Story 3 — Persist Per-Event Outcomes In The Evidence Bundle (Priority: P2)

**Goal**: Every declared event produces exactly one row in a fixed `input-dispatch-outcomes.jsonl` artifact referenced from the current run's manifest-centered evidence bundle, including partial-run rows when the playtest crashes mid-script, and stale artifacts from earlier runs are never reused.

**Independent Test**: After running the Pong numpad-Enter fixture, `pwsh ./tools/evidence/validate-evidence-manifest.ps1 -ManifestPath <manifest>` passes, the manifest references `input-dispatch-outcomes.jsonl`, the JSONL file contains one row per declared event with the fixed status enum, and a follow-up run in the same output directory replaces the artifact rather than inheriting the previous run's rows.

### Validation for User Story 3 ⚠️

- [ ] T024 [P] [US3] Add Pester coverage `tools/tests/InputDispatchOutcomeArtifact.Tests.ps1` that runs the Pong numpad-Enter fixture and asserts (a) the manifest references `input-dispatch-outcomes` with the expected file and media type, (b) the JSONL file contains exactly two rows with `kind = key`, `identifier = KP_ENTER`, and `status` drawn from the fixed enum, and (c) each row conforms to `specs/006-input-dispatch/contracts/input-dispatch-outcome-row.schema.json` via `pwsh ./tools/validate-json.ps1`.
- [ ] T025 [P] [US3] Add a stale-artifact regression test in the same Pester file that pre-seeds `input-dispatch-outcomes.jsonl` with rows from a fake prior run, executes a fresh run in the same output directory, and asserts the post-run file contains only the current run's `runId`.

### Implementation for User Story 3

- [ ] T026 [P] [US3] Extend `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd` with an `append_input_dispatch_outcome(row)` method that writes one JSONL row with the fields `runId`, `eventIndex`, `declaredFrame`, `dispatchedFrame`, `kind`, `identifier`, `phase`, `status`, and optional `reasonCode` / `reasonMessage`, and a `finalize_input_dispatch_outcomes()` method that flushes pending rows and registers the artifact reference with the manifest writer.
- [ ] T027 [P] [US3] Call the new writer methods from `input_dispatch_runtime.gd` (from T020) for every dispatched, failed, or skipped event, and ensure the finalize call runs even when the playtest is shutting down due to an error (use `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` / `_exit_tree` guardrails consistent with the existing artifact writer shutdown path).
- [ ] T028 [US3] Update the manifest writer path in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd` (and any editor-side manifest consolidator) to reference the new `input-dispatch-outcomes` artifact kind alongside `scenegraph-snapshot`, `scenegraph-diagnostics`, `scenegraph-summary`, and `trace`, and truncate the target file at the start of the run to enforce the FR-014 freshness rule.
- [ ] T029 [US3] Update `tools/evidence/validate-evidence-manifest.ps1` (or confirm no change is needed because the registry entry from T005 is sufficient) so the manifest validator recognizes the new artifact kind when present.

**Checkpoint**: All three stories are functional — valid scripts are dispatched through the real input pipeline and persisted into a manifest-referenced JSONL artifact including partial-run rows.

---

## Phase 6: User Story 4 — Advertise Input Dispatch Capability Before Request (Priority: P3)

**Goal**: Agents can detect whether input dispatch is supported on the current editor and platform by reading the existing capability artifact, and the harness rejects input-dispatch requests on unsupported environments with a machine-readable reason consistent with the advertised capability.

**Independent Test**: `pwsh ./tools/automation/get-editor-evidence-capability.ps1 -ProjectRoot examples/pong-testbed` reports `inputDispatch.supported = true` with `supportedKinds = ["key", "action"]`, and a forced-unsupported configuration causes a submitted request to reject with a code that matches the advertised capability `reason`.

### Validation for User Story 4 ⚠️

- [ ] T030 [P] [US4] Add Pester coverage `tools/tests/InputDispatchCapability.Tests.ps1` that (a) asserts the capability artifact produced by `tools/automation/get-editor-evidence-capability.ps1` includes an `inputDispatch` entry with `supported`, optional `reason`, and `supportedKinds = ["key", "action"]`, and (b) forces `supported = false` through a fixture or environment override and asserts a submitted request rejects with a code aligned with the advertised `reason`.

### Implementation for User Story 4

- [ ] T031 [P] [US4] Publish the new `inputDispatch` capability entry from the editor-side broker in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` with fields `supported` (boolean), optional `reason` (short machine-readable string), and `supportedKinds = ["key", "action"]`.
- [ ] T032 [P] [US4] Update `tools/automation/get-editor-evidence-capability.ps1` to surface the new `inputDispatch` capability entry as a first-class property on the returned capability object so PowerShell consumers do not have to dig through a generic bag.
- [ ] T033 [US4] Add capability-gating to `InputDispatchRequestValidator` (or to the run coordinator call site from T015) so that when capability reports `supported = false`, the validator rejects with `capability_unsupported` and includes the advertised `reason` in the rejection payload.

**Checkpoint**: All four user stories are independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, aggregate validation, and link-through of the new evidence surface into existing agent-facing docs.

- [ ] T034 [P] Update `docs/AGENT_RUNTIME_HARNESS.md` (and `docs/BEHAVIOR_CAPTURE_SLICES.md` if appropriate) to list `input-dispatch-outcomes.jsonl` alongside the existing scenegraph, diagnostics, summary, and trace artifacts and to mention the new capability entry.
- [ ] T035 [P] Update `docs/AGENT_TOOLING_FOUNDATION.md` (or the corresponding agent workflow doc) to mention the deterministic Pong numpad-Enter reproduction as the canonical runtime-verification example for input-driven behavior.
- [ ] T036 [P] Update the Pong testbed README at `examples/pong-testbed/README.md` (if it exists) to list the new `input-dispatch/` request fixtures and link to the quickstart reproduction steps.
- [ ] T037 Run `pwsh ./tools/tests/run-tool-tests.ps1` and confirm all new Pester files pass alongside the existing suite.
- [ ] T038 Run the quickstart reproduction end-to-end from `specs/006-input-dispatch/quickstart.md` against `examples/pong-testbed/` and confirm the manifest references the new artifact, the JSONL file is well-formed, and `pwsh ./tools/evidence/validate-evidence-manifest.ps1` passes.
- [ ] T039 Re-run the Constitution Check from `specs/006-input-dispatch/plan.md` against the final implementation and record any deltas in the plan's Post-Design Constitution Check section.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories.
- **User Story 1 (Phase 3, P1)**: Depends on Foundational. Produces the validator and applied summary that US2/US3/US4 all rely on.
- **User Story 2 (Phase 4, P1)**: Depends on Foundational and on US1 (needs the applied summary and the `configure_session` plumbing to reach the runtime).
- **User Story 3 (Phase 5, P2)**: Depends on Foundational and on US2 (needs the runtime dispatcher to produce outcome rows).
- **User Story 4 (Phase 6, P3)**: Depends on Foundational and on US1 (reuses the validator; runs independently from US2/US3).
- **Polish (Phase 7)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **US1 (P1)** is the MVP core and unlocks US2/US3/US4.
- **US2 (P1)** requires the applied summary to reach the runtime (built in US1); independent otherwise.
- **US3 (P2)** requires dispatched events to exist to write outcome rows; builds strictly on US2.
- **US4 (P3)** depends only on US1's validator; can run in parallel with US2/US3 once US1 is done.

### Within Each User Story

- Validation tasks MUST be written first and confirmed failing or incomplete before implementation.
- Runtime artifact production lands with the feature, not as a later cleanup step.
- Core implementation before integration.
- Story complete before moving to next priority.

### Parallel Opportunities

- Setup: T002 and T003 are `[P]`.
- Foundational: T005, T006, T007, T008, T009 are `[P]` (different files).
- US1 validation: T010 and T011 are `[P]`.
- US1 implementation: T012, T013, T014 are `[P]`; T015 and T016 are sequential because they edit integration points in order.
- US2 validation: T018 and T019 are `[P]`.
- US2 implementation: T020 and T021 are `[P]`; T022/T023 integrate.
- US3 validation: T024 and T025 are `[P]`.
- US3 implementation: T026 and T027 are `[P]`; T028/T029 finalize manifest integration.
- US4 validation: T030.
- US4 implementation: T031 and T032 are `[P]`; T033 integrates.
- Polish: T034, T035, T036 are `[P]`.

---

## Parallel Example: User Story 1

```bash
# Launch validation for User Story 1 together:
Task: "Add Pester coverage in tools/tests/InputDispatchRequestValidator.Tests.ps1"
Task: "Add JSON Schema validation test for input-dispatch script fixtures"

# Launch parallel implementation for User Story 1:
Task: "Implement InputDispatchRequestValidator rules in addons/agent_runtime_harness/shared/input_dispatch_request_validator.gd"
Task: "Add the valid Pong numpad-Enter fixture under examples/pong-testbed/harness/automation/requests/input-dispatch/"
Task: "Add one invalid fixture per rejection code under the same directory"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2 — both P1)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 3: User Story 1 (declaration, validation, normalization, applied summary plumbing).
4. Complete Phase 4: User Story 2 (runtime dispatch through real input pipeline, Pong numpad-Enter reproduction for issue #12).
5. **STOP and VALIDATE**: Confirm the Pong numpad-Enter crash reproduces end-to-end through the brokered contract.
6. Deploy/demo if ready.

### Incremental Delivery

1. Setup + Foundational → Foundation ready.
2. US1 → validator normalizes scripts; test independently.
3. US2 → runtime dispatches through `Input.parse_input_event`; reproduces issue #12; deploy/demo.
4. US3 → outcomes persist as JSONL referenced from the manifest.
5. US4 → capability advertisement and capability-gated rejection.
6. Polish → doc updates and aggregate validation.

### Parallel Team Strategy

With multiple developers once Foundational is done:

1. Developer A: US1 → US2 (the P1 reproduction path).
2. Developer B: US3 once US2 dispatcher lands (outcome persistence).
3. Developer C: US4 in parallel with US3 (capability surface).

---

## Notes

- `[P]` tasks touch different files and have no incomplete dependencies.
- `[Story]` labels map tasks back to `specs/006-input-dispatch/spec.md` user stories for traceability.
- Each user story is independently completable and testable with Pester plus a deterministic Pong run.
- Verify validation fails or is incomplete before implementing.
- Commit after each task or logical group per the repository convention.
- Stop at any checkpoint to validate story independently.
- Avoid: vague tasks, same-file conflicts, cross-story dependencies that break independence, and any code path that substitutes `Input.parse_input_event` with autoload shims, direct method calls, or OS-level keystroke injection (forbidden by FR-009).
