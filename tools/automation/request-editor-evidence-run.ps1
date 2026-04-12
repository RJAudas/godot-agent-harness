[CmdletBinding()]
param(
    [string]$ProjectRoot = 'examples/pong-testbed',
    [string]$ConfigPath,
    [string]$RequestPath,
    [string]$RequestFixturePath,
    [string]$RequestId,
    [string]$ScenarioId,
    [string]$RunId,
    [string]$TargetScene,
    [string]$OutputDirectory,
    [string]$ArtifactRoot,
    [string[]]$ExpectationFiles = @(),
    [string]$RequestedBy = 'vscode-agent',
    [bool]$StopAfterValidation = $true,
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
        [string]$Path,

        [switch]$CreateParent
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = $Path
    }
    else {
        $resolvedPath = Join-Path (Get-RepoRoot) $Path
    }

    if ($CreateParent) {
        $parentPath = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
    }

    return $resolvedPath
}

function Resolve-ProjectResourcePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootPath,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$CreateParent
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = $Path
    }
    elseif ($Path.StartsWith('res://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $Path.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $resolvedPath = Join-Path $ProjectRootPath $relativePath
    }
    else {
        $resolvedPath = Resolve-RepoPath -Path $Path
    }

    if ($CreateParent) {
        $parentPath = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
    }

    return $resolvedPath
}

function Convert-ToStringArray {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return ,@()
    }

    if ($Value -is [string]) {
        return ,@($Value)
    }

    return ,@($Value | ForEach-Object { [string]$_ })
}

$resolvedProjectRoot = Resolve-RepoPath -Path $ProjectRoot
$resolvedConfigPath = if ($PSBoundParameters.ContainsKey('ConfigPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $ConfigPath
}
else {
    Join-Path $resolvedProjectRoot 'harness/inspection-run-config.json'
}

$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json -Depth 100
$defaultRequest = if ($PSBoundParameters.ContainsKey('RequestFixturePath')) {
    $fixturePath = Resolve-RepoPath -Path $RequestFixturePath
    Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -Depth 100
}
else {
    [pscustomobject]@{}
}

$requestDocument = [ordered]@{
    requestId = if ($PSBoundParameters.ContainsKey('RequestId')) { $RequestId } elseif ($defaultRequest.requestId) { $defaultRequest.requestId } else { [guid]::NewGuid().Guid }
    scenarioId = if ($PSBoundParameters.ContainsKey('ScenarioId')) { $ScenarioId } elseif ($defaultRequest.scenarioId) { $defaultRequest.scenarioId } else { $config.scenarioId }
    runId = if ($PSBoundParameters.ContainsKey('RunId')) { $RunId } elseif ($defaultRequest.runId) { $defaultRequest.runId } else { ('run-' + [guid]::NewGuid().Guid) }
    targetScene = if ($PSBoundParameters.ContainsKey('TargetScene')) { $TargetScene } elseif ($defaultRequest.targetScene) { $defaultRequest.targetScene } else { $config.targetScene }
    outputDirectory = if ($PSBoundParameters.ContainsKey('OutputDirectory')) { $OutputDirectory } elseif ($defaultRequest.outputDirectory) { $defaultRequest.outputDirectory } else { $config.outputDirectory }
    artifactRoot = if ($PSBoundParameters.ContainsKey('ArtifactRoot')) { $ArtifactRoot } elseif ($defaultRequest.artifactRoot) { $defaultRequest.artifactRoot } else { $config.artifactRoot }
    expectationFiles = if ($ExpectationFiles.Count -gt 0) { Convert-ToStringArray $ExpectationFiles } elseif ($defaultRequest.expectationFiles) { Convert-ToStringArray $defaultRequest.expectationFiles } else { Convert-ToStringArray $config.expectationFiles }
    capturePolicy = if ($defaultRequest.capturePolicy) { $defaultRequest.capturePolicy } else { $config.capturePolicy }
    stopPolicy = [ordered]@{ stopAfterValidation = $StopAfterValidation }
    requestedBy = $RequestedBy
    createdAt = [DateTime]::UtcNow.ToString('o')
}

if ($defaultRequest.PSObject.Properties.Name -contains 'overrides') {
    $requestDocument.overrides = $defaultRequest.overrides
}

$resolvedRequestPath = if ($PSBoundParameters.ContainsKey('RequestPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $RequestPath -CreateParent
}
else {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $config.automation.requestPath -CreateParent
}

$requestDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedRequestPath
$validation = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedRequestPath -SchemaPath 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json' -PassThru -AllowInvalid

$result = [ordered]@{
    projectRoot = $resolvedProjectRoot
    configPath = $resolvedConfigPath
    requestPath = $resolvedRequestPath
    requestId = $requestDocument.requestId
    runId = $requestDocument.runId
    schemaValid = [bool]$validation.valid
}

if (-not $result.schemaValid) {
    throw 'Generated automation run request did not pass schema validation.'
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}
