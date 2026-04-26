<#
.SYNOPSIS
    Run a Godot project and surface any build or compile errors in a single invocation.

.DESCRIPTION
    invoke-build-error-triage.ps1 wraps the full harness loop
    (capability check → request delivery → poll → manifest read) into a single
    invocation. It delivers a run-request fixture to the editor broker, waits for
    completion, and emits a stable stdout JSON envelope.

    On build failure the envelope carries failureKind = "build" and
    outcome.firstDiagnostic with the offending file and line.
    On a healthy run the envelope carries status = "success" with
    outcome.firstDiagnostic = null.

    The script requires an editor running against the specified ProjectRoot.

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox.

.PARAMETER RequestFixturePath
    Repo-relative or absolute path to a tracked fixture under
    tools/tests/fixtures/runbook/build-error-triage/. Mutually exclusive with
    -RequestJson.

.PARAMETER RequestJson
    Inline JSON string. Mutually exclusive with -RequestFixturePath.

.PARAMETER IncludeRawBuildOutput
    When present, populates outcome.rawBuildOutputPath with the path to the
    raw build output artifact (if available in the manifest).

.PARAMETER TimeoutSeconds
    End-to-end wall-clock budget. Default: 60.

.PARAMETER MaxCapabilityAgeSeconds
    Maximum allowed age of capability.json. Default: 300.

.PARAMETER PollIntervalMilliseconds
    Polling interval for run-result.json. Default: 250.

.EXAMPLE
    # First, scaffold a sandbox to triage (idempotent; -Force re-creates):
    pwsh ./tools/scaffold-sandbox.ps1 -Name probe

    # Then triage:
    pwsh ./tools/automation/invoke-build-error-triage.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json

    Runs the project and emits a JSON envelope. On build failure:
    outcome.firstDiagnostic contains the first error's file, line, and message.

.EXAMPLE
    pwsh ./tools/automation/invoke-build-error-triage.ps1 `
        -ProjectRoot ./integration-testing/probe `
        -RequestFixturePath ./tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json `
        -IncludeRawBuildOutput

    Same as above, also setting outcome.rawBuildOutputPath.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$RequestFixturePath,

    [string]$RequestJson,

    [switch]$IncludeRawBuildOutput,

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
$workflowSlug = 'build-error-triage'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

$_lifecycleDiags = [System.Collections.Generic.List[string]]::new()

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $diags = @($_lifecycleDiags) + @($Message)
    $rrPath = Join-Path $resolvedRoot 'harness/automation/results/run-result.json'
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics $diags -Outcome @{
            rawBuildOutputPath = $null
            firstDiagnostic    = $null
            runResultPath      = $rrPath
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

$rr = $runResult.RunResult
$runId = if (-not [string]::IsNullOrWhiteSpace($rr.runId)) { $rr.runId } else { $runId }

# B16: surface validationResult.notes for failureKind=validation before the
# downstream Test-RunbookManifest check, which otherwise reports a misleading
# "manifest not found" when the runtime wrote the manifest under a different
# runId than run-result references.
if ($rr.finalStatus -eq 'failed' -and ([string]$rr.failureKind) -eq 'validation') {
    $vNotes = Get-RunResultValidationDiagnostics -RunResult $rr
    if ($vNotes.Count -gt 0) {
        $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind 'validation' -FallbackKind 'internal'
        $diags = @($_lifecycleDiags) + @($vNotes)
        # Match Exit-Failure's outcome shape so consumers see the same keys on every failure path.
        $rrPath = Join-Path $resolvedRoot 'harness/automation/results/run-result.json'
        Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
                rawBuildOutputPath = $null
                firstDiagnostic    = $null
                runResultPath      = $rrPath
            }
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

# Validate the manifest when present (run-result-failed runs may not produce one).
if (-not [string]::IsNullOrWhiteSpace($absManifest)) {
    $manifestCheck = Test-RunbookManifest -ManifestPath $absManifest -ProjectRoot $resolvedRoot
    if (-not $manifestCheck.Ok) {
        # B7/B9: propagate run-result.failureKind instead of collapsing to internal.
        $kind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind ([string]$rr.failureKind) -FallbackKind 'internal'
        Exit-Failure $kind $manifestCheck.Diagnostic
    }
}

# Step 9: Build outcome
$rawBuildOutputPath = $null
$firstDiagnostic    = $null
$runResultPath      = Join-Path $resolvedRoot 'harness/automation/results/run-result.json'

if (-not [string]::IsNullOrWhiteSpace($absManifest) -and (Test-Path -LiteralPath $absManifest)) {
    try {
        $manifest = Get-Content -LiteralPath $absManifest -Raw | ConvertFrom-Json -Depth 20
        if ($IncludeRawBuildOutput) {
            $buildRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'build-output' } | Select-Object -First 1
            if ($null -ne $buildRef) {
                $rawBuildOutputPath = Resolve-RunbookEvidencePath -Path $buildRef.path -ProjectRoot $resolvedRoot
            }
        }
        $errRef = $manifest.artifactRefs | Where-Object { $_.kind -eq 'build-error-records' } | Select-Object -First 1
        if ($null -ne $errRef) {
            $errPath = Resolve-RunbookEvidencePath -Path $errRef.path -ProjectRoot $resolvedRoot
            if (Test-Path -LiteralPath $errPath) {
                $firstLine = Get-Content -LiteralPath $errPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
                if (-not [string]::IsNullOrWhiteSpace($firstLine)) {
                    $d = $firstLine | ConvertFrom-Json -Depth 5 -ErrorAction SilentlyContinue
                    $firstDiagnostic = ConvertTo-FirstBuildDiagnostic -Diagnostic $d
                }
            }
        }
    }
    catch {
        Exit-Failure 'internal' "Failed to assemble build-error outcome from manifest: $($_.Exception.Message)"
    }
}

# B4: when the manifest didn't yield a firstDiagnostic (e.g., the runtime
# wrote buildDiagnostics to run-result.json but no build-error-records
# artifact reached the manifest), fall back to run-result.buildDiagnostics[0].
if ($null -eq $firstDiagnostic -and `
    $null -ne ($rr | Get-Member -Name 'buildDiagnostics' -ErrorAction SilentlyContinue) -and `
    $null -ne $rr.buildDiagnostics -and @($rr.buildDiagnostics).Count -gt 0)
{
    $firstDiagnostic = ConvertTo-FirstBuildDiagnostic -Diagnostic @($rr.buildDiagnostics)[0]
}

# Pass through any harness-reported failure (build, runtime, timeout, internal, ...).
# Only the build case carries enriched outcome.firstDiagnostic; all other kinds
# still surface failureKind on the envelope so callers can route accordingly.
if ($rr.finalStatus -eq 'failed' -and -not [string]::IsNullOrWhiteSpace([string]$rr.failureKind)) {
    $fk = [string]$rr.failureKind
    if ($fk -eq 'build') {
        # B5: surface the run-result.json path on every build failure so an
        # agent that needs raw diagnostics can read it without filesystem search.
        $msg = if ($null -ne $firstDiagnostic) {
            "Build error at $($firstDiagnostic.file):$($firstDiagnostic.line): $($firstDiagnostic.message)"
        } else {
            "Build failed. See run-result at $runResultPath."
        }
        $diags = @($_lifecycleDiags) + @($msg)
        Write-RunbookEnvelope -Status 'failure' -FailureKind 'build' -ManifestPath $absManifest `
            -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
                rawBuildOutputPath = $rawBuildOutputPath
                firstDiagnostic    = $firstDiagnostic
                runResultPath      = $runResultPath
            }
        Write-RunbookStderrSummary "FAIL: build; $msg"
        exit 1
    }
    $envelopeKind = ConvertTo-EnvelopeFailureKind -RunResultFailureKind $fk -FallbackKind 'internal'
    $msg = "Run failed with failureKind='$fk' (build-error triage handles diagnostics for failureKind=build only). See $runResultPath."
    $diags = @($_lifecycleDiags) + @($msg)
    Write-RunbookEnvelope -Status 'failure' -FailureKind $envelopeKind -ManifestPath $absManifest `
        -RunId $runId -RequestId $requestId -Diagnostics $diags -Outcome @{
            rawBuildOutputPath = $rawBuildOutputPath
            firstDiagnostic    = $firstDiagnostic
            runResultPath      = $runResultPath
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
        rawBuildOutputPath = $rawBuildOutputPath
        firstDiagnostic    = $null
        runResultPath      = $runResultPath
    }
$envelope
Write-RunbookStderrSummary "OK: build clean; manifest at $absManifest"
exit 0

}
finally {
    Clear-RunbookInFlightMarker -ProjectRoot $resolvedRoot
}
