[CmdletBinding()]
param(
    [string]$ManifestPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json',

    # Base directory for resolving relative artifact paths in the manifest.
    # When set (e.g. by Test-RunbookManifest from a runbook orchestrator), artifact
    # paths are resolved against this directory; otherwise they fall back to the
    # repo root (legacy behaviour for fixture-bundle validation).
    [string]$ProjectRoot,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'artifact-registry.ps1')

function Get-RepoRoot {
    return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path (Get-RepoRoot) $Path)).Path
}

function Convert-ToArtifactPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory
    )

    $base = [System.IO.Path]::GetFullPath($BaseDirectory)
    $baseWithSeparator = $base.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    else {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $base $Path))
    }

    # Containment check. Use case-insensitive comparison on Windows (NTFS is
    # case-insensitive by default) and case-sensitive elsewhere — otherwise
    # a path like 'EVIDENCE/...' could be classified as inside 'evidence/...'
    # on a case-sensitive Linux/macOS volume even though the OS would treat
    # them as distinct directories and the artifact would never be found.
    $comparison = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    if ($fullPath -ne $base -and -not $fullPath.StartsWith($baseWithSeparator, $comparison)) {
        throw "Artifact path '$Path' resolves outside the base directory '$base'."
    }

    return $fullPath
}

$resolvedManifestPath = Resolve-RepoPath -Path $ManifestPath
$schemaResult = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedManifestPath -SchemaPath 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json' -PassThru -AllowInvalid
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -Depth 100
$missingArtifactPaths = New-Object System.Collections.Generic.List[string]
$unsupportedArtifactKinds = New-Object System.Collections.Generic.List[string]
$supportedArtifactKinds = Get-EvidenceArtifactKinds

# Resolve artifact paths against -ProjectRoot when provided (the runbook orchestrator
# path; manifest paths are project-relative because the runtime writes under
# res://evidence/automation/...). Fall back to repo root for legacy callers that
# validate fixture-bundled manifests committed under tools/evals/fixtures/.
$artifactBase = if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    if ([System.IO.Path]::IsPathRooted($ProjectRoot)) { $ProjectRoot }
    else { (Resolve-Path -LiteralPath (Join-Path (Get-RepoRoot) $ProjectRoot)).Path }
} else {
    Get-RepoRoot
}

foreach ($artifactRef in $manifest.artifactRefs) {
    if ($artifactRef.kind -notin $supportedArtifactKinds) {
        [void]$unsupportedArtifactKinds.Add([string]$artifactRef.kind)
    }

    try {
        $artifactPath = Convert-ToArtifactPath -Path $artifactRef.path -BaseDirectory $artifactBase
    }
    catch {
        [void]$missingArtifactPaths.Add($artifactRef.path)
        continue
    }

    if (-not (Test-Path -LiteralPath $artifactPath)) {
        [void]$missingArtifactPaths.Add($artifactRef.path)
    }
}

$bundleValid = [bool]$schemaResult.valid -and $missingArtifactPaths.Count -eq 0 -and $unsupportedArtifactKinds.Count -eq 0

# ---------------------------------------------------------------------------
# T028: runtimeErrorReporting block invariants
# ---------------------------------------------------------------------------
$runtimeReportingViolations = New-Object System.Collections.Generic.List[string]
$validTerminations  = @('completed', 'stopped_by_agent', 'stopped_by_default_on_pause_timeout', 'crashed', 'killed_by_harness')
$validPauseOnErrorModes = @('active', 'unavailable_degraded_capture_only')

if ($null -ne ($manifest | Get-Member -Name 'runtimeErrorReporting' -ErrorAction SilentlyContinue) -and
    $null -ne $manifest.runtimeErrorReporting) {
    $rer = $manifest.runtimeErrorReporting

    # Required: termination must be a valid enum value
    $hasTermination = $null -ne ($rer | Get-Member -Name 'termination' -ErrorAction SilentlyContinue)
    $termination = if ($hasTermination) { [string]$rer.termination } else { '' }
    if ([string]::IsNullOrEmpty($termination)) {
        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.termination is missing or empty")
    } elseif ($termination -notin $validTerminations) {
        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.termination '$termination' is not a recognized enum value (expected one of: $($validTerminations -join ', '))")
    }

    # Required: pauseOnErrorMode must be a valid enum value
    $hasPauseMode = $null -ne ($rer | Get-Member -Name 'pauseOnErrorMode' -ErrorAction SilentlyContinue)
    $pauseMode = if ($hasPauseMode) { [string]$rer.pauseOnErrorMode } else { '' }
    if ([string]::IsNullOrEmpty($pauseMode)) {
        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.pauseOnErrorMode is missing or empty")
    } elseif ($pauseMode -notin $validPauseOnErrorModes) {
        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.pauseOnErrorMode '$pauseMode' is not a recognized enum value (expected one of: $($validPauseOnErrorModes -join ', '))")
    }

    # Conditional: lastErrorAnchor REQUIRED when termination = crashed
    $hasLastErrorAnchor = $null -ne ($rer | Get-Member -Name 'lastErrorAnchor' -ErrorAction SilentlyContinue)
    if ($termination -eq 'crashed') {
        if (-not $hasLastErrorAnchor -or $null -eq $rer.lastErrorAnchor) {
            [void]$runtimeReportingViolations.Add("runtimeErrorReporting.lastErrorAnchor is required when termination = crashed but is absent")
        } else {
            $anchor = $rer.lastErrorAnchor
            # Accept { lastError: "none" } marker, or a full anchor shape
            $hasLastErrorProp = $null -ne ($anchor | Get-Member -Name 'lastError' -ErrorAction SilentlyContinue)
            $isNoneMarker = $hasLastErrorProp -and [string]$anchor.lastError -eq 'none'
            if (-not $isNoneMarker) {
                foreach ($required in @('scriptPath', 'line', 'severity', 'message')) {
                    $hasProp = $null -ne ($anchor | Get-Member -Name $required -ErrorAction SilentlyContinue)
                    if (-not $hasProp) {
                        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.lastErrorAnchor.$required is required for a crash anchor but is missing or empty")
                        continue
                    }
                    $val = $anchor.$required
                    if ($null -eq $val -or ($val -is [string] -and [string]::IsNullOrEmpty($val))) {
                        [void]$runtimeReportingViolations.Add("runtimeErrorReporting.lastErrorAnchor.$required is required for a crash anchor but is missing or empty")
                    }
                }
            }
        }
    } elseif (-not [string]::IsNullOrEmpty($termination)) {
        # lastErrorAnchor MUST NOT be present for non-crash terminations
        if ($hasLastErrorAnchor -and $null -ne $rer.lastErrorAnchor) {
            [void]$runtimeReportingViolations.Add("runtimeErrorReporting.lastErrorAnchor must not be present when termination = '$termination' (only allowed for crashed)")
        }
    }

    if ($runtimeReportingViolations.Count -gt 0) {
        $bundleValid = $false
    }
}

$result = [ordered]@{
    manifestPath = $resolvedManifestPath
    schemaValid = [bool]$schemaResult.valid
    missingArtifactPaths = $missingArtifactPaths
    unsupportedArtifactKinds = $unsupportedArtifactKinds
    runtimeReportingViolations = $runtimeReportingViolations
    bundleValid = $bundleValid
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}

if (-not $bundleValid) {
    exit 1
}