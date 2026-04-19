
# Research: Runtime Input Dispatch

## Decision 1: Request Surface

**Decision**: Carry the script through the existing automation run request under `overrides.inputDispatchScript`, matching the existing `overrides.behaviorWatchRequest` precedent. No new broker, no new request file, no new IPC entrypoint.

**Rationale**: The current automation request is already the single control-plane surface for run-scoped overrides that are evaluated before launch. Reusing `overrides.*` keeps the run identifier, target scene, capture policy, stop policy, behavior watch, and input dispatch in one validated document the editor normalizes before start. This matches the reuse-before-reinvention constitution gate and mirrors feature 005.

**Alternatives Considered**:

- Separate `harness/automation/requests/input-dispatch-script.json` next to the run request. Rejected because it creates two parallel control surfaces the agent must keep in sync for a single run.
- New `EngineDebugger` capture message type dedicated to input dispatch. Rejected because it forces the editor to ship and validate an additional command path for a feature that can live in the existing session configuration.

## Decision 2: Dispatch Path

**Decision**: Deliver every accepted event from the runtime addon by building an `InputEventKey` (for `key` events, setting `keycode` from the logical `Key` enum and `pressed` from the phase) or an `InputEventAction` (for `action` events, setting `action` to the declared name and `pressed` from the phase) and calling `Input.parse_input_event()`.

**Rationale**: `Input.parse_input_event()` is the documented Godot API that routes a synthesized event through the same pipeline as a real keypress, so `_input`, `_unhandled_input`, and `Input.is_action_*` observe the event identically. This is the minimum plugin-first surface that can reproduce the Pong numpad-Enter `_unhandled_input` crash described in issue #12 without bypassing the input code path. Using `InputEventKey.keycode` (the `Key` enum) instead of `physical_keycode` keeps the contract layout-neutral across host keyboards.

**Alternatives Considered**:

- Calling scene scripts (autoload shim) or signalling action handlers directly. Rejected because it skips `_unhandled_input` and `Input.is_action_*`, meaning issue #12 would not be reproduced through the crashing code path.
- Synthesizing OS keystrokes with host tools (`xdotool`, `SendInput`). Rejected because it depends on window focus and host keyboard layouts and produces no in-engine outcome evidence.
- Using only `Input.action_press()` / `Input.action_release()`. Insufficient because the Pong crash is anchored on `_unhandled_input` receiving an `InputEventKey` with `KEY_KP_ENTER`, and some game scripts only read `InputEventKey` (not action state) inside `_unhandled_input`; keyboard-keycode events are required.

## Decision 3: Frame Timeline Anchor

**Decision**: Anchor declared frames to `Engine.get_process_frames()` offset from a baseline captured at the runtime addon's first `_process()` callback after the playtest boots. A declared event with `frame: N` is delivered on the first process frame where `Engine.get_process_frames() - baseline >= N`, in declared order for ties.

**Rationale**: Process-frame anchoring is deterministic across hosts at the granularity the harness already uses for behavior-watch cadence. Capturing the baseline at the first post-boot `_process()` tick gives a stable playtest-local frame 0 that is independent of editor build or launch overhead. Physics-frame anchoring is a later-slice field and MUST be rejected at validation (FR-021).

**Alternatives Considered**:

- Wall-clock anchoring with millisecond offsets. Rejected because it is not deterministic across hosts under load.
- `Engine.get_physics_frames()` anchoring. Rejected for v1; physics-frame scripting is a later-slice field per the clarifications.

## Decision 4: Outcome Artifact Shape

**Decision**: Register a new `input-dispatch-outcomes` artifact kind (file name `input-dispatch-outcomes.jsonl`, media type `application/jsonl`) in `tools/evidence/artifact-registry.ps1`. Each declared event writes exactly one row with explicit top-level fields `runId`, `eventIndex`, `declaredFrame`, `dispatchedFrame`, `kind`, `identifier`, `phase`, `status`, `reasonCode`, `reasonMessage`. `status` uses the fixed enum `dispatched | skipped_frame_unreached | skipped_run_ended | failed`.

**Rationale**: JSONL matches the existing `trace.jsonl` pattern and allows the runtime addon to flush per-event rows deterministically, including in the partial-run path if the playtest crashes mid-script (which is the case for issue #12). Registering the kind in `tools/evidence/artifact-registry.ps1` keeps `tools/evidence/validate-evidence-manifest.ps1` aware of the new artifact without a one-off schema. The fixed four-value status enum removes ambiguity for agents reading outcomes.

**Alternatives Considered**:

- Single `input-dispatch-outcomes.json` document with an array. Rejected because it does not survive a playtest crash partway through writing, and the per-event row format is a better fit for the existing evidence-bundle reading pattern.
- Embedding outcomes in the scenegraph summary or the behavior-trace artifact. Rejected because it conflates unrelated evidence surfaces and forces the summary or trace schema to carry input-dispatch fields.

## Decision 5: Capability Advertisement

**Decision**: Add an `inputDispatch` entry to the existing editor-evidence capability artifact produced by `addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd` and read by `tools/automation/get-editor-evidence-capability.ps1`. The entry reports `supported: bool` and, when `false`, a short machine-readable `reason`. The request validator rejects requests with `unsupported_identifier` or a matching `capability_unsupported` code when capability is `false`.

**Rationale**: Agents already gate automation requests on capability. Adding a first-class capability entry lets agents detect environments where input dispatch is not supported before composing a run request, and guarantees that unsupported runs fail fast and machine-readably.

**Alternatives Considered**:

- Deriving support implicitly from the current plugin version. Rejected because the capability artifact is the existing single source of truth for "what the editor can do right now", and platform-specific reasons (for example, headless builds that suppress input) deserve a machine-readable reason field.

## Decision 6: Validation Strategy

**Decision**: Add a new `InputDispatchRequestValidator` class in `addons/agent_runtime_harness/shared/` modeled on `BehaviorWatchRequestValidator`. It returns a normalized `accepted` payload or a structured `rejected` payload with one or more `reasonCode` values from the enum `missing_field | unsupported_field | later_slice_field | unsupported_identifier | unmatched_release | script_too_long | invalid_phase | invalid_frame | duplicate_event`. Deterministic Pester coverage runs against fixture files that exercise each code.

**Rationale**: Reusing the validator pattern keeps the rejection style consistent across features and makes the request contract easy for agents to reason about. The codes follow the behavior-watch precedent. Fixture-driven coverage proves rejection paths without needing an editor session and keeps the validator independent of runtime code.

**Alternatives Considered**:

- Inline validation inside the run coordinator. Rejected because it couples script rules to editor orchestration and makes it hard to reuse the same validator from other consumers (for example, an agent that wants to dry-run a script).

## Decision 7: Out-of-Scope Rejection

**Decision**: Explicitly reject later-slice fields at the validator with `later_slice_field`. Rejected fields include `mouse`, `touch`, `gamepad`, `recordedReplay`, `physicalKeycode`, and `physicsFrame`.

**Rationale**: Following feature 005's precedent ensures agents get a clear, machine-readable signal that these inputs are deferred to later work rather than silently accepted or partially implemented. This prevents drift between the contract and the runtime.

**Alternatives Considered**:

- Silently ignore unknown fields. Rejected because it lets agents accumulate scripts that look valid but never produce their intended effects.

## Decision 8: Deterministic Reproduction Target

**Decision**: Use the Pong testbed (`examples/pong-testbed/`) with a new request fixture that declares a two-event numpad-Enter script (`press` then `release` on `KP_ENTER`) starting a few frames after title-screen entry. The acceptance criterion is that the playtest reaches the `_unhandled_input` crash described in issue #12 and the resulting evidence bundle captures both the diagnostics manifest entry for the crash and the `input-dispatch-outcomes.jsonl` artifact with the press row recorded as `dispatched` and the release row recorded as either `dispatched` or `skipped_run_ended` (crash-dependent).

**Rationale**: Grounding the feature on a real crash fixture gives the team a single unambiguous acceptance signal and tests the partial-run flush path automatically. It also confirms the end-to-end loop (request -> validate -> launch -> dispatch -> capture -> persist -> shutdown) with no hand-wavy "it should work" steps.

**Alternatives Considered**:

- A synthetic counter scene that increments on `KP_ENTER`. Rejected because it would not exercise the `_unhandled_input` crash path or the partial-run flush.
