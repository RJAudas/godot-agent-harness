# Pass 6 — Hardening test pass

## Goal

After [pass 1](01-unblock-the-loop.md), [pass 2](02-dry-ergonomics.md), [pass 3](03-hardening-tests.md), [pass 4](04-polish.md), and [pass 5](05-test-pass-results.md), this pass re-runs the full matrix against a real Godot editor (`Godot_v4.6.2-stable_win64`) and a real Godot project to confirm pass-5 fixes landed and to surface anything that regressed or was missed.

The test was performed by acting as a fresh agent following [RUNBOOK.md](../RUNBOOK.md): use the slash command if one exists, otherwise call the invoke script. Tool-call count is tracked as an ergonomics signal — a workflow that takes a fresh agent more than 2–3 calls to drive end-to-end is friction.

## Test methodology

- **Sandboxes used**: [`integration-testing/probe`](../integration-testing/probe) (canonical minimal sandbox) and [`integration-testing/runtime-error-loop`](../integration-testing/runtime-error-loop) (deliberate runtime-error fixtures).
- **Editor instances**: launched via `tools/automation/invoke-launch-editor.ps1`. Two editors used at one point (probe + runtime-error-loop) since the harness is per-project.
- **Fixtures**: shipping fixtures under `tools/tests/fixtures/runbook/<workflow>/` plus an inline `-RequestJson` payload (loaded via file) where no fixture matched.
- **Failure-path coverage**: where a workflow has both clean and failure paths (build-error triage, runtime-error triage), both were exercised — including injecting deliberate compile and runtime errors into probe and reverting after.

Tool-call counts below are the **minimum** path a fresh agent would take, excluding investigation calls made to confirm bugs.

## Test matrix

| # | Workflow | Slash command | Sandbox | Tool calls (min path) | Status | Notable issues |
|---|---|---|---|---|---|---|
| 1 | Editor launch | — | probe | 1 | ✅ pass | Stderr heartbeats (`spawned Godot PID …`, `editor ready …`) alongside pure JSON stdout. |
| 2 | Scene inspection | `/godot-inspect` | probe | 2 | ✅ pass | **B1 fixed** — `evidence/automation/runbook-scene-inspection-<id>` (no doubled prefix). |
| 3 | Input dispatch | `/godot-press` | probe | 2 | ⚠️ misleading-field | **B2 partially fixed** — `status=failure`, `actualDispatchedCount=0`, `declaredEventCount=2` are now correct. **B14 (new)** — legacy `dispatchedEventCount=2` field is still present and equals `declaredEventCount`, not actual dispatched count. |
| 4 | Behavior watch | `/godot-watch` | probe | 2 | ⚠️ shape-bug | **B3 partially fixed** — `warnings` populated when target node missing. **B15 (new)** — `warnings` is a nested array `[[<string>]]` instead of flat `[<string>]`. |
| 5a | Build-error triage (clean) | `/godot-debug-build` | probe | 2 | ✅ pass | Clean. `outcome.runResultPath` now exposed (B5 partial). |
| 5b | Build-error triage (compile error) | `/godot-debug-build` | probe + injected | 3 | ✅ pass | **B4 fixed** — `firstDiagnostic={file,line,column,message}` populated verbatim. **B5 fixed** — `outcome.runResultPath` carries absolute path. |
| 6a | Runtime-error triage (clean) | `/godot-debug-runtime` | probe | 2 | ✅ pass | Used smoke fixture (`run-and-watch-for-errors.json`); clean. |
| 6b | Runtime-error triage (non-default scene) | `/godot-debug-runtime` | runtime-error-loop | 4+ | ❌ broken | **B8 still present** — `inspection-run-config.json` silently overrides request `targetScene` and `outputDirectory`; manifest is written to `evidence/scenegraph/latest/` with the config's runId/scenarioId, not the request's. **B7/B9 fixed** — `failureKind` is now correctly `runtime` (not `internal`) when run-result reports `validation`. **B16 (new)** — diagnostic surface still says only `manifest not found at <path>`; the run-result has the truth (`Manifest runId did not match the active automation request.`) but the envelope drops it. |
| 6c | Runtime-error triage (null-deref in `_ready`) | `/godot-debug-runtime` | probe + injected | 3 | ❌ false-clean | **B10 STILL present** — even with `stopAfterValidation: false` (no-early-stop fixture), the null-deref in `_ready` is not captured. `runtime-error-records.jsonl` is 0 bytes; manifest references only scenegraph artifacts (`scenegraph_harness_runtime` producer, snapshot trigger=`startup`). Envelope reports `status=success`, `terminationReason=completed`, `latestErrorSummary=null`. |
| 7 | Pin run | `/godot-pin` | probe | 2 | ✅ pass | 7-file pin (manifest + 3 scenegraph artifacts + run-result + lifecycle-status + pin-metadata). |
| 8 | List pinned (1 pin / 2 pins) | `/godot-pins` | probe | 4 | ✅ pass | **B11 fixed** — `pinnedRunIndex` is a JSON array even with exactly 1 pin. **B12 fixed** — pinned `scenarioId="runbook-scene-inspection-scenario"` (no doubled prefix). |
| 9 | Unpin run (success + refusal) | `/godot-unpin` | probe | 2 | ✅ pass | Refusal path (`pin-target-not-found`) exits 0 per RUNBOOK contract. |
| 10 | Stop editor | — | probe / runtime-error-loop | 1 | ✅ pass | Idempotent no-op returns `noopReason="no-matching-editor"`. |
| 11 | `-EnsureEditor` shortcut (cold-start) | (any runtime workflow) | probe (cold-start) | 1 | ❌ hang | **B13 STILL HANGS**. Launcher reported `editor ready (…0s ago); dispatching workflow` after 5s, then no further output and no workflow envelope for 6+ minutes; killed manually. The two-step explicit pattern works in seconds (proven in tests 1+2). |

Legend: ✅ pass | ⚠️ partial / misleading | ❌ broken or data-loss

**Aggregate**: 13 distinct workflows / paths exercised. **8 passed clean**, **2 partial / shape-bug**, **3 broken**. Pass-5 fixes for B1, B4, B5, B7, B9, B11, B12 verified; B2 + B3 partially fixed (semantic improvement plus a new vestigial-field / shape bug); **B8, B10, B13 unchanged**.

## Issues

Issue IDs continue from prior passes' lettering convention (B = bug, F = friction). Pass 5 ended at B13/F1; new issues start at B14. Issue details and proposed fixes are split across three companion docs grouped by surface area:

| Doc | Issues | Theme | Risk |
|---|---|---|---|
| [06a — Outcome shape cleanup](06a-outcome-shape-cleanup.md) | B14, B15, B16 | Orchestration-side envelope/outcome projection lies | Low — small diffs, unit-testable |
| [06b — Runtime semantic correctness](06b-runtime-semantic-correctness.md) | B8, B10 | Addon-side bugs that make the harness untrustworthy | High — addon edits gate every workflow |
| [06c — Editor lifecycle hardening](06c-editor-lifecycle-hardening.md) | B13, F2, F3 | Editor/playtest process coordination + deadlocks | Mixed — F3 small, B13 deep |

Each companion doc is self-contained: scope, reproductions, fix proposals, subtasks, and verification criteria. Cross-batch dependencies are called out at the bottom of each.

### Quick lookup

- **B14** — input-dispatch `dispatchedEventCount` field still equals declared count, not actual → [06a](06a-outcome-shape-cleanup.md#b14)
- **B15** — behavior-watch `warnings` is nested array `[[<string>]]` → [06a](06a-outcome-shape-cleanup.md#b15)
- **B16** — diagnostic message drops run-result notes on validation failures → [06a](06a-outcome-shape-cleanup.md#b16)
- **B8** — `inspection-run-config.json` silently overrides request fields (regression check, unfixed in pass 5) → [06b](06b-runtime-semantic-correctness.md#b8)
- **B10** — runtime errors in `_ready` not captured (regression check, unfixed in pass 5) → [06b](06b-runtime-semantic-correctness.md#b10)
- **B13** — `-EnsureEditor` cold-start hang (regression check, unfixed in pass 5) → [06c](06c-editor-lifecycle-hardening.md#b13)
- **F2** — `scene_already_running` after runtime-error-triage carries misleading remediation hint → [06c](06c-editor-lifecycle-hardening.md#f2)
- **F3** — `invoke-stop-editor` leaks playtest child processes → [06c](06c-editor-lifecycle-hardening.md#f3)

---

## Summary

**Critical (workflow broken)**: **B8, B10, B13**. Three regressions from pass 5 — none of these were fixed in pass 5 because they all require runtime-side or orchestration-deadlock work that was deliberately scoped out. **B10 remains the worst** — runtime-error triage silently masks real `_ready`-time errors; this is the workflow agents reach for first when triaging crashes, and it lies. B13 blocks the convenience switch the runbook used to recommend. B8 makes any non-default-scene run on a config-bearing sandbox unusable.

**Significant (misleading semantics / shape)**: **B14, B15, B16**. `dispatchedEventCount` lies (vestigial field), `warnings` is a nested array (TypeScript / Pydantic break), build-on-validation diagnostic message hides the real cause. None of these prevent the workflow from running, but all of them make the envelope surface untrustworthy.

**Minor (cosmetic / churn)**: **F2, F3**. `scene_already_running` carries the wrong remediation hint; orphan playtest processes leak across long test sessions.

**Verified pass-5 fixes**: **B1** (no doubled prefix in evidence path), **B4** (build-error `firstDiagnostic` populated), **B5** (`outcome.runResultPath` exposed), **B7/B9** (`failureKind` correctly mapped from validation→runtime), **B11** (`pinnedRunIndex` is array even with 1 pin), **B12** (no doubled prefix in pinned `scenarioId`). **Partial fixes**: **B2** (correct status but vestigial field — see B14), **B3** (warnings shown but shape buggy — see B15). **B6** not specifically retested but no `cleanup-unclassified` diagnostic surfaced in any run; presumed fixed.

**Tool-call ergonomics**: most workflows hit the 2-call ideal (skill + invoke). Test 6b cost 4+ calls because the inline `-RequestJson` pattern is hard to drive from bash (PowerShell single-quoting collides with bash backtick interpretation — I had to write the payload to a file and `Get-Content -Raw | …`). That's a cross-shell ergonomics gap, not a harness bug, but worth noting: an agent driving the harness from bash will pay this tax whenever a fixture doesn't exist for the desired override.

**One-step convenience flag still broken**: B13 unchanged. The RUNBOOK.md warning block remains correct. **Recommend keeping the warning until B13 lands fully**, and consider downgrading the `-EnsureEditor` example to a footnote rather than a prominent code block.

**Suggested next pass**: split into three focused batches, one per companion doc.

- **[06a — Outcome shape cleanup](06a-outcome-shape-cleanup.md)**: B14, B15, B16. Orchestration-side envelope projection fixes. Small diffs, low risk, one PR. Land first — quick wins that make the envelope contract trustworthy and make 06b's bugs easier to triage when they fail.
- **[06b — Runtime semantic correctness](06b-runtime-semantic-correctness.md)**: B8, B10. Addon-side fixes deferred from pass 5. **Land B10 first or standalone** — it's the load-bearing one (silent data loss on the runtime-error triage workflow). B8 has a design-precedence question that should be aligned before code.
- **[06c — Editor lifecycle hardening](06c-editor-lifecycle-hardening.md)**: B13, F2, F3. Process coordination + deadlock investigation. Recommended order within the batch: F3 → B13 → F2 (smallest first; F3's process-tracking groundwork informs B13's deadlock spike).

Pass 5's lesson: ten fixes in a single PR landed B15 (a new defect from the B3 fix) because it slipped past review. Smaller batches with one focused reviewer per surface area would have caught the `,@(@(...))` shape bug. These three docs are sized so each is a comfortable single PR.

If schedule pressure forces a single batch, prioritize **B10 → B13 → B8** by impact: silent data loss > workflow-blocking hang > sandbox-specific override.
