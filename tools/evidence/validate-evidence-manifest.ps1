[CmdletBinding()]
param(
    [string]$ManifestPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json',
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
        throw "Artifact path '$Path' resolves outside the repository root."
    }

    return $fullPath
}

$resolvedManifestPath = Resolve-RepoPath -Path $ManifestPath
$schemaResult = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedManifestPath -SchemaPath 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json' -PassThru -AllowInvalid
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -Depth 100
$missingArtifactPaths = New-Object System.Collections.Generic.List[string]
$unsupportedArtifactKinds = New-Object System.Collections.Generic.List[string]
$supportedArtifactKinds = Get-EvidenceArtifactKinds

foreach ($artifactRef in $manifest.artifactRefs) {
    if ($artifactRef.kind -notin $supportedArtifactKinds) {
        [void]$unsupportedArtifactKinds.Add([string]$artifactRef.kind)
    }

    try {
        $artifactPath = Convert-ToRepoChildPath -Path $artifactRef.path
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
$result = [ordered]@{
    manifestPath = $resolvedManifestPath
    schemaValid = [bool]$schemaResult.valid
    missingArtifactPaths = $missingArtifactPaths
    unsupportedArtifactKinds = $unsupportedArtifactKinds
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