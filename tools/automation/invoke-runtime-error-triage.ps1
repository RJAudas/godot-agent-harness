<#
.SYNOPSIS
    Run a Godot project and surface any GDScript runtime errors in a single invocation.

.DESCRIPTION
    invoke-runtime-error-triage.ps1 wraps the full harness loop
    (capability check → request delivery → poll → manifest read) into a single
    invocation. It delivers a run-request fixture to the editor broker, waits for
    completion, and emits a stable stdout JSON envelope.

    On runtime error the envelope carries failureKind = "runtime" and
    outcome.latestErrorSummary with the most recent error's file, line, and message.
    On a healthy run the envelope carries status = "success".

    The script requires an editor running against the specified ProjectRoot.

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox.

.PARAMETER RequestFixturePath
    Repo-relative or absolute path to a tracked fixture under
    tools/tests/fixtures/runbook/runtime-error-triage/. Mutually exclusive with
    -RequestJson.

.PARAMETER RequestJson
    Inline JSON string. Mutually exclusive with -RequestFixturePath.

.PARAMETER IncludeFullStack
    When present, the outcome.latestErrorSummary message field contains the full
    stack trace instead of just the first line.

.PARAMETER TimeoutSeconds
    End-to-end wall-clock budget. Default: 60.

.PARAMETER MaxCapabilityAgeSeconds
    Maximum allowed age of capability.json. Default: 300.

.PARAMETER PollIntervalMilliseconds
    Polling interval for run-result.json. Default: 250.

.EXAMPLE
    # First, scaffold a sandbox to run (idempotent; -Force re-creates):
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then triage:
    pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json

    Runs the project with pauseOnError enabled and emits a JSON envelope.
    On runtime error: outcome.latestErrorSummary contains the offending file, line,
    and message. outcome.terminationReason reports how the run ended.

.EXAMPLE
    pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors-no-early-stop.json `
        -IncludeFullStack

    Same as above, with full stack trace in outcome.latestErrorSummary.message.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$RequestFixturePath,

    [string]$RequestJson,

    [switch]$IncludeFullStack,

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
$workflowSlug = 'runtime-error-triage'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $diags = @($_lifecycleDiags) + @($Message)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics $diags -Outcome @{
            runtimeErrorRecordsPath = $null
            latestErrorSummary      = $null
            terminationReason       = 'unknown'
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

# Step 5: Materialize payload
# F1: when the request's targetScene is missing or points at a scene that
# doesn't exist in the project, fall back to project.godot's main_scene so
# every project is drivable without a per-sandbox fixture variant.
$payloadJson = if ($hasFixture) {
    Get-Content -LiteralPath (Resolve-RunbookRepoPath -Path $RequestFixturePath) -Raw
} else {
    $RequestJson
}

try {
    $payloadObj = $payloadJson | ConvertFrom-Json -Depth 20 -AsHashtable
}
catch {
    Exit-Failure 'request-invalid' "Could not parse request payload as JSON: $($_.Exception.Message)"
}

$declaredScene = if ($payloadObj.ContainsKey('targetScene')) { [string]$payloadObj['targetScene'] } else { '' }
$declaredSceneFile = if ($declaredScene.StartsWith('res://')) {
    Join-Path $resolvedRoot $declaredScene.Substring('res://'.Length)
} else { '' }
$declaredSceneExists = (-not [string]::IsNullOrWhiteSpace($declaredSceneFile)) -and (Test-Path -LiteralPath $declaredSceneFile)

if ([string]::IsNullOrWhiteSpace($declaredScene) -or -not $declaredSceneExists) {
    $mainScene = Get-ProjectMainScene -ProjectRoot $resolvedRoot
    if (-not [string]::IsNullOrWhiteSpace($mainScene)) {
        $reason = if ([string]::IsNullOrWhiteSpace($declaredScene)) {
            "request omitted targetScene; defaulting to project.godot run/main_scene='$mainScene'"
        } else {
            "request targetScene '$declaredScene' does not exist in '$resolvedRoot'; defaulting to project.godot run/main_scene='$mainScene'"
        }
        $_lifecycleDiags.Add($reason)
        $payloadObj['targetScene'] = $mainScene
    }
}

$payloadArgs = @{
    RequestId  = $requestId
    ProjectRoot = $resolvedRoot
    InlineJson = ($payloadObj | ConvertTo-Json -Depth 20)
}

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

# B16: when run-result already classified the failure as validation, surface the
# validationResult.notes immediately. Without this pre-empt, Test-RunbookManifest
# below fires a misleading "manifest not found at <path>" when the runtime wrote
# the manifest under a different runId (e.g. inspection-run-config override),
# masking the real cause that validationResult.notes already explains.
if ($rr.finalStatus -eq 'failed' -and ([string]$rr.failureKind) -eq 'validation') {
    $vNotes = Get-RunResultValidationDiagnostics -RunResult $rr
    if ($vNotes.Count -gt 0) {
        $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind 'validation' -FallbackKind 'internal'
        $diags = @($_lifecycleDiags) + @($vNotes)
        Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{}
        Write-RunbookStderrSummary "FAIL: $envelopeKind; $($vNotes -join ' | ')"
        exit 1
    }
}

# Step 8: Read manifest
$manifestPath = [string]$rr.manifestPath
$absManifest  = $null
if (-not [string]::IsNullOrWhiteSpace($manifestPath)) {
    $absManifest = Resolve-RunbookEvidencePath -Path $manifestPath -ProjectRoot $resolvedRoot
}

# Validate manifest when present.
if (-not [string]::IsNullOrWhiteSpace($absManifest)) {
    $manifestCheck = Test-RunbookManifest -ManifestPath $absManifest -ProjectRoot $resolvedRoot
    if (-not $manifestCheck.Ok) {
        # B7/B9: propagate run-result.failureKind instead of collapsing to internal.
        $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
        Exit-Failure $kind $manifestCheck.Diagnostic
    }
}

# Step 9: Build outcome
$runtimeErrorRecordsPath = $null
$latestErrorSummary      = $null
$terminationReason       = 'completed'

if (-not [string]::IsNullOrWhiteSpace($absManifest) -and (Test-Path -LiteralPath $absManifest)) {
    try {
        $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20

        # Termination reason from runtimeErrorReporting block
        if ($null -ne $manifest.runtimeErrorReporting -and -not [string]::IsNullOrWhiteSpace($manifest.runtimeErrorReporting.termination)) {
            $terminationReason = [string]$manifest.runtimeErrorReporting.termination
        }

        # Runtime error records
        $errRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'runtime-error-records' } | Select-Object -First 1
        if ($null -ne $errRef) {
            $runtimeErrorRecordsPath = Resolve-RunbookEvidencePath -Path $errRef.path -ProjectRoot $resolvedRoot
            if (Test-Path -LiteralPath $runtimeErrorRecordsPath) {
                # Get last (most recent) error record
                $lines = Get-Content -LiteralPath $runtimeErrorRecordsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $lastLine = $lines | Select-Object -Last 1
                if (-not [string]::IsNullOrWhiteSpace($lastLine)) {
                    $d = $lastLine | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
                    if ($null -ne $d) {
                        $msgText = if ($IncludeFullStack -and -not [string]::IsNullOrWhiteSpace($d.stackTrace)) {
                            "$($d.message)`n$($d.stackTrace)"
                        }
                        else { [string]$d.message }
                        $latestErrorSummary = @{
                            file    = [string]$d.scriptPath
                            line    = [int]$d.line
                            message = $msgText
                        }
                    }
                }
            }
        }
    }
    catch {
        Exit-Failure 'internal' "Failed to assemble runtime-error outcome from manifest: $($_.Exception.Message)"
    }
}

# Pass through any harness-reported failure (runtime, build, timeout, internal, ...).
# Only the runtime case carries enriched outcome.latestErrorSummary; all other
# kinds still surface failureKind on the envelope so callers can route accordingly.
if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace([string]$rr.failureKind)) {
    $fk = [string]$rr.failureKind
    if ($fk -eq 'runtime') {
        $msg = if ($null -ne $latestErrorSummary) { "Runtime error at $($latestErrorSummary.file):$($latestErrorSummary.line): $($latestErrorSummary.message)" } else { 'Runtime error. Check the manifest for details.' }
        $diags = @($_lifecycleDiags) + @($msg)
        Write-RunbookEnvelope -Status 'failure' -FailureKind 'runtime' -ManifestPath $absManifest `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
                runtimeErrorRecordsPath = $runtimeErrorRecordsPath
                latestErrorSummary      = $latestErrorSummary
                terminationReason       = $terminationReason
            }
        Write-RunbookStderrSummary "FAIL: runtime; $msg"
        exit 1
    }
    $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind $fk -FallbackKind 'internal'
    $msg = "Run failed with failureKind='$fk' (runtime-error triage handles diagnostics for failureKind=runtime only)."
    $diags = @($_lifecycleDiags) + @($msg)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind -ManifestPath $absManifest `
        -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
            runtimeErrorRecordsPath = $runtimeErrorRecordsPath
            latestErrorSummary      = $latestErrorSummary
            terminationReason       = $terminationReason
        }
    Write-RunbookStderrSummary "FAIL: $envelopeKind; $msg"
    exit 1
}

# Success path requires non-null manifestPath per envelope schema.
if ([string]::IsNullOrWhiteSpace($absManifest)) {
    $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
    Exit-Failure $kind "run-result.json did not contain a manifestPath on a successful run."
}

# Steps 10-12
$envelope = Write-RunbookEnvelope -Status 'success' -ManifestPath $absManifest `
    -RunId $runId -RequestId $requestId -Diagnostics @($_lifecycleDiags) -Outcome @{
        runtimeErrorRecordsPath = $runtimeErrorRecordsPath
        latestErrorSummary      = $null
        terminationReason       = $terminationReason
    }
$envelope
Write-RunbookStderrSummary "OK: no runtime errors; manifest at $absManifest"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
