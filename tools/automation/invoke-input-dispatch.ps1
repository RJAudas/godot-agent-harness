<#
.SYNOPSIS
    Dispatch key or InputMap action events in a running Godot game and capture the resulting scene state.

.DESCRIPTION
    invoke-input-dispatch.ps1 wraps the full harness loop
    (capability check → request delivery → poll → manifest read) into a single
    invocation. It accepts a tracked request fixture or an inline JSON payload,
    delivers it to the editor broker, waits for completion, and emits a stable
    stdout JSON envelope containing the input-dispatch outcome.

    The script requires an editor running against the specified ProjectRoot.
    When the editor is not running or the capability is stale, it exits non-zero
    with failureKind = "editor-not-running".

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox that the
    Godot editor is running against.

.PARAMETER RequestFixturePath
    Repo-relative or absolute path to a tracked request fixture under
    tools/tests/fixtures/runbook/input-dispatch/. Mutually exclusive with
    -RequestJson.

.PARAMETER RequestJson
    Inline JSON string containing the full run-request payload with an
    inputDispatchScript field. Mutually exclusive with -RequestFixturePath.

.PARAMETER TimeoutSeconds
    End-to-end wall-clock budget in seconds. Default: 60.

.PARAMETER MaxCapabilityAgeSeconds
    Maximum allowed age of capability.json in seconds before the editor is
    considered not running. Default: 300.

.PARAMETER PollIntervalMilliseconds
    How often to poll run-result.json while waiting for the request to complete.
    Default: 250.

.EXAMPLE
    # First, scaffold a sandbox to dispatch into (idempotent; -Force re-creates):
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then dispatch:
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/input-dispatch/press-enter.json

    Dispatches the Enter key once and emits a JSON envelope with
    outcome.declaredEventCount, outcome.actualDispatchedCount, and
    outcome.outcomesPath.

.EXAMPLE
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestJson '{"requestId":"x","scenarioId":"s","runId":"r","targetScene":"res://scenes/main.tscn","outputDirectory":"res://evidence/r","artifactRoot":"tools/tests/fixtures","capturePolicy":{"startup":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"2026-01-01T00:00:00Z","inputDispatchScript":{"events":[{"kind":"key","identifier":"ENTER","phase":"press","frame":30},{"kind":"key","identifier":"ENTER","phase":"release","frame":32}]}}'

    Same as above, using an inline JSON payload instead of a fixture file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$RequestFixturePath,

    [string]$RequestJson,

    [int]$TimeoutSeconds = 60,

    [int]$MaxCapabilityAgeSeconds = 300,

    [int]$PollIntervalMilliseconds = 250,

    # When set, auto-launch a Godot editor against -ProjectRoot before running.
    # Idempotent: reuses an existing editor if capability.json is fresh.
    [switch]$EnsureEditor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleDir  = $PSScriptRoot
$modulePath = Join-Path $moduleDir 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$repoRoot        = Get-RunbookRepoRoot
$resolvedRoot    = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug    = 'input-dispatch'
$requestId       = New-RunbookRequestId -Workflow $workflowSlug
$runId           = $requestId

$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $diags = @($_lifecycleDiags) + @($Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics $diags -Outcome @{
            outcomesPath          = $null
            declaredEventCount    = 0
            actualDispatchedCount = 0
            firstFailureSummary   = $null
        }
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

# Step 1: Validate parameter set
$hasFixture = $PSBoundParameters.ContainsKey('RequestFixturePath') -and -not [string]::IsNullOrWhiteSpace($RequestFixturePath)
$hasInline  = $PSBoundParameters.ContainsKey('RequestJson') -and -not [string]::IsNullOrWhiteSpace($RequestJson)

if ($hasFixture -and $hasInline) {
    Exit-Failure 'request-invalid' '-RequestFixturePath and -RequestJson are mutually exclusive. Supply exactly one.'
}
if (-not $hasFixture -and -not $hasInline) {
    Exit-Failure 'request-invalid' 'Exactly one of -RequestFixturePath or -RequestJson must be supplied.'
}

# Step 2-3: Resolve project root (already done above)

# End-to-end TimeoutSeconds budget. The optional EnsureEditor step deducts
# its elapsed time so the total wall-clock stays bounded by TimeoutSeconds.
$_timeoutBudget = $TimeoutSeconds

# Optional: auto-launch the editor if the caller asked for -EnsureEditor.
if ($EnsureEditor) {
    $launcher     = Join-Path $PSScriptRoot 'invoke-launch-editor.ps1'
    $_ensureStart = Get-Date
    $ensureResult = Invoke-EnsureEditor -LauncherScriptPath $launcher `
        -ProjectRoot $resolvedRoot -MaxCapabilityAgeSeconds $MaxCapabilityAgeSeconds `
        -TimeoutSeconds $_timeoutBudget
    $_timeoutBudget = [Math]::Max(1, $TimeoutSeconds - [int]((Get-Date) - $_ensureStart).TotalSeconds)
    if (-not $ensureResult.Ok) {
        Exit-Failure 'editor-not-running' $ensureResult.Diagnostic
    }
    try {
        $launchEnv = $ensureResult.EnvelopeJson | ConvertFrom-Json -Depth 20
    }
    catch {
        Exit-Failure 'editor-not-running' "Auto-launch produced non-JSON output: $($ensureResult.EnvelopeJson)"
    }
    if ($launchEnv.status -ne 'success') {
        $detail = if ($null -ne $launchEnv.diagnostics -and @($launchEnv.diagnostics).Count -gt 0) { $launchEnv.diagnostics[0] } else { 'no diagnostic' }
        Exit-Failure 'editor-not-running' "Auto-launch failed (failureKind=$($launchEnv.failureKind)): $detail"
    }
}

# Lifecycle preamble (US1): concurrent-run guard, in-flight marker, transient-zone cleanup
$_assertResult   = Assert-NoInFlightRun -ProjectRoot $resolvedRoot
if (-not $_assertResult.Ok) {
    Exit-Failure $_assertResult.FailureKind $_assertResult.Diagnostics[0]
}
if ($null -ne $_assertResult.StaleDiagnostic) { $_lifecycleDiags.Add($_assertResult.StaleDiagnostic) }
$null = New-RunbookInFlightMarker -ProjectRoot $resolvedRoot -RequestId $requestId -InvokeScript (Split-Path $PSCommandPath -Leaf)

try {

$_cleanup = Initialize-RunbookTransientZone -ProjectRoot $resolvedRoot
if (-not $_cleanup.Ok) {
    Exit-Failure $_cleanup.FailureKind ($_cleanup.Diagnostics | Select-Object -First 1)
}
foreach ($_d in $_cleanup.Diagnostics) { $_lifecycleDiags.Add($_d) }

# Step 4: Capability check
$cap = Test-RunbookCapability -ProjectRoot $resolvedRoot -MaxAgeSeconds $MaxCapabilityAgeSeconds
if (-not $cap.Ok) {
    Exit-Failure $cap.FailureKind $cap.Diagnostic
}

# Step 5: Materialize payload
$payloadArgs = @{ RequestId = $requestId; ProjectRoot = $resolvedRoot }
if ($hasFixture) { $payloadArgs['FixturePath'] = $RequestFixturePath }
else             { $payloadArgs['InlineJson']  = $RequestJson }

try {
    $materialized = Resolve-RunbookPayload @payloadArgs
}
catch {
    Exit-Failure 'request-invalid' $_.Exception.Message
}

# Step 6-7: Request + poll
$runResult = Invoke-RunbookRequest `
    -ProjectRoot $resolvedRoot `
    -RequestPath $materialized.TempRequestPath `
    -ExpectedRequestId $requestId `
    -TimeoutSeconds $_timeoutBudget `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

# B16: when run-result already classified the failure as validation, surface
# the validationResult.notes immediately. They carry the authoritative cause
# (e.g. "Manifest runId did not match the active automation request"); without
# this, the agent sees only the generic "Run failed with failureKind='validation'"
# text below or a misleading "manifest not found" diagnostic from a downstream
# Test-RunbookManifest call against a path the runtime never wrote to.
if ($rr.finalStatus -eq 'failed' -and ([string]$rr.failureKind) -eq 'validation') {
    $vNotes = Get-RunResultValidationDiagnostics -RunResult $rr
    if ($vNotes.Count -gt 0) {
        $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind 'validation' -FallbackKind 'internal'
        $diags = @($_lifecycleDiags) + @($vNotes)
        # Match Exit-Failure's outcome shape so consumers see the same per-workflow keys
        # on every failure path. Validation failures don't produce per-workflow data, so
        # the values are null/0 just like Exit-Failure's literal.
        Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
                outcomesPath          = $null
                declaredEventCount    = 0
                actualDispatchedCount = 0
                firstFailureSummary   = $null
            }
        Write-RunbookStderrSummary "FAIL: $envelopeKind; $($vNotes -join ' | ')"
        exit 1
    }
}

# B19: emit a structured envelope when the broker refused the run before any
# evidence could be captured (e.g. scene_already_running). Without this branch
# the script would fall through to the manifestPath read and crash differently.
$blockedMsg = Get-BlockedRunDiagnostics -RunResult $rr
if ($null -ne $blockedMsg) {
    Exit-Failure 'runtime' $blockedMsg
}

# Check for harness-reported failures
if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace($rr.failureKind)) {
    $fk = [string]$rr.failureKind
    $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind $fk -FallbackKind 'internal'
    Exit-Failure $envelopeKind "Run failed with failureKind='$fk'. Check the manifest for details."
}

# Step 8: Read manifest
$manifestPath = [string]$rr.manifestPath
if ([string]::IsNullOrWhiteSpace($manifestPath)) {
    $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
    Exit-Failure $kind "run-result.json did not contain a manifestPath."
}
$absManifest = Resolve-RunbookEvidencePath -Path $manifestPath -ProjectRoot $resolvedRoot

$manifestCheck = Test-RunbookManifest -ManifestPath $absManifest -ProjectRoot $resolvedRoot
if (-not $manifestCheck.Ok) {
    # B7/B9: when run-result already reported a non-internal failure, propagate
    # that classification rather than collapsing to 'internal' on a downstream
    # manifest check.
    $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
    Exit-Failure $kind $manifestCheck.Diagnostic
}

# Step 9: Build outcome
# B2: status='dispatched' rows are events that actually fired. Anything else
# (skipped_frame_unreached, skipped_run_ended, failed) means the event was
# DECLARED but not delivered. Track both counts so the agent can tell the
# difference, and surface failure when they diverge.
$outcomesPath          = $null
$declaredEventCount    = 0
$actualDispatchedCount = 0
$firstFailureSummary   = $null
$firstFailedStatus     = $null

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
    $outcomeRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'input-dispatch-outcomes' } | Select-Object -First 1
    if ($null -ne $outcomeRef) {
        $outcomesPath = Resolve-RunbookEvidencePath -Path $outcomeRef.path -ProjectRoot $resolvedRoot
        if (Test-Path -LiteralPath $outcomesPath) {
            $lines = Get-Content -LiteralPath $outcomesPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $declaredEventCount = @($lines).Count
            foreach ($line in $lines) {
                $row = $line | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
                if ($null -eq $row) { continue }
                $hasStatus = $null -ne ($row | Get-Member -Name 'status' -ErrorAction SilentlyContinue)
                if (-not $hasStatus) { continue }
                $rowStatus = [string]$row.status
                if ($rowStatus -eq 'dispatched') {
                    $actualDispatchedCount += 1
                } elseif ($null -eq $firstFailureSummary) {
                    $hasReason = $null -ne ($row | Get-Member -Name 'reasonMessage' -ErrorAction SilentlyContinue)
                    $firstFailureSummary = if ($hasReason) { [string]$row.reasonMessage } else { $rowStatus }
                    $firstFailedStatus   = $rowStatus
                }
            }
        }
    }
}
catch {
    Exit-Failure 'internal' "Failed to assemble input-dispatch outcome from manifest: $($_.Exception.Message)"
}

# Steps 10-12: Emit envelope and exit
$outcome = @{
    outcomesPath          = $outcomesPath
    declaredEventCount    = $declaredEventCount
    actualDispatchedCount = $actualDispatchedCount
    firstFailureSummary   = $firstFailureSummary
}

if ($declaredEventCount -gt 0 -and $actualDispatchedCount -lt $declaredEventCount) {
    # B2: not every declared event actually fired. Don't claim success.
    $msg = "Only $actualDispatchedCount of $declaredEventCount declared events were dispatched (firstFailedStatus=$firstFailedStatus, firstFailureSummary='$firstFailureSummary'). The run may have ended before the requested frames were reached."
    $diags = @($_lifecycleDiags) + @($msg)
    Write-RunbookEnvelope -Status 'failure' -FailureKind 'runtime' -ManifestPath $absManifest `
        -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome $outcome
    Write-RunbookStderrSummary "FAIL: runtime; $msg"
    exit 1
}

$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @($_lifecycleDiags) -Outcome $outcome
$envelope
Write-RunbookStderrSummary "OK: dispatched $actualDispatchedCount of $declaredEventCount events; manifest at $absManifest"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
