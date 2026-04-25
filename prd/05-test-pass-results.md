# Pass 5 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), and [pass 4](04-polish.md), this pass exercises every runbook tool against a real Godot editor and a real Godot project — not via `Pester`, not via the broker mock — and captures any unexpected behaviors or bugs that show up only against a live editor.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox per pass 4) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures).
- **Editor instances**: launched via `tools/automation/invoke-launch-editor.ps1`. Two editors were used at one point (probe + runtime-error-loop) since the harness is per-project.
- **Fixtures**: shipping fixtures under `tools/tests/fixtures/runbook/<workflow>/` plus inline `-RequestJson` payloads where no fixture matched.
- **Failure-path coverage**: where a workflow has both a clean path and a failure path (build-error triage, runtime-error triage), both were exercised — including injecting deliberate compile and runtime errors into probe and reverting after.

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls I made to confirm bugs (reading run-result.json, listing fixture directories I should have known about, etc.). Investigation calls are not friction *for the test*, but the fact that I needed them is captured per-row.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Stderr line "OK: …" alongside stdout JSON; verified stdout is pure JSON. |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | Clean. |
| 3 | Input dispatch | `/godot-press` | probe | 3 | ⚠️ misleading-success | **B1** doubled-prefix output dir; **B2** `status=success` while both events `skipped_frame_unreached`. |
| 4 | Behavior watch | `/godot-watch` | probe | 3 | ⚠️ misleading-success | **B3** `status=success sampleCount=0` when target node missing (no diagnostic). Doubled-prefix dir confirmed. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | Clean. |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe (broken script injected) | 3 | ❌ data loss | **B4** `firstDiagnostic: null` despite run-result.json having full file/line/column/message; **B5** "Check the run-result for details" with no path. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | Clean. |
| 6b | Runtime-error triage (target other scene) | `/godot-debug-runtime` | runtime-error-loop | 4+ | ❌ broken | **F1** default fixture targets `main.tscn` which doesn't exist; **B6** cleanup-unclassified diagnostic on `.gitkeep`; **B7/B9** `failureKind=internal` when underlying issue was `validation`; **B8** sandbox's `inspection-run-config.json` overrides request `targetScene` and `outputDirectory` silently. |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe (error injected) | 3 | ❌ false-clean | **B10** runtime error NOT captured; envelope reports `status=success terminationReason=completed` despite a guaranteed null-deref in the target scene. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | Clean. |
| 8 | List pinned | `/godot-pins` | probe | 2 | ⚠️ schema-lies | **B11** `pinnedRunIndex` is an object (not array) with a single pin; becomes array on ≥2. **B12** doubled prefix in pinned `scenarioId` for scene-inspection runs. |
| 9 | Unpin run | `/godot-unpin` | probe | 2 | ✅ pass | Refusal path (`pin-target-not-found`) works, exit 0 per RUNBOOK contract. |
| 10 | Stop editor | — | probe / runtime-error-loop | 1 | ✅ pass | Idempotent no-op returns `noopReason=no-matching-editor`. |
| 11 | `-EnsureEditor` shortcut | (any runtime workflow) | probe (cold-start) | 1 | ❌ hang | **B13** orchestration hung 10+ minutes after editor cold-start; capability.json kept refreshing but no request was ever written to `harness/automation/requests/`. Killing + explicit `invoke-launch-editor` then plain workflow worked in seconds. |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 11 distinct workflows / paths exercised. **5 passed clean**, **3 partial / misleading-success**, **3 broken**.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction).

### B1 — Doubled `<workflow>-` prefix in evidence directory paths

**Where**: every fixture in [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/) that uses `outputDirectory: "res://evidence/automation/runbook-<workflow>-$REQUEST_ID"`. After pass 4's M6 substitution, `$REQUEST_ID` is replaced with the requestId, which already starts with `runbook-<workflow>-`. Result: `runbook-input-dispatch-runbook-input-dispatch-20260425T192459Z-cf2676`.

Concrete instances observed:
- `evidence/automation/runbook-input-dispatch-runbook-input-dispatch-…`
- `evidence/automation/runbook-behavior-watch-runbook-behavior-watch-…`
- `evidence/automation/runbook-build-error-triage-runbook-build-error-triage-…`
- `evidence/automation/runbook-runtime-error-triage-runbook-runtime-error-triage-…`

**Symptom**: cosmetic — long paths, harder to grep, noisy in pin metadata. No functional break.

**Fix**: in each fixture under `tools/tests/fixtures/runbook/`, change

```json
"outputDirectory": "res://evidence/automation/runbook-input-dispatch-$REQUEST_ID"
```

to either

```json
"outputDirectory": "res://evidence/automation/$REQUEST_ID"
```

(since the requestId already encodes the workflow), or rename the placeholder so it isn't doubled — but the simpler fix is to drop the redundant prefix in the fixture.

**How to verify**: run any invoke script, inspect the manifest path printed in the envelope. The directory under `evidence/automation/` should equal exactly the `requestId`.

---

### B2 — Input-dispatch reports `success` + `dispatchedEventCount=2` when both events were `skipped_frame_unreached`

**Where**: [tools/automation/invoke-input-dispatch.ps1](../tools/automation/invoke-input-dispatch.ps1) outcome construction; [RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1) input-dispatch outcome shaping.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

**Observed envelope**:
```json
"status": "success",
"outcome": {
    "dispatchedEventCount": 2,
    "firstFailureSummary": "Run ended before the requested frame was reached."
}
```

**Underlying** `input-dispatch-outcomes.jsonl`:
```jsonl
{"declaredFrame":30,"dispatchedFrame":-1,"status":"skipped_frame_unreached", …}
{"declaredFrame":32,"dispatchedFrame":-1,"status":"skipped_frame_unreached", …}
```

The probe sandbox's main scene quits during validation before frame 30. Both events were *declared* but never *dispatched*. The envelope is misleading on three fronts:

1. `dispatchedEventCount: 2` should be 0 (or there should be a separate `declaredEventCount` distinct from `dispatchedEventCount`).
2. `status: success` while a `firstFailureSummary` is non-null is contradictory.
3. Agents reading the skill doc see "Report `dispatchedEventCount`" — they will tell the user "ENTER was pressed" when in fact no key fired.

**Fix**: in the script's outcome assembly, classify the run as `failure` (failureKind = `runtime` or a new `inputs-skipped`) when any event has `status != "dispatched"`. Or at minimum:

- Rename `dispatchedEventCount` → `declaredEventCount` and add `actualDispatchedCount`.
- Set `status = "failure"` when `actualDispatchedCount < declaredEventCount`.

**How to verify**: re-run the same fixture against probe (whose `stopAfterValidation: true` exits before frame 30). The envelope should make it obvious that no keys actually fired. Add a Pester unit test that constructs a synthetic `input-dispatch-outcomes.jsonl` with all `skipped_frame_unreached` entries and asserts the script produces `status: failure`.

---

### B3 — Behavior-watch reports `success` + `sampleCount=0` when the target node doesn't exist

**Where**: behavior-watch outcome shaping in [RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1).

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/single-property-window.json
```

The fixture targets `/root/Main/Paddle`. Probe has no Paddle node.

**Observed envelope**:
```json
"status": "success",
"outcome": { "samplesPath": null, "sampleCount": 0, "frameRangeCovered": null }
```

No diagnostic about the missing node, no warning, no failure classification. The skill's report-line ("Report `sampleCount` and the frame range") becomes "0 samples captured" with no actionable next step.

**Symptom**: agents debugging why a property doesn't change will see this and conclude the property genuinely never changed — when actually the node never existed. Confusion compounds when the user asks for help diagnosing "why didn't the paddle move?".

**Fix**: in behavior-watch outcome assembly, when `sampleCount == 0` AND the runtime emitted a "node not found" diagnostic (which it should), surface as `status=failure failureKind=runtime` with the node path in `diagnostics[0]`. Alternatively, emit a soft `status=success` with `outcome.warnings = ["target node not found: /root/Main/Paddle"]` so the agent has something to report.

**How to verify**: same reproduction; envelope should either be a failure with a clear diagnostic, or include a populated `warnings` array.

---

### B4 — Build-error triage drops `firstDiagnostic` despite run-result.json containing it

**Where**: [tools/automation/invoke-build-error-triage.ps1](../tools/automation/invoke-build-error-triage.ps1) outcome shaping.

**Reproduction**: write an invalid `.gd` script and reference it from `scenes/main.tscn`, then:
```powershell
pwsh ./tools/automation/invoke-build-error-triage.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json
```

**Observed envelope**:
```json
"status": "failure",
"failureKind": "build",
"diagnostics": ["Build failed. Check the run-result for details."],
"outcome": { "firstDiagnostic": null, "rawBuildOutputPath": null }
```

**Underlying** `harness/automation/results/run-result.json`:
```json
"buildDiagnostics": [
  {
    "code": null, "column": 1, "line": 4,
    "message": "Unexpected \"Indent\" in class body.",
    "rawExcerpt": "Error at ([hint=Line 4, column 1]4, 1[/hint]): …",
    "resourcePath": "res://scripts/broken.gd",
    "severity": "error", "sourceKind": "script"
  },
  …
]
```

The diagnostics are captured by the runtime and persisted to run-result.json with full file/line/column/message — but the orchestration script does not propagate the first one into `outcome.firstDiagnostic`. The skill doc explicitly says:

> On `failureKind=build`, report `firstDiagnostic.file:line: message` verbatim to the user — do not paraphrase.

Agents following the skill have nothing to report.

**Fix**: in [tools/automation/invoke-build-error-triage.ps1](../tools/automation/invoke-build-error-triage.ps1), when `failureKind=build`, read the persisted run-result.json (the orchestrator already has the path) and project `buildDiagnostics[0]` into `outcome.firstDiagnostic` with shape `{ "file": resourcePath, "line": …, "column": …, "message": … }`. Same shape the skill documents.

**How to verify**: same reproduction; envelope should include
```json
"outcome": {
  "firstDiagnostic": {
    "file": "res://scripts/broken.gd",
    "line": 4,
    "column": 1,
    "message": "Unexpected \"Indent\" in class body."
  }
}
```

---

### B5 — Build failure diagnostic says "Check the run-result" without a path

**Where**: same site as B4. The diagnostics array on build failure says:

```
"Build failed. Check the run-result for details."
```

…but does not include the absolute path to `harness/automation/results/run-result.json`. An agent reading only the envelope cannot locate the run-result without scanning the project.

**Fix**: include the absolute path of `run-result.json` in `diagnostics[0]` whenever the orchestrator points at it. Either:

```
"Build failed. See D:/dev/godot-agent-harness/integration-testing/probe/harness/automation/results/run-result.json"
```

or surface it as `outcome.runResultPath` (a new field) so it's machine-readable. The latter is cleaner.

**How to verify**: same reproduction; an agent should be able to extract `outcome.runResultPath` (or a literal path inside `diagnostics[0]`) and read it without filesystem search.

Note: B4 fix subsumes most of B5's pain — if `firstDiagnostic` carries the file/line/message, the agent rarely needs to crack open run-result.json. B5 is a defense-in-depth fix for cases where `outcome` is empty for other reasons.

---

### B6 — Cleanup walker emits "cleanup-unclassified" for `.gitkeep` in transient zone

**Where**: `Get-RunZoneClassification` in [RunbookOrchestration.psm1:449-490](../tools/automation/RunbookOrchestration.psm1#L449-L490).

**Reproduction**: in any sandbox where `harness/automation/results/.gitkeep` is committed (a normal pattern to keep an empty directory in git), run any invoke script. The envelope's `diagnostics[]` includes:

```
"cleanup-unclassified: deleting 'D:\\dev\\…\\harness\\automation\\results\\.gitkeep' --
 file is not in Get-RunZoneClassification. Add it to the classification table to suppress this diagnostic."
```

The walker correctly cleans transient files (per pass 3's M4), but `.gitkeep` is treated as unclassified and surfaced as a diagnostic on every run. Worse, the walker *deletes* the `.gitkeep` — so the directory is no longer empty-but-tracked after the first run, and the file has to be recreated on every commit.

**Fix**: extend `Get-RunZoneClassification` to map `.gitkeep` (and possibly `.gitignore`) to a new zone `'preserve'` that the cleanup walker never touches. Alternatively, treat any file whose name starts with `.git` as preserved.

```powershell
$classifications = @{
    'run-request.json'         = 'transient'
    'run-result.json'          = 'transient'
    '.in-flight.json'          = 'transient'
    'capability.json'          = 'transient'
    'lifecycle-status.json'    = 'transient'
    '.gitkeep'                 = 'preserve'  # <-- add this row
    '.gitignore'               = 'preserve'  # <-- and this
}
```

In the walker's switch, add a `'preserve' { return }` arm that no-ops.

**How to verify**: in a sandbox with `.gitkeep` committed under `harness/automation/results/`, run `invoke-scene-inspection.ps1`. The diagnostic should not appear, and the file should still exist after the run.

---

### B7 / B9 — Misleading `failureKind` classification when validation fails

**Where**: orchestration script's translation from run-result.failureKind to envelope.failureKind.

**Reproduction**: see B8 for the actual run that exposed this. The run-result.json said `"failureKind": "validation"` but the envelope reported `"failureKind": "internal"` with diagnostic "manifest not found at …".

The orchestration script appears to short-circuit on "manifest not found" → `internal`, rather than reading the run-result's own `failureKind` and propagating it. This obscures the real cause: the manifest *did* exist, it just didn't match the expected runId/scenarioId.

**Fix**: when the orchestrator encounters a populated run-result.json with a non-null `failureKind`, propagate that classification rather than re-classifying based on what the orchestrator can see. Reserve `internal` for truly unrecognized states.

```powershell
# Pseudocode in the orchestration script:
if ($runResult.failureKind) {
    # Map run-result classifications to envelope classifications
    $envelope.failureKind = switch ($runResult.failureKind) {
        'validation'  { 'runtime' }   # or a new 'validation' enum value
        'build'       { 'build' }
        'runtime'     { 'runtime' }
        default       { 'internal' }
    }
} else {
    $envelope.failureKind = 'internal'
}
```

**How to verify**: pre-seed a run-result.json with `failureKind: "validation"` and stale runId/scenarioId, run an invoke script, confirm the envelope reports `failureKind: "runtime"` (or whatever the chosen mapping is) — not `internal`.

---

### B8 — `inspection-run-config.json` silently overrides request `targetScene` and `outputDirectory`

**Where**: [integration-testing/runtime-error-loop/harness/inspection-run-config.json](../integration-testing/runtime-error-loop/harness/inspection-run-config.json) — and any sandbox that ships an inspection-run-config with hard-coded `runId`, `scenarioId`, `targetScene`, `outputDirectory`.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
    -ProjectRoot ./integration-testing/runtime-error-loop `
    -RequestJson '{… "targetScene":"res://scenes/error_on_frame.tscn", "outputDirectory":"res://evidence/automation/$REQUEST_ID" …}'
```

**Observed**: the resulting evidence-manifest.json has `runId: "runtime-error-loop-run-01"` and `scenarioId: "runtime-error-loop-smoke-test"` (from the config), and was written to `evidence/scenegraph/latest/` (from the config's `outputDirectory`). My request's `targetScene` and `outputDirectory` were silently ignored. The runtime ran `no_errors.tscn` (the config's targetScene), not `error_on_frame.tscn`.

The orchestrator then failed validation because the on-disk manifest's runId didn't match the requestId it was waiting for.

**Symptom**: any sandbox with a populated `inspection-run-config.json` cannot be driven by the runbook against a non-default scene. The agent's request is silently disregarded; no diagnostic, no warning. The orchestrator interprets the resulting confusion as `internal` failure.

**Fix**: this is two bugs in one.

1. **Runtime side** — the addon should let request-time fields override config defaults, *not* the other way around. If the request payload sets `targetScene`, that should take precedence over the config's `targetScene`.
2. **Orchestrator side** — when the produced manifest's runId/scenarioId don't match the request, surface that explicitly (`failureKind: "runtime"`, diagnostic: "manifest produced for a different request — check inspection-run-config.json overrides"), not `internal`.

The runtime-side fix is the load-bearing one. The orchestrator-side fix is defense in depth.

Alternatively (smaller fix): treat `inspection-run-config.json` as scaffolding for *editor-side defaults* only and never let it override an explicit automation request. Document this in the addon source and `specs/008-agent-runbook/contracts/`.

**How to verify**: re-run the reproduction. The runtime should run `error_on_frame.tscn` and the manifest's `runId` should equal the requestId.

---

### B10 — Runtime errors in `_ready` not captured by default `runtime-error-triage` fixture

**Where**: [tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json](../tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json) — the default fixture has `stopPolicy.stopAfterValidation: true`.

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
    -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json
```

**Observed envelope**:
```json
"status": "success",
"failureKind": null,
"outcome": {
  "terminationReason": "completed",
  "runtimeErrorRecordsPath": null,
  "latestErrorSummary": null
}
```

**Underlying** `runtime-error-records.jsonl`: 0 bytes. The scenegraph-summary says `"trigger": "startup"` — meaning the snapshot was captured at startup, the orchestrator validated it, and the runtime exited via `stopAfterValidation` before the error path could surface (or before `_ready` ran in the playtest at all).

**Symptom**: the workflow agents reach for when triaging real runtime errors silently returns clean success. This is the **highest-impact bug** in the matrix.

**Fix**: at minimum, ship a fixture variant that does **not** stop after validation:

`tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json`:
```json
{
  …
  "stopPolicy": {
    "stopAfterValidation": false,
    "frameLimit": 600
  }
}
```

Update the [godot-debug-runtime skill](../.claude/skills/godot-debug-runtime/SKILL.md) and [RUNBOOK.md](../RUNBOOK.md) to point at the new fixture as the default, with the existing one available for very-fast smoke tests.

Also: the addon's runtime-error capture should fire even when the scene errors during `_ready`. If the playtest is exiting before `_ready` runs, that's a separate runtime-side bug — the playtest should always run `_ready` before any harness-issued stop signal can quit.

**How to verify**: same reproduction with the new fixture. The envelope should report `failureKind: "runtime"` and `outcome.latestErrorSummary` populated with file/line/message of the null-deref.

---

### B11 — `pinnedRunIndex` collapses to object when only one pin exists

**Where**: [tools/automation/invoke-list-pinned-runs.ps1](../tools/automation/invoke-list-pinned-runs.ps1) — the `ConvertTo-Json` call without `-AsArray`.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName test1
pwsh ./tools/automation/invoke-list-pinned-runs.ps1 -ProjectRoot ./integration-testing/probe
```

With one pin:
```json
"pinnedRunIndex": { "pinName": "test1", … }
```

With two:
```json
"pinnedRunIndex": [ { "pinName": "test1", … }, { "pinName": "test2", … } ]
```

The skill SKILL.md says `pinnedRunIndex[]` is an array. Code that does `for pin in envelope.pinnedRunIndex:` will iterate the object's properties (or fail) when only one pin exists.

**Fix**: in `invoke-list-pinned-runs.ps1`, wrap the array argument before serialization:

```powershell
$envelope.pinnedRunIndex = ,@($pins)   # the leading comma forces array
# or
$envelope | ConvertTo-Json -Depth 10 -AsArray:$false  # check options
```

The idiomatic PowerShell fix is the leading-comma array constructor.

**How to verify**: re-run the reproduction with one pin. `pinnedRunIndex` should be a JSON array of length 1, not an object.

---

### B12 — Doubled `runbook-scene-inspection-` prefix in `scenarioId` for inline-synthesized requests

**Where**: [tools/automation/invoke-scene-inspection.ps1:151](../tools/automation/invoke-scene-inspection.ps1#L151) (the inline payload synthesizer).

**Observed**: pinned scene-inspection runs show `scenarioId: "runbook-scene-inspection-runbook-scene-inspection-20260425T192946Z-bda19e"` — same doubled-prefix pattern as B1, but in the `scenarioId` field rather than the path.

**Fix**: in the inline payload synthesis, set `scenarioId` to a stable string (e.g. `"runbook-scene-inspection-scenario"`) rather than concatenating the requestId. The requestId is unique per run; scenarioId is not supposed to be.

**How to verify**: pin a scene-inspection run, list pins, confirm `scenarioId` does not contain a doubled prefix.

---

### B13 — `-EnsureEditor` shortcut hangs on cold-start

**Where**: orchestration glue between `-EnsureEditor` switch and `invoke-launch-editor.ps1` in [RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1).

**Reproduction** (against a fully-stopped editor):
```powershell
pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe -EnsureEditor
```

**Observed**: the orchestration hung for >12 minutes. The Godot editor process started; capability.json refreshed every minute (heartbeat). But the requests/ directory remained empty — the orchestration never wrote `run-request.json`. Stopping the task and running the explicit two-step pattern instead worked in seconds:

```powershell
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
```

**Hypothesis**: the `-EnsureEditor` glue waits for capability.json with a generous timeout (or no timeout?), and either the wait never returns or the subsequent workflow step fails to fire after the wait completes. There may also be a deadlock when launch + workflow are chained in the same pwsh process versus two separate processes.

**Fix**: requires source investigation. As a first cut:

1. Add a hard timeout to the EnsureEditor wait (e.g. 60s) with a clear envelope `failureKind: "editor-not-running"` if it expires.
2. Log a heartbeat to stderr while waiting ("waiting for capability.json … N seconds elapsed") so the agent can tell something's happening.
3. After the launch helper returns, log "editor ready, dispatching workflow" before continuing — that diagnostic alone would have made this bug self-explanatory.

**How to verify**:
1. Stop the editor.
2. Run a workflow with `-EnsureEditor`.
3. Either it completes within 30 seconds, or the envelope returns a clear timeout failure within 60 seconds. Indefinite hangs are not acceptable.

Until B13 is fixed, the documentation should warn agents to prefer the explicit two-step pattern. RUNBOOK.md currently shows `-EnsureEditor` as the "one-step convenience" — that recommendation is dangerous on cold-starts.

---

### F1 — Default runtime-error fixture targets a scene that doesn't exist in `runtime-error-loop`

**Where**: [tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json](../tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json) — `"targetScene": "res://scenes/main.tscn"`.

The runtime-error-loop sandbox has scenes `crash_after_error.tscn`, `error_on_frame.tscn`, etc. — no `main.tscn`. An agent pointed at this sandbox by RUNBOOK gets a confusing failure (compounded by B8 — the config silently swaps in a different scene).

**Fix**: ship per-sandbox fixture variants, or have the runtime-error-triage default fixture pick the project's `[application] run/main_scene` setting from `project.godot` if `targetScene` is omitted from the request. The latter is more general — it makes any sandbox usable without per-sandbox fixtures.

**How to verify**: an agent runs `invoke-runtime-error-triage.ps1` against a sandbox that doesn't have `scenes/main.tscn`; the run targets the project's actual main scene without manual fixture editing.

---

## Summary

**Critical (workflow broken)**: B4, B5, B8, B10, B13. Five issues that an agent can hit on a normal task and silently return wrong data, or that block the workflow entirely. **B10 is the worst** — runtime-error triage silently masks real errors with the default fixture; this is the most-used failure-path tool in the runbook.

**Significant (misleading semantics)**: B2, B3, B7, B11. Envelopes claim success when something didn't happen, schema docs lie about types. Agents acting on these envelopes will mis-report to users.

**Minor (cosmetic / churn)**: B1, B6, B9, B12, F1, F2. Long path names, .gitkeep churn, fixture mismatches. Easy to fix.

**Tool-call ergonomics**: most workflows are 2 calls (skill load + invoke), which is ideal. Three workflows take 3 calls because the agent has to discover what fixtures exist (`ls` of the fixtures directory). One option: have each skill SKILL.md preview its fixtures directory contents at the top of the doc, so a fresh agent knows the menu without an extra Bash call. (The behavior-watch skill in particular is forced to discover fixtures because the SKILL.md tells the agent to "treat the user's input as a fixture path under … behavior-watch/" without enumerating what's there.)

**One-step convenience flag is broken**: until B13 lands, `-EnsureEditor` should be removed from RUNBOOK's "one-step convenience" example or annotated with a known-issue warning. The two-step explicit pattern (`invoke-launch-editor` → workflow) is the only reliable path today.

**Suggested next pass**: split into two batches.

- **Pass 6a** — semantic correctness: B2, B3, B4, B5, B10, B11. These are bugs that lie to the agent. They make the harness untrustworthy.
- **Pass 6b** — surface polish: B1, B6, B7, B8, B9, B12, B13, F1. Mix of fixture cleanups, classification fixes, and the one-step convenience hang.

B10 is severe enough to land standalone if 6a is too big a batch.
