Set-StrictMode -Version Latest

$script:RepoRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path

function Get-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $script:RepoRoot $Path)
}

function Invoke-RepoPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$Arguments = @()
    )

    $resolvedScriptPath = Get-RepoPath -Path $ScriptPath
    $commandArguments = @('-NoProfile', '-File', $resolvedScriptPath) + $Arguments
    $output = & pwsh @commandArguments 2>&1
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | ForEach-Object {
                    if ($null -ne $_) {
                        $_.ToString()
                    }
                }) -join [System.Environment]::NewLine).Trim()
    }
}

function Invoke-RepoJsonScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$Arguments = @()
    )

    $invocation = Invoke-RepoPowerShell -ScriptPath $ScriptPath -Arguments $Arguments
    $parsedOutput = $null

    if (-not [string]::IsNullOrWhiteSpace($invocation.Output)) {
        $parsedOutput = $invocation.Output | ConvertFrom-Json -Depth 100
    }

    [pscustomobject]@{
        ExitCode = $invocation.ExitCode
        Output = $invocation.Output
        ParsedOutput = $parsedOutput
    }
}

function Invoke-RepoScriptPassThru {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [hashtable]$Parameters = @{}
    )

    $resolvedScriptPath = Get-RepoPath -Path $ScriptPath
    & $resolvedScriptPath @Parameters
}

function New-RepoSandboxDirectory {
    $sandboxRoot = Join-Path (Join-Path $script:RepoRoot 'tools') 'tests/.tmp'
    if (-not (Test-Path -LiteralPath $sandboxRoot)) {
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
    }

    $sandboxPath = Join-Path $sandboxRoot ([guid]::NewGuid().Guid)
    New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null
    return $sandboxPath
}