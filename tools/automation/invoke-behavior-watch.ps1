<#
.SYNOPSIS
    Sample a Godot node property over a frame window in a single invocation.

.DESCRIPTION
    invoke-behavior-watch.ps1 wraps the full harness loop
    (capability check → request delivery → poll → manifest read) into a single
    invocation. It accepts a tracked behavior-watch fixture or an inline JSON
    payload, delivers it to the editor broker, waits for completion, and emits a
    stable stdout JSON envelope with the behavior-watch outcome.

    The script requires an editor running against the specified ProjectRoot.

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox.

.PARAMETER RequestFixturePath
    Repo-relative or absolute path to a tracked fixture under
    tools/tests/fixtures/runbook/behavior-watch/. Mutually exclusive with
    -RequestJson.

.PARAMETER RequestJson
    Inline JSON string containing the full run-request payload with a
    behaviorWatchRequest field. Mutually exclusive with -RequestFixturePath.

.PARAMETER TimeoutSeconds
    End-to-end wall-clock budget. Default: 60.

.PARAMETER MaxCapabilityAgeSeconds
    Maximum allowed age of capability.json. Default: 300.

.PARAMETER PollIntervalMilliseconds
    Polling interval for run-result.json. Default: 250.

.EXAMPLE
    # First, scaffold a sandbox to sample (idempotent; -Force re-creates):
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then sample:
    pwsh ./tools/automation/invoke-behavior-watch.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/behavior-watch/single-property-window.json

    Samples the paddle's position over 10 frames and emits a JSON envelope with
    outcome.samplesPath, outcome.sampleCount, and outcome.frameRangeCovered.

.EXAMPLE
    pwsh ./tools/automation/invoke-behavior-watch.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestJson '{"requestId":"x","scenarioId":"s","runId":"r","targetScene":"res://scenes/main.tscn","outputDirectory":"res://evidence/r","artifactRoot":"tools/tests/fixtures","capturePolicy":{"startup":true},"stopPolicy":{"stopAfterValidation":true},"requestedBy":"agent","createdAt":"2026-01-01T00:00:00Z","behaviorWatchRequest":{"targets":[{"nodePath":"/root/Main/Paddle","properties":["position"]}],"frameCount":10}}'

    Same as above, using an inline JSON payload.
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

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug = 'behavior-watch'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $diags = @($_lifecycleDiags) + @($Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics $diags -Outcome @{
            samplesPath       = $null
            sampleCount       = 0
            frameRangeCovered = $null
            warnings          = @()
        }
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

# Step 1: Validate parameter set
$hasFixture = $PSBoundParameters.ContainsKey('RequestFixturePath') -and -not [string]::IsNullOrWhiteSpace($RequestFixturePath)
$hasInline  = $PSBoundParameters.ContainsKey('RequestJson') -and -not [string]::IsNullOrWhiteSpace($RequestJson)

if ($hasFixture -and $hasInline) {
    Exit-Failure 'request-invalid' '-RequestFixturePath and -RequestJson are mutually exclusive.'
}
if (-not $hasFixture -and -not $hasInline) {
    Exit-Failure 'request-invalid' 'Exactly one of -RequestFixturePath or -RequestJson must be supplied.'
}

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

# Steps 6-7: Request + poll
$runResult = Invoke-RunbookRequest `
    -ProjectRoot $resolvedRoot `
    -RequestPath $materialized.TempRequestPath `
    -ExpectedRequestId $requestId `
    -TimeoutSeconds $_timeoutBudget `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr    = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

# B16: surface validationResult.notes for failureKind=validation before the
# generic failed-status branch or the downstream Test-RunbookManifest check.
if ($rr.finalStatus -eq 'failed' -and ([string]$rr.failureKind) -eq 'validation') {
    $vNotes = Get-RunResultValidationDiagnostics -RunResult $rr
    if ($vNotes.Count -gt 0) {
        $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind 'validation' -FallbackKind 'internal'
        $diags = @($_lifecycleDiags) + @($vNotes)
        # Match Exit-Failure's outcome shape so consumers see the same keys on every failure path.
        Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
                samplesPath       = $null
                sampleCount       = 0
                frameRangeCovered = $null
                warnings          = @()
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

if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace($rr.failureKind)) {
    $fk = [string]$rr.failureKind
    $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind $fk -FallbackKind 'internal'
    Exit-Failure $envelopeKind "Run failed with failureKind='$fk'."
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
    # B7/B9: propagate run-result.failureKind instead of collapsing to internal.
    $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
    Exit-Failure $kind $manifestCheck.Diagnostic
}

# Step 9: Build outcome from the manifest's appliedWatch.outcomes block.
#
# Issue #45: previously this script counted rows on disk and synthesized
# warnings from the request payload's nodePath when the row count was zero.
# Two compounding bugs made the envelope contradict the manifest:
#  1. The artifact-kind filter used 'behavior-samples' / 'behavior-trace',
#     but the runtime emits kind="trace" (per InspectionConstants.
#     ARTIFACT_KIND_TRACE). The filter never matched, so the row-count
#     read was skipped and sampleCount always stayed at 0.
#  2. The zero-row fallback synthesized "target node not found or never
#     sampled: <nodePath>" from the REQUEST payload — a string that's not
#     informed by what actually happened at runtime. The watch could have
#     succeeded fully (manifest's missingTargets: []) and still get a false
#     missing-target warning.
#
# Fix: trust the manifest. appliedWatch.outcomes already has sampleCount,
# missingTargets, missingProperties, and noSamples — populated by the
# runtime in scenegraph_artifact_writer.gd:72-79. Source warnings from
# THERE, not from the request payload. Use the trace file only for
# frameRangeCovered (which the manifest doesn't carry) and for surfacing
# the resolved samplesPath.
$samplesPath       = $null
$sampleCount       = 0
$frameRangeCovered = $null
$warnings          = [System.Collections.Generic.List[string]]::new()

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20

    # Source-of-truth: appliedWatch.outcomes block (issue #45).
    $watchOutcomes = $null
    if ($manifest.PSObject.Properties.Name -contains 'appliedWatch' -and $null -ne $manifest.appliedWatch) {
        if ($manifest.appliedWatch.PSObject.Properties.Name -contains 'outcomes') {
            $watchOutcomes = $manifest.appliedWatch.outcomes
        }
    }
    if ($null -ne $watchOutcomes) {
        if ($watchOutcomes.PSObject.Properties.Name -contains 'sampleCount') {
            $sampleCount = [int]$watchOutcomes.sampleCount
        }
        if ($watchOutcomes.PSObject.Properties.Name -contains 'missingTargets') {
            foreach ($mt in @($watchOutcomes.missingTargets)) {
                if (-not [string]::IsNullOrWhiteSpace($mt)) {
                    $warnings.Add("target node not found or never sampled: $mt")
                }
            }
        }
        if ($watchOutcomes.PSObject.Properties.Name -contains 'missingProperties') {
            foreach ($mp in @($watchOutcomes.missingProperties)) {
                if ($null -eq $mp) { continue }
                $mpNode = if ($mp.PSObject.Properties.Name -contains 'nodePath') { [string]$mp.nodePath } else { '' }
                if ([string]::IsNullOrWhiteSpace($mpNode)) { continue }
                $mpProps = @()
                if ($mp.PSObject.Properties.Name -contains 'properties') {
                    $mpProps = @($mp.properties | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
                $propsList = ($mpProps -join ', ')
                $warnings.Add("target node '$mpNode' sampled but properties never observed: $propsList")
            }
        }
        $noSamples = $false
        if ($watchOutcomes.PSObject.Properties.Name -contains 'noSamples') {
            $noSamples = [bool]$watchOutcomes.noSamples
        }
        if ($noSamples -and $warnings.Count -eq 0) {
            $warnings.Add("no samples produced for the configured frame window")
        }
    }

    # Trace artifact: surface samplesPath and derive frameRangeCovered.
    # Issue #45 fix: filter on the actual emitted kind ('trace'), not the
    # ghost names that never existed in the runtime.
    $samplesRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'trace' } | Select-Object -First 1
    if ($null -ne $samplesRef) {
        $samplesPath = Resolve-RunbookEvidencePath -Path $samplesRef.path -ProjectRoot $resolvedRoot
        if (-not (Test-Path -LiteralPath $samplesPath)) {
            # Manifest references a trace that's not on disk. If the manifest
            # also claimed samples, that's a real inconsistency worth surfacing
            # — don't silently zero it out (which was the pre-fix failure mode).
            if ($sampleCount -gt 0) {
                $warnings.Add("manifest claims $sampleCount samples but trace file missing at '$samplesPath'")
            }
            $samplesPath = $null
        }
        else {
            $rows = Get-Content -LiteralPath $samplesPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { $_ | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue } |
                    Where-Object { $null -ne $_ }
            if (@($rows).Count -gt 0) {
                $frames = @($rows | ForEach-Object { [int]$_.frame } | Sort-Object)
                $frameRangeCovered = @{ first = $frames[0]; last = $frames[-1] }
            }
        }
    }
}
catch {
    Exit-Failure 'internal' "Failed to assemble behavior-watch outcome from manifest: $($_.Exception.Message)"
}

# Steps 10-12
$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @($_lifecycleDiags) -Outcome @{
        samplesPath       = $samplesPath
        sampleCount       = $sampleCount
        frameRangeCovered = $frameRangeCovered
        warnings          = @($warnings)
    }
$envelope
$warnSuffix = if ($warnings.Count -gt 0) { "; warnings: $($warnings -join ' | ')" } else { '' }
Write-RunbookStderrSummary "OK: $sampleCount samples captured; manifest at $absManifest$warnSuffix"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
