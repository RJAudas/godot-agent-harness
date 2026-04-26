# Stop-PlaytestChildren.ps1
#
# B18: reap any Godot* descendant processes of the editor that survived
# editor_interface.stop_playing_scene(). Invoked synchronously from
# playtest_process_reaper.gd at run finalization. Idempotent: when the
# graceful stop already worked, no descendants exist and we exit 0 with
# killedPids:[].
#
# Reuses the F3 tree-kill primitive from tools/automation/invoke-stop-editor.ps1
# (Stop-GodotProcessTree, lines 111-130). The addon must be self-contained when
# deployed to a target project, so tools/ helpers are not reachable; this is the
# editor-side copy.
#
# CRITICAL: -EditorPid is NEVER killed. Only its Godot* descendants.
#
# On non-Windows hosts the WMI/Win32_Process filter is unavailable; emit an
# empty result and exit 0. The leak doesn't reproduce there anyway because
# Godot's own SIGTERM propagation handles child cleanup.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$EditorPid,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param(
        [int[]]$KilledPids = @(),
        [int[]]$SurvivorPids = @(),
        [string[]]$Errors = @(),
        [string]$Skipped = $null
    )
    $payload = [ordered]@{
        killedPids   = @($KilledPids)
        survivorPids = @($SurvivorPids)
        errors       = @($Errors)
    }
    if ($Skipped) { $payload['skipped'] = $Skipped }
    if ($Json) {
        # Single-line JSON so GDScript's parser can consume output[0] directly.
        ($payload | ConvertTo-Json -Compress -Depth 4)
    } else {
        $payload
    }
}

if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
    Write-Result -Skipped 'non_windows'
    exit 0
}

function Stop-DescendantTree {
    # Recursively stop a descendant subtree. Unlike Stop-GodotProcessTree in
    # invoke-stop-editor.ps1, the entry point here is ONE LEVEL DOWN from the
    # editor — i.e. the caller has already filtered to non-editor descendants —
    # so the recursion may freely kill its $RootPid argument.
    param(
        [Parameter(Mandatory)][int]$RootPid,
        [System.Collections.Generic.List[int]]$Collected,
        [System.Collections.Generic.List[string]]$Errs
    )
    try {
        $children = Get-CimInstance Win32_Process `
            -Filter "ParentProcessId=$RootPid AND Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
        foreach ($child in @($children)) {
            Stop-DescendantTree -RootPid ([int]$child.ProcessId) -Collected $Collected -Errs $Errs
        }
    } catch {
        [void]$Errs.Add("enumerate-children-of-$($RootPid): $($_.Exception.Message)")
    }
    try {
        Stop-Process -Id $RootPid -Force -ErrorAction Stop
        [void]$Collected.Add($RootPid)
    } catch {
        [void]$Errs.Add("stop-process-$($RootPid): $($_.Exception.Message)")
    }
}

$collected = [System.Collections.Generic.List[int]]::new()
$errors = [System.Collections.Generic.List[string]]::new()

# Verify the editor PID itself exists; if not, nothing to do.
$editorAlive = $false
try {
    $editorAlive = $null -ne (Get-Process -Id $EditorPid -ErrorAction SilentlyContinue)
} catch { }

if (-not $editorAlive) {
    Write-Result -Skipped 'editor_pid_not_found'
    exit 0
}

# Enumerate the editor's DIRECT Godot* children. Each subtree is reaped, but
# the editor itself (its $EditorPid) is never targeted by Stop-DescendantTree.
try {
    $directChildren = Get-CimInstance Win32_Process `
        -Filter "ParentProcessId=$EditorPid AND Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
    foreach ($child in @($directChildren)) {
        $childPid = [int]$child.ProcessId
        if ($childPid -eq $EditorPid) { continue }  # Defense-in-depth.
        Stop-DescendantTree -RootPid $childPid -Collected $collected -Errs $errors
    }
} catch {
    [void]$errors.Add("enumerate-direct-children: $($_.Exception.Message)")
}

# Re-verify: did anything we tried to kill survive?
$survivors = [System.Collections.Generic.List[int]]::new()
foreach ($p in $collected) {
    if (Get-Process -Id $p -ErrorAction SilentlyContinue) {
        [void]$survivors.Add($p)
    }
}

Write-Result -KilledPids $collected -SurvivorPids $survivors -Errors $errors

if ($survivors.Count -gt 0) { exit 1 }
exit 0
