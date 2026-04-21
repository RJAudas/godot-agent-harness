---
applyTo: "addons/agent_runtime_harness/**"
---

# Addon Instructions

- Keep changes plugin-first and compatible with normal Godot addon patterns.
- For GDScript addon code, keep `const` initializers to literal constant expressions (`[]`, `{}`, scalars) instead of constructors such as `PackedStringArray(...)`, and prefer explicit `RegEx`/`RegExMatch` typing when APIs like `search()` do not infer cleanly.
- Prefer structured runtime outputs that an agent can consume directly over editor-only UI state.
- Preserve deterministic scenario and evidence expectations when introducing runtime-facing behavior.
- Do not propose engine-fork changes from addon files unless the task includes evidence that addon, debugger, and GDExtension options are insufficient.
- When a tooling task touches addon files, document the runtime evidence it should emit or consume.
- `addons/agent_runtime_harness/runtime/pause_decision_request_validator.gd` validates pause-decision request payloads received by the broker; keep it aligned with `specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json`.
- New constants added for specs/007 live in `shared/inspection_constants.gd`: `PAUSE_ON_ERROR_MODE_ACTIVE`, `PAUSE_ON_ERROR_MODE_UNAVAILABLE_DEGRADED_CAPTURE_ONLY`, `RUNTIME_TERMINATION_CRASHED`, `RUNTIME_TERMINATION_STOPPED_BY_AGENT`, `RUNTIME_TERMINATION_STOPPED_BY_DEFAULT_ON_PAUSE_TIMEOUT`, `RUNTIME_ERROR_MSG_SET_PAUSE_ON_ERROR_MODE`, `RUNTIME_ERROR_MSG_PAUSE_DECISION_LOG`, `RUNTIME_ERROR_MSG_SET_TERMINATION`, `DEFAULT_LAST_ERROR_ANCHOR_FILE`, `PAUSE_DECISION_STOPPED_BY_DISCONNECT`, `PAUSE_DECISION_RESOLVED_BY_RUN_END`.
- Fix #17 handshake constants also live in `shared/inspection_constants.gd`: `RUNTIME_TO_EDITOR_MSG_SESSION_READY` (runtime → editor after transport registered), `EDITOR_TO_RUNTIME_MSG_CONFIGURE_SESSION_SKIP` (editor → runtime when no broker context is pending), and `SESSION_READY_WATCHDOG_MSEC` (1500 ms fallback before startup capture self-fires). The startup capture in `scenegraph_runtime.gd` MUST NOT fire via `call_deferred` from `_ready()`; it is gated by `_trigger_startup_capture_if_pending()` which fires exactly once after the editor handshake reply (or after the watchdog).
