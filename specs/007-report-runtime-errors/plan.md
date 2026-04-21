
# Implementation Plan: Report Runtime Errors And Pause-On-Error

**Branch**: `007-report-runtime-errors` | **Date**: 2026-04-19 | **Spec**: [specs/007-report-runtime-errors/spec.md](spec.md)
**Input**: Feature specification from `/specs/007-report-runtime-errors/spec.md`

## Summary

Extend the existing editor-launched evidence loop so the harness captures every GDScript runtime error and warning observed after the runtime addon attaches, persists them as a deduplicated `runtime-error-records.jsonl` artifact (per-key `repeatCount` capped at 100), pauses the running playtest on `error`-severity records and unhandled exceptions through Godot's existing engine debug-pause state, surfaces a machine-readable pause notification through the same plugin-owned file broker already used for capability and run requests, accepts an agent `continue`/`stop` decision through a new `harness/automation/requests/pause-decision.json` request file, persists each pause outcome as a `pause-decision-log.jsonl` row, and stamps the manifest with a fixed `runtimeErrorReporting.termination` classification (`completed | stopped_by_agent | stopped_by_default_on_pause_timeout | crashed | killed_by_harness`) plus a `pauseOnErrorMode` field (`active | unavailable_degraded_capture_only`) and, when crashed, a `lastErrorAnchor`. The preferred v1 path reuses the current `EditorDebuggerPlugin`, runtime addon, broker, manifest writer, capability publisher, validator pattern, and shared artifact registry rather than introducing a parallel transport, a second broker, or any GDExtension-level engine instrumentation. User-set GDScript `breakpoint` statements are out of scope as a pause trigger; the harness suppresses them at runtime where the engine exposes a documented hook and otherwise routes them through the same pause-decision flow with a distinct `paused_at_user_breakpoint` cause so they never silently stall a run.

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon and runtime scripts, JSON Schema Draft 2020-12 for contract surfaces, Markdown for design artifacts, PowerShell 7+ for request-writing, capability-read, and validation helpers under `tools/`
**Primary Dependencies**: Godot `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, the engine's existing debug-pause state, GDScript `push_error`/`push_warning`/`assert`/`breakpoint`; existing automation run request and result contracts in `specs/003-editor-evidence-loop/contracts/`; editor bridge in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`; run coordinator in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`; broker in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`; runtime session handling in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`; manifest writer in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`; validator pattern in `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd` and `input_dispatch_request_validator.gd`; artifact registry in `tools/evidence/artifact-registry.ps1`; capability publisher and reader in the broker and `tools/automation/get-editor-evidence-capability.ps1`
**Storage**: Run-scoped automation request and result JSON under project-local `harness/automation/`; new `harness/automation/requests/pause-decision.json` request file consumed-and-deleted by the broker; run-scoped evidence bundles under project `res://evidence/...` output directories; new fixed `runtime-error-records.jsonl` and `pause-decision-log.jsonl` colocated with the existing `manifest`, `scenegraph-snapshot`, `scenegraph-diagnostics`, `summary`, `trace`, and `input-dispatch-outcomes` artifacts; feature planning artifacts under `specs/007-report-runtime-errors/`
**Testing**: Contract-fixture validation for the new pause-decision request validator and JSON schemas without launching the game (new Pester coverage alongside `BehaviorWatchRequestValidator` and the input-dispatch validator tests); deterministic editor-launched runs against a new `integration-testing/runtime-error-loop/` sandbox with seeded fixtures (`error_on_frame.gd`, `unhandled_exception.gd`, `warning_only.gd`, plus a no-error Pong reuse) for capture, pause-on-error, decision honoring, and termination classification; manifest validation with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`; existing PowerShell regression suite with `pwsh ./tools/tests/run-tool-tests.ps1` when tool, schema, capability, or artifact-registry helpers change; addon parse check with `pwsh ./tools/check-addon-parse.ps1` after every GDScript edit under `addons/agent_runtime_harness/`; combined validation because the feature changes runtime-visible behavior and has an existing deterministic tool-level test surface
**Target Platform**: Godot 4.x editor on Windows, macOS, and Linux with the example or integration-testing project already open on the same machine as VS Code; headless export builds may report `pauseOnError.supported = false` and run in capture-only degraded mode
**Project Type**: Editor addon plus runtime addon plus debugger-integration contract extension layered onto the current plugin-owned file broker
**Performance Goals**: Maintain the existing per-frame budget of the runtime addon; runtime-error capture MUST be O(1) per record (dedup hash lookup) and MUST NOT add measurable per-frame overhead in the no-error path; per-key `repeatCount` cap of 100 keeps the runtime-error artifact bounded; pause-decision poll cadence on the editor side MUST NOT exceed once per editor frame and MUST stop polling as soon as a decision is consumed; the new manifest block and two artifacts MUST be written within the existing 60-second post-run budget used by other evidence artifacts
**Constraints**: Plugin-first only; no engine fork; no GDExtension unless documented addon, autoload, debugger, and engine-debugger surfaces prove insufficient; pause is the engine's existing debug-pause state (no new threading model); pause triggers limited to `error`-severity records and unhandled exceptions; user `breakpoint` statements out of scope as a pause trigger (suppress where possible, route as `paused_at_user_breakpoint` otherwise); fixed pause-decision timeout default `stop`; per-key dedup with a 100 cap; pause-on-error degraded mode (capture-only) when capability is unsupported, never reject; no stale artifact reuse across runs; no agent-facing transport other than the existing file broker
**Scale/Scope**: Primarily touches `addons/agent_runtime_harness/shared/` (new `pause_decision_request_validator.gd` and new `runtime_error_constants.gd`-style additions to `inspection_constants.gd`), `addons/agent_runtime_harness/editor/` (broker capability extension, run coordinator integration, debugger bridge messages, decision polling), `addons/agent_runtime_harness/runtime/` (runtime error capture, pause raising, dedup, partial-run flush, breakpoint suppression hook, artifact writer additions), `tools/automation/` (new `submit-pause-decision.ps1` plus capability-reader update), `tools/evidence/` (artifact registry entry for two new kinds), `tools/tests/` (Pester coverage for the validator, capability extension, artifact registry entry, and broker decision flow), feature-local contracts and design artifacts under `specs/007-report-runtime-errors/`, deterministic seeded fixtures under `integration-testing/runtime-error-loop/` and `tools/tests/fixtures/runtime-error-loop/`, and documentation updates to `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AI_TOOLING_AUTOMATION_MATRIX.md`, `.github/copilot-instructions.md`, the relevant `.github/instructions/*.instructions.md`, and the deployable `addons/agent_runtime_harness/templates/project_root/` snippets

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md` (problem statement, plugin-first stack, evidence bundle handoff, runtime input dispatch precedent), `docs/AGENT_TOOLING_FOUNDATION.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `docs/AI_TOOLING_AUTOMATION_MATRIX.md`, `docs/AI_TOOLING_BEST_PRACTICES.md`, `docs/INTEGRATION_TESTING.md`, `docs/BEHAVIOR_CAPTURE_SLICES.md`, `specs/003-editor-evidence-loop/spec.md`, `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`, `specs/004-report-build-errors/spec.md`, `specs/004-report-build-errors/plan.md`, `specs/004-report-build-errors/contracts/build-error-run-result-contract.md`, `specs/005-behavior-watch-sampling/spec.md`, `specs/005-behavior-watch-sampling/plan.md`, `specs/006-input-dispatch/spec.md`, `specs/006-input-dispatch/plan.md`, `specs/006-input-dispatch/contracts/input-dispatch-script.schema.json`, `specs/006-input-dispatch/contracts/input-dispatch-outcome-row.schema.json`, `addons/agent_runtime_harness/plugin.gd`, `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`, `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`, `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`, `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`, `addons/agent_runtime_harness/shared/inspection_constants.gd`, `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`, `tools/evidence/artifact-registry.ps1`, `tools/automation/request-editor-evidence-run.ps1`, `tools/automation/get-editor-evidence-capability.ps1`, `tools/check-addon-parse.ps1`
- **External Docs**: Godot `EditorDebuggerPlugin` reference (https://docs.godotengine.org/en/stable/classes/class_editordebuggerplugin.html), `EditorDebuggerSession` reference, `EngineDebugger` reference (https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html), the GDScript debugger and `breakpoint` keyword tutorial (https://docs.godotengine.org/en/stable/tutorials/scripting/debug/index.html), `push_error`/`push_warning` API documentation, the engine's debug-pause/continue documentation
- **Source References**: `../godot/editor/debugger/` for editor-side debugger session and pause/resume control flow when verifying that `EditorDebuggerSession` exposes a stable continue path; `../godot/core/debugger/` for engine-side error and breakpoint reporting when confirming the runtime-side capture surface and the breakpoint-suppression hook surface area. Both checkouts are read-only reference material per the constitution.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays inside the existing editor addon, runtime addon, debugger transport, broker, manifest writer, and capability publisher, and uses the engine's existing debug-pause state plus the documented `EngineDebugger` error stream rather than any engine-fork or GDExtension path.
- [x] Reference coverage complete: repo docs (`docs/AGENT_RUNTIME_HARNESS.md`, `docs/INTEGRATION_TESTING.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `docs/AI_TOOLING_AUTOMATION_MATRIX.md`), feature-003/004/005/006 precedents, automation-request and run-result contracts, broker and runtime source surfaces, artifact registry, capability helpers, and the cited Godot `EditorDebuggerPlugin`/`EngineDebugger`/`breakpoint` references are cited for each key decision.
- [x] Runtime evidence defined: the plan names the new `runtime-error-records.jsonl` artifact, the new `pause-decision-log.jsonl` artifact, the manifest `runtimeErrorReporting` block (`termination`, `pauseOnErrorMode`, optional `lastErrorAnchor`, two artifact references), the three new capability entries (`runtimeErrorCapture`, `pauseOnError`, `breakpointSuppression`), and the existing run-result `terminationStatus` field as the machine-readable product surface.
- [x] Test loop defined: deterministic Pester fixtures for the pause-decision request validator and the schemas; deterministic editor-launched runs against the `integration-testing/runtime-error-loop/` sandbox with `error_on_frame.gd`, `unhandled_exception.gd`, `warning_only.gd`, and a no-error Pong reuse for capture, pause-on-error, decision honoring, partial-run flush, and termination classification; manifest validation; existing PowerShell regression suite.
- [x] Reuse justified: the preferred path extends the current automation surface, broker, debugger bridge, manifest writer, capability publisher, validator pattern, and artifact registry instead of creating a new broker, second evidence path, or new agent-facing transport.
- [x] Documentation synchronization planned: the plan enumerates updates to `docs/AGENT_RUNTIME_HARNESS.md` (new "Runtime error reporting and pause-on-error" section), `docs/AI_TOOLING_AUTOMATION_MATRIX.md` (capability/routing entries for the three new capability bits), `.github/copilot-instructions.md` (plan pointer between SPECKIT markers; new validation command rows for `submit-pause-decision.ps1` if added), `.github/instructions/addons.instructions.md` and `.github/instructions/tools.instructions.md` (path-scope additions for the new files), `.github/prompts/` and `.github/agents/` only where they currently mention runtime-error or pause behavior, and the deployable `addons/agent_runtime_harness/templates/project_root/` snippets only if the broker default schema or the request directory shape changes. The feature's own `quickstart.md` is the canonical end-to-end agent walkthrough.
- [x] Addon parse-check planned: every implementation task that adds, removes, or edits GDScript under `addons/agent_runtime_harness/` includes a step to run `pwsh ./tools/check-addon-parse.ps1`. A non-zero exit is treated as blocking.

## Project Structure

### Documentation (this feature)

```text
specs/007-report-runtime-errors/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── runtime-error-record.schema.json
│   ├── pause-decision-record.schema.json
│   ├── pause-decision-request.schema.json
│   └── runtime-error-reporting-contract.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
addons/
└── agent_runtime_harness/
    ├── editor/
    ├── runtime/
    ├── shared/
    └── templates/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AGENT_TOOLING_FOUNDATION.md
├── AI_TOOLING_AUTOMATION_MATRIX.md
├── AI_TOOLING_BEST_PRACTICES.md
├── GODOT_PLUGIN_REFERENCES.md
└── INTEGRATION_TESTING.md

integration-testing/
└── runtime-error-loop/        # New sandbox for end-to-end pause-on-error verification

specs/
├── 003-editor-evidence-loop/
├── 004-report-build-errors/
├── 005-behavior-watch-sampling/
├── 006-input-dispatch/
└── 007-report-runtime-errors/

tools/
├── automation/
├── evidence/
└── tests/
    └── fixtures/runtime-error-loop/   # Seeded request fixtures and expected manifests
```

**Structure Decision**: Keep the implementation centered in `addons/agent_runtime_harness/` because runtime-error capture, pause raising, breakpoint suppression, decision validation, and manifest persistence all belong to the same plugin-first control path already used for scenegraph capture, behavior watch, and input dispatch. Extend the broker's capability artifact and add `harness/automation/requests/pause-decision.json` as the inbound decision surface alongside the existing run-request file. Add slice-specific contracts and fixtures under `specs/007-report-runtime-errors/contracts/` and `tools/tests/fixtures/runtime-error-loop/`. Use a new `integration-testing/runtime-error-loop/` sandbox (per `docs/INTEGRATION_TESTING.md` and the "End-to-end plugin testing" section of `tools/README.md`) for end-to-end editor-launched verification rather than reusing the Pong testbed, because pause-on-error verification needs scenes that intentionally emit errors and that intent should not be entangled with the Pong gameplay fixtures.

## Implementation Alternatives

### Preferred V1 Path: Extend the current debugger channel, broker, and manifest flow

- Capture engine-reported errors and `push_error`/`push_warning` records on the runtime side through the existing `EngineDebugger` capture channel; deduplicate by `(scriptPath, line, severity)` with a rolling `repeatCount` capped at 100; forward each new dedup-key occurrence to the editor as a `runtime_error_record` debugger message.
- Raise the engine's existing debug-pause state from the runtime when an `error`-severity record or unhandled exception is observed and `pauseOnError.supported = true`; emit a `runtime_pause` debugger message carrying cause, originating location, and `Engine.get_process_frames()` ordinal.
- Poll `harness/automation/requests/pause-decision.json` from the broker while a pause is outstanding; validate via a new `PauseDecisionRequestValidator`; forward the accepted decision through the debugger channel as `pause_decision`; resume or stop via `EditorDebuggerSession`.
- Persist `runtime-error-records.jsonl` and `pause-decision-log.jsonl` through the existing manifest writer; register both kinds in `tools/evidence/artifact-registry.ps1`; add the `runtimeErrorReporting` block (with `termination`, `pauseOnErrorMode`, `lastErrorAnchor`, and two artifact references) to the manifest.
- Advertise three first-class capability entries (`runtimeErrorCapture`, `pauseOnError`, `breakpointSuppression`) in the broker's capability artifact and the workspace-side reader.
- Apply degraded mode automatically when `pauseOnError.supported = false`: capture-only, no pause, manifest stamped `pauseOnErrorMode = "unavailable_degraded_capture_only"`. Never reject the run on this basis.
- Suppress user `breakpoint` statements at runtime through the documented engine hook where available; otherwise route any breakpoint pause through the same pause-decision flow with `cause = paused_at_user_breakpoint`.

### Alternative 1: Introduce a separate runtime-error broker or second request path

- A dedicated request file or IPC path could isolate pause-decision traffic from the existing run request.
- Rejected for v1 because it splits the autonomous run contract into parallel entrypoints and forces agents to coordinate across multiple request surfaces. The single broker is the supported v1 control plane.

### Alternative 2: Pause from the editor side based on streamed error messages

- The editor could decide which runtime-error messages constitute pause triggers and issue `EditorDebuggerSession` debug-pause requests.
- Rejected for v1 because severity classification belongs at the runtime where the error is observed; round-tripping severity decisions to the editor adds latency and races between the next-frame error fire and the editor's pause signal.

### Alternative 3: Implement pause as an in-runtime sleep loop

- The runtime addon could sleep its `_process` loop while a pause is outstanding instead of using the engine's debug-pause state.
- Rejected because it does not actually pause the engine (physics, signals, autoloads keep ticking) and would violate the "real engine pause" expectation the clarifications encode.

### Alternative 4: Stream errors live to the editor without a persisted artifact

- Live debugger streams could let the editor display errors without writing an artifact.
- Rejected because the manifest-centered evidence bundle is the agreed post-run handoff, and live-only capture would not survive a partial-run crash, which is exactly the case the `lastErrorAnchor` field is meant to handle.

### Alternative 5: Capture all `print` output as runtime-error records

- A broader capture surface could include plain `print`/`print_rich` output.
- Rejected because it explodes artifact size, conflates diagnostics with general logging, and contradicts clarification Q2's `error`/`warning`-only severity scope.

### Escalation Paths Not Planned For V1

- GDExtension is not planned unless the engine-debugger error stream and the documented breakpoint-suppression hook prove insufficient on supported platforms. Concrete blockers MUST be cited before escalation.
- Engine changes remain out of scope unless documented addon, autoload, debugger, and GDExtension options are shown insufficient with cited evidence.
- C# exceptions, GDExtension-side faults, and native crashes remain best-effort with explicit unknown markers; first-class non-GDScript exception capture is a later slice.
- Replay-style "rewind to before the error" is out of scope; the harness only pauses, captures, and lets the agent stop or continue.

## Phase 0: Research Focus

1. Confirm the smallest additive extension to the existing `EngineDebugger`/`EditorDebuggerPlugin` channel that can carry the three new message names (`runtime_error_record`, `runtime_pause`, `pause_decision`) without breaking the existing `snapshot`, `persisted`, `session_configured`, and `runtime_error` messages.
2. Confirm that the runtime-side capture surface for `push_error`, `push_warning`, failed `assert`, unhandled exceptions, and engine-reported runtime errors is exposed through the documented `EngineDebugger` API, and document any Godot version caveats relevant for the first release. Confirm the dedup hash key (`scriptPath`, `line`, `severity`) is sufficient given Godot's error metadata.
3. Confirm that the engine's existing debug-pause state can be raised from the runtime side (without the user pressing pause in the editor) and resumed via `EditorDebuggerSession.send_message("continue")` (or the documented equivalent), and confirm the stop path (`EditorDebuggerSession` stop) is the supported way to terminate a paused run cleanly.
4. Confirm whether the engine exposes a documented runtime hook to suppress user-set GDScript `breakpoint` statements while the harness owns the debugger session. If no such hook exists on the current Godot 4.x release, confirm that breakpoints at least raise the same engine debug-pause state so the harness can route them through the pause-decision flow with a distinct cause.
5. Confirm the new artifact shapes against the existing artifact registry contract: `runtime-error-records` (`runtime-error-records.jsonl`, media type `application/jsonl`) and `pause-decision-log` (`pause-decision-log.jsonl`, media type `application/jsonl`). Confirm the manifest writer can attach the new `runtimeErrorReporting` block alongside existing artifact references without breaking `pwsh ./tools/evidence/validate-evidence-manifest.ps1`.
6. Confirm the capability extension shape: three first-class entries (`runtimeErrorCapture`, `pauseOnError`, `breakpointSuppression`) each carrying `{ supported, reason }`, mirroring the existing `inputDispatch` entry.
7. Confirm the deterministic validation shape for valid and invalid pause-decision requests (codes `missing_field`, `unsupported_field`, `invalid_decision`, `unknown_pause`, `decision_already_recorded`) and the deterministic editor-launched fixture set (`error_on_frame.gd`, `unhandled_exception.gd`, `warning_only.gd`, plus a no-error Pong reuse) for end-to-end verification.

## Phase 1: Design Focus

1. Design the runtime-error capture path: subscribe to the engine's error stream through `EngineDebugger`, classify severity (`error` for runtime errors / failed `assert` / `push_error` / unhandled exceptions; `warning` for `push_warning`), dedup on `(scriptPath, line, severity)` with a rolling `repeatCount` and `truncatedAt: 100` annotation, and forward each new dedup-key occurrence to the editor as a `runtime_error_record` debugger message.
2. Design the pause-on-error path: when an `error`-severity record or unhandled exception is observed and `pauseOnError.supported = true`, raise the engine's existing debug-pause state from the runtime, send a `runtime_pause` message with cause/script/line/function/message/processFrame, and freeze any cooperating subsystems (queued input-dispatch events from feature 006).
3. Design the pause-decision request flow: new `harness/automation/requests/pause-decision.json` consumed-and-deleted by the broker; new `PauseDecisionRequestValidator` modeled on `BehaviorWatchRequestValidator` and `InputDispatchRequestValidator`; rejection codes `missing_field | unsupported_field | invalid_decision | unknown_pause | decision_already_recorded`; broker poll cadence bounded to once per editor frame; broker forwards accepted decisions to the runtime via `pause_decision` debugger message; runtime resumes via `EditorDebuggerSession` continue or terminates via stop.
4. Design the decision-timeout path: editor-side timer (default 30 s, configurable) that fires when a pause notification is outstanding without a recorded decision; on expiry, applies `decision = timeout_default_applied`/`decisionSource = timeout_default`, sends the runtime a stop instruction, records the per-pause row, and stamps the manifest termination as `stopped_by_default_on_pause_timeout`.
5. Design the artifact and manifest shape: `runtime-error-records.jsonl` and `pause-decision-log.jsonl` registered in `tools/evidence/artifact-registry.ps1`; new `runtimeErrorReporting` block on the manifest carrying `termination`, `pauseOnErrorMode`, `lastErrorAnchor` (when crashed), and two artifact references; partial-run flush path that writes both artifacts at runtime shutdown even when the run crashed mid-script; stale-artifact guards that ensure the current run's manifest references current-run files only.
6. Design the capability extension and degraded mode: three first-class entries (`runtimeErrorCapture`, `pauseOnError`, `breakpointSuppression`) on the capability artifact; broker logic to apply degraded mode automatically when `pauseOnError.supported = false` (capture-only, no pause, manifest stamped `unavailable_degraded_capture_only`); never reject the run on this basis.
7. Design the breakpoint-suppression hook: install runtime-side suppression where the engine exposes a documented hook; otherwise advertise `breakpointSuppression.supported = false` with `reason = "engine_hook_unavailable"` and route any breakpoint-triggered pause through the same pause-decision flow with `cause = paused_at_user_breakpoint` and a distinct decision-record path.
8. Design deterministic fixtures and the end-to-end verification flow: seeded `integration-testing/runtime-error-loop/` sandbox with `error_on_frame.gd`, `unhandled_exception.gd`, `warning_only.gd`, and a no-error Pong reuse; matching request fixtures and expected-outcome JSON under `tools/tests/fixtures/runtime-error-loop/`; a workspace-side `tools/automation/submit-pause-decision.ps1` helper modeled on `request-editor-evidence-run.ps1`; quickstart instructions that prove each acceptance scenario without depending on later-slice fields or non-GDScript exception capture.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the preferred path still relies on the current editor addon, runtime addon, debugger bridge, broker, manifest writer, capability publisher, and the engine's existing debug-pause state only.
- [x] Reference coverage remains complete after design: every design decision maps back to repo docs, feature-003/004/005/006 precedents, the automation-request and run-result contracts, the artifact registry, the capability surface, and the cited Godot `EditorDebuggerPlugin`/`EngineDebugger`/`breakpoint` references.
- [x] Runtime evidence remains the product surface: agents still read the run result and persisted manifest first, then open `runtime-error-records.jsonl` and `pause-decision-log.jsonl` from the manifest references alongside the existing scenegraph, diagnostics, summary, behavior-trace, and input-dispatch artifacts.
- [x] Test loop remains defined after design: deterministic request-fixture validation for the new validator and schemas, deterministic editor-launched runs against the `integration-testing/runtime-error-loop/` sandbox for capture/pause/decision/termination paths, manifest validation, addon parse-check, and the existing PowerShell regression suite remain the proof path.
- [x] Reuse remains justified after design: the feature stays an incremental extension of the current debugger channel, broker, manifest writer, capability surface, validator pattern, and artifact registry instead of a parallel subsystem.
- [x] Documentation synchronization remains planned after design: the surfaces enumerated in the pre-design check are unchanged, with the addition that the new `tools/automation/submit-pause-decision.ps1` helper, if added, MUST appear in `tools/README.md` and the validation-commands list in `.github/copilot-instructions.md` and `AGENTS.md`.
- [x] Addon parse-check remains planned: every Phase 2 task touching GDScript under `addons/agent_runtime_harness/` includes a `pwsh ./tools/check-addon-parse.ps1` step and treats a non-zero exit as blocking.

## Phase 2 Preview

Expected tasks will group into:

1. Capability surface: extend the broker's `evaluate_capability` to publish `runtimeErrorCapture`, `pauseOnError`, and `breakpointSuppression`; update `tools/automation/get-editor-evidence-capability.ps1` to surface them; add Pester coverage for the new entries.
2. Constants and validator: extend `addons/agent_runtime_harness/shared/inspection_constants.gd` with the new severity, cause, decision, decision-source, termination, pause-mode, and rejection-code constants; add `addons/agent_runtime_harness/shared/pause_decision_request_validator.gd` mirroring the existing validator pattern; add Pester coverage for each rejection code.
3. Runtime capture and pause: extend `scenegraph_runtime.gd` to subscribe to engine errors, classify and dedup records, install the breakpoint-suppression hook (where available), raise engine debug-pause for `error`-severity and unhandled-exception cases, and emit the new debugger messages; add the partial-run flush path. Run `pwsh ./tools/check-addon-parse.ps1` after each edit.
4. Editor bridge and broker decision flow: extend `scenegraph_debugger_bridge.gd` to recognize `runtime_error_record`, `runtime_pause`, and `pause_decision_ack`; extend `scenegraph_automation_broker.gd` and `scenegraph_run_coordinator.gd` to poll for `pause-decision.json`, validate it, forward decisions, enforce the timeout default, classify termination, and stamp the manifest. Run `pwsh ./tools/check-addon-parse.ps1` after each edit.
5. Outcome persistence: extend `scenegraph_artifact_writer.gd` to write `runtime-error-records.jsonl` and `pause-decision-log.jsonl`; register both kinds in `tools/evidence/artifact-registry.ps1`; add the `runtimeErrorReporting` manifest block; ensure stale-artifact guards stay current-run-only; update `tools/evidence/validate-evidence-manifest.ps1` if the manifest schema changes; add Pester coverage for the registry entries.
6. Workspace helper: add `tools/automation/submit-pause-decision.ps1` mirroring `request-editor-evidence-run.ps1`, with parameter validation that mirrors the GDScript validator's rejection codes.
7. Deterministic verification: scaffold `integration-testing/runtime-error-loop/` per `docs/INTEGRATION_TESTING.md`, deploy the harness with `pwsh ./tools/deploy-game-harness.ps1`, parse-check, run the four seeded fixtures (error / unhandled exception / warning-only / no-error), and confirm artifacts and manifest classification with `pwsh ./tools/evidence/validate-evidence-manifest.ps1` and `pwsh ./tools/tests/run-tool-tests.ps1`.
8. Documentation synchronization: add the "Runtime error reporting and pause-on-error" section to `docs/AGENT_RUNTIME_HARNESS.md`; add the new capability and routing rows to `docs/AI_TOOLING_AUTOMATION_MATRIX.md`; update `.github/copilot-instructions.md`, the relevant `.github/instructions/*.instructions.md`, and `AGENTS.md` validation-commands sections to mention the new artifact kinds, capability bits, request file, and helper script; cross-link the quickstart from the docs.

## Complexity Tracking

No constitution violations are expected. The preferred path deliberately stays narrow: reuse the current debugger channel, the plugin-owned broker, the manifest writer, the capability publisher, the validator pattern already established for behavior-watch and input-dispatch requests, and the engine's existing debug-pause state. No GDExtension or engine-fork escalation is planned for v1.
