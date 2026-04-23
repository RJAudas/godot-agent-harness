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
    $stdoutTmp = [System.IO.Path]::GetTempFileName()
    $stderrTmp = [System.IO.Path]::GetTempFileName()
    try {
        $procArgs = @('-NoProfile', '-File', $resolvedScriptPath) + $Arguments
        $process = Start-Process -FilePath 'pwsh' -ArgumentList $procArgs `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutTmp `
            -RedirectStandardError $stderrTmp
        $exitCode = [int]$process.ExitCode

        $stdout = (Get-Content -LiteralPath $stdoutTmp -Raw)
        if ($null -eq $stdout) { $stdout = '' }
        $stderr = (Get-Content -LiteralPath $stderrTmp -Raw)
        if ($null -eq $stderr) { $stderr = '' }

        [pscustomobject]@{
            ExitCode = $exitCode
            Output = $stdout.Trim()
            Stderr = $stderr.Trim()
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutTmp -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrTmp -ErrorAction SilentlyContinue
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
    $Diagnostic.severity | Should -Be 'error'
    $Diagnostic.sourceKind | Should -BeIn @('script', 'scene', 'resource', 'unknown')
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'resourcePath'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'line'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'column'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'code'
    $Diagnostic.PSObject.Properties.Name | Should -Contain 'rawExcerpt'

    if ($PSBoundParameters.ContainsKey('ExpectedResourcePath')) {
        $Diagnostic.resourcePath | Should -Be $ExpectedResourcePath
        $Diagnostic.rawExcerpt | Should -Match ([regex]::Escape($ExpectedResourcePath))
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

function Read-RepoJsonLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return Get-Content -LiteralPath (Get-RepoPath -Path $Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $_ | ConvertFrom-Json -Depth 100
    }
}

function Assert-BehaviorWatchAppliedWatch {
    param(
        [Parameter(Mandatory = $true)]
        $AppliedWatch,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedRunId,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedNodePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedProperties,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMode,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedStartFrameOffset,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedFrameCount,

        [int]$ExpectedSampleCount = -1
    )

    $AppliedWatch.runId | Should -Be $ExpectedRunId
    $AppliedWatch.traceArtifact | Should -Be 'trace.jsonl'
    @($AppliedWatch.targets).Count | Should -Be 1
    $AppliedWatch.targets[0].nodePath | Should -Be $ExpectedNodePath
    @($AppliedWatch.targets[0].properties) | Should -Be $ExpectedProperties
    $AppliedWatch.cadence.mode | Should -Be $ExpectedMode
    $AppliedWatch.startFrameOffset | Should -Be $ExpectedStartFrameOffset
    $AppliedWatch.frameCount | Should -Be $ExpectedFrameCount

    if ($ExpectedMode -eq 'every_frame') {
        $AppliedWatch.cadence.everyNFrames | Should -BeNullOrEmpty
    }

    if ($ExpectedSampleCount -ge 0) {
        $AppliedWatch.outcomes.sampleCount | Should -Be $ExpectedSampleCount
        $AppliedWatch.outcomes.noSamples | Should -BeFalse
    }
}

function Assert-BehaviorWatchTraceRows {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedNodePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ExpectedProperties,

        [int[]]$ExpectedFrames = @()
    )

    @($Rows).Count | Should -BeGreaterThan 0
    $allowedKeys = @('frame', 'timestampMs', 'nodePath') + $ExpectedProperties

    foreach ($row in @($Rows)) {
        $row.nodePath | Should -Be $ExpectedNodePath
        foreach ($propertyName in $ExpectedProperties) {
            $row.PSObject.Properties.Name | Should -Contain $propertyName
        }
        foreach ($propertyName in $row.PSObject.Properties.Name) {
            $propertyName | Should -BeIn $allowedKeys
        }
    }

    if ($ExpectedFrames.Count -gt 0) {
        @($Rows | ForEach-Object { [int]$_.frame }) | Should -Be $ExpectedFrames
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
