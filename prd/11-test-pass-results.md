# Pass 11 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md), [pass 5](05-test-pass-results.md), [pass 6](06-test-pass-results.md) (split into [6a](06a-outcome-shape-cleanup.md), [6b](06b-runtime-semantic-correctness.md), [6c](06c-editor-lifecycle-hardening.md)), [pass 7](07-test-pass-results.md), [pass 8](08-test-pass-results.md) (its three load-bearing defects shipped as [#40](https://github.com/RJAudas/godot-agent-harness/pull/40), [#41](https://github.com/RJAudas/godot-agent-harness/pull/41), [#42](https://github.com/RJAudas/godot-agent-harness/pull/42)), [pass 9](09-test-pass-results.md), and [pass 10](10-test-pass-results.md) — this is the **first execution of the updated 14-row matrix** (the template was just refactored to split row 4 into 4a/4b, add cross-cutting #58/#59 regression checks, and bind the new probe-targeted fixture `tools/tests/fixtures/runbook/behavior-watch/probe-label-window.json` to row 4a). The sweep also re-verifies the seven recent issue-fix PRs (#54–#60) against `Godot_v4.6.2-stable_win64` and the canonical sandboxes.

The PRs whose regression footprint is exercised here:

- [#54 (issue #47)](https://github.com/RJAudas/godot-agent-harness/pull/54) — behavior-watch property allowlist + enum-error enrichment
- [#55 (issue #46)](https://github.com/RJAudas/godot-agent-harness/pull/55) — behavior-watch lifetime cross-field gate (`stopPolicy.minRuntimeFrames`)
- [#56 (issue #53)](https://github.com/RJAudas/godot-agent-harness/pull/56) — behavior-watch trace uses physics-tick counter
- [#57 (issue #52)](https://github.com/RJAudas/godot-agent-harness/pull/57) — runtime-error-records dedup uses user GDScript frame
- [#58 (issue #43)](https://github.com/RJAudas/godot-agent-harness/pull/58) — `targetScene` falls back to project `application/run/main_scene`
- [#59 (issue #44)](https://github.com/RJAudas/godot-agent-harness/pull/59) — split overloaded `target_scene_missing` into `target_scene_unspecified` + `target_scene_file_not_found`
- [#60 (issue #45)](https://github.com/RJAudas/godot-agent-harness/pull/60) — invoke-behavior-watch envelope sourced from manifest, not request payload

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox, restored to default Control + Label between mutating tests) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures, multi-scene). Both required a fresh `tools/deploy-game-harness.ps1` redeploy at the start of this pass — see B22 for details.
- **Editor instances**: launched via [tools/automation/invoke-launch-editor.ps1](../tools/automation/invoke-launch-editor.ps1). Both probe and runtime-error-loop editors were active concurrently during 6b. The probe editor was restarted between rows 5b → 6a and 6a → 6c so each new injection (broken script, error_main.gd) was picked up.
- **Fixtures**: shipping fixtures under [tools/tests/fixtures/runbook/](../tools/tests/fixtures/runbook/), including the newly-added [`probe-label-window.json`](../tools/tests/fixtures/runbook/behavior-watch/probe-label-window.json) for row 4a, plus inline `-RequestJson`-equivalent payloads (written to `harness/tmp-*.json` because nested-quote escaping over PowerShell-via-bash is brittle) for row 6b's `targetScene` override and the cross-cutting #54/#55/#58/#59 checks.
- **Failure-path coverage**: behavior-watch (success + missing target + disallowed property + lifetime gate violation), build-error triage (clean + injected compile error), runtime-error triage (clean + non-default scene + `_ready` null deref + targetScene-omitted fallback + targetScene-not-found fallback), pin-run (success + collision refusal + invalid-name refusal), unpin (success + not-found refusal), stop-editor (active + idempotent no-op).

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Editor PID 43068, `reusedExistingEditor: false`, `capabilityAgeSeconds: 0`. Stdout envelope rendered cleanly this pass (no buffering). |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | `nodeCount: 2`, `sceneTreePath` populated, no doubled prefix in `runbook-scene-inspection-20260503T141136Z-ef0b3e/`. |
| 3 | Input dispatch | `/godot-press` | probe | 2 | ⚠️ partial | Same longstanding probe/press-enter fixture mismatch as passes 7–10: probe ends before frame 30, all events `skipped_frame_unreached`. Envelope honestly reports `status=failure`, `failureKind=runtime`, `actualDispatchedCount=0`, `firstFailureSummary='Run ended before the requested frame was reached.'` Not a regression. |
| 4a | Behavior watch (success path) | `/godot-watch` | probe | 2 | ✅ pass | **First live execution of row 4a.** With the redeployed addon, `probe-label-window.json` returned `sampleCount: 3`, `frameRangeCovered: {first: 7, last: 9}`, `warnings: []`. Trace JSONL has 3 monotonic-frame rows for `/root/Main/Label.text` + `.visible`. **#54 ✅** (`text` and `visible` accepted), **#56 ✅** (frames 7→8→9 and timestampMs 0→1→2 confirm physics-tick cadence), **#60 ✅** (envelope `samplesPath`/`sampleCount`/`warnings` match manifest's `appliedWatch.outcomes` byte-for-byte). |
| 4b | Behavior watch (missing target) | `/godot-watch` | probe | 2 | ✅ pass | `single-property-window.json` against probe targets `/root/Main/Paddle` (doesn't exist). Envelope returns `samplesPath` non-null (post-#60), `sampleCount: 0`, warnings `["target node not found or never sampled: /root/Main/Paddle", "target node '/root/Main/Paddle' sampled but properties never observed: position"]` sourced from manifest's `missingTargets[]`/`missingProperties[]`. **#60 ✅** verified again here. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | `firstDiagnostic: null`, `runResultPath` populated, `status=success`. |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | 4 | ✅ pass | `failureKind=build`, `firstDiagnostic={file: "res://scripts/broken.gd", line: 3, column: 1, message: "Unexpected \"Indent\" in class body."}`. Verbatim parser message. Exit 1. **Editor restart between mutating tests took 2 extra tool calls** — same structural cost as prior passes. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | `latestErrorSummary: null`, `terminationReason: "completed"`, `runtimeErrorRecordsPath` populated. **#58 ✅ (cross-cutting)** — exercised here by running the same workflow with an inline payload that omitted `targetScene` entirely; envelope returned `status=success` with diagnostic `request omitted targetScene; defaulting to project.godot run/main_scene='res://scenes/main.tscn'`. The orchestrator-side fallback runs cleanly to completion. **#59 ✅ (cross-cutting)** — a follow-up inline payload pointing at `res://scenes/does_not_exist.tscn` produced the orchestrator-side fallback diagnostic `request targetScene 'res://scenes/does_not_exist.tscn' does not exist in '...'; defaulting to project.godot run/main_scene='res://scenes/main.tscn'`, status=success. The legacy generic `target_scene_missing` did not appear in either envelope. (Broker-side `target_scene_unspecified`/`target_scene_file_not_found` codes only fire when no fallback is available — that branch is covered by [BrokerTargetSceneFallback.Tests.ps1](../tools/tests/BrokerTargetSceneFallback.Tests.ps1).) |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | 4 | ✅ pass | Inline payload override of `targetScene` to `res://scenes/error_on_frame.tscn` produced `latestErrorSummary={file: "res://scripts/error_on_frame.gd", line: 20, message: "Cannot call method 'get_name' on a null value."}`, `failureKind=runtime`, `status=failure`. **B8 ✅ still fixed** — `runId="runbook-runtime-error-triage"` from request, not from a stale config field. |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | 3 | ✅ pass | `latestErrorSummary={file: "res://scripts/error_main.gd", line: 4, message: "Cannot call method 'get_name' on a null value."}`, `failureKind=runtime`, `status=failure` from `run-and-watch-for-errors-no-early-stop.json`. JSONL has 1 record: `{"function":"_ready","scriptPath":"res://scripts/error_main.gd","line":4,...}`. **#57 ✅ verified live** — record points at user GDScript frame, not engine-side C++ emission point. **B10 ✅ still fixed**. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | 8-file pin (5 evidence + 2 results + 1 metadata). Refusal paths verified: `pin-name-collision` returned `status="refused"` exit 0; `pin-name-invalid` returned `status="refused"` exit 0 with `Pin name 'Bad Name!' is invalid. Must match ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$.` |
| 8 | List pinned (1 pin / 2 pins) | `/godot-pins` | probe | 4 | ✅ pass | `pinnedRunIndex` is a JSON array in both 1-pin and 2-pin states. Both pins show correct `scenarioId` (`runbook-runtime-error-triage-scenario` / `runbook-scene-inspection-scenario`) — no doubled prefix. **B11 ✅ still fixed**. |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | 2 | ✅ pass | Success: `plannedPaths` lists 8 deletions, exit 0. Refusal (`does-not-exist` pin): `status=refused`, `failureKind=pin-target-not-found`, exit 0 (RUNBOOK contract upheld). |
| 10 | Stop editor (active + idempotent) | — | probe | 1 | ✅ pass | Active stop returned `stoppedPids: [17072]`. Idempotent re-call returned `noopReason="no-matching-editor"`. |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe (cold-start) | 1 | ✅ pass | End-to-end cold-start scene-inspection: editor PID 25028 spawned, capability published in 5s, manifest written at `evidence/automation/runbook-scene-inspection-20260503T141839Z-f9bc15/`, `nodeCount: 2`. Stdout was clean this pass (unlike passes 9 and 10 where the test runner buffered). **B13 still fixed**. |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 15 distinct workflows / paths exercised (matrix rows 1, 2, 3, 4a, 4b, 5a, 5b, 6a, 6b, 6c, 7, 8, 9, 10, 11). **14 passed clean**, **1 partial** (longstanding probe/press-enter fixture mismatch), **0 broken**. **All seven recent issue PRs (#54–#60) verified live**: behavior-watch property allowlist (#54), lifetime gate (#55), physics-tick counter (#56), runtime-error user-frame dedup (#57), targetScene fallback (#58), split target-scene codes (#59), envelope agrees with manifest (#60). One new defect found: **B22** — sandbox addon copies were stale relative to source-of-truth. One new friction defect: **F4** — `tools/deploy-game-harness.ps1` appends to sandbox `CLAUDE.md` instead of replacing the marker block on re-run.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction). Pass 10 ended at B21 / F3 (per pass 9). This pass adds **B22** and **F4**.

### B22 — Integration-testing sandbox addon copies were stale relative to source-of-truth

**Where**: [`integration-testing/probe/addons/agent_runtime_harness/`](../integration-testing/probe/addons/agent_runtime_harness/), [`integration-testing/runtime-error-loop/addons/agent_runtime_harness/`](../integration-testing/runtime-error-loop/addons/agent_runtime_harness/), seeded by [`tools/deploy-game-harness.ps1`](../tools/deploy-game-harness.ps1).

**Reproduction**:

```powershell
# At start of pass 11, probe sandbox addon was missing #54/#55/#56/#60 wiring.
diff -rq addons/agent_runtime_harness/ integration-testing/probe/addons/agent_runtime_harness/
# Six files differ; SUPPORTED_PROPERTIES list in shared/behavior_watch_request_validator.gd
# was missing text, visible, linear_velocity, angular_velocity, modulate, rotation, scale.
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
  -ProjectRoot ./integration-testing/probe `
  -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/probe-label-window.json
```

**Observed** (before redeploy):

```json
{
  "status": "failure",
  "failureKind": "runtime",
  "diagnostics": [
    "Behavior watch rejection: unsupported_property [targets[0].properties] Behavior watch property 'text' is not supported in slice 1 or slice 2.",
    "Behavior watch rejection: unsupported_property [targets[0].properties] Behavior watch property 'visible' is not supported in slice 1 or slice 2."
  ]
}
```

The `is not supported in slice 1 or slice 2` wording is the pre-#54 message text — confirmation that the sandbox was running pre-#54 validator code even though the source-of-truth at `addons/agent_runtime_harness/shared/behavior_watch_request_validator.gd` already had `text` and `visible` in `SUPPORTED_PROPERTIES` and an enriched enum-error message ("...is not in the supported allowlist. Allowed values: ...").

**Symptom**: Pass 11 row 4a would have falsely failed despite #54 being correctly merged. The matrix template's claim "#54 verified live" in pass 10 was based on the missing-target case (pre-#60 code path) — the *property allowlist itself* had never actually been exercised in a live sandbox until row 4a was added in pass 11. Pass 10 row 4 only succeeded because `/root/Main/Paddle` doesn't exist on probe, so failure occurred upstream of the allowlist check. With the redeployed addon, row 4a returned `sampleCount: 3` cleanly.

**Fix**: Two complementary fixes worth considering:

1. **Pass-time hygiene**: at the start of every test pass that runs against integration-testing sandboxes, re-run `pwsh ./tools/deploy-game-harness.ps1 -GameRoot integration-testing/<sandbox>` (or `tools/scaffold-sandbox.ps1 -Force`) to ensure addon-source/sandbox parity. Add this as a one-line "test-pass pre-flight" command in the matrix template.
2. **Drift detection**: an optional `-VerifyAddonParity` flag on the invoke scripts (or a standalone `tools/check-sandbox-addon-parity.ps1`) that diffs the sandbox addon against the source and warns/refuses when they diverge. Cheap to implement (`Compare-Object -ReferenceObject (Get-FileHash ...) -DifferenceObject ...`), and would have caught this immediately.

**How to verify**: after the redeploy step in this pass, `diff -rq addons/agent_runtime_harness/ integration-testing/probe/addons/agent_runtime_harness/` returned no differences and row 4a then passed with `sampleCount: 3`. Adding option (1) to the matrix template would make this catchable in pre-flight; adding option (2) would make it impossible to miss.

---

### F4 — `tools/deploy-game-harness.ps1` appends to sandbox `CLAUDE.md` instead of replacing marker block on re-run

**Where**: [`tools/deploy-game-harness.ps1`](../tools/deploy-game-harness.ps1) → the agent-assets installation step. Visible at [`integration-testing/probe/CLAUDE.md`](../integration-testing/probe/CLAUDE.md) lines 47–92 after re-deploy.

**Reproduction**:

```powershell
pwsh ./tools/deploy-game-harness.ps1 -GameRoot ./integration-testing/probe `
  -TargetScene 'res://scenes/main.tscn' -PassThru
# Inspect integration-testing/probe/CLAUDE.md — the
# <!-- BEGIN AGENT_RUNTIME_HARNESS --> ... <!-- END AGENT_RUNTIME_HARNESS -->
# block now appears twice. The first copy lacks the markers (was inserted by
# an earlier deploy run before the marker convention existed); the second
# copy has them. Re-running deploy will append a third copy.
```

**Observed**: the file ends up with duplicated "Runtime Harness" / "Fast path" sections. Functionally harmless (the slash commands and runtime-harness loop still work) but it pollutes the file with each deploy.

**Symptom**: Cosmetic noise in sandbox `CLAUDE.md`. Harmless to runtime behaviour, but a fresh agent reading the file to orient itself sees two near-identical fast-path blocks separated by the marker comments and might be momentarily confused. This is minor unless a sandbox is re-deployed many times.

**Fix**: in the agent-assets step, before writing, scan the existing `CLAUDE.md` for the `<!-- BEGIN AGENT_RUNTIME_HARNESS -->` / `<!-- END AGENT_RUNTIME_HARNESS -->` markers and replace the slice between them; only append (with markers wrapping the block) when no existing marker is found. The same pattern is used by similar tools (e.g. `git-credential-manager` writing to `~/.gitconfig`).

**How to verify**: re-run the deploy command twice in succession against a fresh sandbox; `CLAUDE.md` should contain exactly one occurrence of the fast-path block, regardless of run count.

---

## Summary

**Critical (workflow broken)**: none. No row produced silently wrong data; no envelope contradicts its manifest.

**Significant (misleading semantics)**: B22 — the sandbox addon drift would have caused pass 11 row 4a to falsely fail and obscure the new probe-label fixture's working state. The `unsupported_property` diagnostic with pre-#54 wording was load-bearing evidence that the sandbox was running stale code, but a quick reader could have mistaken it for a real allowlist defect. Now mitigated for this pass by the redeploy. Recommended fix is permanent — see B22 above.

**Minor (cosmetic / churn)**: F4 (sandbox CLAUDE.md duplication on re-deploy). No agent-impacting behaviour change.

**Tool-call ergonomics**: stable at the pass-9/10 baseline. The 5b row's 4-call cost (vs. the 3-call ideal) and the 6b/6c rows' 3–4-call cost are structural — injecting a script + tscn edit + editor restart is fundamentally a 4-call sequence. The ergonomics pattern unchanged from prior passes. Cross-cutting #58/#59 checks adopted into row 6a added one extra inline-payload-via-temp-file pair (two extra "writes + invokes") to row 6a's accounting; counted as part of "investigation" not the min path.

**Suggested next pass**: prioritise (1) implementing one of the B22 fixes — either auto-redeploy at scaffold-time or a pre-flight parity-check script — so the next pass can rely on sandbox addon currency instead of re-discovering drift; (2) closing the longstanding probe/press-enter fixture mismatch (Row 3 has been ⚠️ since pass 7) by either binding the existing `input-dispatch` sandbox to row 3 or extending the probe's main scene + frameLimit to make press-enter run cleanly. After that the matrix would be at 15/15 clean. The recent issue-fix wave (#54–#60) is stable and no longer needs dedicated regression coverage beyond the matrix template's existing per-row bullets.
