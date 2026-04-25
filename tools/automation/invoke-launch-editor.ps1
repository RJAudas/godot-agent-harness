<#
.SYNOPSIS
    Launch (or attach to) a Godot editor for a sandbox project, returning when
    the harness capability surface is ready.

.DESCRIPTION
    invoke-launch-editor.ps1 is the missing prerequisite step every runtime-
    verification workflow needs: a live editor running against the target
    project. It is idempotent — when an editor for the same -ProjectRoot is
    already running and capability.json is fresh, it returns success in well
    under a second. Otherwise it spawns Godot with `--editor --path <ProjectRoot>`,
    redirects stdout/stderr to <ProjectRoot>/.editor-logs/, and polls
    capability.json until it appears (or -ReadyTimeoutSeconds elapses).

    The script emits a stable JSON envelope on stdout matching the same shape
    as the runtime-verification invokers (status / failureKind / manifestPath /
    runId / requestId / completedAt / diagnostics / outcome). manifestPath is
    always null because no run was performed. outcome carries the editor PID,
    the absolute capability.json path, and capability.json's age in seconds.

    Pair with invoke-stop-editor.ps1 to terminate the editor cleanly.

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the integration-testing sandbox.

.PARAMETER ReadyTimeoutSeconds
    Wall-clock budget for capability.json to appear after spawn. Default 90.
    Cold starts (first launch with no shader cache) typically need 30-60s.

.PARAMETER MaxCapabilityAgeSeconds
    Existing capability.json is treated as "fresh" if its mtime is within this
    window. When a fresh capability is found alongside a live Godot process,
    the launcher short-circuits and returns success without spawning. Default 300.

.PARAMETER ForceRestart
    Stop any existing Godot processes for this project before launching. Use
    when you suspect a stale editor is misbehaving.

.EXAMPLE
    pwsh ./tools/automation/invoke-launch-editor.ps1 -ProjectRoot integration-testing/probe

    Launches (or reuses) the editor and returns when capability.json is ready.

.EXAMPLE
    pwsh ./tools/automation/invoke-launch-editor.ps1 `
        -ProjectRoot integration-testing/probe -ForceRestart

    Stops any existing editor for this project, then launches a fresh one.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [int]$ReadyTimeoutSeconds = 90,

    [int]$MaxCapabilityAgeSeconds = 300,

    [switch]$ForceRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot
$workflowSlug = 'launch-editor'
$requestId    = New-RunbookRequestId -Workflow $workflowSlug
$runId        = $requestId

function Exit-Failure {
    param([string]$Kind, [string]$Message, [hashtable]$Outcome)
    if ($null -eq $Outcome) {
        $Outcome = @{ editorPid = $null; capabilityPath = $null; capabilityAgeSeconds = $null }
    }
    Write-RunbookEnvelope -Status 'failure' -FailureKind $Kind -RunId $runId -RequestId $requestId `
        -Diagnostics @($Message) -Outcome $Outcome
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

function Resolve-GodotBinary {
    if ($env:GODOT_BIN) {
        if (Test-Path -LiteralPath $env:GODOT_BIN) {
            return (Resolve-Path -LiteralPath $env:GODOT_BIN).Path
        }
        throw "GODOT_BIN is set to '$($env:GODOT_BIN)' but the file does not exist."
    }
    foreach ($candidate in @('godot', 'godot4')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    $found = Get-Command 'Godot*' -CommandType Application -ErrorAction SilentlyContinue
    if ($found) {
        # On Windows, prefer the *_console.exe build for reliable stdout capture.
        $console = $found | Where-Object { $_.Name -match 'console' } | Select-Object -First 1
        if ($console) { return $console.Source }
        return ($found | Select-Object -First 1).Source
    }
    throw "Could not locate the Godot binary. Set GODOT_BIN or add godot/godot4 to PATH."
}

function Get-EditorProcessesForProject {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    # Match Godot processes whose CommandLine includes --path <ProjectRoot> so
    # we never touch unrelated editor instances. CIM is Windows-only; on POSIX
    # we fall back to a name match (good enough for the common case).
    $isWin = $IsWindows -or $env:OS -eq 'Windows_NT'
    $matches = @()
    if ($isWin) {
        try {
            $procs = Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
            foreach ($p in @($procs)) {
                $cmd = [string]$p.CommandLine
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                # Compare on normalised slashes since Godot may have been launched with either.
                $normCmd = $cmd.Replace('/', '\')
                $normRoot = $ProjectRoot.Replace('/', '\')
                if ($normCmd -like "*--path*$normRoot*") {
                    $matches += [pscustomobject]@{ Id = [int]$p.ProcessId; CommandLine = $cmd; Name = [string]$p.Name }
                }
            }
        }
        catch { }
    }
    else {
        $matches = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue |
            Select-Object -Property @{N='Id';E={$_.Id}}, @{N='Name';E={$_.ProcessName}}, @{N='CommandLine';E={''}})
    }
    return ,$matches
}

function Test-CapabilityFresh {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$MaxAgeSeconds
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $age = ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds
    if ($age -gt $MaxAgeSeconds) { return $null }
    try {
        $null = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20
    }
    catch { return $null }
    return [int]$age
}

# --- Resolve project root + capability path ---

if (-not (Test-Path -LiteralPath $resolvedRoot)) {
    Exit-Failure 'internal' "ProjectRoot '$resolvedRoot' does not exist."
}
$projectGodot = Join-Path $resolvedRoot 'project.godot'
if (-not (Test-Path -LiteralPath $projectGodot)) {
    Exit-Failure 'internal' "No project.godot at '$resolvedRoot' — not a Godot project root."
}

$capabilityPath = Join-Path $resolvedRoot 'harness/automation/results/capability.json'

# --- ForceRestart path: stop any existing editors for this project first ---

if ($ForceRestart) {
    foreach ($p in (Get-EditorProcessesForProject -ProjectRoot $resolvedRoot)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
}

# --- Idempotent fast path: live editor + fresh capability -> return success ---

if (-not $ForceRestart) {
    $existing = Get-EditorProcessesForProject -ProjectRoot $resolvedRoot
    $existingCount = @($existing).Count
    if ($existingCount -gt 0) {
        $age = Test-CapabilityFresh -Path $capabilityPath -MaxAgeSeconds $MaxCapabilityAgeSeconds
        if ($null -ne $age) {
            $outcome = @{
                editorPid            = [int](@($existing)[0].Id)
                capabilityPath       = $capabilityPath
                capabilityAgeSeconds = $age
                reusedExistingEditor = $true
            }
            $envelope = Write-RunbookEnvelope -Status 'success' -RunId $runId -RequestId $requestId `
                -Diagnostics @() -Outcome $outcome
            $envelope
            Write-RunbookStderrSummary "OK: reused existing editor PID $($outcome.editorPid); capability ${age}s old."
            exit 0
        }
    }
}

# --- Launch a fresh editor ---

try {
    $godot = Resolve-GodotBinary
}
catch {
    Exit-Failure 'internal' $_.Exception.Message
}

$logDir = Join-Path $resolvedRoot '.editor-logs'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$stdoutLog = Join-Path $logDir 'editor.stdout.log'
$stderrLog = Join-Path $logDir 'editor.stderr.log'

try {
    $proc = Start-Process -FilePath $godot `
        -ArgumentList @('--editor', '--path', $resolvedRoot, '--verbose') `
        -PassThru `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog
}
catch {
    Exit-Failure 'editor-not-running' "Failed to spawn Godot at '$godot': $($_.Exception.Message)"
}

# Poll capability.json until it appears + parses, OR until ReadyTimeoutSeconds.
$deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$age = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    # If the editor process already died, surface that immediately.
    if ($proc.HasExited) {
        $tailErr = if (Test-Path -LiteralPath $stderrLog) {
            (Get-Content -LiteralPath $stderrLog -Tail 5 -ErrorAction SilentlyContinue) -join '; '
        } else { '' }
        Exit-Failure 'editor-not-running' "Godot process exited with code $($proc.ExitCode) before capability.json appeared. stderr tail: $tailErr"
    }

    $age = Test-CapabilityFresh -Path $capabilityPath -MaxAgeSeconds $MaxCapabilityAgeSeconds
    if ($null -ne $age) { break }
}

if ($null -eq $age) {
    Exit-Failure 'timeout' "capability.json did not appear within ${ReadyTimeoutSeconds}s. Editor PID $($proc.Id) is still running; inspect '$stdoutLog' / '$stderrLog' for clues." @{
        editorPid            = $proc.Id
        capabilityPath       = $capabilityPath
        capabilityAgeSeconds = $null
    }
}

$outcome = @{
    editorPid            = $proc.Id
    capabilityPath       = $capabilityPath
    capabilityAgeSeconds = $age
    reusedExistingEditor = $false
}
$envelope = Write-RunbookEnvelope -Status 'success' -RunId $runId -RequestId $requestId `
    -Diagnostics @() -Outcome $outcome
$envelope
Write-RunbookStderrSummary "OK: spawned editor PID $($proc.Id); capability ready in $((Get-Date) - (Get-Process -Id $proc.Id).StartTime | Select-Object -ExpandProperty TotalSeconds | ForEach-Object { [int]$_ })s (or ${age}s old)."
exit 0
