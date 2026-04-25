# Pass 3 — Hardening and tests

## Goal

After [pass 1](01-unblock-the-loop.md) (the basic loop works) and [pass 2](02-dry-ergonomics.md) (DRY + ergonomics), this pass tightens the harness against latent footguns and gives CI the ability to catch regressions of the bugs that pass 1 fixed. Four issues:

- **M1**: `harness/automation/requests/` is not in the transient-cleanup list. A stale `run-request.json` from a crashed run can sit there indefinitely.
- **M2**: the Pester suite for the runtime invokers doesn't mock the broker — it just exercises parameter validation. Bugs that only surface against a live editor (like pass 1's C1 race) cannot be caught in CI.
- **M4**: `Initialize-RunbookTransientZone` silently deletes any unclassified file in the transient directories. Future addon work that emits a new artifact kind gets wiped between runs without warning.
- **M5**: `pwsh` is hardcoded in three child-spawn sites. Breaks on environments where only `powershell.exe` is available (locked-down Windows servers, some CI images).

## Quick context (read first if you're fresh)

The harness is a Godot tooling project that gives AI agents machine-readable runtime evidence. Agents call `tools/automation/invoke-<workflow>.ps1` scripts; each writes a request to a canonical path the editor watches, polls for results, reads a manifest, and emits a JSON envelope on stdout.

Two key concepts:

**File broker**: the editor and orchestrator communicate via files in the sandbox project:
- Editor watches: `harness/automation/requests/run-request.json`
- Editor writes: `harness/automation/results/{capability,run-result,lifecycle-status,.in-flight}.json`
- Editor writes evidence to: `evidence/automation/<requestId>/`

**Transient zone**: the orchestrator wipes "transient" files before each run so a fresh run never reads stale state. Zone classification lives in `Get-RunZoneClassification` at [RunbookOrchestration.psm1:449-490](../tools/automation/RunbookOrchestration.psm1#L449-L490). The cleanup walker is `Initialize-RunbookTransientZone` at [lines 689-800](../tools/automation/RunbookOrchestration.psm1#L689-L800).

For deeper context: [CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md), [RUNBOOK.md](../RUNBOOK.md), [specs/009-evidence-lifecycle/data-model.md](../specs/009-evidence-lifecycle/data-model.md).

## Issues in this pass

### M1 — `harness/automation/requests/` is not in the transient cleanup list

**Where**: [RunbookOrchestration.psm1:718-721](../tools/automation/RunbookOrchestration.psm1#L718-L721)

```powershell
$transientDirs = @(
    (Join-Path $ProjectRoot 'harness/automation/results'),
    (Join-Path $ProjectRoot 'evidence/automation')
)
```

The `harness/automation/requests/` directory — where `run-request.json` lives — isn't in the cleanup walker.

**Symptom**: if an orchestration crashes after writing the request but before the broker consumes it (e.g., agent kill, process panic, a hard pwsh exception), the stale `run-request.json` persists. Mostly harmless because:
- The next orchestration will overwrite the canonical path before the broker can re-process the stale file.
- The poll loop matches on `expectedRequestId` so a stale `run-result.json` for the prior request won't satisfy the new caller.

But: if the editor was offline when the crash happened and gets restarted later, it might re-process the stale request before the next orchestration starts. That would write a stale `run-result.json` and burn evidence directory space. It's a low-probability footgun but the cleanup zone classification claims `'run-request.json' = 'transient'` already (see [RunbookOrchestration.psm1:477](../tools/automation/RunbookOrchestration.psm1#L477)), so the discrepancy is just a missed inclusion.

**Fix**: add the requests dir to the walker.

```powershell
$transientDirs = @(
    (Join-Path $ProjectRoot 'harness/automation/results'),
    (Join-Path $ProjectRoot 'harness/automation/requests'),
    (Join-Path $ProjectRoot 'evidence/automation')
)
```

The existing classification table already maps `'run-request.json' = 'transient'`, so no further change is needed — the walker will pick it up via the `if ($null -eq $zone -or $zone -eq 'transient')` branch at [line 746](../tools/automation/RunbookOrchestration.psm1#L746).

**Caveat**: pass 1's C1 fix uses an atomic-rename pattern that briefly creates `run-request.json.tmp` in the requests dir. If C1 is implemented and a prior orchestration crashed mid-rename leaving a `.tmp` behind, this cleanup will sweep it up too — desired behavior. Verify the classification table doesn't over-restrict: `*.tmp` files in the transient dirs go through the unclassified-fallback branch and get deleted, which is what you want.

**How to verify**:

```powershell
# Pre-seed a stale request as if a prior run had crashed.
$stale = './integration-testing/probe/harness/automation/requests/run-request.json'
'{"requestId":"stale-001","scenarioId":"x","runId":"r","targetScene":"res://x.tscn"}' | `
    Set-Content -LiteralPath $stale

# Run any orchestration. Cleanup should wipe the stale file before writing the new one.
pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe

# After the run completes (or times out), the requests dir should NOT contain the stale file.
Get-ChildItem ./integration-testing/probe/harness/automation/requests/
# Expect: empty or only the in-flight new request, NOT the stale-001 payload.
```

Add a Pester test in [tools/tests/InvokeRunbookScripts.Tests.ps1](../tools/tests/InvokeRunbookScripts.Tests.ps1) (or a sibling lifecycle-cleanup test file): seed a stale request, call `Initialize-RunbookTransientZone`, assert the file is gone.

---

### M2 — Pester suite for runtime invokers doesn't mock the broker

**Where**: [tools/tests/InvokeRunbookScripts.Tests.ps1](../tools/tests/InvokeRunbookScripts.Tests.ps1) (756 lines). Search for `Mock` — there are zero mocks of `Invoke-Helper` or `Invoke-RunbookRequest`. The tests that exercise invoke scripts only cover parameter validation and envelope-shape contracts (e.g. [lines 282-299](../tools/tests/InvokeRunbookScripts.Tests.ps1#L282-L299)).

The shared module [exposes `Invoke-Helper`](../tools/automation/RunbookOrchestration.psm1#L1216) precisely so Pester can mock it (per the comment at [lines 32-34](../tools/automation/RunbookOrchestration.psm1#L32-L34)) — but no test actually does.

**Symptom**: bugs that only surface against a real editor get past CI. Pass 1's C1 race (validator runs after broker consumes the file) can never be caught here because nothing simulates a broker writing to `run-result.json` after the request appears. Pass 1's C2 (`artifactRoot` mismatch) is actively masked by the test fixtures, which encode the broken format — see `FakeRunResultSuccess.manifestPath` at [InvokeRunbookScripts.Tests.ps1:17](../tools/tests/InvokeRunbookScripts.Tests.ps1#L17), which points at `tools/tests/fixtures/pong-testbed/evidence/...` (the bug pattern).

**Fix**: add Pester scenarios that mock the broker to drive each runtime invoker through a full success path, and a full failure path, in CI.

The pattern (using Pester's `Mock`):

```powershell
# In a new Describe block — e.g. 'invoke-input-dispatch.ps1 broker round-trip':

BeforeEach {
    $script:FakeRoot = Join-Path $TestDrive 'fake-project'
    New-Item -ItemType Directory -Path $script:FakeRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:FakeRoot 'harness/automation/results') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:FakeRoot 'harness/automation/requests') -Force | Out-Null

    # Pre-seed a fresh capability.json so Test-RunbookCapability passes.
    @{
        runtimeBridgeAvailable = $true
        captureControlAvailable = $true
        inputDispatch = @{ supported = $true; supportedKinds = @('key','action'); supportedPhases = @('press','release') }
        runtimeErrorCapture = @{ supported = $true }
        pauseOnError = @{ supported = $true }
        breakpointSuppression = @{ supported = $true; reason = '' }
        validationAvailable = $true
        launchControlAvailable = $true
        shutdownControlAvailable = $true
        persistenceAvailable = $true
        recommendedControlPath = 'file_broker'
        singleTargetReady = $true
        notes = @()
        blockedReasons = @()
        projectIdentifier = $script:FakeRoot
        checkedAt = (Get-Date -Format 'o')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath `
        (Join-Path $script:FakeRoot 'harness/automation/results/capability.json') -Encoding utf8
}

It 'completes a full success round-trip when the broker writes a matching run-result' {
    # Fake the broker by writing run-result.json shortly after the request appears.
    $resultPath = Join-Path $script:FakeRoot 'harness/automation/results/run-result.json'

    Mock -ModuleName 'RunbookOrchestration' -CommandName 'Invoke-Helper' -MockWith {
        # The orchestrator calls Invoke-Helper for capability probe + schema validation.
        # Return success for both; for the validate call, also start an async writer
        # that drops a matching run-result.json after a tiny delay.
        if ($ArgumentList -contains '-SchemaPath') {
            # Schema validate call — return valid:true synchronously.
            $reqPath = $ArgumentList[($ArgumentList.IndexOf('-InputPath')+1)]
            $req = Get-Content -LiteralPath $reqPath -Raw | ConvertFrom-Json
            Start-Job -ScriptBlock {
                param($p, $rid)
                Start-Sleep -Milliseconds 100
                @{
                    requestId = $rid
                    runId = $rid
                    finalStatus = 'completed'
                    failureKind = $null
                    completedAt = (Get-Date -Format 'o')
                    manifestPath = "$using:script:FakeRoot/evidence/automation/$rid/evidence-manifest.json"
                } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding utf8
            } -ArgumentList @($resultPath, $req.requestId) | Out-Null
            return [pscustomobject]@{ ExitCode = 0; CapturedOutput = '{"valid":true,"inputPath":"x","schemaPath":"y"}' }
        }
        return [pscustomobject]@{ ExitCode = 0; CapturedOutput = '' }
    }

    # ... pre-seed a fake manifest at the path the mock claims, then invoke the script.
    # Assert envelope.status = 'success', failureKind = $null, manifestPath populated.
}
```

Cover the failure paths too: `failureKind=runtime`, `failureKind=build`, `failureKind=timeout` (let the broker mock NOT write any file). Each failure mode should produce the correct envelope shape per [specs/008-agent-runbook/contracts/orchestration-stdout.schema.json](../specs/008-agent-runbook/contracts/orchestration-stdout.schema.json).

Once these mocks exist, add a regression test specifically for pass 1's C1 race — simulate a broker that consumes (deletes) the request *before* the orchestrator's validator runs, and assert the validator sees the validated payload anyway (because pass 1's fix validates pre-write).

Also fix the test fixtures' `manifestPath` ([line 17](../tools/tests/InvokeRunbookScripts.Tests.ps1#L17), [line 35](../tools/tests/InvokeRunbookScripts.Tests.ps1#L35)) to point under `evidence/automation/` rather than `tools/tests/fixtures/pong-testbed/evidence/automation/...`. The current shape encodes pass 1's C2 bug; once C2 lands, fixtures should reflect the correct shape.

**How to verify**:
1. `pwsh ./tools/tests/run-tool-tests.ps1` — new broker-round-trip tests pass.
2. Re-introduce pass 1's C1 bug temporarily (revert the validate-then-rename fix). The new regression test should fail. Re-apply the fix; test passes again.
3. CI run on a fresh checkout (no Godot) should still complete green — all new tests are mocked, none require a live editor.

---

### M4 — Silent wipe of unclassified files in the transient zone

**Where**: [RunbookOrchestration.psm1:746](../tools/automation/RunbookOrchestration.psm1#L746)

```powershell
# Unmatched files in the transient directories are also cleared
if ($null -eq $zone -or $zone -eq 'transient') {
    # ... delete with one retry ...
}
```

**Symptom**: any file that lands in `harness/automation/results/` or `evidence/automation/` and isn't in the classification table at [lines 472-489](../tools/automation/RunbookOrchestration.psm1#L472-L489) gets deleted between runs. No warning, no diagnostic. If a future addon update introduces a new artifact kind (say, `physics-trace.jsonl`), it disappears between runs and the developer sees no signal.

**Root cause**: the unclassified-fallback rule treats "I don't recognize this file" as "delete it." Defensive choice for safety, but silent.

**Fix**: keep the deletion behavior (otherwise unknown junk accumulates), but emit a diagnostic so the developer knows. Two-line change:

```powershell
if ($null -eq $zone) {
    $diagnostics.Add("cleanup-unclassified: deleted '$relPath' — file is not in Get-RunZoneClassification. Add it to the classification table to suppress this diagnostic.")
    # ... fall through to the existing delete-with-retry block ...
}
elseif ($zone -eq 'transient') {
    # ... existing delete-with-retry block ...
}
```

The diagnostic flows out via the orchestrator's lifecycle diagnostics (see how `$_lifecycleDiags` is populated in each invoke script, e.g. [invoke-input-dispatch.ps1:117-126](../tools/automation/invoke-input-dispatch.ps1#L117-L126)) into the envelope's `diagnostics[]` array. Agents reading the envelope see "deleted unclassified file" and know to either add a classification or stop writing the file.

**Stronger alternative**: add a `-StrictClassification` switch that turns unclassified files into a hard `cleanup-blocked` failure instead of a silent delete. Useful in CI; risky in the field. Recommend the diagnostic-only fix for now and add the strict switch later if the diagnostics get noisy.

**How to verify**:
```powershell
# Drop a junk file in the transient zone, then run any orchestration.
'junk' | Set-Content ./integration-testing/probe/harness/automation/results/mystery.dat

pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe | ConvertFrom-Json
# → envelope.diagnostics[] contains an entry mentioning 'mystery.dat' and 'cleanup-unclassified'.
# → file is gone afterward (existing behavior preserved).
```

Add a Pester test that pre-seeds an unclassified file in `$TestDrive`, calls `Initialize-RunbookTransientZone`, and asserts the returned `Diagnostics[]` includes a `cleanup-unclassified` entry.

---

### M5 — `pwsh` is hardcoded in three child-spawn sites

**Where**:
- [RunbookOrchestration.psm1:51](../tools/automation/RunbookOrchestration.psm1#L51) — `Invoke-Helper`
- [RunbookOrchestration.psm1:414](../tools/automation/RunbookOrchestration.psm1#L414) — `Test-RunbookManifest`
- [tools/tests/TestHelpers.ps1:31](../tools/tests/TestHelpers.ps1#L31) — `Invoke-RepoPowerShell`

All three call `Start-Process -FilePath 'pwsh' ...` or `& pwsh ...`.

**Symptom**: on Windows installations where only `powershell.exe` (Windows PowerShell 5.1) is available — locked-down servers, some CI images, fresh Windows VMs without PowerShell 7 installed — every orchestration call fails to spawn the child process. The error is unhelpful: `The term 'pwsh' is not recognized as the name of a cmdlet, function, script file, or operable program.`

**Root cause**: assumes PowerShell 7 is on PATH. Documented as a prerequisite in [RUNBOOK.md](../RUNBOOK.md), but the failure mode is opaque.

**Fix**: reuse the binary running the current process. PowerShell exposes its own path via `(Get-Process -Id $PID).Path` or via `$PSHOME\pwsh.exe` (or `\powershell.exe` for Windows PowerShell). The first form works reliably across editions:

```powershell
# At the top of the module (and TestHelpers.ps1):
$script:CurrentPwshPath = (Get-Process -Id $PID).Path
```

Then replace each `'pwsh'` literal with `$script:CurrentPwshPath`:

```powershell
# RunbookOrchestration.psm1:51
$captured = & $script:CurrentPwshPath -NoProfile -File $resolvedScript @ArgumentList 2>&1

# RunbookOrchestration.psm1:414 (inside Start-Process arglist)
$proc = Start-Process -FilePath $script:CurrentPwshPath ...

# TestHelpers.ps1:31
$process = Start-Process -FilePath $script:CurrentPwshPath ...
```

**Caveat**: if the user is somehow running `pwsh` 7 but expects child processes to use Windows PowerShell 5, this change makes that explicit (children use 7). That's almost always what you want — consistency with the parent. Document the behavior.

**Alternative**: defensive fallback. Try `pwsh` first, fall back to `powershell` if absent:

```powershell
$script:CurrentPwshPath = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    (Get-Command pwsh).Source
} elseif ($PSVersionTable.PSEdition -eq 'Core') {
    (Get-Process -Id $PID).Path
} else {
    'powershell.exe'
}
```

This works in mixed environments but introduces version skew (parent might be pwsh 7, child might be Windows PowerShell 5.1). The reuse-current-binary approach is cleaner.

**How to verify**:
1. `pwsh ./tools/tests/run-tool-tests.ps1` — all tests still pass.
2. `& 'C:\Program Files\PowerShell\7\pwsh.exe' ./tools/tests/run-tool-tests.ps1` — explicit-path invocation works.
3. Rename or hide `pwsh` temporarily (`Rename-Item C:\Program Files\PowerShell\7\pwsh.exe pwsh.bak`), then run any invoke script through an absolute path. Should still work after fix; would have failed before.

## How to validate the whole pass

### Static checks

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

Expectation:
- New M2 broker-round-trip tests for all 5 runtime invokers.
- New M1 cleanup test for `requests/` dir.
- New M4 unclassified-diagnostic test.
- All existing tests pass (including the M3 exit-code change from pass 2, if pass 2 has landed first).

If pass 2's `-EnsureEditor` switch landed, also add a Pester test that asserts `-EnsureEditor` correctly delegates to `invoke-launch-editor.ps1` (mock the launch helper).

### Live integration test

```powershell
# Combined: M1 (stale request cleanup) + M4 (unclassified diagnostic).
pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru

# Pre-seed stale + unclassified files.
'{"requestId":"stale","scenarioId":"x","runId":"r","targetScene":"res://x.tscn"}' | `
    Set-Content ./integration-testing/probe/harness/automation/requests/run-request.json
'mystery' | Set-Content ./integration-testing/probe/harness/automation/results/mystery.dat

# Launch + run.
pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe   # if pass 2 landed
$env = pwsh ./tools/automation/invoke-scene-inspection.ps1 `
    -ProjectRoot ./integration-testing/probe | ConvertFrom-Json

# Assert.
$env.status | ForEach-Object { if ($_ -ne 'success') { throw "expected success" } }
$env.diagnostics | Where-Object { $_ -match 'cleanup-unclassified' } | `
    ForEach-Object { if ($null -eq $_) { throw "expected unclassified diagnostic" } }

# Pre-seeded files are gone.
Test-Path ./integration-testing/probe/harness/automation/requests/run-request.json   # likely False
Test-Path ./integration-testing/probe/harness/automation/results/mystery.dat        # False

pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
```

### M5 portability check (optional, environment-dependent)

If you have access to a Windows machine without PowerShell 7 on PATH:
```cmd
:: From cmd.exe, with pwsh removed from PATH:
"C:\full\path\to\pwsh.exe" .\tools\tests\run-tool-tests.ps1
```
Should pass. Without the M5 fix, the child-process spawns inside Pester would fail with `pwsh not recognized`.

## Out of scope for this pass

- **Pass 1** ([01-unblock-the-loop.md](01-unblock-the-loop.md)): validate-then-rename, drop `artifactRoot`, fix `.TrimEnd()` template leak, strip ANSI from envelope diagnostics. Should land before this pass — M2's broker-mock tests are most useful as regression coverage for pass 1's fixes.
- **Pass 2** ([02-dry-ergonomics.md](02-dry-ergonomics.md)): editor launch helper, scene-inspection refactor to use `Resolve-RunbookPayload`, pin/unpin exit codes for `refused`. Should land before this pass to keep test scaffolding aligned.
- **Pass 4** ([04-polish.md](04-polish.md)): scaffold-standalone tweaks, fix Get-Help examples, document the junction trick, requestId-suffix `outputDirectory`.

Do not refactor `Get-RunZoneClassification` to a class or external file — keep it as the in-module hashtable. Do not change `Initialize-RunbookTransientZone`'s policy of cleaning before each run — only the diagnostic surface.
