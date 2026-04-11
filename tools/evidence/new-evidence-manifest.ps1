[CmdletBinding()]
param(
    [string]$RuntimeArtifactsPath = 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample',
    [string]$OutputPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.generated.json',
    [string]$ScenarioId,
    [string]$RunId,
    [string]$Status,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
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
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $Path)
    return ($relativePath -replace '\\', '/')
}

$resolvedArtifactsPath = Resolve-RepoPath -Path $RuntimeArtifactsPath
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

$artifactMap = @(
    @{ kind = 'trace'; file = 'trace.jsonl'; mediaType = 'application/jsonl'; description = 'Per-frame trace data for the runtime sample.' },
    @{ kind = 'events'; file = 'events.json'; mediaType = 'application/json'; description = 'Structured runtime events for the sample run.' },
    @{ kind = 'scene_snapshot'; file = 'scene-snapshot.json'; mediaType = 'application/json'; description = 'Scene snapshot captured around the failure window.' },
    @{ kind = 'stdout_summary'; file = 'summary.json'; mediaType = 'application/json'; description = 'Normalized summary for the sample run.' },
    @{ kind = 'invariant_report'; file = 'invariants.json'; mediaType = 'application/json'; description = 'Invariant outcomes for the sample run.' }
)

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
        bundleValid = $true
        validatorVersion = '1.0.0'
        notes = @('Generated from a deterministic runtime sample fixture.')
    }
    createdAt = [DateTime]::UtcNow.ToString('o')
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath

$result = [ordered]@{
    manifestPath = $resolvedOutputPath
    artifactCount = @($artifactRefs).Count
    scenarioId = $resolvedScenarioId
    runId = $resolvedRunId
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}