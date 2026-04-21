# Fix Plan: Issue #19 — Runtime Error Records Never Persisted on Abnormal Stop

**Issue**: https://github.com/RJAudas/godot-agent-harness/issues/19  
**Status**: Open (PRs #20 and #21 eliminated the upstream cause but did not fix this bug)

## Problem Summary

When a runtime error fires and the play session ends unexpectedly (or the user hits Stop), `runtime-error-records.jsonl` stays 0 bytes and `last-error-anchor.json` is never written. Two distinct failure paths contribute.

**Path A — coordinator never flushes in-memory records on crash**  
`_fail_run_as_crashed()` in `scenegraph_run_coordinator.gd` emits a status and calls `_finalize_run` but never writes the error records it has already accumulated via `_on_runtime_error_record`. Those records are silently discarded when the session drops.

**Path B — runtime never receives the record before exit**  
The runtime's dedup map and `_flush_last_error_anchor` only fire after a *round-trip* through the editor bridge (`_on_engine_error` → `_send_request(RUNTIME_ERROR_MSG_RECORD, ...)` → runtime handler). If the process exits before that message is processed, neither file is written. There is no runtime-local engine-error sink.

## Proposed Fix

### Step 1 — Coordinator-side accumulation + emergency flush (Path A)

**File**: `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd`

1. Add a new `_runtime_error_records: Array` field. Promote `_on_runtime_error_record` to append the full record there (dedup by `"scriptPath|line|severity"`, respect `RUNTIME_ERROR_REPEAT_CAP`). The existing `_last_error_anchor` / `_runtime_error_record_count` logic is unchanged.
2. Reset `_runtime_error_records` in `start_run`.
3. Add `_emergency_persist_runtime_errors()`:
   - Resolves the absolute output directory via `ProjectSettings.globalize_path` (mirrors `_read_last_error_anchor_sidecar`).
   - Writes `runtime-error-records.jsonl` (one JSON object per line) if the file is missing or 0 bytes — does **not** overwrite a file the runtime already wrote.
   - Writes `last-error-anchor.json` from `_last_error_anchor` if absent.
   - Any I/O failure becomes a coordinator note rather than a second crash.
4. In `_fail_run_as_crashed`, call `_emergency_persist_runtime_errors()` before emitting status / `_finalize_run`.
5. Stamp `validationResult.notes` with `"runtime_error_records: emergency_persisted"` or `"runtime_error_records: none_observed"` so triage agents know this path was used.

### Step 2 — Runtime-side local anchor fallback (Path B)

**File**: `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd`

1. In `_register_debugger_transport`, register a local message capture for the engine's built-in `"error"` channel using `EngineDebugger.register_message_capture`. Parse the payload with the same defensive field extraction already in the bridge's `_on_engine_error`.
2. Route locally-captured records through the existing `_record_runtime_error_from_editor` path — dedup, ordinal, `_flush_last_error_anchor`, and pause-on-error logic remain unchanged.
3. Guard against double-counting: the `(scriptPath, line, severity)` dedup key already coalesces duplicate arrivals from both paths (increments `repeatCount`). Add a note that this is expected behaviour.
4. In `_exit_tree`, attempt a best-effort flush of `_runtime_error_dedup` to `runtime-error-records.jsonl` if the file is missing or 0 bytes — write with `FileAccess`/`DirAccess` only, no SceneTree access.

### Step 3 — Tests

1. **Coordinator unit test** (`tools/tests/`): drive `ScenegraphRunCoordinator` with synthetic `runtime_error_record_received` signals, then trigger a `"disconnected"` state (no manifest, no `stop_requested`). Assert `runtime-error-records.jsonl` and `last-error-anchor.json` are written, non-empty, and valid against the schema.
2. **Runtime unit test** (`tools/tests/`): invoke the local engine-error capture path with a representative `data` array and assert dedup and anchor side effects.
3. **End-to-end repro**: use the existing fixtures in `integration-testing/runtime-error-loop/scripts/` (`crash_after_error.gd`, `unhandled_exception.gd`) in the sandbox project per the steps in the issue.

### Step 4 — Validation gate

After all edits:

1. `pwsh ./tools/check-addon-parse.ps1` — must exit 0.
2. `pwsh ./tools/validate-json.ps1` against the `runtime-error-record` schema for the emergency-written JSONL.
3. `pwsh ./tools/evidence/validate-evidence-manifest.ps1` on a bundle produced by the integration-testing project; manifest must reference the JSONL artifact even on a `crashed` termination.
4. Manual repro in `integration-testing/runtime-error-loop/`: run `crash_after_error.gd`, stop manually, confirm both `runtime-error-records.jsonl` and `last-error-anchor.json` are non-empty.

## Out of Scope

- Changes to the pause-on-error decision flow.
- Reworking the bridge → runtime forwarding contract (kept as primary path; this fix adds belt-and-braces, not a replacement).
- Schema changes to `runtime-error-record`.

## Risk Notes

- Registering `"error"` channel capture inside the runtime needs verification that it does not conflict with the editor-side capture or produce duplicates inside the editor process. The runtime path should be a no-op when running without an active debugger peer (`EngineDebugger.is_active()` guard). Dedup absorbs any double-arrival.
- The `_exit_tree` flush must not access `SceneTree`. Restrict to `FileAccess`/`DirAccess` only.
- Emergency writes on the coordinator side must resolve `res://`-prefixed output directories correctly on all platforms via `ProjectSettings.globalize_path`.

## Files Changed

| File | Change |
|------|--------|
| `addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd` | Add `_runtime_error_records`, promote `_on_runtime_error_record`, add `_emergency_persist_runtime_errors`, call from `_fail_run_as_crashed` |
| `addons/agent_runtime_harness/runtime/scenegraph_runtime.gd` | Register local `"error"` channel sink, add `_exit_tree` best-effort flush |
| `tools/tests/` | New coordinator crash-persist unit test, new runtime local-capture unit test |
