---

description: "Task list for 009-evidence-lifecycle — run-artifact cleanup, pinning, git hygiene"
---

# Tasks: Run-Artifact Evidence Lifecycle

**Input**: Design documents in [/specs/009-evidence-lifecycle/](./)
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md) — all present

**Tests**: Every user story MUST include executable validation tasks (Pester, `git status --porcelain` assertions, schema validations) — per constitution §III and the spec's Independent Test clauses.

**Organization**: Tasks are grouped by user story so each story can be implemented, tested, and merged independently. US1 and US2 together form the MVP (clean slate + git hygiene); US3 and US4 add the pin affordance and documentation synchronization.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User-story tag (US1, US2, US3, US4). Setup/Foundational/Polish phases carry no story tag.
- Paths are repository-root-relative.

## Path Conventions

- PowerShell source: [tools/automation/](../../tools/automation/)
- PowerShell tests: [tools/tests/](../../tools/tests/)
- Schemas for this feature: [specs/009-evidence-lifecycle/contracts/](./contracts/)
- Deployed-project template: [addons/agent_runtime_harness/templates/project_root/](../../addons/agent_runtime_harness/templates/project_root/)
- Agent-facing docs at repo root and under [docs/](../../docs/)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm references, wire the feature's schemas into the repo's validation tooling, and record the current accidentally-tracked-files baseline before any changes.

- [ ] T001 Capture the exact list of files to be purged by running `git ls-files tools/tests/fixtures/pong-testbed/evidence/ tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json` and writing the output to [specs/009-evidence-lifecycle/research.md](./research.md) §"Cross-cutting: migration" as a verbatim block — this is the FR-004 baseline.
- [ ] T002 [P] Confirm against [docs/GODOT_PLUGIN_REFERENCES.md](../../docs/GODOT_PLUGIN_REFERENCES.md) and an inspection of [../godot](../../../godot) that no new Godot API surface is touched; add a one-line note to the plan's Constitution Check if any surprise surfaces (none expected per FR-011).
- [ ] T003 [P] Register the three new schemas under [specs/009-evidence-lifecycle/contracts/](./contracts/) with the repo's JSON-schema-validation harness by adding them to whatever schema index [tools/validate-json.ps1](../../tools/validate-json.ps1) uses (no code change to the validator itself — only the index/catalog it reads).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared PowerShell primitives every user story depends on — the zone classification, the in-flight marker, the cleanup helper, the lifecycle envelope writer — plus the `.gitignore` rules that US2 will actually land.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. US1 integrates these primitives into each `invoke-*.ps1`; US2 relies on the gitignore block landed here; US3 reuses the envelope and marker primitives.

- [ ] T004 Add the `Get-RunZoneClassification` function to [tools/automation/RunbookOrchestration.psm1](../../tools/automation/RunbookOrchestration.psm1), returning the FR-001 table from [data-model.md](./data-model.md) §"Classification table" as a static hashtable keyed by filename glob → zone enum (`transient | pinned | oracle | input`). This is the single-source-of-truth FR-001 requires.
- [ ] T005 Add `New-RunbookInFlightMarker`, `Clear-RunbookInFlightMarker`, and `Test-InFlightMarkerStaleness` to [tools/automation/RunbookOrchestration.psm1](../../tools/automation/RunbookOrchestration.psm1) conforming to [contracts/in-flight-marker.schema.json](./contracts/in-flight-marker.schema.json) and the staleness rules from [research.md](./research.md) §2 (alive-PID check + 2× timeout horizon).
- [ ] T006 Add `Initialize-RunbookTransientZone` to [tools/automation/RunbookOrchestration.psm1](../../tools/automation/RunbookOrchestration.psm1) implementing the two-step clear from [research.md](./research.md) §1 — per-file delete with one 50 ms retry, `.in-flight.json` explicitly skipped, partial-failure surfaces into the caller's diagnostics (never silent; FR-010).
- [ ] T007 Extend `Write-RunbookEnvelope` in [tools/automation/RunbookOrchestration.psm1](../../tools/automation/RunbookOrchestration.psm1) to emit envelopes conforming to [contracts/lifecycle-envelope.schema.json](./contracts/lifecycle-envelope.schema.json) when the caller supplies a lifecycle `operation` — reusing the shared core fields and accepting the `operation`, `dryRun`, `plannedPaths[]`, `pinName`, `pinnedRunIndex[]` extensions.
- [ ] T008 [P] Update [.gitignore](../../.gitignore) with the exact block from [research.md](./research.md) §4 (`**/harness/automation/results/`, `**/harness/automation/pinned/`, `**/evidence/automation/`, with the `!**/harness/automation/results/*.expected.json` re-include). Verify with `git check-ignore -v` the four canonical paths listed in research §4.
- [ ] T009 [P] Mirror the same block into [addons/agent_runtime_harness/templates/project_root/.gitignore](../../addons/agent_runtime_harness/templates/project_root/.gitignore) so deployed projects inherit the hygiene rules without per-project authoring.
- [ ] T010 [P] Add write-boundary entries to [tools/automation/write-boundaries.json](../../tools/automation/write-boundaries.json) covering the new pinned-zone path pattern `*/harness/automation/pinned/**` with `allowedEditTypes: ["create"]` (pin-copy) and `*/harness/automation/pinned/<pin-name>/**` with `allowedEditTypes: ["create", "update"]` for unpin-force, matching [tools/automation/write-boundaries.schema.json](../../tools/automation/write-boundaries.schema.json).
- [ ] T011 Add Pester coverage for the Foundational primitives in a new file [tools/tests/EvidenceLifecycleCore.Tests.ps1](../../tools/tests/EvidenceLifecycleCore.Tests.ps1) — `Get-RunZoneClassification` returns expected map, marker round-trip, staleness detection on dead-PID fixtures, `Initialize-RunbookTransientZone` against a temp-dir sandbox asserts only transient-classified files are deleted.

**Checkpoint**: Foundation ready — user story implementation can begin. The `.gitignore` is already landed, but the 14 tracked files remain in the index until US2.

---

## Phase 3: User Story 1 — Clean slate before every run (Priority: P1) 🎯 MVP-part-1

**Goal**: Every orchestration script clears the transient zone and writes an in-flight marker before dispatching the new request. A second concurrent invocation fails fast with `failureKind: "run-in-progress"`.

**Independent Test**: Pester test runs `invoke-input-dispatch.ps1` twice in a row against a mocked sandbox, asserts no field value from run-1's `run-result.json` appears in run-2's. Separately, a concurrent-invocation test asserts the second call exits with a `lifecycle-envelope.schema.json`-conformant refusal envelope naming run-1's requestId.

### Validation for User Story 1

- [ ] T012 [P] [US1] Add Pester test "stale files cleared before second run" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — dispatches two different fixture requests back-to-back against a `TestDrive:` sandbox with a seeded prior `run-result.json`, asserts the second envelope's `run-result.json` has no field values from the first.
- [ ] T013 [P] [US1] Add Pester test "concurrent invocation refused" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — writes a fake `.in-flight.json` with a live-PID marker, invokes any orchestration script, asserts stdout envelope has `status: "refused"`, `failureKind: "run-in-progress"`, and the existing requestId in `diagnostics[0]`.
- [ ] T014 [P] [US1] Add Pester test "stale marker auto-recovers" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — seeds a marker with a dead PID and old `startedAt`, invokes a script, asserts normal dispatch proceeds and `diagnostics[]` includes a "recovered from stale marker" note.
- [ ] T015 [P] [US1] Add Pester test "cleanup-blocked halts dispatch" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — stages a locked file in the transient zone, asserts the script exits before dispatch with `status: "failed"`, `failureKind: "cleanup-blocked"`, and the locked path in `diagnostics[]` (FR-010).

### Implementation for User Story 1

- [ ] T016 [US1] Integrate the Foundational primitives into [tools/automation/invoke-input-dispatch.ps1](../../tools/automation/invoke-input-dispatch.ps1): call `Assert-NoInFlightRun` → `New-RunbookInFlightMarker` → `Initialize-RunbookTransientZone` before the existing `Test-RunbookCapability` call; wrap the script body in `try { ... } finally { Clear-RunbookInFlightMarker }`.
- [ ] T017 [P] [US1] Apply the same integration to [tools/automation/invoke-scene-inspection.ps1](../../tools/automation/invoke-scene-inspection.ps1).
- [ ] T018 [P] [US1] Apply the same integration to [tools/automation/invoke-behavior-watch.ps1](../../tools/automation/invoke-behavior-watch.ps1).
- [ ] T019 [P] [US1] Apply the same integration to [tools/automation/invoke-build-error-triage.ps1](../../tools/automation/invoke-build-error-triage.ps1) and [tools/automation/invoke-runtime-error-triage.ps1](../../tools/automation/invoke-runtime-error-triage.ps1) (distinct files — both marked [P] relative to each other and to T016–T018).

**Checkpoint**: US1 validates independently. Transient zone is self-cleaning and self-serialized. No doc changes yet — that's US4's job.

---

## Phase 4: User Story 2 — Run output never reaches git (Priority: P1) 🎯 MVP-part-2

**Goal**: The 14 accidentally-tracked run artifacts are removed from the index, future runs leave `git status` clean, and CI enforces it.

**Independent Test**: `git ls-files tools/tests/fixtures/pong-testbed/evidence/ tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json` returns empty after the change. Running any canonical `invoke-*.ps1` then executing `git status --porcelain` returns empty relative to the transient and pinned zones. (US1 must merge first so runs actually produce the ignored files.)

### Validation for User Story 2

- [ ] T020 [P] [US2] Add Pester test "canonical runs produce zero git diff" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — sets up a throwaway git-init inside `TestDrive:`, seeds the new `.gitignore` block, runs a mocked orchestration that writes the canonical output filenames, asserts `git status --porcelain` returns empty.
- [ ] T021 [P] [US2] Add Pester test "oracle files still tracked" to [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) — same harness, places a `run-result.success.expected.json` under `harness/automation/results/`, asserts `git check-ignore` reports it *not* ignored.

### Implementation for User Story 2

- [ ] T022 [US2] Execute `git rm --cached` on the 14 files captured in T001's baseline (the 13 under `tools/tests/fixtures/pong-testbed/evidence/**` and `tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json`). Stage the removals together with the Foundational-phase `.gitignore` edit so no intermediate commit leaves them ignored-but-tracked.
- [ ] T023 [US2] Re-run the full Pester suite via `pwsh ./tools/tests/run-tool-tests.ps1` to confirm the `*.expected.json` oracles under `tools/tests/fixtures/pong-testbed/harness/automation/results/` still resolve correctly for the existing suite — the removed files must not have been silent dependencies.
- [ ] T024 [US2] Add a CI-runnable assertion in [tools/tests/InvokeRunbookScripts.Tests.ps1](../../tools/tests/InvokeRunbookScripts.Tests.ps1) (or a new sibling) that after the canonical workflow invocations complete in the test sandbox, `git status --porcelain` relative to the sandbox subtree is empty — this is the SC-001 gate.

**Checkpoint**: MVP complete. US1 + US2 together deliver the core complaint (stale files + git noise). US3/US4 add the pin affordance and the documentation story.

---

## Phase 5: User Story 3 — Deliberately preserve a prior run (Priority: P2)

**Goal**: Three new `invoke-*.ps1` scripts (pin, unpin, list) let an agent name a run, keep it across future cleanups, and enumerate pins on demand. Pinned-run contents include the orchestration-level `run-result.json` / `lifecycle-status.json` (per clarification Q5) and are byte-identical copies.

**Independent Test**: Pester invokes a workflow, pins the result under "baseline", invokes the workflow again, lists pins, asserts the pin's files are byte-identical to the first run's outputs and the live transient zone reflects the second run only. Pin-name collision refusal and `-Force` overwrite both tested.

### Validation for User Story 3

- [ ] T025 [P] [US3] Add Pester test "pin copies full file set" to a new file [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — pins a mocked completed run, asserts `harness/automation/pinned/<name>/evidence/<runId>/evidence-manifest.json`, every manifest-referenced artifact, and `harness/automation/pinned/<name>/results/{run-result,lifecycle-status}.json` are all present and byte-identical (SHA) to the transient sources.
- [ ] T026 [P] [US3] Add Pester test "pin-name collision refused" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — pins twice with the same name, asserts the second call returns a `lifecycle-envelope.schema.json` envelope with `status: "refused"`, `failureKind: "pin-name-collision"`, no filesystem mutation.
- [ ] T027 [P] [US3] Add Pester test "pin -Force overwrites" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — pins, modifies source, pins again with `-Force`, asserts new content and `plannedPaths[]` reflects the overwrite.
- [ ] T028 [P] [US3] Add Pester test "list emits pinned-run-index" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — creates three pins, invokes list, asserts `pinnedRunIndex[]` conforms to [contracts/pinned-run-index.schema.json](./contracts/pinned-run-index.schema.json) and orders entries alphabetically by pinName.
- [ ] T029 [P] [US3] Add Pester test "unpin -DryRun mutates nothing" + "unpin removes pin" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — `-DryRun` returns `plannedPaths[]` with `action: "delete"` rows and leaves the pin on disk; the non-DryRun call removes the pin and returns `status: "ok"`.
- [ ] T030 [P] [US3] Add Pester test "pin refuses when manifest absent" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — transient zone has only `lifecycle-status.json` (no manifest), pin call returns `status: "refused"`, `failureKind: "pin-source-missing"`.

### Implementation for User Story 3

- [ ] T031 [US3] Add `Copy-RunToPinnedZone`, `Remove-PinnedRun`, and `Get-PinnedRunIndex` helpers to [tools/automation/RunbookOrchestration.psm1](../../tools/automation/RunbookOrchestration.psm1) — pin-name regex validation (`^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`), collision check, `-Force` path, `pin-metadata.json` write, legacy-pin tolerance (status `"unknown"`).
- [ ] T032 [P] [US3] Create [tools/automation/invoke-pin-run.ps1](../../tools/automation/invoke-pin-run.ps1) — parameters `-ProjectRoot`, `-PinName`, `-Force`, `-DryRun`; emits lifecycle envelope with `operation: "pin"`; uses `Copy-RunToPinnedZone`.
- [ ] T033 [P] [US3] Create [tools/automation/invoke-unpin-run.ps1](../../tools/automation/invoke-unpin-run.ps1) — parameters `-ProjectRoot`, `-PinName`, `-DryRun`; emits lifecycle envelope with `operation: "unpin"`; uses `Remove-PinnedRun`.
- [ ] T034 [P] [US3] Create [tools/automation/invoke-list-pinned-runs.ps1](../../tools/automation/invoke-list-pinned-runs.ps1) — parameter `-ProjectRoot`; emits lifecycle envelope with `operation: "list"` and populated `pinnedRunIndex[]`; uses `Get-PinnedRunIndex`.

**Checkpoint**: All three pin operations work end-to-end against a test sandbox. Docs still not updated — that is US4.

---

## Phase 6: User Story 4 — Agents know when and how to clean up (Priority: P2)

**Goal**: Every agent-facing surface describes the new lifecycle: automatic cleanup on each run, pin/unpin/list as the only supported preservation operations, dry-run for every mutation. The docs static check rejects any recipe that instructs an ad-hoc delete.

**Independent Test**: A `Select-String` / grep static check across `docs/runbook/` and `AGENTS.md` finds zero references to `Remove-Item`, `rm -rf`, or hand-authored cleanup against `harness/` / `evidence/` paths. Each `invoke-*.ps1` appears exactly once in the updated [RUNBOOK.md](../../RUNBOOK.md) table. The dry-run behavior of each lifecycle operation is demonstrated by an example in the corresponding [docs/runbook/](../../docs/runbook/) recipe.

### Validation for User Story 4

- [ ] T035 [P] [US4] Add Pester static-check test "no ad-hoc cleanup advice in recipes" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — scans every `.md` file under [docs/runbook/](../../docs/runbook/) and [AGENTS.md](../../AGENTS.md) for forbidden patterns (`Remove-Item.*(?:harness|evidence)`, `rm -rf.*(?:harness|evidence)`, etc.), fails on any match. This is the SC-006 gate.
- [ ] T036 [P] [US4] Add Pester test "RUNBOOK.md lists every lifecycle script" to [tools/tests/EvidenceLifecycle.Tests.ps1](../../tools/tests/EvidenceLifecycle.Tests.ps1) — parses [RUNBOOK.md](../../RUNBOOK.md) and asserts `invoke-pin-run.ps1`, `invoke-unpin-run.ps1`, `invoke-list-pinned-runs.ps1` each appear exactly once in the workflow table.

### Implementation for User Story 4

- [ ] T037 [US4] Add three new rows to [RUNBOOK.md](../../RUNBOOK.md) for pin / unpin / list-pinned-runs pointing to the new invoke scripts; add a brief note under "How runs are cleaned" linking to [specs/009-evidence-lifecycle/quickstart.md](./quickstart.md).
- [ ] T038 [P] [US4] Create the three new recipe docs [docs/runbook/pin-run.md](../../docs/runbook/pin-run.md), [docs/runbook/unpin-run.md](../../docs/runbook/unpin-run.md), and [docs/runbook/list-pinned-runs.md](../../docs/runbook/list-pinned-runs.md) mirroring the style of [docs/runbook/input-dispatch.md](../../docs/runbook/input-dispatch.md); each recipe includes a `-DryRun` example and the refusal-envelope example.
- [ ] T039 [P] [US4] Update the five existing recipe docs ([docs/runbook/input-dispatch.md](../../docs/runbook/input-dispatch.md), [docs/runbook/inspect-scene-tree.md](../../docs/runbook/inspect-scene-tree.md), [docs/runbook/behavior-watch.md](../../docs/runbook/behavior-watch.md), [docs/runbook/build-error-triage.md](../../docs/runbook/build-error-triage.md), [docs/runbook/runtime-error-triage.md](../../docs/runbook/runtime-error-triage.md)) with a short note about automatic pre-run cleanup and a link to the pin-run recipe for "keep this for later" cases. No change to the workflow body.

**Checkpoint**: All four user stories independently testable. Static checks enforce the behavior at PR time.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation synchronization across surfaces the user stories did not already touch (constitution §VI), plus final validation.

- [ ] T040 [P] Update [CLAUDE.md](../../CLAUDE.md) "Architecture (one-pager)" and "Do not" sections to mention the transient/pinned zones and pin operations, and re-state the "do not read prior-run artifacts" rule as now backed by automatic cleanup. One-paragraph change.
- [ ] T041 [P] Update [AGENTS.md](../../AGENTS.md) validation-routing / write-boundary sections to describe the new zones and reference [data-model.md](./data-model.md) §"Classification table" as the source of truth.
- [ ] T042 [P] Update [tools/README.md](../../tools/README.md) to list the three new `invoke-*.ps1` scripts under the orchestration section with a one-line description each.
- [ ] T043 [P] Update [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md) and [docs/AGENT_RUNTIME_HARNESS.md](../../docs/AGENT_RUNTIME_HARNESS.md) to reference the lifecycle zones; delete any now-contradicted advice about manual cleanup inside sandboxes.
- [ ] T044 [P] Update [.github/copilot-instructions.md](../../.github/copilot-instructions.md) and the relevant path-scoped files under [.github/instructions/](../../.github/instructions/) (`tools.instructions.md`, `integration-testing.instructions.md`) so repo-wide agent guidance matches the new lifecycle; update [.github/prompts/godot-runtime-verification.prompt.md](../../.github/prompts/godot-runtime-verification.prompt.md) and [.github/agents/godot-evidence-triage.agent.md](../../.github/agents/godot-evidence-triage.agent.md) to mention pinned-run comparison as the sanctioned cross-run reference pattern.
- [ ] T045 Run `pwsh ./tools/check-addon-parse.ps1` and resolve any GDScript parse, compile, or script-load errors before sign-off — mandatory per constitution §III whenever addon GDScript *could* have been touched. No GDScript edits are expected for this feature; a zero-exit run still gates merge.
- [ ] T046 Run [specs/009-evidence-lifecycle/quickstart.md](./quickstart.md) end-to-end against a throwaway integration-testing sandbox — pin, reproduce, list, unpin, then `git status --porcelain` — and confirm every step matches the recipe verbatim with zero manual filesystem intervention. Record the evidence path in the PR description.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup; **blocks all user stories**.
- **US1 (Phase 3)**: Depends on Foundational — modifies the five existing `invoke-*.ps1` scripts.
- **US2 (Phase 4)**: Depends on Foundational (for the `.gitignore` block) AND on US1 being at least in-flight (canonical invocations need to produce ignored output to prove the rules work). Practically: merge US1 before US2's validation tasks can run green, but US2's T022 (`git rm --cached`) can land in the same commit as the Foundational gitignore edit.
- **US3 (Phase 5)**: Depends on Foundational — independent of US1/US2; reuses the envelope writer and marker primitives.
- **US4 (Phase 6)**: Depends on US3 completion (the recipe docs describe US3's scripts) and at least US1 in-flight (existing recipes' cleanup notes require US1's behavior to exist).
- **Polish (Phase 7)**: Depends on all user stories being at least in-flight.

### User Story Dependencies

- **US1 (P1)**: Foundational only.
- **US2 (P1)**: Foundational; co-merges cleanly with US1 in the same PR if desired.
- **US3 (P2)**: Foundational only. Can run in parallel with US1 if implementers split.
- **US4 (P2)**: US3 for the new recipes; US1 for the "automatic cleanup" note in existing recipes.

### Within Each User Story

- Validation tasks (T012–T015, T020–T021, T025–T030, T035–T036) MUST be authored and confirmed failing before their implementation siblings land, per constitution §III.
- Runtime-artifact writers land with the feature, not as a later cleanup step.
- Documentation updates for US3's new surfaces live within US3; cross-cutting docs live in Polish.

### Parallel Opportunities

- **Setup**: T002 and T003 are [P] (different files).
- **Foundational**: T008, T009, T010 are [P] (different files). T004–T007 share `RunbookOrchestration.psm1` and must be sequential; T011 can start once T004–T006 are scaffolded.
- **US1**: T012–T015 are [P] validation writes across different test blocks. T017, T018, T019 are [P] once T016 has established the pattern.
- **US2**: T020, T021 are [P]. T022 is a one-file operation but must land with the Foundational `.gitignore`.
- **US3**: T025–T030 are [P]. T031 is the shared helper and must land before T032/T033/T034 (which are [P] relative to each other).
- **US4**: T035, T036 are [P]. T038, T039 are [P] (different doc files). T037 is a single-file edit.
- **Polish**: T040–T044 are all [P] (different files). T045 is a single command. T046 is a sequential end-to-end run.

---

## Parallel Example: User Story 3

```powershell
# Launch validation for US3 in parallel (different test blocks in the same new file):
# T025, T026, T027, T028, T029, T030

# Once T031 lands the shared helpers, launch the three scripts in parallel:
# T032 (invoke-pin-run.ps1)
# T033 (invoke-unpin-run.ps1)
# T034 (invoke-list-pinned-runs.ps1)
```

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup (T001–T003).
2. Complete Phase 2: Foundational (T004–T011) — critical.
3. Complete Phase 3: US1 (T012–T019) — every `invoke-*.ps1` is self-cleaning.
4. Complete Phase 4: US2 (T020–T024) — the 14 files are gone, git stays clean.
5. **STOP and VALIDATE**: Run the full Pester suite; run [quickstart.md](./quickstart.md) §1 against a throwaway sandbox; confirm `git status --porcelain` stays empty. Deploy/demo if ready. This is the minimum to address the user's complaint.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → Test independently → Deploy/demo (stale-file bug class eliminated).
3. US2 → Test independently → Deploy/demo (MVP complete; fixture tree clean).
4. US3 → Test independently → Deploy/demo (pin affordance available).
5. US4 → Test independently → Deploy/demo (agents taught the new workflow).
6. Polish → final docs synchronization + parse check.

### Parallel Team Strategy

With multiple contributors:

1. Team finishes Setup + Foundational together (small, shared surface).
2. Split:
   - Contributor A: US1 + US2 (touches 5 existing scripts + gitignore + Pester).
   - Contributor B: US3 (3 new scripts + new Pester file) — fully independent of A.
3. Rejoin for US4 (docs describe both A's and B's work) and Polish.

---

## Notes

- All new scripts and helpers emit JSON on stdout conforming to [contracts/lifecycle-envelope.schema.json](./contracts/lifecycle-envelope.schema.json); schema validation runs via [tools/validate-json.ps1](../../tools/validate-json.ps1).
- No GDScript edits are expected. T045 (`check-addon-parse.ps1`) remains mandatory as a constitution §III safety net.
- Commit the Foundational `.gitignore` edit (T008) and US2's `git rm --cached` (T022) together — never split across commits so no intermediate state leaves the 14 files "ignored but tracked."
- `[P]` tasks = different files, no shared state. Within `RunbookOrchestration.psm1` (T004–T007, T031), tasks must be sequential.
- Every validation task must be authored to fail before the corresponding implementation lands, per constitution §III.
