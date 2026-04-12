[CmdletBinding()]
param(
    [string]$RuntimeArtifactsPath = 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample',
    [string]$OutputPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.generated.json',
    [ValidateNotNullOrEmpty()]
    [string]$ScenarioId,
    [ValidateNotNullOrEmpty()]
    [string]$RunId,
    [ValidateSet('pass', 'fail', 'error', 'unknown')]
    [string]$Status,
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
        [string]$Path,

        [switch]$CreateParent
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolved = $Path
    }
    else {
        $resolved = Join-Path (Get-RepoRoot) $Path
    }

    if ($CreateParent) {
        $parent = Split-Path -Parent $resolved
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    return $resolved
}

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $repoRoot = Get-RepoRoot
    $fullPath = Convert-ToRepoChildPath -Path $Path
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath)
    return ($relativePath -replace '\\', '/')
}

function Convert-ToRepoChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $repoRoot = [System.IO.Path]::GetFullPath((Get-RepoRoot))
    $repoRootWithSeparator = $repoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    else {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
    }

    if ($fullPath -ne $repoRoot -and -not $fullPath.StartsWith($repoRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$Path' resolves outside the repository root."
    }

    return $fullPath
}

function Assert-NonEmptyValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must not be null or empty."
    }
}

function Assert-ValidStatus {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$Value
    )

    $allowedStatuses = @('pass', 'fail', 'error', 'unknown')
    if ($Value -notin $allowedStatuses) {
        throw "Status must be one of: $($allowedStatuses -join ', ')."
    }
}

$resolvedArtifactsPath = Convert-ToRepoChildPath -Path $RuntimeArtifactsPath
$resolvedOutputPath = Resolve-RepoPath -Path $OutputPath -CreateParent

$summaryPath = Join-Path $resolvedArtifactsPath 'summary.json'
if (-not (Test-Path -LiteralPath $summaryPath)) {
    throw "Runtime summary file not found at $summaryPath"
}

$summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 100
$invariantsPath = Join-Path $resolvedArtifactsPath 'invariants.json'
$invariants = @()

if (Test-Path -LiteralPath $invariantsPath) {
    $invariants = @(Get-Content -LiteralPath $invariantsPath -Raw | ConvertFrom-Json -Depth 100)
}

$artifactMap = Get-EvidenceArtifactDefinitions

$artifactRefs = foreach ($artifact in $artifactMap) {
    $artifactPath = Join-Path $resolvedArtifactsPath $artifact.file
    if (Test-Path -LiteralPath $artifactPath) {
        [ordered]@{
            kind = $artifact.kind
            path = Get-RepoRelativePath -Path $artifactPath
            mediaType = $artifact.mediaType
            description = $artifact.description
        }
    }
}

$resolvedScenarioId = if ($PSBoundParameters.ContainsKey('ScenarioId')) { $ScenarioId } else { $summary.scenarioId }
$resolvedRunId = if ($PSBoundParameters.ContainsKey('RunId')) { $RunId } else { $summary.runId }
$resolvedStatus = if ($PSBoundParameters.ContainsKey('Status')) { $Status } else { $summary.status }

Assert-NonEmptyValue -Value $resolvedScenarioId -Name 'ScenarioId'
Assert-NonEmptyValue -Value $resolvedRunId -Name 'RunId'
Assert-ValidStatus -Value $resolvedStatus

$artifactCount = @($artifactRefs).Count
$expectedArtifactCount = $artifactMap.Count
$validationNotes = @(
    'Manifest generation does not assert bundle validity. Run tools/evidence/validate-evidence-manifest.ps1 to validate schema and artifact presence.',
    "Generated manifest includes $artifactCount of $expectedArtifactCount expected runtime artifacts."
)

$manifest = [ordered]@{
    schemaVersion = '1.0.0'
    manifestId = "evidence-$resolvedRunId"
    runId = $resolvedRunId
    scenarioId = $resolvedScenarioId
    status = $resolvedStatus
    summary = [ordered]@{
        headline = $summary.headline
        outcome = $summary.outcome
        keyFindings = @($summary.keyFindings)
    }
    invariants = @(
        foreach ($invariant in $invariants) {
            $entry = [ordered]@{
                id = $invariant.id
                status = $invariant.status
                message = $invariant.message
            }

            if ($null -ne $invariant.PSObject.Properties['artifactRefs']) {
                $entry.artifactRefs = @($invariant.artifactRefs)
            }

            $entry
        }
    )
    artifactRefs = @($artifactRefs)
    producer = [ordered]@{
        toolingArtifactId = 'tools/evidence/new-evidence-manifest.ps1'
        surface = 'repo-local'
    }
    validation = [ordered]@{
        bundleValid = $false
        notes = $validationNotes
    }
    createdAt = [DateTime]::UtcNow.ToString('o')
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath

$result = [ordered]@{
    manifestPath = $resolvedOutputPath
    artifactCount = $artifactCount
    scenarioId = $resolvedScenarioId
    runId = $resolvedRunId
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}