# Pass 2 — DRY and ergonomics

## Goal

After [pass 1](01-unblock-the-loop.md) makes the basic loop work, this pass cleans up duplication and removes friction from the agent UX. Three issues:

- **H2**: orchestrators assume a Godot editor is already running. There's no helper to launch one. Agents have to manually `Start-Process` the binary, poll for `capability.json`, and clean up — every time.
- **H3**: `invoke-scene-inspection.ps1` re-implements the materialize-and-write-the-request logic instead of calling the shared `Resolve-RunbookPayload` helper that the other four runtime workflows use.
- **M3**: `invoke-pin-run.ps1` and `invoke-unpin-run.ps1` exit with code 1 even when the operation was correctly **refused** (not failed). Conflates valid precondition denial with hard error.

This pass assumes pass 1 has landed (validate-then-rename, single `outputDirectory`, no `.TrimEnd()` leak, ANSI-clean diagnostics). If those aren't done first, H3's refactor will inherit the bug instead of fixing it.

## Quick context (read first if you're fresh)

The harness is a Godot tooling project that gives AI agents machine-readable runtime evidence. Agents call `tools/automation/invoke-<workflow>.ps1` scripts; each wraps a capability check → request delivery → poll → manifest read loop and emits a stable JSON envelope on stdout.

The five runtime workflows talk to a Godot editor via a file broker. The editor must be running against the target sandbox project before any invoke script can succeed; otherwise the script returns `status=failure, failureKind=editor-not-running`.

The three lifecycle workflows (`pin-run`, `unpin-run`, `list-pinned-runs`) don't need the editor — they manipulate the on-disk evidence directory directly. They emit a separate "lifecycle envelope" with `status` of `ok | refused | failed`.

Shared helpers live in [tools/automation/RunbookOrchestration.psm1](../tools/automation/RunbookOrchestration.psm1). For deeper context: [CLAUDE.md](../CLAUDE.md), [AGENTS.md](../AGENTS.md), [RUNBOOK.md](../RUNBOOK.md).

## Issues in this pass

### H2 — No editor-launch helper

**Where**: missing functionality. All five runtime invoke scripts assume the editor is already running and immediately return `editor-not-running` if it isn't (capability check at [RunbookOrchestration.psm1:91-141](../tools/automation/RunbookOrchestration.psm1#L91-L141)). [RUNBOOK.md](../RUNBOOK.md) just says "An Godot editor running against an integration-testing sandbox" with no script that does the launching.

**Symptom (agent UX)**: a fresh agent has to:
1. Find the Godot binary (per the documented `$env:GODOT_BIN` / PATH resolution).
2. Spawn it with `--editor --path <sandbox>`, redirecting stdout/stderr.
3. Poll `harness/automation/results/capability.json` for up to ~60 seconds (cold start with shader cache + import).
4. Realize the windowed Godot exe detaches stdout on Windows and switch to the `*_console.exe` build.
5. Run the actual workflow.
6. Eventually `Stop-Process Godot*` to clean up — and remember three Godot processes typically spawn (project manager, editor, console wrapper).

This is documented nowhere in one place. Every agent rediscovers it.

**Fix**: ship a sibling helper, `tools/automation/invoke-launch-editor.ps1`, with the same envelope contract as the other invokers. It is idempotent: if the editor is already running and `capability.json` is fresh, return success immediately; otherwise launch, wait, return.

Sketch:

```powershell
# tools/automation/invoke-launch-editor.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [int]$ReadyTimeoutSeconds = 90,
    [int]$MaxCapabilityAgeSeconds = 300,
    [switch]$ForceRestart
)

# 1. Resolve Godot binary (mirror tools/check-addon-parse.ps1's Resolve-GodotBinary).
# 2. Resolve absolute project root.
# 3. Check existing editor: if Get-Process Godot* against this project root exists
#    AND capability.json is fresh (< MaxCapabilityAgeSeconds), return success.
# 4. If -ForceRestart, stop existing Godot processes for this project and proceed.
# 5. Start-Process godot --editor --path <root> --verbose
#    -RedirectStandardOutput <ProjectRoot>/.editor-logs/editor.stdout.log
#    -RedirectStandardError  <ProjectRoot>/.editor-logs/editor.stderr.log
# 6. Poll capability.json until present + parseable, OR until ReadyTimeoutSeconds.
# 7. Emit a JSON envelope with:
#    { status, failureKind, manifestPath: null, runId, requestId,
#      completedAt, diagnostics, outcome: { editorPid, capabilityPath, capabilityAgeSeconds } }
```

Use `Write-RunbookEnvelope` (already exported from the module — see [line 1213](../tools/automation/RunbookOrchestration.psm1#L1213)) so the envelope shape matches the other invokers.

Add a sibling stop helper too: `tools/automation/invoke-stop-editor.ps1 -ProjectRoot <root>` that finds Godot processes whose command-line includes `--path <ProjectRoot>` and stops them. Three Godot processes typically spawn (launcher, editor, optional console wrapper) — match by command-line, not just process name.

Also wire each existing runtime invoker to *optionally* auto-launch via a new `-EnsureEditor` switch. Inside each `invoke-*.ps1`, after the parameter block:

```powershell
if ($EnsureEditor) {
    $launchResult = pwsh -NoProfile -File (Join-Path $PSScriptRoot 'invoke-launch-editor.ps1') `
        -ProjectRoot $resolvedRoot | ConvertFrom-Json
    if ($launchResult.status -ne 'success') {
        Exit-Failure 'editor-not-running' "Auto-launch failed: $($launchResult.diagnostics[0])"
    }
}
```

Update [RUNBOOK.md](../RUNBOOK.md) to reference the launch helper as the prerequisite step. Update [docs/INTEGRATION_TESTING.md](../docs/INTEGRATION_TESTING.md) (if present) and the Claude skills under [.claude/skills/](../.claude/skills/) to mention `-EnsureEditor`.

**How to verify**:
1. With no Godot processes running:
   ```powershell
   pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
   ```
   Should emit `status=success` within ~60 seconds. `outcome.editorPid` should reference a live process.
2. Re-run the same command. Should return success in <1 second (idempotent path — capability.json is fresh).
3. Run a runtime workflow with `-EnsureEditor` against a fresh sandbox where the editor isn't running yet. The workflow should auto-launch and succeed.
4. Run `pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe`. `Get-Process Godot*` should return nothing.

Add Pester coverage in a new file `tools/tests/InvokeLaunchEditor.Tests.ps1`:
- Param-validation tests don't need a real editor.
- Idempotent-success path can mock `Get-Process` and a pre-created `capability.json` fixture.
- Live launch path is harder to test in CI; gate it behind an `if (-not $env:CI -and $env:GODOT_BIN)` skip.

---

### H3 — `invoke-scene-inspection.ps1` duplicates payload-write logic

**Where**: [invoke-scene-inspection.ps1:144-167](../tools/automation/invoke-scene-inspection.ps1#L144-L167) hand-rolls the payload synthesis and canonical-path write; the other four runtime invokers go through [Resolve-RunbookPayload](../tools/automation/RunbookOrchestration.psm1#L143-L218).

**Symptom (developer UX)**: any fix to the payload pipeline (validation, atomic rename, transient cleanup ordering, etc.) has to be applied in two places. Pass 1's C1 fix lives in `Resolve-RunbookPayload` AND has to be duplicated into `invoke-scene-inspection.ps1`. C2's `artifactRoot` removal is a two-place edit. Future bugs will follow the same pattern.

**Root cause**: when scene-inspection was built it had no fixture (the workflow takes no payload), so it short-circuited the helper. But the helper's `Resolve-RunbookPayload` accepts `-InlineJson` — scene-inspection could pass a synthesized JSON string just like inline callers do.

**Fix**: synthesize the minimal payload as a JSON string, then call `Resolve-RunbookPayload -InlineJson <json>` like every other invoker. Replace lines 144-175 of `invoke-scene-inspection.ps1`:

```powershell
# Step 5: Synthesize payload and route through the shared helper.
$inlinePayload = @{
    requestId        = $requestId   # Resolve-RunbookPayload will overwrite this; harmless.
    scenarioId       = "runbook-scene-inspection-$requestId"
    runId            = $requestId
    targetScene      = $TargetScene
    outputDirectory  = "res://evidence/automation/$requestId"
    expectationFiles = @()
    capturePolicy    = @{ startup = $true; manual = $false; failure = $false }
    stopPolicy       = @{ stopAfterValidation = $true }
    requestedBy      = 'runbook-scene-inspection'
    createdAt        = (Get-Date -Format 'o')
} | ConvertTo-Json -Depth 10

try {
    $materialized = Resolve-RunbookPayload -InlineJson $inlinePayload `
        -RequestId $requestId -ProjectRoot $resolvedRoot
}
catch {
    Exit-Failure 'request-invalid' $_.Exception.Message
}

# Step 6-7: Request + poll
$runResult = Invoke-RunbookRequest `
    -ProjectRoot $resolvedRoot `
    -RequestPath $materialized.TempRequestPath `
    -ExpectedRequestId $requestId `
    -TimeoutSeconds $TimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds
```

Note: this drops the explicit `artifactRoot` line that pass 1's C2 deleted. If pass 1 hasn't landed yet, do that first — otherwise this refactor will reintroduce it.

The `targetScene` resolution logic at [lines 83-108](../tools/automation/invoke-scene-inspection.ps1#L83-L108) stays — that's scene-inspection-specific.

**How to verify**:
1. `pwsh ./tools/tests/run-tool-tests.ps1` — all existing tests pass. The scene-inspection-related tests in [InvokeRunbookScripts.Tests.ps1](../tools/tests/InvokeRunbookScripts.Tests.ps1) (search for `Describe 'invoke-scene-inspection.ps1'`) should pass without modification.
2. Live: run scene-inspection per [pass 1](01-unblock-the-loop.md)'s "How to validate the whole pass" — same envelope shape, same outcome.
3. Diff the canonical `harness/automation/requests/run-request.json` written by the new code path against one written by the old code path (capture both before broker consumption). They should match modulo timestamps.

---

### M3 — Pin/unpin scripts always exit 1 on `Exit-Failure`, even for valid `refused` outcomes

**Where**: [invoke-pin-run.ps1:72-80](../tools/automation/invoke-pin-run.ps1#L72-L80) and [invoke-unpin-run.ps1:65-73](../tools/automation/invoke-unpin-run.ps1#L65-L73). Both have:

```powershell
function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $status = if ($script:RefusalFailureKinds -contains $Kind) { 'refused' } else { 'failed' }
    Write-LifecycleEnvelope -Status $status -FailureKind $Kind -Operation 'pin' `
        -DryRun $DryRun.IsPresent -Diagnostics @($Message) -PlannedPaths @() -PinName $PinName
    $label = $status.ToUpperInvariant()
    Write-RunbookStderrSummary "${label}: $Kind; $Message"
    exit 1   # <-- always 1, even when status='refused'
}
```

`$RefusalFailureKinds` includes `pin-name-collision`, `pin-name-invalid`, `pin-source-missing`, `pin-target-not-found`, `run-in-progress` — all of which are precondition denials, not script errors.

**Symptom**: an agent that pipes `pwsh ./invoke-pin-run.ps1 ... ; if ($?) { ... }` can't distinguish "the harness correctly declined to pin a name that already exists" from "the script crashed". Both produce exit code 1. Agents have to parse stdout JSON to decide.

**Fix**: differentiate exit codes by status.

```powershell
function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $status = if ($script:RefusalFailureKinds -contains $Kind) { 'refused' } else { 'failed' }
    Write-LifecycleEnvelope -Status $status -FailureKind $Kind -Operation 'pin' `
        -DryRun $DryRun.IsPresent -Diagnostics @($Message) -PlannedPaths @() -PinName $PinName
    $label = $status.ToUpperInvariant()
    Write-RunbookStderrSummary "${label}: $Kind; $Message"
    if ($status -eq 'refused') { exit 0 } else { exit 1 }
}
```

Apply the same change to `invoke-unpin-run.ps1` (replace `'pin'` with `'unpin'` in the operation field).

**Rationale**: a "refused" outcome is the script doing its job correctly — telling the caller why it declined. The envelope's `status` field encodes the answer. Exit 0 says "I ran successfully; here's the result." Exit 1 should be reserved for "I encountered an unexpected error you should investigate."

**Caveat**: this is a behavior change. Any caller that already treats exit 1 as "needs my attention" will lose that signal for refusals. Update:
- [RUNBOOK.md](../RUNBOOK.md) failure-handling table to document the new convention.
- [docs/runbook/](../docs/runbook/) recipes for pin/unpin (if they reference exit codes).
- The Claude skills under [.claude/skills/godot-pin/](../.claude/skills/godot-pin/) and `.claude/skills/godot-unpin/`.
- Any Pester tests in [InvokeRunbookScripts.Tests.ps1](../tools/tests/InvokeRunbookScripts.Tests.ps1) or sibling files that assert `$result.ExitCode | Should -Not -Be 0` for refusal scenarios.

**How to verify**:
1. Pin name collision (refused, exit 0):
   ```powershell
   pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName foo
   pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName foo
   echo $LASTEXITCODE   # Was 1; should now be 0.
   ```
   Stdout still shows `status=refused`, `failureKind=pin-name-collision`.

2. Pin source missing (refused, exit 0):
   ```powershell
   # Empty sandbox with no completed run yet:
   pwsh ./tools/scaffold-sandbox.ps1 -Name empty -Force -PassThru
   pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/empty -PinName x
   echo $LASTEXITCODE   # Should be 0; status=refused; failureKind=pin-source-missing.
   ```

3. Hard failure path (e.g., simulate I/O error by making the pinned/ directory read-only) should still exit 1.

## How to validate the whole pass

### Static checks

```powershell
pwsh ./tools/tests/run-tool-tests.ps1
```

Expectation:
- Existing pin/unpin tests that asserted exit-code 1 for refusals will need updating. Find them with `grep -rn 'ExitCode.*Should -Not -Be 0' tools/tests/`.
- New tests for `invoke-launch-editor.ps1` (envelope shape, idempotency, parameter validation).
- Existing scene-inspection tests pass without modification (they assert envelope shape, not internals).

### Live integration test

```powershell
# 1. Pure ergonomics check — H2: launch via helper, run, stop via helper.
pwsh ./tools/scaffold-sandbox.ps1 -Name probe -Force -PassThru

pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot ./integration-testing/probe
# → status=success within ~60s, outcome.editorPid populated

pwsh ./tools/automation/invoke-scene-inspection.ps1 -ProjectRoot ./integration-testing/probe
# → status=success (assuming pass 1 has landed)

pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot ./integration-testing/probe
Get-Process Godot* -ErrorAction SilentlyContinue
# → empty
```

### -EnsureEditor convenience check

```powershell
# Editor not running. Auto-launch via -EnsureEditor flag.
pwsh ./tools/automation/invoke-scene-inspection.ps1 `
    -ProjectRoot ./integration-testing/probe -EnsureEditor
# → success, with editor still running afterward (the launcher leaves it up).
```

### M3 exit-code check

```powershell
pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName demo
echo "first: $LASTEXITCODE"   # 0
pwsh ./tools/automation/invoke-pin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName demo
echo "second: $LASTEXITCODE"  # was 1, now 0; envelope still shows status=refused
pwsh ./tools/automation/invoke-unpin-run.ps1 -ProjectRoot ./integration-testing/probe -PinName demo
```

## Out of scope for this pass

- **Pass 1** ([01-unblock-the-loop.md](01-unblock-the-loop.md)): validate-then-rename, drop `artifactRoot`, fix `.TrimEnd()` template leak, strip ANSI from envelope diagnostics. Must land before this pass — H3's refactor depends on a working `Resolve-RunbookPayload`.
- **Pass 3** ([03-hardening-tests.md](03-hardening-tests.md)): clean `requests/` between runs, mock the broker in Pester for end-to-end coverage, tighten silent-wipe behavior, decouple from hardcoded `pwsh` binary.
- **Pass 4** ([04-polish.md](04-polish.md)): scaffold-standalone tweaks, fix Get-Help examples that reference a non-existent `pong` sandbox, document the junction trick in `check-addon-parse.ps1`, requestId-suffix `outputDirectory`.

Do not change the editor broker protocol shape. Do not introduce per-request request filenames (the broker only watches the canonical path). The `-EnsureEditor` flag is opt-in; do not change the default failure mode of the existing scripts.
