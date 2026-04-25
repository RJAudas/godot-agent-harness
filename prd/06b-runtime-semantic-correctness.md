# Pass 6b — Runtime semantic correctness

## Scope

Two addon-side bugs deferred from pass 5 and re-confirmed in [pass 6](06-test-pass-results.md). Both require edits to `addons/agent_runtime_harness/` source — the runtime side that pass 5 deliberately scoped out.

| ID | Workflow | What's broken | Fix area |
|---|---|---|---|
| B10 | Runtime-error triage | Runtime errors during `_ready` are not captured; `runtime-error-records.jsonl` stays 0 bytes; envelope reports clean success | addon runtime-error capture pipeline + manifest builder |
| B8 | Runtime-error triage (and any workflow) | Sandbox-level `inspection-run-config.json` silently overrides request `targetScene`, `outputDirectory`, `runId`, `scenarioId` | addon config reader / request precedence logic |

## Why these fit together

- Both addon-side, both touch the runtime/autoload layer.
- Both deferred from pass 5 deliberately (CLAUDE.md guidance steers fixes to orchestration scripts unless the task is explicitly addon).
- Both require running the full broker loop to verify (`tools/check-addon-parse.ps1` is necessary but not sufficient — needs a real editor + injected fault).
- Same risk profile: a regression here breaks every workflow.

## Recommended landing order

**B10 first.** Reasons:

1. It is the load-bearing bug — runtime-error triage is the workflow agents reach for when triaging real crashes, and right now it lies. Every day this stays broken, agents misreport runtime errors as "no errors found."
2. It is conceptually self-contained: instrument the playtest with an error handler, write records, add the artifact to the manifest. No design-precedence questions.
3. It can ship standalone if 6b is too big as a single batch.

**B8 second.** Reasons:

1. Has a design-precedence question that needs alignment before code (see fix proposal below).
2. Less catastrophic — most sandboxes do not ship an `inspection-run-config.json` with hard-coded fields; only `runtime-error-loop` does today. A user-installed sandbox is unlikely to hit this.

If schedule pressure forces a single fix, ship B10 alone.

## Not in scope

- **B14, B15, B16** — orchestration-side envelope shape. See [pass 6a](06a-outcome-shape-cleanup.md). B16's diagnostic-text fix complements B8 — landing it independently makes B8's failure mode less confusing in the meantime.
- **B13, F2, F3** — editor process lifecycle. See [pass 6c](06c-editor-lifecycle-hardening.md). F2's *runtime-side half* (broker idle-state cleanup) is adjacent to B8's config-precedence work; investigation may overlap.

---

## B10 — Runtime errors in `_ready` not captured by runtime-error-triage workflow

**Status**: regression check — same bug surface as pass 5's B10. Pass 5 shipped a `run-and-watch-for-errors-no-early-stop.json` fixture with `stopAfterValidation: false`; the no-early-stop fixture does *not* surface `_ready`-time errors. The fix is runtime-side, not fixture-side.

**Where**: addon runtime-error capture pipeline (the `runtime-error-records.jsonl` writer) and the manifest builder for runtime-error-triage workflows. Files to investigate:

- [addons/agent_runtime_harness/runtime/](../addons/agent_runtime_harness/runtime/) — autoload entry point, capture coordinator
- The manifest builder that emits `evidence-manifest.json` for runtime-error scenarios

**Reproduction**: inject a guaranteed runtime error into probe:
```gdscript
extends Control
func _ready() -> void:
    var n: Node = null
    n.get_name()  # null deref
```
…attach the script to `scenes/main.tscn` Main node, then:
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json
```

**Observed envelope**:
```json
"status": "success",
"failureKind": null,
"outcome": {
  "terminationReason": "completed",
  "latestErrorSummary": null,
  "runtimeErrorRecordsPath": null
}
```

**Underlying state**:
- `runtime-error-records.jsonl` exists but is **0 bytes**.
- The manifest references **only scenegraph artifacts** — `scenegraph-snapshot.json`, `scenegraph-diagnostics.json`, `scenegraph-summary.json`. There is no `artifactRef` of kind `runtime-error-records`.
- `producer.surface = "scenegraph_harness_runtime"`, `manifestId = "scenegraph-runbook-runtime-error-triage-run"` — the manifest is a scenegraph capture, not a runtime-error capture.
- `summary.keyFindings` includes `"Trigger: startup"` — the snapshot is taken at the startup-validation pass, before `_ready` runs (or the playtest exits before the error path can fire).

So pass 5's fixture variant (`stopAfterValidation: false`) is necessary but not sufficient. The real bug is runtime-side: when running under runtime-error-triage scenarios, the addon should:

1. Wait for the playtest to actually run `_ready` (and a few subsequent frames) before validating.
2. Hook into the engine's error-printing path (`EngineDebugger` in Godot 4.x) to capture errors.
3. Add the resulting `runtime-error-records.jsonl` to the manifest's `artifactRefs[]` with kind `runtime-error-records`, **even if empty** when no errors fire (consumers should be able to verify the capture pipeline ran, not infer it from absence).
4. If any error is captured, set `status=fail` in the manifest and populate `latestErrorSummary` from the first record.

The orchestrator can then trust the manifest and project the error into the envelope.

**Symptom (unchanged from pass 5)**: the workflow agents reach for when triaging real runtime errors silently returns clean success. **Highest-impact bug in the matrix.**

**Fix proposal**: this is genuinely runtime-side. As a first cut, instrument the playtest with an autoload that registers an error handler in `_enter_tree` (which fires before any scene `_ready`) and writes records to the configured `runtime-error-records.jsonl` path. Then add the file to the manifest builder's emitted artifacts unconditionally for the runtime-error-triage scenario kind. Suggest a focused spike to confirm `EngineDebugger` (or `add_print_handler` equivalent) is the right hook in Godot 4.6.

**Subtasks**:
1. Spike: in a throwaway script, prove that an autoload running before `_ready` can capture a null-deref in another autoload's `_ready`. ~1 hour. If `EngineDebugger` doesn't fire for `_ready`-time GDScript errors, escalate — may need a different hook entirely.
2. Plumb the captured records into the configured `runtime-error-records.jsonl` path (already declared in the run-request schema).
3. Update the manifest builder to emit `runtime-error-records` as an `artifactRef` for runtime-error-triage scenarios.
4. Update the orchestrator's manifest reader to project `latestErrorSummary` from the first record when `status=fail` in the manifest.
5. Pester / harness integration test: replay the probe-injected null-deref above; assert envelope reports `failureKind=runtime` and `latestErrorSummary` is populated.

**How to verify**: same reproduction. The envelope should report `failureKind=runtime`, `outcome.latestErrorSummary={ file: "res://scripts/error_main.gd", line: 4, message: "Attempt to call function 'get_name' …" }` (or equivalent), and `outcome.runtimeErrorRecordsPath` should resolve to a non-empty JSONL.

---

## B8 — `inspection-run-config.json` silently overrides request `targetScene` and `outputDirectory`

**Status**: regression check — pass 5 noted this as a runtime-side fix, deliberately deferred.

**Where**: [integration-testing/runtime-error-loop/harness/inspection-run-config.json](../integration-testing/runtime-error-loop/harness/inspection-run-config.json) plus the addon code that reads it. The config has:

```json
{
  "scenarioId": "runtime-error-loop-smoke-test",
  "runId": "runtime-error-loop-run-01",
  "targetScene": "res://scenes/no_errors.tscn",
  "outputDirectory": "res://evidence/scenegraph/latest",
  …
}
```

…and these fields take precedence over the request's `targetScene`, `outputDirectory`, `runId`, `scenarioId` even when the request is the active automation request.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot ./integration-testing/runtime-error-loop `
    -RequestJson '<json with targetScene=res://scenes/error_on_frame.tscn, outputDirectory=res://evidence/automation/$REQUEST_ID>'
```

**Observed**: the resulting evidence-manifest.json has `runId: "runtime-error-loop-run-01"` and `scenarioId: "runtime-error-loop-smoke-test"` (from the config), and is written to `evidence/scenegraph/latest/` (from the config's `outputDirectory`). The runtime ran `no_errors.tscn` (the config's `targetScene`), not `error_on_frame.tscn`. The orchestrator then fails validation because the on-disk manifest's runId doesn't match the requestId it was waiting for.

**Symptom**: any sandbox with a populated `inspection-run-config.json` cannot be driven by the runbook against a non-default scene. The agent's request is silently disregarded; no diagnostic, no warning. Combined with B16, the envelope reports a misleading "manifest not found" failure.

**Design question to resolve before coding**: what is `inspection-run-config.json` *for*?

- **Option A (recommended)**: it is editor-side scaffolding that provides defaults *only when no automation request is active*. An incoming `run-request.json` always wins on every overlapping field. Document this in [specs/008-agent-runbook/contracts/](../specs/008-agent-runbook/contracts/).
- **Option B**: it is a sandbox-fixture mechanism — the sandbox author *wants* a fixed scene/runId regardless of what the agent requests. In this case, requests against such sandboxes need explicit error messages ("this sandbox locks targetScene; remove or edit inspection-run-config.json to change it") rather than silent overrides.

Option A is consistent with how the runbook is documented today and how every other field in the automation contract behaves. Option B is more flexible for sandbox authors but introduces a "request can be silently ignored" contract that's hostile to agents. Recommend Option A.

**Fix (assuming Option A)**:

1. **Runtime side** — in the addon's request handler, when both an automation request and an `inspection-run-config.json` are present, request fields *always* take precedence on overlap. Treat the config as a defaults source, not an overrides source.
2. **Orchestrator side** — when the produced manifest's runId/scenarioId don't match the request, surface that explicitly (already partially handled by [B16's fix](06a-outcome-shape-cleanup.md#b16) once landed). Belt-and-suspenders: even with the runtime-side fix, the diagnostic should be specific enough that a regression is obvious.
3. **Documentation** — update [specs/008-agent-runbook/contracts/](../specs/008-agent-runbook/contracts/) to state that automation requests override `inspection-run-config.json` defaults.

**Subtasks**:
1. Locate the addon code that merges request + config. Currently appears to be in the autoload's `apply_run_config()` or equivalent.
2. Invert the precedence: request fields override config fields, not vice versa. Be explicit about which fields are "requestable" (targetScene, outputDirectory, runId, scenarioId, capturePolicy, stopPolicy) versus "automation-only" (the broker paths).
3. Add an addon-level Pester / scene test that loads a config with one set of fields, sends a request with overrides, and asserts the *request* values land in the resulting manifest.
4. Run [pass 6 test 6b](06-test-pass-results.md#test-matrix) end-to-end against runtime-error-loop; the manifest's `runId` should equal the requestId.

**How to verify**: re-run the test 6b reproduction (runtime-error-loop with overridden `targetScene=error_on_frame.tscn`). The runtime should run `error_on_frame.tscn` and produce a manifest whose `runId` equals the requestId. Envelope should report `failureKind=runtime` with `latestErrorSummary` populated from the error_on_frame scene's deliberate error.

---

## Verification — whole batch

After both fixes land:

1. **B10 — re-run pass 6 test 6c**: probe + injected null-deref in `_ready`. Envelope must report `failureKind=runtime` and `outcome.latestErrorSummary` populated. The injected `error_main.gd` reproduction in pass 6's test plan is the canonical test.
2. **B8 — re-run pass 6 test 6b**: runtime-error-loop with `targetScene=error_on_frame.tscn` and `outputDirectory=res://evidence/automation/$REQUEST_ID`. Envelope must show the request's runId and scenarioId in the manifest, not the config's. Runtime must execute `error_on_frame.tscn` (verifiable via the captured runtime-error record's file path).
3. **Combined**: with both fixed, the existing `runtime-error-loop` sandbox should work for any scene the agent requests, and `_ready`-time errors in those scenes should land in the envelope.

## Cross-batch dependencies

- **B10 has no dependencies** — can land standalone.
- **B8 → B10**: a comprehensive B10 fix that always emits `runtime-error-records.jsonl` makes B8's symptom (manifest written to wrong path) easier to verify, because the records file *not* being there at all becomes a separate clear signal from "records there but empty."
- **B8 ↔ B16 ([pass 6a](06a-outcome-shape-cleanup.md#b16))**: B16's fix surfaces `validationResult.notes` to the envelope, making B8's failure mode self-explanatory. Either order works; landing B16 first makes B8's bug easier to triage.
