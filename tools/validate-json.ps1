[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$SchemaPath,

    [switch]$PassThru,

    [switch]$AllowInvalid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    return (Resolve-Path -LiteralPath (Join-Path $repoRoot $Path)).Path
}

$resolvedInputPath = Resolve-RepoPath -Path $InputPath
$resolvedSchemaPath = Resolve-RepoPath -Path $SchemaPath

$jsonText = Get-Content -LiteralPath $resolvedInputPath -Raw
[void](ConvertFrom-Json -InputObject $jsonText -Depth 100)

$isValid = $true
$validationError = $null

try {
    $isValid = Test-Json -Json $jsonText -SchemaFile $resolvedSchemaPath
}
catch {
    $isValid = $false
    $validationError = $_.Exception.Message
}

$result = [ordered]@{
    inputPath = $resolvedInputPath
    schemaPath = $resolvedSchemaPath
    valid = [bool]$isValid
}

if (-not $isValid) {
    $result.error = if ($null -ne $validationError) {
        $validationError
    }
    else {
        'JSON validation failed against the supplied schema.'
    }
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}

if (-not $isValid -and -not $AllowInvalid) {
    exit 1
}