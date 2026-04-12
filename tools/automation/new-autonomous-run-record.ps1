[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactId,

    [Parameter(Mandatory = $true)]
    [string]$WriteBoundaryId,

    [Parameter(Mandatory = $true)]
    [string]$RequestSummary,

    [string]$OutputPath = 'tools/automation/run-records/latest-run-record.json',

    [ValidateSet('autonomous', 'simulated')]
    [string]$Mode = 'simulated',

    [ValidateSet('success', 'stopped', 'escalated', 'failed')]
    [string]$Status = 'success',

    [string[]]$OperationPath = @(),
    [string[]]$OperationEditType = @(),
    [string[]]$OperationStatus = @(),
    [string[]]$OperationNote = @(),
    [string[]]$StopReason = @(),
    [string[]]$EscalationReason = @(),
    [string[]]$ValidationName = @(),
    [string[]]$ValidationStatus = @(),
    [string[]]$ValidationDetails = @(),
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

function Test-ArrayCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Expected,

        [Parameter(Mandatory = $true)]
        [int]$Actual
    )

    if ($Expected -ne $Actual) {
        throw "$Name must contain $Expected entries, but found $Actual."
    }
}

if ($OperationEditType.Count -gt 0) {
    Test-ArrayCount -Name 'OperationEditType' -Expected $OperationPath.Count -Actual $OperationEditType.Count
}

if ($OperationStatus.Count -gt 0) {
    Test-ArrayCount -Name 'OperationStatus' -Expected $OperationPath.Count -Actual $OperationStatus.Count
}

if ($OperationNote.Count -gt 0) {
    Test-ArrayCount -Name 'OperationNote' -Expected $OperationPath.Count -Actual $OperationNote.Count
}

if ($ValidationStatus.Count -gt 0) {
    Test-ArrayCount -Name 'ValidationStatus' -Expected $ValidationName.Count -Actual $ValidationStatus.Count
}

if ($ValidationDetails.Count -gt 0) {
    Test-ArrayCount -Name 'ValidationDetails' -Expected $ValidationName.Count -Actual $ValidationDetails.Count
}

$resolvedOutputPath = Resolve-RepoPath -Path $OutputPath -CreateParent
$timestamp = [DateTime]::UtcNow

$operations = for ($index = 0; $index -lt $OperationPath.Count; $index++) {
    $entry = [ordered]@{
        path = $OperationPath[$index]
        editType = if ($OperationEditType.Count -gt 0) { $OperationEditType[$index] } else { 'read-only' }
        status = if ($OperationStatus.Count -gt 0) { $OperationStatus[$index] } else { 'performed' }
    }

    if ($OperationNote.Count -gt 0) {
        $entry.note = $OperationNote[$index]
    }

    $entry
}

$validations = for ($index = 0; $index -lt $ValidationName.Count; $index++) {
    [ordered]@{
        name = $ValidationName[$index]
        status = if ($ValidationStatus.Count -gt 0) { $ValidationStatus[$index] } else { 'info' }
        details = if ($ValidationDetails.Count -gt 0) { $ValidationDetails[$index] } else { 'No additional details recorded.' }
    }
}

$record = [ordered]@{
    schemaVersion = '1.0.0'
    recordId = [guid]::NewGuid().Guid
    artifactId = $ArtifactId
    runId = [guid]::NewGuid().Guid
    mode = $Mode
    status = $Status
    requestSummary = $RequestSummary
    writeBoundaryId = $WriteBoundaryId
    operations = @($operations)
    stopReasons = @($StopReason)
    escalationReasons = @($EscalationReason)
    validations = @($validations)
    startedAt = $timestamp.ToString('o')
    endedAt = [DateTime]::UtcNow.ToString('o')
}

$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath
[void](& (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedOutputPath -SchemaPath 'tools/automation/autonomous-run-record.schema.json' -PassThru)

$result = [ordered]@{
    recordPath = $resolvedOutputPath
    operationCount = @($operations).Count
    validationCount = @($validations).Count
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}