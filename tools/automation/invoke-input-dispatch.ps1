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
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot integration-testing/pong `
        -RequestFixturePath tools/tests/fixtures/runbook/input-dispatch/press-enter.json

    Dispatches the Enter key once and emits a JSON envelope with
    outcome.dispatchedEventCount and outcome.outcomesPath.

.EXAMPLE
    pwsh ./tools/automation/invoke-input-dispatch.ps1 `
        -ProjectRoot integration-testing/pong `
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

    [int]$PollIntervalMilliseconds = 250
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

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics @($Message) -Outcome @{
            outcomesPath        = $null
            dispatchedEventCount = 0
            firstFailureSummary = $null
        }
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
    -TimeoutSeconds $TimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

# Check for harness-reported failures
if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace($rr.failureKind)) {
    $fk = [string]$rr.failureKind
    Exit-Failure $fk "Run failed with failureKind='$fk'. Check the manifest for details."
}

# Step 8: Read manifest
$manifestPath = [string]$rr.manifestPath
if ([string]::IsNullOrWhiteSpace($manifestPath)) {
    Exit-Failure 'internal' "run-result.json did not contain a manifestPath."
}
$absManifest = Resolve-RunbookRepoPath -Path $manifestPath

# Step 9: Build outcome
$outcomesPath        = $null
$dispatchedCount     = 0
$firstFailureSummary = $null

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
    $outcomeRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'input-dispatch-outcomes' } | Select-Object -First 1
    if ($null -ne $outcomeRef) {
        $outcomesPath = Resolve-RunbookRepoPath -Path $outcomeRef.path
        if (Test-Path -LiteralPath $outcomesPath) {
            $lines = Get-Content -LiteralPath $outcomesPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $dispatchedCount = @($lines).Count
            foreach ($line in $lines) {
                $row = $line | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
                if ($null -ne $row -and $row.outcome -ne 'success') {
                    $firstFailureSummary = [string]$row.message
                    break
                }
            }
        }
    }
}
catch {
    # Non-fatal: outcome assembly failed; still emit envelope
}

# Steps 10-12: Emit envelope and exit
$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @() -Outcome @{
        outcomesPath        = $outcomesPath
        dispatchedEventCount = $dispatchedCount
        firstFailureSummary = $firstFailureSummary
    }
$envelope
exit 0
