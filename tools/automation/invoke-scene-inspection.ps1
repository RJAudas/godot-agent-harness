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

.PARAMETER TargetScene
    The res:// path to the scene to launch and inspect. When omitted, the
    script reads `run/main_scene` from the target project's `project.godot`
    and resolves UIDs via the project's `.tscn` files. Override only when
    you need to target a scene other than the project's main scene.

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

.EXAMPLE
    pwsh ./tools/automation/invoke-scene-inspection.ps1 `
        -ProjectRoot D:/gameDev/pong `
        -TargetScene res://main.tscn

    Same as above, but for a project whose main scene is at the repo root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$TargetScene,

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

# Resolve the target scene. Priority: (1) -TargetScene passed by caller,
# (2) run/main_scene from the target project's project.godot (with UID
# resolution), (3) an obviously-invalid placeholder path so the broker
# returns target_scene_missing loudly instead of silently running
# whatever happens to live at a default guess.
if (-not $PSBoundParameters.ContainsKey('TargetScene') -or [string]::IsNullOrWhiteSpace($TargetScene)) {
    $projectFilePath = Join-Path $resolvedRoot 'project.godot'
    $resolvedFromProject = $null
    if (Test-Path -LiteralPath $projectFilePath) {
        $projectContent = Get-Content -LiteralPath $projectFilePath -Raw
        if ($projectContent -match 'run/main_scene\s*=\s*"([^"]+)"') {
            $mainScene = $Matches[1]
            if ($mainScene -match '^res://') {
                $resolvedFromProject = $mainScene
            }
            elseif ($mainScene -match '^uid://') {
                # Resolve UID by scanning .tscn files for a matching uid="..." in the header line.
                $scenes = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Filter '*.tscn' -File -ErrorAction SilentlyContinue
                foreach ($scene in $scenes) {
                    $firstLine = Get-Content -LiteralPath $scene.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                    if ($firstLine -and $firstLine -match ([regex]::Escape($mainScene))) {
                        $relative = $scene.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
                        $resolvedFromProject = "res://$relative"
                        break
                    }
                }
            }
        }
    }
    $TargetScene = if ($resolvedFromProject) { $resolvedFromProject } else { 'res://__main_scene_unresolved__.tscn' }
}

$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $diags = @($_lifecycleDiags) + @($Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics $diags -Outcome @{ sceneTreePath = $null; nodeCount = 0 }
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
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

# Step 5: Synthesize payload internally
# NOTE: expectationFiles is required by the schema even when empty.
# NOTE: the broker watches the canonical run-request.json path, not a per-request filename.
$internalPayload = @{
    requestId        = $requestId
    scenarioId       = "runbook-scene-inspection-$requestId"
    runId            = $requestId
    targetScene      = $TargetScene
    outputDirectory  = "res://evidence/automation/$requestId"
    artifactRoot     = "tools/tests/fixtures/runbook/inspect-scene-tree/evidence/$requestId"
    expectationFiles = @()
    capturePolicy    = @{ startup = $true; manual = $false; failure = $false }
    stopPolicy       = @{ stopAfterValidation = $true }
    requestedBy      = 'runbook-scene-inspection'
    createdAt        = (Get-Date -Format 'o')
}

$requestsDir = Join-Path $resolvedRoot 'harness/automation/requests'
if (-not (Test-Path -LiteralPath $requestsDir)) {
    New-Item -ItemType Directory -Path $requestsDir -Force | Out-Null
}
# Write to the canonical path the editor broker watches (run-request.json),
# not a per-request filename that the broker would never pick up.
$canonicalPath = Join-Path $requestsDir 'run-request.json'

# C1: validate-then-rename. The editor broker consumes $canonicalPath the
# instant FileSystemWatcher fires; validating after the write means the
# validator's Resolve-Path crashes when the broker has already moved the
# file. Write to <canonical>.tmp first, validate the temp path (which the
# broker is not watching), then atomic-rename into place. Mirrors the
# pattern in Resolve-RunbookPayload. (Pass 2 H3 will fold this script's
# inline write into Resolve-RunbookPayload via -InlineJson.)
$tmpPath = "$canonicalPath.tmp"
$internalPayload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpPath -Encoding utf8

$schemaPath = 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
$schemaResolved = Resolve-RunbookRepoPath -Path $schemaPath
$validation = & pwsh -NoProfile -File (Resolve-RunbookRepoPath -Path 'tools/validate-json.ps1') `
    -InputPath $tmpPath -SchemaPath $schemaResolved -AllowInvalid 2>&1
$validationExit = $LASTEXITCODE

try {
    if ($validationExit -ne 0) {
        $captured = ($validation | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        $captured = [regex]::Replace($captured, "`e\[[0-?]*[ -/]*[@-~]", '')
        Exit-Failure 'request-invalid' "Schema validator could not run (exit $validationExit): $captured"
    }
    $captured = ($validation | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    $captured = [regex]::Replace($captured, "`e\[[0-?]*[ -/]*[@-~]", '')
    $parsed = $captured | ConvertFrom-Json -Depth 20
    if (-not $parsed.valid) {
        $errDetail = if ($null -ne $parsed.PSObject.Properties['error']) { $parsed.error } else { 'schema validation failed' }
        Exit-Failure 'request-invalid' "Run request does not satisfy schema '$schemaPath': $errDetail"
    }
    Move-Item -LiteralPath $tmpPath -Destination $canonicalPath -Force
}
catch {
    Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    if ($_.Exception.Message -match '^Run request does not satisfy|^Schema validator could not run') {
        # Already routed through Exit-Failure; the catch is just for cleanup.
        throw
    }
    Exit-Failure 'request-invalid' "Failed to validate run-request.json: $($_.Exception.Message)"
}

# Step 6-7: Request + poll
$runResult = Invoke-RunbookRequest `
    -ProjectRoot $resolvedRoot `
    -RequestPath $canonicalPath `
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

if ($rr.finalStatus -eq 'blocked') {
    $reasons = if ($null -ne $rr.blockedReasons) { ($rr.blockedReasons | ForEach-Object { [string]$_ }) -join ', ' } else { 'unknown' }
    Exit-Failure 'runtime' "Run was blocked before evidence was captured. blockedReasons: $reasons. Check that targetScene '$TargetScene' exists in the project."
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
    -RunId $runId -RequestId $requestId -Diagnostics @($_lifecycleDiags) -Outcome @{
        sceneTreePath = $sceneTreePath
        nodeCount     = $nodeCount
    }
$envelope
Write-RunbookStderrSummary "OK: $nodeCount nodes captured; manifest at $absManifest"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
