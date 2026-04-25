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
    # Match Godot processes whose command-line carries `--path <ProjectRoot>` as a
    # discrete argument (quoted or unquoted) so we never confuse "/proj" with
    # "/proj2" or stop unrelated editor instances. The match enforces a token
    # boundary after the path (whitespace, closing quote, or end-of-string) and
    # treats forward / back slashes as interchangeable on Windows.
    $isWin = $IsWindows -or $env:OS -eq 'Windows_NT'

    $found = [System.Collections.Generic.List[object]]::new()

    if ($isWin) {
        # Case-insensitive regex requiring `--path` (or `--path=`) followed by
        # an exact, slash-normalised root token bounded by whitespace or EOL.
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
                    [void]$found.Add([pscustomobject]@{ Id = [int]$p.ProcessId; CommandLine = $cmd; Name = [string]$p.Name })
                }
            }
        }
        catch { }
        return ,@($found)
    }

    # POSIX: shell out to /usr/bin/env ps for cmdline inspection. We deliberately
    # avoid the `ps` alias (resolves to Get-Process in PowerShell) and skip the
    # name-only `Get-Process Godot*` fallback -- that returns every Godot
    # editor on the box and breaks the "leave unrelated instances alone"
    # contract that invoke-stop-editor depends on.
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
        # Restrict to Godot binaries to avoid matching unrelated invocations
        # that happen to carry `--path`.
        if ($cmd -notmatch '(?i)\bGodot') { continue }
        if ($cmd -match $pattern) {
            [void]$found.Add([pscustomobject]@{ Id = $procId; CommandLine = $cmd; Name = 'Godot' })
        }
    }
    return ,@($found)
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

# Capture spawn time BEFORE Start-Process so the post-spawn poll loop can
# require capability.json's mtime >= $spawnedAt. Otherwise a stale
# capability.json from a prior session that's still within
# MaxCapabilityAgeSeconds would short-circuit the cold launch path and
# return success before the freshly spawned editor is actually ready.
$spawnedAt = [DateTime]::UtcNow

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

# B13: emit a heartbeat to stderr so an agent watching the orchestration can
# tell something's happening. Cold starts can take 30-60s; without the
# heartbeat the call looks indistinguishable from a hang.
[Console]::Error.WriteLine("[invoke-launch-editor] spawned Godot PID $($proc.Id); waiting up to ${ReadyTimeoutSeconds}s for capability.json (mtime >= ${spawnedAt:o})")

# Poll capability.json until the *newly spawned* editor publishes one, OR until
# ReadyTimeoutSeconds. "Newly published" = file exists, parses cleanly, and its
# LastWriteTimeUtc >= $spawnedAt (ignore prior-session leftovers).
$deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$age = $null
$nextHeartbeatAt = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500

    if ($proc.HasExited) {
        $tailErr = if (Test-Path -LiteralPath $stderrLog) {
            (Get-Content -LiteralPath $stderrLog -Tail 5 -ErrorAction SilentlyContinue) -join '; '
        } else { '' }
        Exit-Failure 'editor-not-running' "Godot process exited with code $($proc.ExitCode) before capability.json appeared. stderr tail: $tailErr"
    }

    if (Test-Path -LiteralPath $capabilityPath) {
        $mtimeUtc = (Get-Item -LiteralPath $capabilityPath).LastWriteTimeUtc
        if ($mtimeUtc -ge $spawnedAt) {
            $candidateAge = Test-CapabilityFresh -Path $capabilityPath -MaxAgeSeconds $MaxCapabilityAgeSeconds
            if ($null -ne $candidateAge) {
                $age = $candidateAge
                break
            }
        }
    }

    if ((Get-Date) -ge $nextHeartbeatAt) {
        $elapsed = [int]((Get-Date) - $spawnedAt.ToLocalTime()).TotalSeconds
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        $capState = if (Test-Path -LiteralPath $capabilityPath) {
            $cm = (Get-Item -LiteralPath $capabilityPath).LastWriteTimeUtc
            if ($cm -lt $spawnedAt) { "stale (mtime $($cm.ToString('o')) predates spawn)" } else { 'parse-pending' }
        } else { 'absent' }
        [Console]::Error.WriteLine("[invoke-launch-editor] still waiting: ${elapsed}s elapsed, ${remaining}s remaining; capability.json $capState")
        $nextHeartbeatAt = (Get-Date).AddSeconds(10)
    }
}

if ($null -eq $age) {
    Exit-Failure 'editor-not-running' "capability.json did not appear within ${ReadyTimeoutSeconds}s. Editor PID $($proc.Id) is still running; inspect '$stdoutLog' / '$stderrLog' for clues." @{
        editorPid            = $proc.Id
        capabilityPath       = $capabilityPath
        capabilityAgeSeconds = $null
    }
}

[Console]::Error.WriteLine("[invoke-launch-editor] editor ready (capability.json mtime ${age}s ago); dispatching workflow")

$outcome = @{
    editorPid            = $proc.Id
    capabilityPath       = $capabilityPath
    capabilityAgeSeconds = $age
    reusedExistingEditor = $false
}
$envelope = Write-RunbookEnvelope -Status 'success' -RunId $runId -RequestId $requestId `
    -Diagnostics @() -Outcome $outcome
$envelope

# Summary is best-effort. Get-Process can throw under StrictMode if the editor
# has already exited (or its PID has been recycled), but the success envelope
# is already on stdout -- never let a cosmetic stderr line turn a successful
# invocation into a failing one.
try {
    $startTime = (Get-Process -Id $proc.Id -ErrorAction Stop).StartTime
    $readySecs = [int]((Get-Date) - $startTime).TotalSeconds
    Write-RunbookStderrSummary "OK: spawned editor PID $($proc.Id); capability ready in ${readySecs}s (mtime ${age}s ago)."
}
catch {
    Write-RunbookStderrSummary "OK: spawned editor PID $($proc.Id); capability mtime ${age}s ago."
}
exit 0
