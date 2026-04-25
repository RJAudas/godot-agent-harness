# Pass 6a — Outcome shape cleanup

## Scope

Three orchestration-side bugs surfaced in [pass 6](06-test-pass-results.md) where the envelope's `outcome` or `diagnostics` projection lies about what happened. All three are fixable in `tools/automation/*.ps1` and `tools/automation/RunbookOrchestration.psm1` — no addon source touched.

| ID | Workflow | What lies | Fix area |
|---|---|---|---|
| B14 | Input dispatch | `dispatchedEventCount` field equals declared count, not actual | invoke-input-dispatch.ps1 outcome assembly |
| B15 | Behavior watch | `warnings` is a nested array `[[<string>]]` not flat | RunbookOrchestration.psm1 behavior-watch outcome |
| B16 | Any validation-failure path | Diagnostic says "manifest not found" while run-result has the real reason | RunbookOrchestration.psm1 diagnostic projection |

## Why these fit together

- Same area of code (orchestration scripts shaping the stdout envelope).
- Same kind of test (Pester unit test that constructs synthetic inputs — JSONL, run-result.json — and asserts envelope shape).
- Small diffs each; low risk; one PR, one reviewer, one context window.
- Together they make the envelope contract trustworthy again — agents acting on `outcome` or `diagnostics` get the truth.

## Not in scope

- **B8, B10** — runtime-side semantic correctness. See [pass 6b](06b-runtime-semantic-correctness.md).
- **B13, F2, F3** — editor process lifecycle and deadlocks. See [pass 6c](06c-editor-lifecycle-hardening.md).

---

## B14 — `dispatchedEventCount` field on input-dispatch envelope still equals declared count, not actual dispatched

**Where**: [tools/automation/invoke-input-dispatch.ps1](../tools/automation/invoke-input-dispatch.ps1) outcome construction. Pass 5 added `actualDispatchedCount` and `declaredEventCount` but kept the legacy `dispatchedEventCount` in place.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-input-dispatch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json
```

**Observed envelope** (probe sandbox quits before frame 30 — 0 keys actually fired):
```json
"outcome": {
  "actualDispatchedCount": 0,
  "declaredEventCount": 2,
  "dispatchedEventCount": 2,
  "firstFailureSummary": "Run ended before the requested frame was reached.",
  "outcomesPath": "…/input-dispatch-outcomes.jsonl"
}
```

`dispatchedEventCount=2` is wrong — the JSONL shows both events with `status: "skipped_frame_unreached"` and `dispatchedFrame: -1`. An agent that reads only the legacy field (still mentioned in some skill prose) will report "2 keys dispatched" when 0 fired. Pass 5 added the correct fields *next to* the misleading one rather than replacing it.

**Symptom**: `status=failure` does land, so an agent that checks `status` first will not be misled. But any consumer keying off `dispatchedEventCount` (including older skill drafts and external tooling) gets the wrong number. The field name lies.

**Fix**: in [tools/automation/invoke-input-dispatch.ps1](../tools/automation/invoke-input-dispatch.ps1) (and any helper in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1) that shapes the input-dispatch outcome), set `dispatchedEventCount = $actualDispatchedCount` (so the field finally tells the truth), or remove the field entirely now that `actualDispatchedCount` exists. The latter is cleaner — search the repo for any reader of `dispatchedEventCount` and migrate them to `actualDispatchedCount`, then drop the legacy key.

**How to verify**: re-run the reproduction. The envelope must show either `dispatchedEventCount=0` (matching `actualDispatchedCount`) or omit the field entirely. Add a Pester test that constructs a synthetic `input-dispatch-outcomes.jsonl` with all `skipped_frame_unreached` entries and asserts `dispatchedEventCount == actualDispatchedCount`.

---

## B15 — Behavior-watch `warnings` is a nested array `[[<string>]]` not a flat array `[<string>]`

**Where**: behavior-watch outcome shaping in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1) — pass 5's fix for B3 added the warnings field but wraps a single-element array in another array, likely because the `,@(...)` idiom was applied around an already-collected array.

**Reproduction**:
```powershell
pwsh ./tools/automation/invoke-behavior-watch.ps1 `
    -ProjectRoot ./integration-testing/probe `
    -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/single-property-window.json
```

**Observed envelope** (probe has no `/root/Main/Paddle`):
```json
"outcome": {
  "warnings": [
    [
      "target node not found or never sampled: /root/Main/Paddle"
    ]
  ],
  "frameRangeCovered": null,
  "samplesPath": null,
  "sampleCount": 0
}
```

Expected:
```json
"warnings": [
  "target node not found or never sampled: /root/Main/Paddle"
]
```

**Symptom**: agents iterating `outcome.warnings` get an array, not a string, on the first element. Code like `for w in outcome.warnings: print(w)` prints `["target node not found …"]` (JSON-array repr) instead of the warning text. In strongly-typed consumers (TypeScript / Pydantic) this is a schema break.

**Fix**: in the warnings projection, drop the leading-comma wrapper around something that is already an array — use `@($warningStrings)` (cast to array, no extra wrap), not `,@($warningStrings)` (single-element wrapper around the array). The leading-comma idiom is for *forcing* a scalar into a one-element array; here the input is already plural.

```powershell
# Wrong (current)
$outcome.warnings = ,@($warningStrings)

# Right
$outcome.warnings = @($warningStrings)
```

**How to verify**: re-run the reproduction. `warnings` must be `["target node not found or never sampled: /root/Main/Paddle"]` — a flat one-element array of string. Add a Pester test that asserts `($envelope.outcome.warnings | Get-Member).TypeName[0]` is `System.String`, not `System.Object[]`.

---

## B16 — Diagnostic surface drops the run-result's actual reason on `validation` failures

**Where**: orchestration-side diagnostic projection in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1) when run-result reports `failureKind=validation` and `validationResult.notes` carries the real cause.

**Reproduction**: same as B8 (runtime-error-loop with a request that overrides `targetScene` to `error_on_frame.tscn`). See [pass 6b](06b-runtime-semantic-correctness.md#b8) for full reproduction; the relevant artefact for *this* fix is the on-disk `harness/automation/results/run-result.json` after the failed run.

**Observed envelope** (after B7/B9 fix landed `failureKind=runtime`):
```json
"failureKind": "runtime",
"diagnostics": [
  "manifest not found at 'D:\\…\\evidence\\automation\\runbook-runtime-error-triage-…\\evidence-manifest.json'"
],
```

**Underlying** `harness/automation/results/run-result.json`:
```json
"failureKind": "validation",
"validationResult": {
  "manifestExists": true,
  "missingArtifacts": [
    "evidence/scenegraph/latest/scenegraph-snapshot.json",
    …
  ],
  "notes": [
    "Manifest runId did not match the active automation request.",
    "Manifest scenarioId did not match the active automation request.",
    "Persisted artifact references were written successfully. Validate the manifest schema and paths …",
    "Persisted evidence bundle failed validation."
  ]
}
```

The orchestrator now correctly maps `validation → runtime` (B7/B9 fix), but the diagnostic message lies: it says "manifest not found" when the manifest **was written**, just to the wrong path with the wrong runId. An agent reading the envelope will conclude "the editor failed to write a manifest" and look in the wrong place; they need to crack `run-result.json` to learn the truth.

**Symptom**: agents acting on `diagnostics[0]` for remediation get a misleading hint. The fix to *this* bug (text projection) is independent of the underlying B8 (config override) — even after B8 lands, validation failures from other causes will carry the same misleading text.

**Fix**: when run-result has `failureKind="validation"` with non-empty `validationResult.notes`, surface those notes in `diagnostics[]` — they already have the correct verbiage. Pseudocode:

```powershell
if ($runResult.failureKind -eq 'validation' -and $runResult.validationResult.notes) {
    $envelope.diagnostics = @($runResult.validationResult.notes |
        Where-Object { $_ -notmatch '^Persisted artifact references were written' })
}
```

Optionally fold "Manifest runId did not match …" into a more agent-friendly hint ("Check inspection-run-config.json for hard-coded runId / scenarioId / outputDirectory"), since the recurring root cause is B8.

**How to verify**: same reproduction as B8 (or any synthetic run-result.json with `failureKind="validation"` and populated `validationResult.notes`). The envelope's `diagnostics[0]` should mention `"Manifest runId did not match the active automation request"` (or an agent-friendly translation), not `"manifest not found"`.

---

## Verification — whole batch

After all three fixes land, re-run the relevant rows from the [pass 6 matrix](06-test-pass-results.md#test-matrix):

1. **Test 3** (input dispatch against probe): envelope must show `dispatchedEventCount == actualDispatchedCount == 0` (or the legacy field omitted). `status=failure` is correct and unchanged.
2. **Test 4** (behavior watch against probe with missing target): `warnings` is a flat string array `["target node not found or never sampled: /root/Main/Paddle"]`.
3. **Test 6b** (runtime-error-loop with overridden targetScene): `diagnostics[0]` mentions "Manifest runId did not match the active automation request" or equivalent — *not* "manifest not found at …". Note: B6b will still fail overall until B8 lands; this batch only fixes the diagnostic *text*, not the underlying override.

## Cross-batch dependencies

- **B16 ↔ B8** — B16's fix is independent of B8's fix; either can land first. B16 makes B8's failure mode self-explanatory, which makes B8's eventual fix easier to verify.
- None of B14, B15, B16 depend on 06b or 06c work.
