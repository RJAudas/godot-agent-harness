[CmdletBinding()]
param(
    [string]$ManifestPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json',
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
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path (Get-RepoRoot) $Path)).Path
}

$resolvedManifestPath = Resolve-RepoPath -Path $ManifestPath
$schemaResult = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedManifestPath -SchemaPath 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json' -PassThru
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -Depth 100
$repoRoot = Get-RepoRoot
$missingArtifactPaths = New-Object System.Collections.Generic.List[string]

foreach ($artifactRef in $manifest.artifactRefs) {
    $artifactPath = Join-Path $repoRoot ($artifactRef.path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        [void]$missingArtifactPaths.Add($artifactRef.path)
    }
}

$bundleValid = [bool]$schemaResult.valid -and $missingArtifactPaths.Count -eq 0
$result = [ordered]@{
    manifestPath = $resolvedManifestPath
    schemaValid = [bool]$schemaResult.valid
    missingArtifactPaths = $missingArtifactPaths
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