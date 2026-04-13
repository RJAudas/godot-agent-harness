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

function Read-RepoJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content -LiteralPath (Get-RepoPath -Path $Path) -Raw | ConvertFrom-Json -Depth 100
}

function Assert-BuildDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        $Diagnostic,

        [string]$ExpectedResourcePath,

        [string]$ExpectedSourceKind
    )

    $Diagnostic.message | Should -Not -BeNullOrEmpty
    $Diagnostic.severity | Should -BeIn @('error', 'warning', 'unknown')
    $Diagnostic.sourceKind | Should -BeIn @('script', 'scene', 'resource', 'unknown')
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'resourcePath'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'line'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'column'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'code'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'rawExcerpt'

    if ($PSBoundParameters.ContainsKey('ExpectedResourcePath')) {
        $Diagnostic.resourcePath | Should -Be $ExpectedResourcePath
    }

    if ($PSBoundParameters.ContainsKey('ExpectedSourceKind')) {
        $Diagnostic.sourceKind | Should -Be $ExpectedSourceKind
    }
}

function Assert-BuildFailureLifecycleStatus {
    param(
        [Parameter(Mandatory = $true)]
        $Status,

        [string]$ExpectedPhase = 'launching',

        [int]$MinimumDiagnosticCount = 1
    )

    $Status.status | Should -Be 'failed'
    $Status.failureKind | Should -Be 'build'
    $Status.buildFailurePhase | Should -Be $ExpectedPhase
    $Status.buildDiagnosticCount | Should -BeGreaterOrEqual $MinimumDiagnosticCount
    $Status.rawBuildOutputAvailable | Should -BeTrue
}

function Assert-BuildFailureResult {
    param(
        [Parameter(Mandatory = $true)]
        $Result,

        [string]$ExpectedPhase = 'launching',

        [int]$MinimumDiagnosticCount = 1
    )

    $Result.finalStatus | Should -Be 'failed'
    $Result.failureKind | Should -Be 'build'
    $Result.buildFailurePhase | Should -Be $ExpectedPhase
    @($Result.buildDiagnostics).Count | Should -BeGreaterOrEqual $MinimumDiagnosticCount
    @($Result.rawBuildOutput).Count | Should -BeGreaterOrEqual 1
    $Result.manifestPath | Should -BeNullOrEmpty
    $Result.validationResult.manifestExists | Should -BeFalse

    foreach ($diagnostic in @($Result.buildDiagnostics)) {
        Assert-BuildDiagnostic -Diagnostic $diagnostic
    }
}

function Assert-BuildFailureRunResult {
    param(
        [Parameter(Mandatory = $true)]
        $Result,

        [string]$ExpectedPhase = 'launching',

        [int]$ExpectedDiagnosticCount = 1
    )

    Assert-BuildFailureResult -Result $Result -ExpectedPhase $ExpectedPhase -MinimumDiagnosticCount $ExpectedDiagnosticCount
    @($Result.buildDiagnostics).Count | Should -Be $ExpectedDiagnosticCount
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

function Assert-BuildDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Diagnostic,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedResourcePath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSourceKind
    )

    $Diagnostic.resourcePath | Should -Be $ExpectedResourcePath
    $Diagnostic.message | Should -Not -BeNullOrEmpty
    $Diagnostic.severity | Should -Be 'error'
    $Diagnostic.sourceKind | Should -Be $ExpectedSourceKind
    $Diagnostic.rawExcerpt | Should -Match ([regex]::Escape($ExpectedResourcePath))
}

function Assert-BuildFailureRunResult {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPhase,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedDiagnosticCount
    )

    $Result.finalStatus | Should -Be 'failed'
    $Result.failureKind | Should -Be 'build'
    $Result.buildFailurePhase | Should -Be $ExpectedPhase
    @($Result.buildDiagnostics).Count | Should -Be $ExpectedDiagnosticCount
    @($Result.rawBuildOutput).Count | Should -BeGreaterThan 0
    $Result.manifestPath | Should -BeNullOrEmpty
    $Result.validationResult.manifestExists | Should -BeFalse
}
