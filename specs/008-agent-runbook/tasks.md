---
description: "Tasks: Agent Runbook & Parameterized Harness Scripts (008-agent-runbook)"
---

# Tasks: Agent Runbook & Parameterized Harness Scripts

**Input**: Design documents from `D:\dev\godot-agent-harness\specs\008-agent-runbook\`
**Branch**: `008-agent-runbook`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Pester coverage is mandatory per FR-014/FR-015. Test tasks are
included for every user story and run against mocked harness helpers
(no live Godot editor required).

**Organization**: Tasks are grouped by user story. Each story is
independently completable, testable, and shippable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (Press Enter), US2 (Scene graph), US3 (Build/Runtime
  error triage — covers build-error-triage AND runtime-error-triage
  recipes/scripts), US4 (Behavior watch)
- File paths are absolute or repo-relative from `D:\dev\godot-agent-harness\`.

## Path Conventions

- Orchestration scripts: `tools/automation/invoke-<workflow>.ps1`
- Recipes: `docs/runbook/<workflow>.md`
- Fixtures: `tools/tests/fixtures/runbook/<workflow>/<name>.json`
- Pester suite: `tools/tests/InvokeRunbookScripts.Tests.ps1`
- Top-level index: `RUNBOOK.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directory skeletons every story will populate, so per-story tasks never have to ensure-directory.

- [ ] T001 Create empty directory `docs/runbook/` with a `.gitkeep` so the path is tracked before any recipe is written
- [ ] T002 [P] Create empty directory `tools/tests/fixtures/runbook/` with subdirectories `input-dispatch/`, `inspect-scene-tree/`, `behavior-watch/`, `build-error-triage/`, `runtime-error-triage/`, each containing a `.gitkeep`
- [ ] T003 [P] Confirm `tools/automation/get-editor-evidence-capability.ps1` and `tools/automation/request-editor-evidence-run.ps1` expose the `Get-RepoRoot` / `Resolve-RepoPath` helpers expected by the foundational module (record findings inline in the foundational task — no new file)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared orchestration core, the stdout-envelope contract surface, and the Pester scaffolding that every per-story script and test will depend on.

**⚠️ CRITICAL**: No user-story work can begin until this phase is complete.

- [ ] T004 Create shared orchestration module `tools/automation/RunbookOrchestration.psm1` exporting:
  - `New-RunbookRequestId -Workflow <string>` (returns `runbook-<workflow>-<UTC-ts>-<short-rand>`)
  - `Test-RunbookCapability -ProjectRoot <string> -MaxAgeSeconds <int>` (invokes `get-editor-evidence-capability.ps1` via an `Invoke-Helper` indirection, then checks `capability.json` mtime; returns a result object with `Ok`/`FailureKind`/`Diagnostic`)
  - `Invoke-RunbookRequest -ProjectRoot <string> -RequestPath <string> -ExpectedRequestId <string> -TimeoutSeconds <int> -PollIntervalMilliseconds <int>` (writes the temp request, calls `request-editor-evidence-run.ps1` via the same indirection, polls `run-result.json` for `requestId` round-trip + `completedAt`, returns the parsed run-result or a timeout failure)
  - `Resolve-RunbookPayload -FixturePath <string> -InlineJson <string> -RequestId <string>` (validates mutual exclusion, loads/parses, overrides `requestId`, returns the materialized payload object plus the temp file path it writes under `<ProjectRoot>/harness/automation/requests/`)
  - `Write-RunbookEnvelope -Status <string> -FailureKind <string?> -ManifestPath <string?> -RunId <string> -RequestId <string> -Diagnostics <string[]> -Outcome <hashtable>` (emits the stdout envelope; throws if it does not validate against `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`)
  - All helper invocations MUST go through a single internal `Invoke-Helper` function so Pester can `Mock` it.
- [ ] T005 [P] Create the Pester scaffolding file `tools/tests/InvokeRunbookScripts.Tests.ps1` that imports `RunbookOrchestration.psm1`, sets up a `BeforeAll` that mocks `Invoke-Helper` for the capability and request helpers, and provides shared fakes for `capability.json` mtime and `run-result.json` content. Include one passing smoke test (`It 'imports the orchestration module' { ... }`) so `pwsh ./tools/tests/run-tool-tests.ps1` keeps passing while later tasks add cases.
- [ ] T006 [P] Create the top-level `RUNBOOK.md` skeleton with the five-row workflow table per `specs/008-agent-runbook/data-model.md`. Rows reference paths that may not exist yet — they will be filled in by per-story tasks. The skeleton MUST have all five rows in the order: Input dispatch, Scene inspection, Behavior watch, Build-error triage, Runtime-error triage.
- [ ] T007 [P] Add `Describe 'RUNBOOK static checks'` block in `tools/tests/InvokeRunbookScripts.Tests.ps1`:
  - Parses `RUNBOOK.md`, validates each row against `specs/008-agent-runbook/contracts/runbook-entry.schema.json` via `tools/validate-json.ps1`, and asserts every row's three referenced paths exist.
  - Scans every `docs/runbook/*.md`, `.github/prompts/godot-runtime-verification.prompt.md`, and `.github/agents/godot-evidence-triage.agent.md` for the substring `addons/agent_runtime_harness/`. Allowed only inside the canonical `<!-- runbook:do-not-read-addon-source -->` marker block. Any other match fails (SC-002).
  - This block will fail until per-story tasks populate the rows; that is expected and is the gating signal for Phase 3+ progress.
- [ ] T008 [P] Document the canonical `<!-- runbook:do-not-read-addon-source -->` callout marker in `docs/runbook/README.md` (a short index page) so per-story recipe authors copy the exact same marker.

**Checkpoint**: Foundation ready — orchestration module, envelope contract, Pester scaffolding, runbook skeleton, and SC-002 static check are all in place. User stories can proceed in parallel.

---

## Phase 3: User Story 1 — "Press Enter in the running game" via one tool call (Priority: P1) 🎯 MVP

**Goal**: A coding agent can dispatch a key (or `InputMap` action) and read the resulting scene state with one orchestration script invocation, using a tracked fixture.

**Independent Test**: From a clean shell, with an editor running against an integration-testing sandbox, run `pwsh ./tools/automation/invoke-input-dispatch.ps1 -ProjectRoot integration-testing/<name> -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json` and observe a single stdout JSON envelope with `status = "success"`, `outcome.dispatchedEventCount >= 1`, and a valid `manifestPath`. Without an editor, `pwsh ./tools/tests/run-tool-tests.ps1` exercises the same script end-to-end via mocked helpers.

### Validation for User Story 1 ⚠️

> Define these checks before implementation and confirm they fail first.

- [ ] T009 [P] [US1] Add Pester `Describe 'invoke-input-dispatch.ps1'` block in `tools/tests/InvokeRunbookScripts.Tests.ps1` covering: required `-ProjectRoot`; mutual exclusion of `-RequestFixturePath` / `-RequestJson`; success envelope shape (validates against `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`); editor-not-running passthrough (`failureKind = "editor-not-running"`, exit code non-zero); build-failure passthrough; runtime-failure passthrough; timeout (`failureKind = "timeout"`); inline `-RequestJson` happy path. All cases use mocked `Invoke-Helper` — no live editor.
- [ ] T010 [P] [US1] Add a JSON-Schema validation case in the same file that loads each `tools/tests/fixtures/runbook/input-dispatch/*.json` file and validates its `inputDispatchScript` payload against `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json` via `tools/validate-json.ps1`.

### Implementation for User Story 1

- [ ] T011 [P] [US1] Create fixture `tools/tests/fixtures/runbook/input-dispatch/press-enter.json` modeled on `tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.healthy.json` with an `inputDispatchScript` that presses `KEY_ENTER` once. `requestId` MUST be a placeholder (e.g., `runbook-input-dispatch-FIXTURE`); the orchestration script overrides it per invocation.
- [ ] T012 [P] [US1] Create fixture `tools/tests/fixtures/runbook/input-dispatch/press-arrow-keys.json` that presses `KEY_LEFT`, `KEY_RIGHT`, `KEY_UP`, `KEY_DOWN` in sequence with default frame spacing.
- [ ] T013 [P] [US1] Create fixture `tools/tests/fixtures/runbook/input-dispatch/press-action.json` that triggers an `InputMap` action (e.g., `ui_accept`) instead of a raw key, demonstrating the action-based dispatch shape.
- [ ] T014 [US1] Create orchestration script `tools/automation/invoke-input-dispatch.ps1` per the contract in `specs/008-agent-runbook/contracts/orchestration-cli.md`:
  - Imports `RunbookOrchestration.psm1`.
  - Implements the 12-step common behavior (capability gate → payload materialization → request → poll → manifest validation → outcome assembly → stdout envelope).
  - Workflow-specific `outcome` block: `outcomesPath` (path to `input-dispatch-outcomes.jsonl` from the manifest's `artifactRefs`), `dispatchedEventCount` (count of lines in that file), `firstFailureSummary` (first non-`success` outcome's message, or `null`).
  - Comment-based help is COMPLETE: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for every parameter, at least one `.EXAMPLE` (FR-008).
  - Stderr summary: `OK: dispatched <N> events; manifest at <path>` on success, `FAIL: <failureKind>; <first diagnostic>` on failure.
- [ ] T015 [US1] Create recipe `docs/runbook/input-dispatch.md` with the 5 required H2 sections (Prerequisites, Run it, Expected output, Failure handling, Anti-patterns) and the optional `Inline payload` section. The Anti-patterns section MUST contain the canonical `<!-- runbook:do-not-read-addon-source -->` marker block.
- [ ] T016 [US1] Update `RUNBOOK.md` row for "Input dispatch" to point at `tools/automation/invoke-input-dispatch.ps1`, `tools/tests/fixtures/runbook/input-dispatch/press-enter.json`, and `docs/runbook/input-dispatch.md`.

**Checkpoint**: User Story 1 is fully functional and testable independently. The static-check Pester block in T007 should now pass for the Input-dispatch row. MVP can be demoed.

---

## Phase 4: User Story 2 — "Inspect the scene graph after launch" via one tool call (Priority: P1)

**Goal**: A coding agent can capture the running game's scene tree with one script invocation and no payload authoring.

**Independent Test**: With an editor running, `pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot integration-testing/<name>` returns a stdout envelope with `outcome.sceneTreePath` pointing at a captured `scene-tree.json` and `outcome.nodeCount > 0`. Mocked end-to-end via Pester.

### Validation for User Story 2 ⚠️

- [ ] T017 [P] [US2] Add Pester `Describe 'invoke-scene-inspection.ps1'` block covering: required `-ProjectRoot`; that `-RequestFixturePath` and `-RequestJson` are NOT exposed (or are no-ops with a documented warning); success envelope shape; editor-not-running passthrough; timeout passthrough. Mocked.

### Implementation for User Story 2

- [ ] T018 [P] [US2] Create fixture stub `tools/tests/fixtures/runbook/inspect-scene-tree/startup-capture.json` containing a comment-only JSON-with-comments-style note that scene inspection takes no payload and the script synthesizes one internally. (Tracked so the fixtures directory is non-empty and discoverable by agents browsing it.)
- [ ] T019 [US2] Create orchestration script `tools/automation/invoke-scene-inspection.ps1`:
  - Imports `RunbookOrchestration.psm1`.
  - Synthesizes a minimal request payload internally (`capturePolicy.startup = true`, no behavior/input fields). No payload parameters exposed.
  - Workflow-specific `outcome` block: `sceneTreePath` (from manifest `artifactRefs` of kind `scene-tree`), `nodeCount` (counted by walking the captured `scene-tree.json`).
  - Complete comment-based help (FR-008).
- [ ] T020 [US2] Create recipe `docs/runbook/inspect-scene-tree.md` with the 5 required H2 sections, `Inline payload` section omitted (no payload). Anti-patterns includes the canonical do-not-read-addon-source marker.
- [ ] T021 [US2] Update `RUNBOOK.md` row for "Scene inspection" with the literal string `no payload` in the Fixture column.

**Checkpoint**: US1 and US2 both pass independently and via the Pester suite.

---

## Phase 5: User Story 3 — "Did the build / runtime error?" surfaced cleanly (Priority: P2)

**Goal**: A coding agent can trigger a run and immediately receive a single `failureKind` plus a pointer to the failing diagnostic, for both build failures and runtime errors. This story covers TWO orchestration scripts (`invoke-build-error-triage.ps1`, `invoke-runtime-error-triage.ps1`) because the spec treats them as a single user-facing capability.

**Independent Test**: With a deliberately broken sandbox, both scripts return `status = "failure"` with the appropriate `failureKind` and an `outcome.firstDiagnostic` / `outcome.latestErrorSummary` pointing at the offending file and line. With a healthy sandbox, both return `status = "success"`. Mocked Pester coverage exercises both paths.

### Validation for User Story 3 ⚠️

- [ ] T022 [P] [US3] Add Pester `Describe 'invoke-build-error-triage.ps1'` block covering: required `-ProjectRoot`; mutual exclusion of payload params; `-IncludeRawBuildOutput` switch toggles `outcome.rawBuildOutputPath`; build-failure passthrough populates `outcome.firstDiagnostic`; healthy run yields `status = "success"`. Mocked.
- [ ] T023 [P] [US3] Add Pester `Describe 'invoke-runtime-error-triage.ps1'` block covering: required `-ProjectRoot`; mutual exclusion of payload params; `-IncludeFullStack` switch toggles full-stack inclusion in `outcome.latestErrorSummary`; runtime-failure passthrough populates `outcome.latestErrorSummary` and `outcome.terminationReason`; healthy run yields `status = "success"`. Mocked.

### Implementation for User Story 3

- [ ] T024 [P] [US3] Create fixture `tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json` modeled on the pong-testbed run-request, with the minimum capture policy needed to surface a build error if one occurs.
- [ ] T025 [P] [US3] Create fixture `tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json` modeled on the pong-testbed run-request, with `pauseOnError = true` (or the spec-007 equivalent) so the broker captures runtime errors.
- [ ] T026 [US3] Create orchestration script `tools/automation/invoke-build-error-triage.ps1`:
  - Imports `RunbookOrchestration.psm1`. Implements the 12-step common behavior.
  - Adds `-IncludeRawBuildOutput` switch parameter.
  - Workflow-specific `outcome`: `rawBuildOutputPath` (string or null), `firstDiagnostic` (`{file, line, message}` or null) sourced from manifest `artifactRefs` of kind `build-error-records`.
  - On build failure, exits non-zero with `failureKind = "build"`. On healthy run, exits 0 with `status = "success"` and `firstDiagnostic = null`.
  - Complete comment-based help.
- [ ] T027 [US3] Create orchestration script `tools/automation/invoke-runtime-error-triage.ps1`:
  - Imports `RunbookOrchestration.psm1`. Implements the 12-step common behavior.
  - Adds `-IncludeFullStack` switch parameter.
  - Workflow-specific `outcome`: `runtimeErrorRecordsPath` (string or null), `latestErrorSummary` (`{file, line, message}` or null) sourced from manifest `artifactRefs` of kind `runtime-error-records`, `terminationReason` (string sourced from manifest summary).
  - On runtime failure, exits non-zero with `failureKind = "runtime"`. On healthy run, exits 0 with `status = "success"`.
  - Complete comment-based help.
- [ ] T028 [P] [US3] Create recipe `docs/runbook/build-error-triage.md` with all 5 required H2 sections, including the canonical do-not-read-addon-source marker in Anti-patterns.
- [ ] T029 [P] [US3] Create recipe `docs/runbook/runtime-error-triage.md` with all 5 required H2 sections, including the canonical do-not-read-addon-source marker in Anti-patterns.
- [ ] T030 [US3] Update `RUNBOOK.md` rows for "Build-error triage" and "Runtime-error triage" with the script, fixture, and recipe paths.

**Checkpoint**: US1, US2, and US3 are all independently functional. Three of the five workflow rows in `RUNBOOK.md` resolve.

---

## Phase 6: User Story 4 — "Watch a value over time" via one tool call (Priority: P3)

**Goal**: A coding agent can sample a node property over a frame window with one script invocation.

**Independent Test**: With an editor running, `pwsh ./tools/automation/invoke-behavior-watch.ps1 -ProjectRoot integration-testing/<name> -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/single-property-window.json` returns a stdout envelope with `outcome.samplesPath` and `outcome.sampleCount > 0`. Mocked Pester coverage included.

### Validation for User Story 4 ⚠️

- [ ] T031 [P] [US4] Add Pester `Describe 'invoke-behavior-watch.ps1'` block covering: required `-ProjectRoot`; mutual exclusion of payload params; success envelope shape with populated `outcome.samplesPath` and `outcome.frameRangeCovered`; editor-not-running passthrough; timeout passthrough. Mocked.
- [ ] T032 [P] [US4] Add JSON-Schema validation case loading `tools/tests/fixtures/runbook/behavior-watch/*.json` and validating their `behaviorWatchRequest` (or wrapped run-request) payloads against `specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json` via `tools/validate-json.ps1`.

### Implementation for User Story 4

- [ ] T033 [P] [US4] Create fixture `tools/tests/fixtures/runbook/behavior-watch/single-property-window.json` modeled on the pong-testbed run-request, embedding a `behaviorWatchRequest` that samples a single deterministic property (e.g., a paddle's `position.y`) over a short frame window.
- [ ] T034 [US4] Create orchestration script `tools/automation/invoke-behavior-watch.ps1`:
  - Imports `RunbookOrchestration.psm1`. Implements the 12-step common behavior.
  - Workflow-specific `outcome`: `samplesPath` (manifest `artifactRefs` of behavior-samples kind), `sampleCount` (count of samples in that artifact), `frameRangeCovered` (`{first, last}`).
  - Complete comment-based help.
- [ ] T035 [US4] Create recipe `docs/runbook/behavior-watch.md` with all 5 required H2 sections, including the canonical do-not-read-addon-source marker in Anti-patterns.
- [ ] T036 [US4] Update `RUNBOOK.md` row for "Behavior watch" with the script, fixture, and recipe paths.

**Checkpoint**: All four user stories functional. All five rows in `RUNBOOK.md` resolve. The static-check Pester block from T007 passes fully.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation-sync surfaces enumerated in Constitution Check (plan.md) and final acceptance gating.

- [ ] T037 [P] Update `.github/copilot-instructions.md` (Validation commands and Path defaults sections) to add the runbook entry-point pointer: read `RUNBOOK.md` first when a runtime workflow is requested. SPECKIT marker block already updated in plan phase — leave it.
- [ ] T038 [P] Update `.github/instructions/tools.instructions.md` to mention the new `tools/automation/invoke-*.ps1` orchestration scripts and the stable stdout-envelope contract at `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json`.
- [ ] T039 [P] Update `.github/prompts/godot-runtime-verification.prompt.md` to instruct the agent to consult `RUNBOOK.md` and prefer the matching `invoke-*.ps1` script over hand-rolling the capability/request/poll loop. Reference recipes in `docs/runbook/`. The substring `addons/agent_runtime_harness/` may appear ONLY inside the canonical `<!-- runbook:do-not-read-addon-source -->` marker block (SC-002).
- [ ] T040 [P] Update `.github/agents/godot-evidence-triage.agent.md` similarly: when an agent is asked to verify runtime behavior, route through `RUNBOOK.md` rather than reading addon sources. Same SC-002 constraint applies.
- [ ] T041 [P] Update `docs/AGENT_RUNTIME_HARNESS.md` to add a short "Agent runbook entry point" subsection pointing at `RUNBOOK.md`, the per-workflow recipes, and the orchestration scripts.
- [ ] T042 [P] Update `docs/AI_TOOLING_AUTOMATION_MATRIX.md` (or the equivalent matrix doc if it exists under `docs/`) to add a column or row for each orchestration script and its stdout envelope contract.
- [ ] T043 [P] Update `tools/README.md` "End-to-end plugin testing" section to mention the runbook scripts as the preferred orchestration entry point for sandbox runs.
- [ ] T044 [P] Update `AGENTS.md` (root) "Validation routing" section to add: when a runtime workflow matches a `RUNBOOK.md` entry, prefer the matching `invoke-*.ps1` script over invoking `get-editor-evidence-capability.ps1` + `request-editor-evidence-run.ps1` directly.
- [ ] T045 [P] Update `addons/agent_runtime_harness/templates/project_root/` agent assets (the prompt and agent files mirrored under that template tree) to match the changes in T039 and T040 so deployed sandboxes pick up the runbook routing.
- [ ] T046 [P] Update `RUNTIME_VERIFICATION_AGENT_UX.md` to add a brief "Phase 1 + Phase 2 implemented" note at the top pointing at this feature's deliverables (`RUNBOOK.md`, `docs/runbook/`, `tools/automation/invoke-*.ps1`). Keep the rest of the document intact.
- [ ] T047 Run `pwsh ./tools/tests/run-tool-tests.ps1` and resolve any failures. Confirm: every `Describe` block from T009/T017/T022/T023/T031 passes; the static-check block from T007 passes for all five rows; SC-002 substring check passes against all updated agent-facing files (T039, T040, T045) and all five recipes.
- [ ] T048 Run `pwsh ./tools/check-addon-parse.ps1` to confirm this feature touched zero addon GDScript (expected exit 0 with no diagnostics; constitution Principle III gate).
- [ ] T049 Execute `specs/008-agent-runbook/quickstart.md` end-to-end against an integration-testing sandbox (live-editor §4 steps), recording the resulting stdout envelopes for each of the five scripts as evidence in the PR description.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup. T004 blocks all per-story implementation. T005/T007 block all per-story validation tasks. T006 blocks T016, T021, T030, T036.
- **User Stories (Phase 3+)**: All depend on Phase 2 completion. After Phase 2:
  - US1, US2, US3, US4 can proceed in **parallel** (no cross-story dependencies).
- **Polish (Phase 7)**: Depends on all four user stories completing.

### User Story Dependencies

- **US1 (P1, MVP)**: depends on Phase 2 only.
- **US2 (P1)**: depends on Phase 2 only. Independent of US1.
- **US3 (P2)**: depends on Phase 2 only. Independent of US1 and US2.
- **US4 (P3)**: depends on Phase 2 only. Independent of US1, US2, US3.

### Within Each User Story

- Validation tasks (Pester `Describe` blocks) are authored *first* and confirmed failing or skipped before the matching script lands.
- Fixtures land before or alongside the script (script reads fixture in tests).
- Recipe lands after the script (recipe documents the script's actual output shape).
- The `RUNBOOK.md` row update is the LAST task of each story (gates the static check from T007).

### Parallel Opportunities

- All Phase 1 [P] tasks (T002, T003) run in parallel with T001.
- All Phase 2 [P] tasks (T005, T006, T007, T008) run in parallel after T004 completes.
- Across stories: US1, US2, US3, US4 can be staffed concurrently after Phase 2.
- Within each story: every `[P]` task on the validation row and on the fixture-creation row is independent.
- All Phase 7 [P] doc-sync tasks (T037–T046) run in parallel.

---

## Parallel Example: User Story 1

```pwsh
# After Phase 2 completes, kick off US1 validation in parallel:
Task: "T009 [P] [US1] Add Describe 'invoke-input-dispatch.ps1' Pester block"
Task: "T010 [P] [US1] Add fixture-payload schema validation case"

# In parallel, author all three input-dispatch fixtures:
Task: "T011 [P] [US1] Create fixture press-enter.json"
Task: "T012 [P] [US1] Create fixture press-arrow-keys.json"
Task: "T013 [P] [US1] Create fixture press-action.json"

# Then sequentially:
Task: "T014 [US1] Create invoke-input-dispatch.ps1"
Task: "T015 [US1] Create docs/runbook/input-dispatch.md"
Task: "T016 [US1] Update RUNBOOK.md row for Input dispatch"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1 (T001–T003).
2. Complete Phase 2 (T004–T008) — orchestration core + Pester scaffolding.
3. Complete Phase 3 (T009–T016) — input dispatch end-to-end.
4. **STOP and VALIDATE**: run `pwsh ./tools/tests/run-tool-tests.ps1`; manually invoke `invoke-input-dispatch.ps1` against an integration-testing sandbox; confirm the stdout envelope.
5. MVP ready — agents can dispatch keys with one tool call.

### Incremental Delivery

1. Setup + Foundational → orchestration core ready.
2. + US1 → Input dispatch shipped (MVP).
3. + US2 → Scene inspection shipped.
4. + US3 → Build/runtime triage shipped (covers TWO scripts in one story).
5. + US4 → Behavior watch shipped.
6. + Polish → all doc-sync surfaces aligned, quickstart executed.

### Parallel Team Strategy

After Phase 2:

- Developer A: US1 (input dispatch).
- Developer B: US2 (scene inspection).
- Developer C: US3 (build + runtime triage — two scripts but one story).
- Developer D: US4 (behavior watch).

All four converge on Phase 7 (polish) once their RUNBOOK row update lands and the T007 static check passes for their row.

---

## Notes

- **Tests**: Pester is mandatory (FR-014/FR-015). Every script has a Pester `Describe` block; all helper invocations are mocked so the suite runs without a Godot editor.
- **Live-editor coverage**: out of scope for CI per research.md. Live coverage is exercised manually via the quickstart and the integration-testing sandbox flow.
- **Constitution Principle III (parse check)**: this feature touches zero addon GDScript; T048 confirms this.
- **SC-002 enforcement**: T007's static-check block is the single deterministic gate. Every recipe and every updated agent-facing file (T039, T040, T045) MUST include the canonical `<!-- runbook:do-not-read-addon-source -->` marker block whenever the substring `addons/agent_runtime_harness/` appears.
- **Stable contracts**: `specs/008-agent-runbook/contracts/orchestration-stdout.schema.json` and `contracts/orchestration-cli.md` are the source of truth. Any per-story script deviation from those contracts is a bug, not a feature.
- **MCP-readiness**: per research.md, every script is a clean subprocess wrapper around the harness loop with a stable stdout envelope. A future MCP server can map each script 1:1 to a tool definition without re-implementing orchestration.
