[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [int]$PauseId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('continue', 'stop')]
    [string]$Decision,

    [string]$SubmittedBy = 'vscode-agent',

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
}

# ---------------------------------------------------------------------------
# Resolve the project root to an absolute path.
# ---------------------------------------------------------------------------

$resolvedProjectRoot = if ([System.IO.Path]::IsPathRooted($ProjectRoot)) {
    $ProjectRoot
} else {
    Join-Path (Get-RepoRoot) $ProjectRoot
}

if (-not (Test-Path -LiteralPath $resolvedProjectRoot -PathType Container)) {
    Write-Error "ProjectRoot '$ProjectRoot' does not resolve to an existing directory."
    exit 1
}

# ---------------------------------------------------------------------------
# Validate inputs before touching the filesystem.
# ---------------------------------------------------------------------------

$result = [ordered]@{
    accepted      = $false
    runId         = $RunId
    pauseId       = $PauseId
    decision      = $Decision
    submittedBy   = $SubmittedBy
    outputPath    = $null
    errors        = @()
}

$validationErrors = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $validationErrors.Add('RunId must not be empty.')
}

if ($PauseId -lt 0) {
    $validationErrors.Add("PauseId must be >= 0 (got $PauseId).")
}

if ([string]::IsNullOrWhiteSpace($SubmittedBy)) {
    $validationErrors.Add('SubmittedBy must not be empty.')
}

if ($validationErrors.Count -gt 0) {
    $result.errors = $validationErrors.ToArray()
    if ($PassThru) {
        return $result
    }
    $result | ConvertTo-Json -Depth 5
    exit 1
}

# ---------------------------------------------------------------------------
# Build the pause-decision request document.
# ---------------------------------------------------------------------------

$document = [ordered]@{
    runId       = $RunId
    pauseId     = $PauseId
    decision    = $Decision
    submittedBy = $SubmittedBy
    submittedAt = [System.DateTime]::UtcNow.ToString('o')
}

# ---------------------------------------------------------------------------
# Resolve the target path and write atomically.
# ---------------------------------------------------------------------------

$requestsDir = Join-Path $resolvedProjectRoot 'harness' 'automation' 'requests'
if (-not (Test-Path -LiteralPath $requestsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $requestsDir -Force | Out-Null
}

$targetPath = Join-Path $requestsDir 'pause-decision.json'
$tempPath   = $targetPath + '.tmp'

$json = $document | ConvertTo-Json -Depth 5
Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8 -NoNewline
Move-Item -LiteralPath $tempPath -Destination $targetPath -Force

$result.accepted   = $true
$result.outputPath = $targetPath

if ($PassThru) {
    return $result
}

$result | ConvertTo-Json -Depth 5
