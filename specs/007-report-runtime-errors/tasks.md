# Tasks: Report Runtime Errors And Pause-On-Error

**Input**: Design documents from `/specs/007-report-runtime-errors/`
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Every user story includes deterministic validation tasks that produce machine-readable evidence (Pester for tools, deterministic editor-launched runs against the `integration-testing/runtime-error-loop/` sandbox for runtime behavior). Per the constitution, addon GDScript edits MUST be followed by `pwsh ./tools/check-addon-parse.ps1`; that step is folded into each implementation task that touches `addons/agent_runtime_harness/`.

**Organization**: Tasks are grouped by user story so each story (US1-US4) can be implemented and validated independently. US1 (capture) and US2 (pause/decision) are both P1; US1 is the MVP because pause depends on capture.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Different files, no dependencies on incomplete tasks
- **[Story]**: User story this task belongs to (US1, US2, US3, US4)
- File paths are workspace-relative

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold sandbox, fixture roots, and the workspace helper surface needed by every story.

- [X] T001 Scaffold the integration sandbox at [integration-testing/runtime-error-loop/](../../integration-testing/runtime-error-loop/) per [docs/INTEGRATION_TESTING.md](../../docs/INTEGRATION_TESTING.md) and the "End-to-end plugin testing" section of [tools/README.md](../../tools/README.md): create `project.godot`, `addons/`, `scenes/`, `scripts/`, `harness/automation/{requests,results}/`, `evidence/`, plus an `AGENTS.md` and `README.md` mirroring [integration-testing/input-dispatch/](../../integration-testing/input-dispatch/). Do NOT download or hard-code a Godot binary path.
- [X] T002 [P] Create the deterministic GDScript fixtures under [integration-testing/runtime-error-loop/scripts/](../../integration-testing/runtime-error-loop/scripts/): `error_on_frame.gd` (raises a runtime error at a known script/line/function via a null-call inside `_process`), `unhandled_exception.gd` (raises an unhandled exception via failing `assert`), `warning_only.gd` (calls `push_warning` once and exits cleanly), and `repeat_error.gd` (re-raises the same error every frame for at least 105 frames so the 100-cap path is exercised).
- [X] T003 [P] Create the matching scenes under [integration-testing/runtime-error-loop/scenes/](../../integration-testing/runtime-error-loop/scenes/) that host each fixture script as the root or a child autoload, plus a `no_errors.tscn` scene that exits cleanly without emitting anything.
- [X] T004 [P] Create the request/expected-outcome fixtures under [tools/tests/fixtures/runtime-error-loop/](../../tools/tests/fixtures/runtime-error-loop/) for the three pause cases (`error-on-frame.json`, `unhandled-exception.json`, `repeat-error.json`), the warning-only case (`warning-only.json`), the no-error case (`no-errors.json`), and one valid `pause-decision.json` per decision (`pause-decision-continue.json`, `pause-decision-stop.json`).
- [X] T005 [P] Create the rejection-case pause-decision fixtures under [tools/tests/fixtures/runtime-error-loop/rejections/](../../tools/tests/fixtures/runtime-error-loop/rejections/): one fixture per code (`missing_field.json`, `unsupported_field.json`, `invalid_decision.json`, `unknown_pause.json`, `decision_already_recorded.json`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared constants, schema registration, validator, artifact registry entries, and capability surface that every user story consumes. **No user-story task may begin until this phase is complete.**

- [X] T006 Extend [addons/agent_runtime_harness/shared/inspection_constants.gd](../../addons/agent_runtime_harness/shared/inspection_constants.gd) with the new constant groups: severities (`error`, `warning`), pause causes (`runtime_error`, `unhandled_exception`, `paused_at_user_breakpoint`), decisions (`continued`, `stopped`, `timeout_default_applied`, `stopped_by_disconnect`, `resolved_by_run_end`), decision sources (`agent`, `timeout_default`, `disconnect`, `run_end`), termination kinds (`completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, `killed_by_harness`), pause-on-error modes (`active`, `unavailable_degraded_capture_only`), pause-decision rejection codes (`missing_field`, `unsupported_field`, `invalid_decision`, `unknown_pause`, `decision_already_recorded`), debugger message names (`runtime_error_record`, `runtime_pause`, `pause_decision`, `pause_decision_ack`), and the per-key cap constant (`RUNTIME_ERROR_REPEAT_CAP = 100`). Run `pwsh ./tools/check-addon-parse.ps1` and treat a non-zero exit as blocking.
- [X] T007 [P] Add the JSON Schemas to [tools/evidence/](../../tools/evidence/) packaging by registering both new artifact kinds in [tools/evidence/artifact-registry.ps1](../../tools/evidence/artifact-registry.ps1): `runtime-error-records` (`runtime-error-records.jsonl`, `application/jsonl`, description from the contract) and `pause-decision-log` (`pause-decision-log.jsonl`, `application/jsonl`, description from the contract). Add Pester coverage in [tools/tests/EvidenceTools.Tests.ps1](../../tools/tests/EvidenceTools.Tests.ps1) (or a new `RuntimeErrorArtifactRegistry.Tests.ps1` mirroring [tools/tests/InputDispatchArtifactRegistry.Tests.ps1](../../tools/tests/InputDispatchArtifactRegistry.Tests.ps1)) that asserts both kinds are present with the expected file/media-type/description shape.
- [X] T008 [P] Add `addons/agent_runtime_harness/shared/pause_decision_request_validator.gd` modeled on [addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd](../../addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd) that validates a parsed pause-decision request dict against the contract: required fields (`runId`, `pauseId`, `decision`, `submittedBy`, `submittedAt`), unknown-field detection, decision enum (`continue`, `stop`), and pluggable lookups (`pause_lookup`, `decision_log_lookup`) for `unknown_pause` and `decision_already_recorded`. Returns a structured `{ ok: bool, code: <rejection-code>, field?: <name>, message: <string> }`. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T009 [P] Add Pester coverage at [tools/tests/PauseDecisionRequestValidator.Tests.ps1](../../tools/tests/PauseDecisionRequestValidator.Tests.ps1) that loads each fixture from T004 and T005 through a thin GDScript harness (or PowerShell equivalent if the validator is mirrored) and asserts the expected `{ ok, code, field }` for valid + each rejection code. Use the same headless invocation pattern as [tools/tests/InputDispatchValidator.Tests.ps1](../../tools/tests/InputDispatchValidator.Tests.ps1) if it exists, otherwise mirror the closest validator test file.
- [X] T010 Extend [addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd](../../addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd) capability publisher to add three first-class entries with the existing `{ supported, reason }` shape: `runtimeErrorCapture` (always `supported = true` for v1), `pauseOnError` (probes the engine's debug-pause hook; `supported = false, reason = "engine_pause_unavailable"` when the platform cannot suspend safely), and `breakpointSuppression` (`supported = true` when the documented runtime hook is available, otherwise `supported = false, reason = "engine_hook_unavailable"`). Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T011 [P] Update [tools/automation/get-editor-evidence-capability.ps1](../../tools/automation/get-editor-evidence-capability.ps1) to surface the three new entries in its return value and add Pester coverage in [tools/tests/AutomationTools.Tests.ps1](../../tools/tests/AutomationTools.Tests.ps1) using a fixture capability artifact under [tools/tests/fixtures/runtime-error-loop/capability/](../../tools/tests/fixtures/runtime-error-loop/capability/) for the supported, pause-blocked, and breakpoint-blocked permutations.
- [X] T012 [P] Add `tools/automation/submit-pause-decision.ps1` modeled on [tools/automation/request-editor-evidence-run.ps1](../../tools/automation/request-editor-evidence-run.ps1): parameters `-ProjectRoot`, `-RunId`, `-PauseId`, `-Decision (continue|stop)`, `-SubmittedBy`. Writes a validated `pause-decision.json` to `<ProjectRoot>/harness/automation/requests/pause-decision.json` (atomic temp-then-rename) and rejects locally on the same parameter shape the GDScript validator enforces. Add Pester coverage in [tools/tests/AutomationTools.Tests.ps1](../../tools/tests/AutomationTools.Tests.ps1).

**Checkpoint**: Foundation ready - US1 through US4 may proceed (US2 still depends on US1's runtime-error capture surface).

---

## Phase 3: User Story 1 - Capture Runtime Errors With Location And Cause (Priority: P1) MVP

**Goal**: Every GDScript runtime error and `push_warning` observed after the runtime addon attaches is captured as a deduplicated row in `runtime-error-records.jsonl`, referenced by the current run's manifest only.

**Independent Test**: Run the seeded `error_on_frame.gd` fixture (one error) and the `warning_only.gd` fixture (one warning); confirm the manifest's `runtimeErrorReporting.runtimeErrorRecordsArtifact` references a current-run file containing exactly one record with the expected script/line/function/message/severity. Run the `repeat_error.gd` fixture and confirm `repeatCount = 100` with `truncatedAt: 100`. Run a no-error scene and confirm an empty record set.

### Validation for User Story 1

- [X] T013 [P] [US1] Add a deterministic Pester scenario in [tools/tests/RuntimeErrorCapture.Tests.ps1](../../tools/tests/RuntimeErrorCapture.Tests.ps1) that asserts each row in `runtime-error-records.jsonl` from the four US1 fixtures (`warning-only`, `error-on-frame`, `unhandled-exception`, `repeat-error`) validates against [contracts/runtime-error-record.schema.json](contracts/runtime-error-record.schema.json) using `pwsh ./tools/validate-json.ps1`, and that the record set matches the expected ordinals, severities, and (for `repeat-error`) the `repeatCount: 100`/`truncatedAt: 100` cap.
- [X] T014 [P] [US1] Add an invariant check inside the same Pester file (or [tools/tests/EvidenceTools.Tests.ps1](../../tools/tests/EvidenceTools.Tests.ps1)) that, for a current run, the manifest's `runtimeErrorReporting.runtimeErrorRecordsArtifact` reference resolves to a file under the current run's output directory and is NOT inherited from a prior run when the new run produces no records.

### Implementation for User Story 1

- [X] T015 [US1] Extend [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd) to subscribe to the engine error stream through `EngineDebugger`, classify severity (`error` for runtime errors / failed `assert` / `push_error` / unhandled exceptions; `warning` for `push_warning`), maintain a per-run dedup map keyed by `(scriptPath, line, severity)` with a rolling `repeatCount` capped at 100, stamp `firstSeenAt` and `lastSeenAt` (UTC ISO-8601), assign a per-run monotonically increasing `ordinal` per dedup key, and emit a `runtime_error_record` debugger message to the editor for each new dedup-key occurrence (only the first occurrence; subsequent occurrences update `repeatCount` in place). Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T016 [US1] Extend [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd) to flush the dedup map to `runtime-error-records.jsonl` (one row per dedup key, ordered by `firstSeenAt` ASC tie-broken by `ordinal`) at run completion, and to perform the same flush on the partial-run shutdown path so a crashed run still writes whatever was captured. Add a current-run-only invariant: never reference a prior run's `runtime-error-records.jsonl`. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T017 [US1] Extend [addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd](../../addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd) to recognize the new `runtime_error_record` debugger message and forward each record to the run coordinator. Replace the current "treat `runtime_error` message as transport error" path with the new typed handling. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T018 [US1] Extend the manifest writer in [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) to attach the `runtimeErrorRecordsArtifact` reference inside a new `runtimeErrorReporting` block on the current-run manifest. Leave `pauseOnErrorMode`, `termination`, `pauseDecisionLogArtifact`, and `lastErrorAnchor` for US2/US3 to fill; for US1 alone, default `pauseOnErrorMode = "active"` and `termination = "completed"`. Run `pwsh ./tools/check-addon-parse.ps1`.

**Checkpoint**: US1 is independently functional. The MVP can be shipped here: agents see every error and warning in a deduplicated machine-readable artifact even without pause control.

---

## Phase 4: User Story 2 - Pause-On-Error Notification And Stop-Or-Continue Decision (Priority: P1)

**Goal**: `error`-severity records and unhandled exceptions pause the running playtest through the engine's debug-pause state, surface a machine-readable pause notification through the broker, accept the agent's `continue` or `stop` decision through `harness/automation/requests/pause-decision.json`, honor it (or apply the documented timeout default), and persist exactly one row per pause to `pause-decision-log.jsonl`. Includes the `paused_at_user_breakpoint` fallback when breakpoint suppression is unavailable.

**Independent Test**: Run `error_on_frame.gd`, submit `continue`; confirm the run resumes and the pause-decision log contains one row with `decision: "continued"`, `decisionSource: "agent"`, and a positive `latencyMs`. Repeat with `stop`; confirm `decision: "stopped"`, termination `stopped_by_agent`. Repeat without submitting any decision; confirm `decision: "timeout_default_applied"`, termination `stopped_by_default_on_pause_timeout`. Run a project containing a user `breakpoint` on an environment where suppression is unavailable; confirm `cause: "paused_at_user_breakpoint"` and an honored agent decision.

### Validation for User Story 2

- [X] T019 [P] [US2] Add a deterministic Pester scenario in [tools/tests/PauseOnErrorBroker.Tests.ps1](../../tools/tests/PauseOnErrorBroker.Tests.ps1) that asserts every row in `pause-decision-log.jsonl` from the US2 fixtures validates against [contracts/pause-decision-record.schema.json](contracts/pause-decision-record.schema.json), and that the `(runId, pauseId)` pair appears exactly once per pause.
- [X] T020 [P] [US2] Add an invariant check inside the same Pester file that asserts: while a pause is outstanding, the broker MUST NOT advance any queued input-dispatch event from feature 006 (use the existing input-dispatch outcome row file as a probe); the consumed `pause-decision.json` MUST be deleted from `harness/automation/requests/`; a second `pause-decision.json` for the same `(runId, pauseId)` MUST be rejected with `decision_already_recorded` and the rejection MUST be observable in the broker's existing automation result/log.

### Implementation for User Story 2

- [X] T021 [US2] Extend [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd) to raise the engine's existing debug-pause state when a new `error`-severity record (US1 dedup-key first occurrence) or an unhandled exception is observed and `pauseOnError.supported = true`; emit a `runtime_pause` debugger message carrying `pauseId`, cause, originating script/line/function/message, and the current `Engine.get_process_frames()` ordinal; freeze any cooperating input-dispatch advancement until a `pause_decision` arrives from the editor. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T022 [US2] Install a runtime-side breakpoint-suppression hook in `scenegraph_runtime.gd` where the engine exposes a documented entry path; when the hook is unavailable, do NOT install it but still recognize the engine's debug-pause state when a user `breakpoint` runs and emit a `runtime_pause` with `cause = "paused_at_user_breakpoint"` (do NOT increment any runtime-error dedup-key counter for this case). Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T023 [US2] Extend [addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd](../../addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd) to recognize `runtime_pause` and `pause_decision_ack` and route them to the run coordinator. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T024 [US2] Extend [addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd](../../addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd) to: poll `harness/automation/requests/pause-decision.json` only while a pause is outstanding (cap at one poll per editor frame); validate via `PauseDecisionRequestValidator` from T008; on success, send a `pause_decision` debugger message and delete the request file; on rejection, write the rejection through the existing automation result/log path with the standardized rejection code. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T025 [US2] Extend [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) to: track outstanding pauses by `(runId, pauseId)`; on accepted decision, call `EditorDebuggerSession` continue (for `continue`) or stop (for `stop`); start a 30-second decision timer per pause and on expiry apply `decision = timeout_default_applied`/`decisionSource = timeout_default` and stop; record exactly one `pause-decision-log.jsonl` row per resolution including `recordedAt` and `latencyMs`; treat `EditorDebuggerSession` disconnect while a pause is outstanding as `decision = stopped_by_disconnect`/`decisionSource = disconnect`; treat a normal run end while a pause is outstanding as `decision = resolved_by_run_end`/`decisionSource = run_end`. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T026 [US2] Extend [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd) to write `pause-decision-log.jsonl` (rows ordered by `pauseId`) on both the normal and partial-run shutdown paths; reference it from the manifest's `runtimeErrorReporting.pauseDecisionLogArtifact`; populate `runtimeErrorReporting.pauseOnErrorMode` from the capability snapshot at run start (`active` or `unavailable_degraded_capture_only`); update `runtimeErrorReporting.termination` based on the decision-source/exit signal (`completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`). Run `pwsh ./tools/check-addon-parse.ps1`.

**Checkpoint**: US1 + US2 give the full capture-and-control loop. Crash classification (US3) and capability advertisement (US4) layer on top.

---

## Phase 5: User Story 3 - Crashes And Abnormal Exits With Last-Known Context (Priority: P2)

**Goal**: The manifest's `runtimeErrorReporting.termination` distinguishes `completed`, `stopped_by_agent`, `stopped_by_default_on_pause_timeout`, `crashed`, and `killed_by_harness`, and a `crashed` run carries a `lastErrorAnchor` that points at the last runtime-error record observed before the process went away (or `{ "lastError": "none" }`).

**Independent Test**: Run a fixture that triggers a process-level abort after emitting one `push_error` and confirm `termination = "crashed"` with a `lastErrorAnchor` matching the seeded error. Run a clean-exit fixture and confirm `termination = "completed"` with no `lastErrorAnchor`. Run a stop-decision fixture (US2) and confirm `termination = "stopped_by_agent"`, NOT `crashed`.

### Validation for User Story 3

- [X] T027 [P] [US3] Add a deterministic Pester scenario in [tools/tests/RuntimeTerminationClassification.Tests.ps1](../../tools/tests/RuntimeTerminationClassification.Tests.ps1) that runs each termination fixture (clean exit, stop-by-agent, timeout-default, crashed, harness-killed) and asserts the manifest's `runtimeErrorReporting.termination` matches the expected enum value and that `lastErrorAnchor` is present iff `termination = "crashed"`.
- [X] T028 [P] [US3] Extend [tools/evidence/validate-evidence-manifest.ps1](../../tools/evidence/validate-evidence-manifest.ps1) (or a new helper invoked from the same flow) to enforce the manifest invariants from [contracts/runtime-error-reporting-contract.md](contracts/runtime-error-reporting-contract.md): required `termination` and `pauseOnErrorMode` enums, conditional `lastErrorAnchor` shape, and current-run-only artifact references. Add a regression in [tools/tests/EvidenceTools.Tests.ps1](../../tools/tests/EvidenceTools.Tests.ps1) covering each shape.

### Implementation for User Story 3

- [X] T029 [US3] Add a crash-classification fixture under [integration-testing/runtime-error-loop/scripts/](../../integration-testing/runtime-error-loop/scripts/) (`crash_after_error.gd`) that emits one `push_error` and then calls `OS.kill(OS.get_process_id())` (or the documented engine-abort path) to force a process exit without a clean shutdown handshake. Add a corresponding scene under [integration-testing/runtime-error-loop/scenes/](../../integration-testing/runtime-error-loop/scenes/) and a request fixture under [tools/tests/fixtures/runtime-error-loop/](../../tools/tests/fixtures/runtime-error-loop/).
- [X] T030 [US3] Extend [addons/agent_runtime_harness/runtime/scenegraph_runtime.gd](../../addons/agent_runtime_harness/runtime/scenegraph_runtime.gd) to track the most recent `error`-severity record's anchor fields (`scriptPath`, `line`, `severity`, `message`) in a sidecar file flushed every time a new dedup-key first occurrence is recorded, so a sudden process exit leaves a recoverable anchor. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T031 [US3] Extend [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) and [addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd](../../addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd) to set `runtimeErrorReporting.termination`: `completed` on a clean shutdown handshake; `stopped_by_agent` when the last decision was `stopped` from `agent`; `stopped_by_default_on_pause_timeout` when the last decision was `timeout_default_applied`; `killed_by_harness` when the editor coordinator initiated the stop for harness-limit reasons; `crashed` otherwise (no clean handshake observed). On `crashed`, populate `runtimeErrorReporting.lastErrorAnchor` from the sidecar from T030, or `{ "lastError": "none" }` if the sidecar is empty. Run `pwsh ./tools/check-addon-parse.ps1`.

**Checkpoint**: All termination paths produce machine-readable, distinguishable manifests; agents can debug a crash from the persisted last-known anchor without running the game again.

---

## Phase 6: User Story 4 - Capability Advertisement For Runtime Error, Pause, And Breakpoint Suppression (Priority: P3)

**Goal**: The capability artifact carries first-class `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression` entries, and a run that depends on pause control on an environment where it is unavailable executes in the documented capture-only degraded mode (NOT rejected) with the manifest stamped `pauseOnErrorMode = "unavailable_degraded_capture_only"`.

**Independent Test**: Read the capability artifact via `pwsh ./tools/automation/get-editor-evidence-capability.ps1` against fixtures representing the supported / pause-blocked / breakpoint-blocked environments and confirm the three entries surface with expected `supported`/`reason`. Submit a run on the pause-blocked environment and confirm the manifest stamps `pauseOnErrorMode = "unavailable_degraded_capture_only"` and an empty pause-decision log even though runtime-error records are still captured.

### Validation for User Story 4

- [X] T032 [P] [US4] Add a deterministic Pester scenario in [tools/tests/RuntimeErrorCapability.Tests.ps1](../../tools/tests/RuntimeErrorCapability.Tests.ps1) that loads each fixture under [tools/tests/fixtures/runtime-error-loop/capability/](../../tools/tests/fixtures/runtime-error-loop/capability/) (T011) and asserts `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression` are present with the expected `supported`/`reason` values for each environment.
- [X] T033 [P] [US4] Add a regression in the same Pester file that asserts a degraded-mode run (pause-blocked) still produces a current-run `runtime-error-records.jsonl` with the expected records, an empty `pause-decision-log.jsonl`, manifest `pauseOnErrorMode = "unavailable_degraded_capture_only"`, and termination drawn from the same enum (typically `completed`).

### Implementation for User Story 4

- [X] T034 [US4] Extend [addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd](../../addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd) and [addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd](../../addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd) to apply degraded mode automatically when the capability snapshot at run start reports `pauseOnError.supported = false`: skip pause-raising; capture-only; stamp the manifest `runtimeErrorReporting.pauseOnErrorMode = "unavailable_degraded_capture_only"`; never reject the run on this basis. Run `pwsh ./tools/check-addon-parse.ps1`.
- [X] T035 [US4] Extend the same broker/coordinator path so that on environments where `breakpointSuppression.supported = false`, any breakpoint-triggered pause is recorded with `cause = "paused_at_user_breakpoint"` and routed through the same pause-decision flow already implemented in US2 (no degraded mode needed; the pause loop already exists). Run `pwsh ./tools/check-addon-parse.ps1`.

**Checkpoint**: All four user stories are independently functional and independently testable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation synchronization, sandbox end-to-end validation, and final regression sweeps.

- [X] T036 [P] Update [docs/AGENT_RUNTIME_HARNESS.md](../../docs/AGENT_RUNTIME_HARNESS.md) with a new "Runtime error reporting and pause-on-error" section that describes the two new artifacts, the `runtimeErrorReporting` manifest block, the `pause-decision.json` request, the three new capability bits, the documented decision timeout default (30 s, applied as `stop`), the per-key 100-cap, the degraded mode, the breakpoint-suppression rules, and the cooperation with feature 006 (no input-dispatch advancement during outstanding pause).
- [X] T037 [P] Update [docs/AI_TOOLING_AUTOMATION_MATRIX.md](../../docs/AI_TOOLING_AUTOMATION_MATRIX.md) with capability and routing rows for `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression`, and reference the new artifact kinds and the new helper `tools/automation/submit-pause-decision.ps1`.
- [X] T038 [P] Update [.github/copilot-instructions.md](../../.github/copilot-instructions.md) and [AGENTS.md](../../AGENTS.md) "Validation commands" / "Validation expectations" sections to mention `pwsh ./tools/automation/submit-pause-decision.ps1` and the two new artifact kinds. Update [.github/instructions/addons.instructions.md](../../.github/instructions/addons.instructions.md) and [.github/instructions/tools.instructions.md](../../.github/instructions/tools.instructions.md) with path-scope notes for `pause_decision_request_validator.gd`, the new constants, and the new tool helper.
- [X] T039 [P] Update the deployable templates under [addons/agent_runtime_harness/templates/project_root/](../../addons/agent_runtime_harness/templates/project_root/) ONLY if the broker changed the request directory layout or default schema (otherwise leave untouched). If updated, add a smoke test in [tools/tests/DeployGameHarness.Tests.ps1](../../tools/tests/DeployGameHarness.Tests.ps1) that confirms `harness/automation/requests/` is created on deploy.
- [X] T040 Run the full end-to-end sandbox flow against [integration-testing/runtime-error-loop/](../../integration-testing/runtime-error-loop/) per [quickstart.md](quickstart.md): `pwsh ./tools/deploy-game-harness.ps1`, `pwsh ./tools/check-addon-parse.ps1`, `pwsh ./tools/automation/get-editor-evidence-capability.ps1`, `pwsh ./tools/automation/request-editor-evidence-run.ps1` for each fixture, `pwsh ./tools/automation/submit-pause-decision.ps1` for each pause case, `pwsh ./tools/evidence/validate-evidence-manifest.ps1` against each persisted manifest. Resolve any non-zero exit before sign-off.
- [X] T041 Run the full PowerShell regression suite via `pwsh ./tools/tests/run-tool-tests.ps1` and the addon parse check via `pwsh ./tools/check-addon-parse.ps1` one final time. A non-zero exit from either is a blocking failure.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, may begin immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1; BLOCKS Phases 3-6.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Depends on Phase 2 AND on US1 (capture surface is the trigger source for pause; the new debugger-message handling lands in US1).
- **Phase 5 (US3)**: Depends on Phase 2 AND on US1 (`lastErrorAnchor` reads the US1 dedup map). Termination-from-decision paths additionally need US2 to be live to be exercised.
- **Phase 6 (US4)**: Depends on Phase 2; can run in parallel with US3 once US2's degraded-mode hook (T034) is reviewed against US2's pause path.
- **Phase 7 (Polish)**: Depends on the user stories that ship.

### Story-Internal Order

- Validation tasks (`Validation for User Story N`) MUST be defined and shown failing before the corresponding implementation tasks land.
- Within each story: constants/contracts/validators (already in Phase 2) → runtime capture → editor bridge → broker/coordinator → artifact writer → manifest stamping.
- Run `pwsh ./tools/check-addon-parse.ps1` after every GDScript edit; a non-zero exit blocks the next task.

### Parallel Opportunities

- All Phase 1 setup tasks marked [P] (T002, T003, T004, T005) may run in parallel with each other.
- All Phase 2 tasks marked [P] (T007, T008, T009, T011, T012) may run in parallel with each other after T006 lands (T006 owns the shared constants every other Phase 2 task imports).
- Within each user story, validation tasks marked [P] may run in parallel with each other, and implementation tasks marked [P] may run in parallel when they touch different files.
- US3 and US4 implementation phases may run in parallel by different developers once Phase 4 (US2) lands.
- All Polish tasks marked [P] (T036, T037, T038, T039) may run in parallel.

---

## Parallel Example: User Story 1

```bash
# Validation in parallel
Task: T013 [P] [US1] Pester scenario asserting record schema + dedup/cap shape
Task: T014 [P] [US1] Invariant: current-run-only manifest reference

# Implementation: file ownership is sequential within US1 (each task touches a different file but later tasks read state added by earlier ones), so run T015 -> T016 -> T017 -> T018 in order, but T013/T014 may be authored alongside T015.
```

---

## Implementation Strategy

### MVP First (US1 only)

1. Complete Phase 1 (Setup).
2. Complete Phase 2 (Foundational).
3. Complete Phase 3 (US1).
4. STOP and VALIDATE: run `error-on-frame`, `warning-only`, `unhandled-exception`, `repeat-error`, and a no-error scene; confirm `runtime-error-records.jsonl` and the `runtimeErrorReporting.runtimeErrorRecordsArtifact` manifest reference are correct.
5. Demo: agents now have machine-readable post-run error visibility even without pause control.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 → demo: capture only (MVP).
3. US2 → demo: capture + pause/decide (the full feature value the user originally asked for).
4. US3 → demo: crash classification with last-known anchor.
5. US4 → demo: capability-honest behavior across environments, including degraded mode.

### Parallel Team Strategy

After Phase 2:

- Developer A: US1 (validation + implementation) → US3 (depends on US1's dedup map).
- Developer B: US2 (validation + implementation) once US1's `runtime_error_record` message lands.
- Developer C: US4 (validation + implementation), in parallel with US3 after T034's hook contract is agreed against US2's pause path.

---

## Notes

- [P] tasks operate on different files with no in-flight dependency on incomplete work.
- [Story] labels map each implementation task to the user story it serves; setup, foundational, and polish tasks intentionally carry no [Story] label.
- Run `pwsh ./tools/check-addon-parse.ps1` after every addon GDScript edit; a non-zero exit is a blocking failure per the constitution.
- Run `pwsh ./tools/validate-json.ps1` against every contract fixture before relying on it in a Pester scenario.
- Treat blocked capability artifacts, blocked pause-decision flows, or stale manifest references as explicit stop conditions per [AGENTS.md](../../AGENTS.md) "Validation routing"; do NOT improvise around them.
- Commit after each task or logical group (the optional `after_implement` git hook can do this automatically).
