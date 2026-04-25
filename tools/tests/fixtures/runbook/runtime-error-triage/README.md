# runtime-error-triage fixtures

Two fixtures here, picked by the agent based on whether they actually expect errors to surface.

## `run-and-watch-for-errors-no-early-stop.json` — **default**

`stopAfterValidation: false`. The playtest is allowed to run past the harness's startup validation pass, so errors that occur during `_ready` or in early gameplay frames are captured. This is the fixture the [`godot-debug-runtime` skill](../../../../../.claude/skills/godot-debug-runtime/SKILL.md) and [RUNBOOK.md](../../../../../RUNBOOK.md) point at by default.

For a clean game (no errors) the playtest will run until the orchestration's `-TimeoutSeconds` budget elapses (default 60s), and the envelope returns `failureKind=timeout`. That's the expected "no errors caught" signal.

## `run-and-watch-for-errors.json` — fast smoke test

`stopAfterValidation: true`. The playtest exits the moment the harness validates the scene, before `_ready` runs in many cases. **Runtime errors that occur during `_ready` or after will NOT be captured.** Use this fixture only when you want a quick capability check that the editor + harness loop is alive — never to triage actual runtime errors.

## Why no `frameLimit`

The current run-request schema (`specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json`) only allows `stopAfterValidation` inside `stopPolicy`, and the runtime coordinator only reads that one field. A `frameLimit` would be silently ignored and would also fail schema validation. The orchestration-level `-TimeoutSeconds` is the only frame-bound for now.
