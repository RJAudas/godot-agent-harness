<#
.SYNOPSIS
    Stop the Godot editor running against a sandbox project, leaving unrelated
    Godot instances untouched.

.DESCRIPTION
    invoke-stop-editor.ps1 finds Godot processes whose command-line includes
    `--path <ProjectRoot>` and terminates them. Three Godot processes typically
    spawn from `--editor --path <root>` (project manager, editor, optional
    console wrapper); the script targets all three.

    Pair with invoke-launch-editor.ps1. The stdout envelope shape mirrors the
    runtime-verification invokers; manifestPath is always null.

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox.

.EXAMPLE
    pwsh ./tools/automation/invoke-stop-editor.ps1 -ProjectRoot integration-testing/probe

    Stops every Godot process for the probe sandbox.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug = 'stop-editor'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

function Exit-Failure {
    param([string]$Kind, [string]$Message, [hashtable]$Outcome)
    if ($null -eq $Outcome) {
        $Outcome = @{ stoppedPids = @(); remainingPids = @() }
    }
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics @($Message) -Outcome $Outcome
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

function Get-EditorProcessesForProject {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $isWin = $IsWindows -or $env:OS -eq 'Windows_NT'
    $matches = @()
    if ($isWin) {
        try {
            $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
            foreach ($p in @($procs)) {
                $cmd = [string]$p.CommandLine
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                $normCmd = $cmd.Replace('/', '\')
                $normRoot = $ProjectRoot.Replace('/', '\')
                if ($normCmd -like "*--path*$normRoot*") {
                    $matches += [int]$p.ProcessId
                }
            }
        }
        catch { }
    }
    else {
        $matches = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    }
    return ,$matches
}

if (-not (Test-Path -LiteralPath $resolvedRoot)) {
    Exit-Failure 'internal' "ProjectRoot '$resolvedRoot' does not exist."
}

$pidsToStop = Get-EditorProcessesForProject -ProjectRoot $resolvedRoot
$pidCount = @($pidsToStop).Count

if ($pidCount -eq 0) {
    $envelope = Write-RunbookEnvelope -Status 'success' -RunId $runId -RequestId $requestId `
        -Diagnostics @() -Outcome @{
            stoppedPids   = @()
            remainingPids = @()
            noopReason    = 'no-matching-editor'
        }
    $envelope
    Write-RunbookStderrSummary "OK: no Godot processes matched ProjectRoot '$resolvedRoot'."
    exit 0
}

$stopped = @()
foreach ($processId in @($pidsToStop)) {
    try {
        Stop-Process -Id $processId -Force -ErrorAction Stop
        $stopped += $processId
    }
    catch { }
}
Start-Sleep -Milliseconds 500

# Re-check: anything still running for this project?
$remaining = Get-EditorProcessesForProject -ProjectRoot $resolvedRoot

if (@($remaining).Count -gt 0) {
    Exit-Failure 'internal' "Stopped $(@($stopped).Count) of $pidCount editor process(es); $(@($remaining).Count) still running: $(@($remaining) -join ', ')." @{
        stoppedPids   = @($stopped)
        remainingPids = @($remaining)
    }
}

$envelope = Write-RunbookEnvelope -Status 'success' -RunId $runId -RequestId $requestId `
    -Diagnostics @() -Outcome @{
        stoppedPids   = @($stopped)
        remainingPids = @()
    }
$envelope
Write-RunbookStderrSummary "OK: stopped $(@($stopped).Count) editor process(es)."
exit 0
