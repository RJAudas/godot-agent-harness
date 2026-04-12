[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactId,

    [Parameter(Mandatory = $true)]
    [string[]]$RequestedPath,

    [Parameter(Mandatory = $true)]
    [string[]]$RequestedEditType,

    [string]$BoundaryPath = 'tools/automation/write-boundaries.json',

    [switch]$PassThru,

    [switch]$AllowViolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Convert-ToRepoRelativePath {
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

    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $fullPath)
    if ($relativePath -eq '.') {
        return ''
    }

    return ($relativePath -replace '\\', '/').Trim()
}

$resolvedBoundaryPath = Resolve-RepoPath -Path $BoundaryPath
[void](& (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedBoundaryPath -SchemaPath 'tools/automation/write-boundaries.schema.json' -PassThru)
$boundaryDocument = Get-Content -LiteralPath $resolvedBoundaryPath -Raw | ConvertFrom-Json -Depth 100
$boundary = $boundaryDocument.boundaries | Where-Object { $_.artifactId -eq $ArtifactId } | Select-Object -First 1

if ($null -eq $boundary) {
    throw "No write boundary found for artifact '$ArtifactId'."
}

if ($RequestedEditType.Count -ne 1 -and $RequestedEditType.Count -ne $RequestedPath.Count) {
    throw 'RequestedEditType must contain either one shared edit type or one edit type per requested path.'
}

$violations = New-Object System.Collections.Generic.List[object]
$normalizedAllowedPaths = @($boundary.allowedPaths | ForEach-Object { Convert-ToRepoRelativePath -Path $_ })

for ($index = 0; $index -lt $RequestedPath.Count; $index++) {
    $normalizedPath = (($RequestedPath[$index] -replace '\\', '/') -replace '^\./', '').Trim()
    $editType = if ($RequestedEditType.Count -eq 1) { $RequestedEditType[0] } else { $RequestedEditType[$index] }
    $pathAllowed = $false
    $pathViolationReason = $null

    try {
        $normalizedPath = Convert-ToRepoRelativePath -Path $RequestedPath[$index]
    }
    catch {
        $pathViolationReason = $_.Exception.Message
    }

    if ($null -eq $pathViolationReason) {
        foreach ($allowedPath in $normalizedAllowedPaths) {
            $trimmedAllowedPath = ($allowedPath -replace '/+$', '')

            if ($normalizedPath -eq $trimmedAllowedPath) {
                $pathAllowed = $true
                break
            }

            if ($normalizedPath.StartsWith($trimmedAllowedPath + '/')) {
                $pathAllowed = $true
                break
            }
        }
    }

    $editAllowed = $editType -in $boundary.allowedEditTypes
    if ($null -ne $pathViolationReason -or -not $pathAllowed -or -not $editAllowed) {
        $violationReason = if ($null -ne $pathViolationReason) {
            $pathViolationReason
        }
        elseif (-not $pathAllowed) {
            'Requested path is outside the declared write boundary.'
        }
        else {
            'Requested edit type is not allowed by the declared write boundary.'
        }

        [void]$violations.Add([pscustomobject]@{
            path = $normalizedPath
            editType = $editType
            reason = $violationReason
        })
    }
}

$requestAllowed = ($violations.Count -eq 0)
$allowedPaths = @($boundary.allowedPaths)
$allowedEditTypes = @($boundary.allowedEditTypes)
$violationItems = $violations.ToArray()

$result = [ordered]@{}
$result['artifactId'] = $ArtifactId
$result['boundaryId'] = $boundary.id
$result['requestAllowed'] = [bool]$requestAllowed
$result['allowedPaths'] = [string[]]$allowedPaths
$result['allowedEditTypes'] = [string[]]$allowedEditTypes
$result['violations'] = $violationItems

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}

if ($violations.Count -gt 0 -and -not $AllowViolation) {
    exit 1
}