[CmdletBinding()]
param(
    [string]$ProjectPath = 'tools/fixtures/addon-parse-check',
    [int]$QuitAfter = 2,
    [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param([string]$Relative)

    if ([System.IO.Path]::IsPathRooted($Relative)) {
        return [System.IO.Path]::GetFullPath($Relative)
    }
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Relative))
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
        if ($command) {
            return $command.Source
        }
    }

    $found = Get-Command 'Godot*' -CommandType Application -ErrorAction SilentlyContinue
    if ($found) {
        # On Windows, the *_console.exe build writes to stdout reliably; prefer it.
        $console = $found | Where-Object { $_.Name -match 'console' } | Select-Object -First 1
        if ($console) { return $console.Source }
        return ($found | Select-Object -First 1).Source
    }

    throw @"
Could not locate the Godot binary.

Set the GODOT_BIN environment variable to the full path of your Godot executable,
or add 'godot'/'godot4' to your PATH. See tools/README.md for setup instructions.
"@
}

$godot = Resolve-GodotBinary
$projectFull = Resolve-RepoPath -Relative $ProjectPath
$projectFile = Join-Path $projectFull 'project.godot'
if (-not (Test-Path -LiteralPath $projectFile)) {
    throw "No project.godot found at '$projectFull'."
}

# The addon's internal preload() calls use absolute res://addons/... paths, so
# we need the addon to appear under the project's own addons/ directory. Create
# a junction (Windows) or symlink so Godot resolves those paths without us
# having to copy the whole addon for every parse check.
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$addonSource = [System.IO.Path]::Combine($repoRoot, 'addons', 'agent_runtime_harness')
$projectAddons = Join-Path $projectFull 'addons'
$projectAddonLink = Join-Path $projectAddons 'agent_runtime_harness'
$createdLink = $false
if (-not (Test-Path -LiteralPath $projectAddonLink)) {
    if (-not (Test-Path -LiteralPath $projectAddons)) {
        New-Item -ItemType Directory -Path $projectAddons | Out-Null
    }
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        cmd /c mklink /J "`"$projectAddonLink`"" "`"$addonSource`"" | Out-Null
    } else {
        New-Item -ItemType SymbolicLink -Path $projectAddonLink -Target $addonSource | Out-Null
    }
    $createdLink = $true
}

Write-Host "Parse-checking addon scripts via '$godot' against '$projectFull'..."

$arguments = @(
    '--headless',
    '--editor',
    '--quit-after', $QuitAfter,
    '--path', $projectFull
)

$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
try {
    $process = Start-Process -FilePath $godot -ArgumentList $arguments `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Godot did not exit within $TimeoutSeconds seconds."
    }

    $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
    $combined = "$stdout`n$stderr"

    $errorPatterns = @(
        'Parse Error:',
        'Compile Error:',
        'Failed to compile',
        'Failed to load script',
        'SCRIPT ERROR:'
    )

    $errorMatches = @()
    foreach ($pattern in $errorPatterns) {
        $errorMatches += Select-String -InputObject $combined -Pattern $pattern -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
    }

    $errorLines = @(($combined -split "`n") | Where-Object {
        $line = $_
        $errorPatterns | Where-Object { $line -match $_ } | Select-Object -First 1
    })

    if ($errorLines.Count -gt 0) {
        Write-Host ""
        Write-Host "Detected GDScript parse/compile errors:" -ForegroundColor Red
        $errorLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Write-Host ""
        exit 1
    }

    Write-Host "OK: no GDScript parse or compile errors detected." -ForegroundColor Green
    exit 0
}
finally {
    Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    if ($createdLink -and (Test-Path -LiteralPath $projectAddonLink)) {
        # Junctions on Windows must be removed with rmdir, not Remove-Item -Recurse.
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            cmd /c rmdir "`"$projectAddonLink`"" | Out-Null
        } else {
            Remove-Item -LiteralPath $projectAddonLink -Force
        }
    }
}
