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
    # First, scaffold a sandbox to inspect (idempotent; -Force re-creates):
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then capture:
    pwsh ./tools/automation/invoke-scene-inspection.ps1 `
        -ProjectRoot ./integration-testing/probe

    Captures the startup scene tree and emits a JSON envelope with
    outcome.sceneTreePath and outcome.nodeCount. To inspect a scene other
    than the project's main_scene, see -TargetScene above.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$TargetScene,

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

# Optional: auto-launch the editor if the caller asked for -EnsureEditor.
if ($EnsureEditor) {
    $launcher = Join-Path $PSScriptRoot 'invoke-launch-editor.ps1'
    # Capture stdout only -- the helper writes a single-line stderr summary that
    # would corrupt the JSON envelope if 2>&1-merged. Thread our own
    # -MaxCapabilityAgeSeconds through so a stricter caller setting is not
    # silently relaxed by the launcher's default (300s).
    $launchOut = & (Get-RunbookPwshPath) -NoProfile -File $launcher `
        -ProjectRoot $resolvedRoot -MaxCapabilityAgeSeconds $MaxCapabilityAgeSeconds
    try {
        $launchEnv = ($launchOut -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20
    }
    catch {
        Exit-Failure 'editor-not-running' "Auto-launch produced non-JSON output: $($launchOut -join '; ')"
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

# Step 5: Synthesize the minimal startup-capture payload and route it through
# the shared Resolve-RunbookPayload helper, like every other runtime invoker.
# The helper handles validate-then-rename (C1), forces artifactRoot='' (C2),
# defaults expectationFiles, and writes to the canonical path the broker
# watches. Scene-inspection takes no caller-supplied fixture, so we synthesize
# the fixed payload as inline JSON.
$inlinePayload = [ordered]@{
    requestId        = $requestId   # Resolve-RunbookPayload re-stamps this; harmless duplicate.
    scenarioId       = "runbook-scene-inspection-$requestId"
    runId            = $requestId
    targetScene      = $TargetScene
    outputDirectory  = "res://evidence/automation/$requestId"
    expectationFiles = @()
    capturePolicy    = [ordered]@{ startup = $true; manual = $false; failure = $false }
    stopPolicy       = [ordered]@{ stopAfterValidation = $true }
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
$absManifest = Resolve-RunbookEvidencePath -Path $manifestPath -ProjectRoot $resolvedRoot

$manifestCheck = Test-RunbookManifest -ManifestPath $absManifest -ProjectRoot $resolvedRoot
if (-not $manifestCheck.Ok) {
    Exit-Failure 'internal' $manifestCheck.Diagnostic
}

# Step 9: Build outcome
$sceneTreePath = $null
$nodeCount     = 0

try {
    $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
    # The runtime emits scenegraph-snapshot (flat nodes array with node_count
    # field), not a tree-shaped 'scene-tree' artifact. Earlier code expected
    # the latter and recursed over $tree.root.children.
    $treeRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'scenegraph-snapshot' } | Select-Object -First 1
    if ($null -eq $treeRef) {
        Exit-Failure 'internal' "manifest did not contain a 'scenegraph-snapshot' artifact reference"
    }
    $sceneTreePath = Resolve-RunbookEvidencePath -Path $treeRef.path -ProjectRoot $resolvedRoot
    if (-not (Test-Path -LiteralPath $sceneTreePath)) {
        Exit-Failure 'internal' "scenegraph-snapshot artifact missing on disk at '$sceneTreePath'"
    }
    $snapshot = Get-Content -LiteralPath $sceneTreePath -Raw | ConvertFrom-Json -Depth 30
    if ($null -ne ($snapshot | Get-Member -Name 'node_count' -ErrorAction SilentlyContinue)) {
        $nodeCount = [int]$snapshot.node_count
    }
    elseif ($null -ne ($snapshot | Get-Member -Name 'nodes' -ErrorAction SilentlyContinue)) {
        $nodeCount = @($snapshot.nodes).Count
    }
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
