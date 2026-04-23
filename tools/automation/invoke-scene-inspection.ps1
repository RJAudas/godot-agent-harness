<#
.SYNOPSIS
    Capture the running Godot game's scene tree with a single invocation.

.DESCRIPTION
    invoke-scene-inspection.ps1 synthesizes a minimal startup-capture request
    internally (capturePolicy.startup = true) and delivers it to the editor
    broker. No request payload parameters are required.

    The script wraps the full harness loop (capability check → request delivery
    → poll → manifest read) and emits a stable stdout JSON envelope containing
    the path to the captured scene-tree.json and the node count.

    The script requires an editor running against the specified ProjectRoot.
    When the editor is not running or the capability is stale, it exits non-zero
    with failureKind = "editor-not-running".

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox that the
    Godot editor is running against.

.PARAMETER TimeoutSeconds
    End-to-end wall-clock budget in seconds. Default: 60.

.PARAMETER MaxCapabilityAgeSeconds
    Maximum allowed age of capability.json in seconds before the editor is
    considered not running. Default: 300.

.PARAMETER PollIntervalMilliseconds
    How often to poll run-result.json while waiting for the request to complete.
    Default: 250.

.EXAMPLE
    pwsh ./tools/automation/invoke-scene-inspection.ps1 `
        -ProjectRoot integration-testing/pong

    Captures the startup scene tree and emits a JSON envelope with
    outcome.sceneTreePath and outcome.nodeCount.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [int]$TimeoutSeconds = 60,

    [int]$MaxCapabilityAgeSeconds = 300,

    [int]$PollIntervalMilliseconds = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug = 'scene-inspection'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics @($Message) -Outcome @{ sceneTreePath = $null; nodeCount = 0 }
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

# Step 4: Capability check
$cap = Test-RunbookCapability -ProjectRoot $resolvedRoot -MaxAgeSeconds $MaxCapabilityAgeSeconds
if (-not $cap.Ok) {
    Exit-Failure $cap.FailureKind $cap.Diagnostic
}

# Step 5: Synthesize payload internally
$internalPayload = @{
    requestId      = $requestId
    scenarioId     = "runbook-scene-inspection-$requestId"
    runId          = $requestId
    targetScene    = 'res://scenes/main.tscn'
    outputDirectory = "res://evidence/automation/$requestId"
    artifactRoot   = "tools/tests/fixtures/runbook/inspect-scene-tree/evidence/$requestId"
    capturePolicy  = @{ startup = $true; manual = $false; failure = $false }
    stopPolicy     = @{ stopAfterValidation = $true }
    requestedBy    = 'runbook-scene-inspection'
    createdAt      = (Get-Date -Format 'o')
}

$requestsDir = Join-Path $resolvedRoot 'harness/automation/requests'
if (-not (Test-Path -LiteralPath $requestsDir)) {
    New-Item -ItemType Directory -Path $requestsDir -Force | Out-Null
}
$tempPath = Join-Path $requestsDir "$requestId.json"
$internalPayload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempPath -Encoding utf8

# Step 6-7: Request + poll
$runResult = Invoke-RunbookRequest `
    -ProjectRoot $resolvedRoot `
    -RequestPath $tempPath `
    -ExpectedRequestId $requestId `
    -TimeoutSeconds $TimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr = $runResult.RunResult
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
$sceneTreePath = $null
$nodeCount     = 0

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
    $treeRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'scene-tree' } | Select-Object -First 1
    if ($null -eq $treeRef) {
        Exit-Failure 'internal' "manifest did not contain a 'scene-tree' artifact reference"
    }
    $sceneTreePath = Resolve-RunbookRepoPath -Path $treeRef.path
    if (-not (Test-Path -LiteralPath $sceneTreePath)) {
        Exit-Failure 'internal' "scene-tree artifact missing on disk at '$sceneTreePath'"
    }
    $tree = Get-Content -LiteralPath $sceneTreePath -Raw | ConvertFrom-Json -Depth 30
    function Count-Nodes { param($n); $c = 1; foreach ($child in @($n.children)) { $c += Count-Nodes $child }; $c }
    $nodeCount = Count-Nodes $tree.root
}
catch {
    Exit-Failure 'internal' "Failed to assemble scene-tree outcome: $($_.Exception.Message)"
}

# Steps 10-12
$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @() -Outcome @{
        sceneTreePath = $sceneTreePath
        nodeCount     = $nodeCount
    }
$envelope
Write-RunbookStderrSummary "OK: $nodeCount nodes captured; manifest at $absManifest"
exit 0
