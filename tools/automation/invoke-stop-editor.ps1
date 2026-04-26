<#
.SYNOPSIS
    Stop the Godot editor running against a sandbox project, leaving unrelated
    Godot instances untouched.

.DESCRIPTION
    invoke-stop-editor.ps1 finds Godot processes whose command-line includes
    `--path <ProjectRoot>` and terminates them along with any child Godot
    processes they spawned (e.g. playtest sessions). On Windows the full
    process tree is walked via Win32_Process; on POSIX only the matched
    editor process is stopped.

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
    # Match Godot processes whose command-line carries `--path <ProjectRoot>` as a
    # discrete argument so we never accidentally stop an unrelated editor when
    # one project root is a prefix of another (C:\proj vs C:\proj2). Token
    # boundary required after the path; slash differences normalised on Windows.
    $isWin = $IsWindows -or $env:OS -eq 'Windows_NT'

    $found = [System.Collections.Generic.List[int]]::new()

    if ($isWin) {
        $normRoot = $ProjectRoot.TrimEnd('\', '/').Replace('/', '\')
        $rootEsc = [regex]::Escape($normRoot)
        $pattern = '(?i)--path(?:\s+|=)("?)' + $rootEsc + '\1(?=\s|$)'

        try {
            $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
            foreach ($p in @($procs)) {
                $cmd = [string]$p.CommandLine
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                $normCmd = $cmd.Replace('/', '\')
                if ($normCmd -match $pattern) {
                    [void]$found.Add([int]$p.ProcessId)
                }
            }
        }
        catch { }
        return ,@($found)
    }

    # POSIX: shell out to ps. Skip Get-Process Godot* fallback -- returning
    # every Godot editor on the box would risk killing unrelated instances.
    $normRoot = $ProjectRoot.TrimEnd('/')
    $rootEsc = [regex]::Escape($normRoot)
    $pattern = '--path(?:\s+|=)("?)' + $rootEsc + '\1(?=\s|$)'

    $psBinary = (Get-Command ps -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($null -eq $psBinary) { return ,@() }

    $psLines = $null
    try {
        $psLines = & $psBinary.Source -eo 'pid=,args=' 2>$null
    }
    catch { return ,@() }

    foreach ($line in @($psLines)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }
        if ($trimmed -notmatch '^\s*\d+\s+') { continue }
        $procId = [int]([regex]::Match($trimmed, '^\s*(\d+)\s+').Groups[1].Value)
        $cmd = $trimmed -replace '^\s*\d+\s+', ''
        if ($cmd -notmatch '(?i)\bGodot') { continue }
        if ($cmd -match $pattern) {
            [void]$found.Add($procId)
        }
    }
    return ,@($found)
}

function Stop-GodotProcessTree {
    # Recursively stops child Godot processes before the root (Windows only).
    # Children are walked depth-first so they are terminated before their parent
    # can disappear, which would otherwise clear their ParentProcessId in WMI.
    param(
        [Parameter(Mandatory)][int]$RootPid,
        [System.Collections.Generic.List[int]]$Collected
    )
    try {
        $children = Get-CimInstance Win32_Process `
            -Filter "ParentProcessId=$RootPid AND Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
        foreach ($child in @($children)) {
            Stop-GodotProcessTree -RootPid $child.ProcessId -Collected $Collected
        }
    } catch { }
    try {
        Stop-Process -Id $RootPid -Force -ErrorAction Stop
        [void]$Collected.Add($RootPid)
    } catch { }
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

$isWin = $IsWindows -or $env:OS -eq 'Windows_NT'
$allStopped = [System.Collections.Generic.List[int]]::new()
foreach ($editorPid in @($pidsToStop)) {
    if ($isWin) {
        Stop-GodotProcessTree -RootPid $editorPid -Collected $allStopped
    } else {
        try { Stop-Process -Id $editorPid -Force -ErrorAction Stop; [void]$allStopped.Add($editorPid) } catch { }
    }
}
$stopped = @($allStopped)
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
