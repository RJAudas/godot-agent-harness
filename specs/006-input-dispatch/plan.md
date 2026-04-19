
# Implementation Plan: Runtime Input Dispatch

**Branch**: `006-input-dispatch` | **Date**: 2026-04-19 | **Spec**: [specs/006-input-dispatch/spec.md](specs/006-input-dispatch/spec.md)
**Input**: Feature specification from `/specs/006-input-dispatch/spec.md`

## Summary

Extend the existing editor-launched evidence loop so an autonomous run can carry a bounded `inputDispatchScript` that names keyboard (`Key` enum) and declared input-action press/release events anchored to the playtest's process-frame timeline, validate and normalize that script before launch using the same strict machine-readable rejection model already used for `behaviorWatchRequest`, deliver each accepted event from the runtime addon through Godot's real input pipeline with `Input.parse_input_event()` (so `_input`, `_unhandled_input`, and `Input.is_action_*` see the event as a genuine keypress), persist a fixed per-event `input-dispatch-outcomes.jsonl` artifact referenced from the current run's manifest-centered evidence bundle, and advertise input-dispatch support through the existing editor-evidence capability artifact. The preferred v1 path reuses the current automation run request surface, the debugger-backed session configuration, the runtime addon, the manifest writer, the capability publisher, and the shared artifact registry rather than creating a second broker, a second evidence path, or an OS-level keystroke injector. The concrete acceptance target is the Pong testbed crash described in issue #12 (numpad Enter on the title screen).

## Technical Context

**Language/Version**: GDScript for Godot 4.x addon and runtime scripts, JSON Schema Draft 2020-12 for contract surfaces, Markdown for design artifacts, PowerShell 7+ for request-writing, capability-read, and validation helpers under `tools/`
**Primary Dependencies**: Godot `EditorPlugin`, `EditorDebuggerPlugin`, `EditorDebuggerSession`, `EngineDebugger`, `Input`, `InputEventKey`, `InputEventAction`, `InputMap`, `Key` enum; existing automation run request contract in `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`; editor bridge in `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`; run coordinator in `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`; runtime session handling in `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`; manifest writer in `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`; validator pattern in `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`; artifact registry in `tools/evidence/artifact-registry.ps1`; capability publisher in `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`; capability reader in `tools/automation/get-editor-evidence-capability.ps1`
**Storage**: Run-scoped automation request and result JSON under project-local `harness/automation/`; run-scoped evidence bundles under project `res://evidence/...` output directories; fixed `input-dispatch-outcomes.jsonl` colocated with the current run's manifest, scenegraph, diagnostics, summary, and behavior-trace artifacts; feature planning artifacts under `specs/006-input-dispatch/`
**Testing**: Contract-fixture validation for script normalization and rejection without launching the game (new Pester coverage alongside the existing `BehaviorWatchRequestValidator` tests); deterministic Pong editor-evidence runs through the existing automation broker for press/release delivery and outcome persistence; manifest validation with `pwsh ./tools/evidence/validate-evidence-manifest.ps1`; existing PowerShell regression suite with `pwsh ./tools/tests/run-tool-tests.ps1` when tool, schema, or capability helpers change; combined validation because the feature changes runtime-visible behavior and has an existing deterministic tool-level test surface
**Target Platform**: Godot 4.x editor on Windows, macOS, and Linux with the example project already open on the same machine as VS Code; headless runs are not required for v1, but the input-dispatch path MUST stay layout-neutral by using logical `Key` enum keycodes rather than physical scancodes
**Project Type**: Editor addon plus runtime addon plus debugger-integration contract extension layered onto the current plugin-owned file broker
**Performance Goals**: Keep the script cap at 256 events per run to bound validator work, per-frame dispatch cost, and outcome artifact size; deliver each accepted event within the same process frame the agent targeted so the dispatched-frame recorded in the outcome artifact equals the requested frame in deterministic Pong runs; emit the final outcome artifact and its manifest reference within the existing 60-second post-run budget used for other evidence artifacts
**Constraints**: Plugin-first only; no engine fork; no GDExtension unless addon and debugger surfaces prove insufficient; keyboard keys and declared input actions only (mouse, touch, gamepad, and real-human-input replay are explicit later-slice fields); logical `Key` enum names only (physical scancodes are a later-slice field); process-frame anchoring only (physics-frame anchoring is a later-slice field); fixed outcome artifact shape with the enum `dispatched | skipped_frame_unreached | skipped_run_ended | failed`; reject release events without a matching prior press before launch with `unmatched_release`; reject scripts over 256 events with `script_too_long`; no stale artifact reuse across runs; no OS-level keystroke injection; no direct method calls into game scripts as substitutes for the input pipeline
**Scale/Scope**: Primarily touches `addons/agent_runtime_harness/shared/` (new validator alongside `behavior_watch_request_validator.gd`), `addons/agent_runtime_harness/editor/` (run coordinator, debugger bridge, and capability publisher), `addons/agent_runtime_harness/runtime/` (runtime session, dispatcher, and artifact writer), `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` (additive `overrides.inputDispatchScript`), feature-local contracts and design artifacts under `specs/006-input-dispatch/`, deterministic Pong fixtures under `examples/pong-testbed/`, and narrow evidence or test helpers under `tools/` (artifact registry entry, capability surface, Pester coverage)

## Reference Inputs

- **Internal Docs**: `README.md`, `AGENTS.md`, `docs/AGENT_RUNTIME_HARNESS.md`, `docs/AGENT_TOOLING_FOUNDATION.md`, `docs/GODOT_PLUGIN_REFERENCES.md`, `docs/BEHAVIOR_CAPTURE_SLICES.md`, `specs/003-editor-evidence-loop/spec.md`, `specs/003-editor-evidence-loop/contracts/editor-evidence-loop-contract.md`, `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`, `specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json`, `specs/004-report-build-errors/plan.md`, `specs/005-behavior-watch-sampling/spec.md`, `specs/005-behavior-watch-sampling/plan.md`, `specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json`, `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd`, `addons/agent_runtime_harness/shared/inspection_constants.gd`, `addons/agent_runtime_harness/editor/scenegraph_debugger_bridge.gd`, `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`, `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd`, `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`, `addons/agent_runtime_harness/runtime/scenegraph_artifact_writer.gd`, `tools/evidence/artifact-registry.ps1`, `tools/automation/request-editor-evidence-run.ps1`, `tools/automation/get-editor-evidence-capability.ps1`, `examples/pong-testbed/harness/inspection-run-config.json`, `examples/pong-testbed/harness/automation/requests/run-request.healthy.json`
- **External Docs**: Godot `Input` class reference (`parse_input_event`, `is_action_pressed`), `InputEvent`, `InputEventKey` (`keycode`, `pressed`, `echo`), `InputEventAction` (`action`, `pressed`), `InputMap` action lookup, `Engine.get_process_frames`, the input examples tutorial, and the unhandled-input tutorial, all as cited in the feature spec and consistent with `docs/GODOT_PLUGIN_REFERENCES.md`
- **Source References**: No `../godot` source files need to be vendored. If runtime-verification of `Input.parse_input_event` propagation into `_unhandled_input` is needed during implementation, the `../godot` checkout MUST be treated as read-only reference material per the constitution.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Plugin-first approach preserved: the plan stays inside the existing editor addon, runtime addon, debugger transport, manifest writer, and capability publisher, and uses the engine-provided `Input.parse_input_event()` API rather than any engine-fork or OS-level injection path.
- [x] Reference coverage complete: repo docs, feature-005 precedent, automation-request contract, editor and runtime source surfaces, artifact registry, capability helpers, and the relevant Godot `Input`/`InputEventKey`/`InputEventAction` references are cited for each key decision.
- [x] Runtime evidence defined: the plan names the normalized applied-input-dispatch summary, the fixed `input-dispatch-outcomes.jsonl` artifact, its `input-dispatch-outcomes` manifest artifact reference, and the capability entry as the machine-readable product surface.
- [x] Test loop defined: deterministic request-fixture validation (valid Pong numpad-Enter script plus invalid fixtures for each rejection code) plus deterministic Pong editor-evidence runs for press/release delivery and outcome persistence, plus Pester regression coverage for the new validator and artifact-registry entry.
- [x] Reuse justified: the preferred path extends the existing automation run request, session configuration, manifest writer, capability publisher, and artifact registry instead of creating a new broker, second evidence path, or OS-level injector.

## Project Structure

### Documentation (this feature)

```text
specs/006-input-dispatch/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
└── tasks.md
```

### Source Code (repository root)

```text
addons/
└── agent_runtime_harness/
    ├── editor/
    ├── runtime/
    └── shared/

docs/
├── AGENT_RUNTIME_HARNESS.md
├── AGENT_TOOLING_FOUNDATION.md
└── GODOT_PLUGIN_REFERENCES.md

examples/
└── pong-testbed/

specs/
├── 003-editor-evidence-loop/
└── 005-behavior-watch-sampling/

tools/
├── automation/
├── evidence/
└── tests/
```

**Structure Decision**: Keep the implementation centered in `addons/agent_runtime_harness/` because script validation (mirroring the behavior-watch validator), runtime dispatch, and manifest persistence all belong to the same plugin-first control path already used for scenegraph capture and behavior watch. Extend `specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json` with an additive `overrides.inputDispatchScript` field, add slice-specific request, outcome-row, and capability contracts under `specs/006-input-dispatch/contracts/`, use `examples/pong-testbed/` for deterministic input-dispatch fixtures (including the numpad-Enter reproduction for issue #12), and touch `tools/evidence/` (artifact registry entry) and `tools/tests/` (new Pester coverage for the validator and artifact registry) only where validation requires it.

## Implementation Alternatives

### Preferred V1 Path: Extend the current automation request, session configuration, and manifest flow

- Carry `inputDispatchScript` through the existing automation run request under `overrides.inputDispatchScript`, matching the `overrides.behaviorWatchRequest` precedent.
- Validate and normalize the script before launch with a new `InputDispatchRequestValidator` class in `addons/agent_runtime_harness/shared/`, modeled on `BehaviorWatchRequestValidator` and sharing its strict machine-readable rejection style.
- Deliver the normalized script through the existing `configure_session` debugger message so the runtime receives it alongside the other run-scoped overrides.
- Dispatch accepted events from the runtime side through `Input.parse_input_event()` using `InputEventKey` (logical `keycode` from the `Key` enum, `pressed` set from the declared phase) for keyboard events and `InputEventAction` (`action` name from `InputMap`, `pressed` set from the declared phase) for action events, so the same engine input pipeline handles each event as it would a genuine keypress.
- Record every declared event as a row in a new fixed `input-dispatch-outcomes.jsonl` artifact in the current run's output directory and add an `input-dispatch-outcomes` reference to the current manifest.
- Advertise input-dispatch support as a first-class entry (`inputDispatch`) in the existing editor-evidence capability artifact so agents can gate requests on advertised support.

### Alternative 1: Introduce a separate input-dispatch broker or second request path

- A dedicated request file or IPC path could isolate input dispatch from scenegraph and behavior automation.
- Rejected for v1 because it would split the autonomous run contract into parallel entrypoints and force agents to coordinate across multiple request surfaces for a single run.

### Alternative 2: Drive input through an autoload shim or direct method calls into game scripts

- An autoload could emit signals or call accept handlers directly when a frame counter matches a requested offset.
- Rejected for v1 because it bypasses `_input`, `_unhandled_input`, action remapping, and `Input.is_action_*`; it would not reproduce the Pong title-screen `_unhandled_input` crash described in issue #12 through the real input code path and is explicitly forbidden by FR-009.

### Alternative 3: Use OS-level keystroke injection (`xdotool`, `SendInput`, etc.)

- Host-side tooling could synthesize real OS keystrokes against the Godot window.
- Rejected for v1 because it depends on window focus, host OS differences, and keyboard layouts the harness is trying to remove from the reproduction loop, and because it provides no in-engine outcome evidence.

### Alternative 4: Stream per-event outcomes live to the editor without a persisted artifact

- A live debugger stream could let the editor display outcomes without writing an artifact.
- Rejected for v1 because the manifest-centered evidence bundle is the agreed post-run handoff surface, and live-only outcomes would not survive a playtest crash partway through a script (which is exactly the case for issue #12's `_unhandled_input` crash).

### Escalation Paths Not Planned For V1

- GDExtension is not planned unless `Input.parse_input_event()` and the associated GDScript APIs prove unable to deliver deterministic per-process-frame press/release events with acceptable overhead.
- Engine changes remain out of scope unless documented addon, autoload, debugger, and GDExtension options are shown insufficient with cited evidence.
- Mouse, touch, gamepad, recorded-real-human-input replay, physical scancode dispatch, and physics-frame anchoring are explicit later-slice fields and MUST be rejected at validation time in v1.

## Phase 0: Research Focus

1. Confirm the smallest additive extension to `automation-run-request.schema.json` that can carry `inputDispatchScript` without inventing a new command surface or disturbing existing `behaviorWatchRequest` shape.
2. Confirm that `Input.parse_input_event()` with `InputEventKey` (using `keycode` from the `Key` enum) and `InputEventAction` is the correct plugin-first dispatch path so normal handlers (`_input`, `_unhandled_input`, `Input.is_action_*`) observe the event as they would a real keypress, and document any Godot version caveats relevant for the first release.
3. Confirm the process-frame anchor: `Engine.get_process_frames()` ordinal counted from playtest start, captured on the same tick as the runtime autoload's `_process` callback, is the reference a deterministic dispatcher can use across hosts.
4. Confirm the outcome artifact format: a new `input-dispatch-outcomes` artifact kind registered in `tools/evidence/artifact-registry.ps1` persisted as JSONL next to the existing `trace.jsonl`, `scenegraph-snapshot.json`, `scenegraph-diagnostics.json`, and `summary.json` artifacts.
5. Confirm the capability entry: advertise `inputDispatch` (with a supported/unsupported value and an optional machine-readable reason) as a first-class capability alongside the existing entries in `tools/automation/get-editor-evidence-capability.ps1` and the editor-side publisher, and confirm the request validator can reject a request when capability reports it as unsupported with a reason consistent with the advertised reason.
6. Confirm the deterministic validation shape for valid and invalid scripts (including the four clarified rejection codes `unsupported_identifier`, `unmatched_release`, `script_too_long`, and the existing `later_slice_field`/`unsupported_field` codes from the behavior-watch precedent) plus the deterministic Pong numpad-Enter reproduction run for issue #12 through the current automation flow.

## Phase 1: Design Focus

1. Design the `inputDispatchScript` contract — events (kind `key` or `action`, identifier, phase `press` or `release`, `frame`), optional ordering hint for intra-frame events, and explicit rejection of later-slice fields (`mouse`, `touch`, `gamepad`, `recordedReplay`, `physicalKeycode`, `physicsFrame`) with machine-readable codes.
2. Design the normalized applied-input-dispatch summary and the validator rules, modeled on `BehaviorWatchRequestValidator`, that enforce the 256-event cap, the press/release matching rule, the logical `Key` enum whitelist, and the declared-action-exists check against the project's `InputMap`.
3. Design the runtime dispatcher: a lightweight per-frame scheduler inside the runtime addon that drains events whose `frame <= Engine.get_process_frames() - baseline` in declared order, constructs the appropriate `InputEventKey` or `InputEventAction`, calls `Input.parse_input_event()`, and appends an outcome row. Include the four-value outcome enum and the partial-run flush path for playtest crashes or early exits.
4. Design the `input-dispatch-outcomes.jsonl` row contract with explicit top-level fields (`runId`, `eventIndex`, `declaredFrame`, `dispatchedFrame`, `kind`, `identifier`, `phase`, `status`, `reasonCode`, `reasonMessage`) and register the `input-dispatch-outcomes` artifact in the shared registry.
5. Design the manifest integration and stale-artifact protections so the current run's manifest points only to the current run's outcome artifact, and the capability advertisement and capability-gated request rejection path.
6. Design deterministic request fixtures (valid numpad-Enter Pong reproduction, plus one fixture for each rejection code), Pong runtime verification fixtures for issue #12, and quickstart instructions that prove each acceptance scenario without depending on later-slice fields or OS-level tooling.

## Post-Design Constitution Check

- [x] Plugin-first approach preserved after design: the preferred path still relies on the current editor addon, runtime addon, debugger bridge, manifest writer, capability publisher, and the engine-provided `Input.parse_input_event()` API only.
- [x] Reference coverage remains complete after design: every design decision maps back to repo docs, feature-005 precedent, the automation-request contract, the artifact registry, the capability surface, and the cited Godot `Input`/`InputEventKey`/`InputEventAction`/`InputMap` references.
- [x] Runtime evidence remains the product surface: agents still read the run result and persisted manifest first, then open `input-dispatch-outcomes.jsonl` from the manifest reference alongside the scenegraph, diagnostics, summary, and behavior-trace artifacts.
- [x] Test loop remains defined after design: deterministic request-fixture validation, deterministic Pong input-dispatch reproduction runs for issue #12, manifest validation, and the existing PowerShell regression suite remain the proof path.
- [x] Reuse remains justified after design: the feature stays an incremental extension of the current automation request, session configuration, manifest writer, and capability surface instead of a parallel subsystem.

## Phase 2 Preview

Expected tasks will group into:

1. Request contract and validator: extend the run-request schema with `overrides.inputDispatchScript`, add the slice-specific script and outcome-row contracts under `specs/006-input-dispatch/contracts/`, add `InputDispatchRequestValidator` alongside `BehaviorWatchRequestValidator`, and implement the rejection rules (logical-key whitelist, action-map check, 256-event cap, `unmatched_release`, later-slice rejection).
2. Capability surface: add `inputDispatch` to the editor-side capability publisher and the `tools/automation/get-editor-evidence-capability.ps1` consumer, and gate the validator on the advertised capability value.
3. Runtime dispatcher: add the per-frame scheduler and dispatch path using `Input.parse_input_event()` with `InputEventKey`/`InputEventAction`, anchored to `Engine.get_process_frames()` from the runtime's playtest-start baseline, with release-on-shutdown safety recording.
4. Outcome persistence: write `input-dispatch-outcomes.jsonl`, register the `input-dispatch-outcomes` artifact kind in `tools/evidence/artifact-registry.ps1`, update the manifest writer to reference it, and add the partial-run flush path.
5. Deterministic validation: add valid and invalid script fixtures (including the Pong numpad-Enter reproduction for issue #12), add Pester coverage for the validator and the artifact-registry entry alongside the existing behavior-watch coverage, and verify end-to-end reproduction plus manifest correctness with `pwsh ./tools/tests/run-tool-tests.ps1` and `pwsh ./tools/evidence/validate-evidence-manifest.ps1`.
6. Supporting docs: update the feature-local contracts and quickstart material to reference the new artifact kind, capability entry, and validator, and cross-link the Pong reproduction from the existing runtime-harness docs.

## Complexity Tracking

No constitution violations are expected. The preferred path deliberately stays narrow: reuse the current automation request surface, extend the current manifest-centered bundle, reuse the validator pattern already established for behavior-watch requests, and rely on the engine-provided `Input.parse_input_event()` API for the dispatch path.
