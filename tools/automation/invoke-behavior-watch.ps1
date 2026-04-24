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
    pwsh ./tools/automation/invoke-behavior-watch.ps1 `
        -ProjectRoot integration-testing/pong `
        -RequestFixturePath tools/tests/fixtures/runbook/behavior-watch/single-property-window.json

    Samples the paddle's position over 10 frames and emits a JSON envelope with
    outcome.samplesPath, outcome.sampleCount, and outcome.frameRangeCovered.

.EXAMPLE
    pwsh ./tools/automation/invoke-behavior-watch.ps1 `
        -ProjectRoot integration-testing/pong `
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

    [int]$PollIntervalMilliseconds = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug = 'behavior-watch'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics @($Message) -Outcome @{
            samplesPath      = $null
            sampleCount      = 0
            frameRangeCovered = $null
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

# Lifecycle preamble (US1): concurrent-run guard, in-flight marker, transient-zone cleanup
$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()
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
    -TimeoutSeconds $TimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr    = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace($rr.failureKind)) {
    $fk = [string]$rr.failureKind
    Exit-Failure $fk "Run failed with failureKind='$fk'."
}

# Step 8: Read manifest
$manifestPath = [string]$rr.manifestPath
if ([string]::IsNullOrWhiteSpace($manifestPath)) {
    Exit-Failure 'internal' "run-result.json did not contain a manifestPath."
}
$absManifest = Resolve-RunbookRepoPath -Path $manifestPath

$manifestCheck = Test-RunbookManifest -ManifestPath $absManifest
if (-not $manifestCheck.Ok) {
    Exit-Failure 'internal' $manifestCheck.Diagnostic
}

# Step 9: Build outcome
$samplesPath       = $null
$sampleCount       = 0
$frameRangeCovered = $null

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
    $samplesRef = $manifest.artifactRefs | Where-Object { $_.kind -in @('behavior-samples', 'behavior-trace') } | Select-Object -First 1
    if ($null -eq $samplesRef) {
        Exit-Failure 'internal' "manifest did not contain a 'behavior-samples' or 'behavior-trace' artifact reference"
    }
    $samplesPath = Resolve-RunbookRepoPath -Path $samplesRef.path
    if (-not (Test-Path -LiteralPath $samplesPath)) {
        Exit-Failure 'internal' "behavior samples artifact missing on disk at '$samplesPath'"
    }
    $rows = Get-Content -LiteralPath $samplesPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue } |
            Where-Object { $null -ne $_ }
    $sampleCount = @($rows).Count
    if ($sampleCount -gt 0) {
        $frames = @($rows | ForEach-Object { [int]$_.frame } | Sort-Object)
        $frameRangeCovered = @{ first = $frames[0]; last = $frames[-1] }
    }
}
catch {
    Exit-Failure 'internal' "Failed to assemble behavior-watch outcome from manifest: $($_.Exception.Message)"
}

# Steps 10-12
$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @() -Outcome @{
        samplesPath       = $samplesPath
        sampleCount       = $sampleCount
        frameRangeCovered = $frameRangeCovered
    }
$envelope
Write-RunbookStderrSummary "OK: $sampleCount samples captured; manifest at $absManifest"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
