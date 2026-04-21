[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [string]$ConfigPath,
    [string]$CapabilityPath,
    [switch]$PassThru
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
        return $Path
    }

    return (Join-Path (Get-RepoRoot) $Path)
}

function Resolve-ProjectResourcePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootPath,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    if ($Path.StartsWith('res://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $Path.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        return Join-Path $ProjectRootPath $relativePath
    }

    return Resolve-RepoPath -Path $Path
}

$resolvedProjectRoot = Resolve-RepoPath -Path $ProjectRoot
$resolvedConfigPath = if ($PSBoundParameters.ContainsKey('ConfigPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $ConfigPath
}
else {
    Join-Path $resolvedProjectRoot 'harness/inspection-run-config.json'
}

$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json -Depth 100
$capabilitySourcePath = if ($PSBoundParameters.ContainsKey('CapabilityPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $CapabilityPath
}
else {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $config.automation.capabilityResultPath
}

$result = [ordered]@{
    projectRoot = $resolvedProjectRoot
    configPath = $resolvedConfigPath
    capabilityPath = $capabilitySourcePath
    exists = [bool](Test-Path -LiteralPath $capabilitySourcePath)
    schemaValid = $false
    capability = $null
    inputDispatch = $null
    runtimeErrorCapture = $null
    pauseOnError = $null
    breakpointSuppression = $null
}

if ($result.exists) {
    $result.capability = Get-Content -LiteralPath $capabilitySourcePath -Raw | ConvertFrom-Json -Depth 100
    $validation = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $capabilitySourcePath -SchemaPath 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json' -PassThru -AllowInvalid
    $result.schemaValid = [bool]$validation.valid
    if ($null -ne $result.capability -and $result.capability.PSObject.Properties.Name -contains 'inputDispatch') {
        $result.inputDispatch = $result.capability.inputDispatch
    }
    if ($null -ne $result.capability -and $result.capability.PSObject.Properties.Name -contains 'runtimeErrorCapture') {
        $result.runtimeErrorCapture = $result.capability.runtimeErrorCapture
    }
    if ($null -ne $result.capability -and $result.capability.PSObject.Properties.Name -contains 'pauseOnError') {
        $result.pauseOnError = $result.capability.pauseOnError
    }
    if ($null -ne $result.capability -and $result.capability.PSObject.Properties.Name -contains 'breakpointSuppression') {
        $result.breakpointSuppression = $result.capability.breakpointSuppression
    }
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}
