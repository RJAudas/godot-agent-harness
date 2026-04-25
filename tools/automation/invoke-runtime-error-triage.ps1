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
    pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
        -ProjectRoot integration-testing/pong `
        -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json

    Runs the project with pauseOnError enabled and emits a JSON envelope.
    On runtime error: outcome.latestErrorSummary contains the offending file, line,
    and message. outcome.terminationReason reports how the run ended.

.EXAMPLE
    pwsh ./tools/automation/invoke-runtime-error-triage.ps1 `
        -ProjectRoot integration-testing/pong `
        -RequestFixturePath tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json `
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

    [int]$PollIntervalMilliseconds = 250
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
    -TimeoutSeconds $TimeoutSeconds `
    -PollIntervalMilliseconds $PollIntervalMilliseconds

if (-not $runResult.Ok) {
    Exit-Failure $runResult.FailureKind $runResult.Diagnostic
}

$rr    = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

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
        Exit-Failure 'internal' $manifestCheck.Diagnostic
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
    $msg = "Run failed with failureKind='$fk' (runtime-error triage handles diagnostics for failureKind=runtime only)."
    $diags = @($_lifecycleDiags) + @($msg)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $fk -ManifestPath $absManifest `
        -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
            runtimeErrorRecordsPath = $runtimeErrorRecordsPath
            latestErrorSummary      = $latestErrorSummary
            terminationReason       = $terminationReason
        }
    Write-RunbookStderrSummary "FAIL: $fk; $msg"
    exit 1
}

# Success path requires non-null manifestPath per envelope schema.
if ([string]::IsNullOrWhiteSpace($absManifest)) {
    Exit-Failure 'internal' "run-result.json did not contain a manifestPath on a successful run."
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
