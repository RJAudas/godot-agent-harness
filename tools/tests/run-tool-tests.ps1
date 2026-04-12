[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
$testsRoot = Join-Path (Join-Path $repoRoot 'tools') 'tests'
$preferredTests = @(
    (Join-Path $testsRoot 'ScenegraphAutomationLoop.Tests.ps1')
)
$discoveredTests = Get-ChildItem -LiteralPath $testsRoot -Filter '*.Tests.ps1' -File |
    Where-Object { $_.FullName -notin $preferredTests } |
    Sort-Object Name |
    ForEach-Object { $_.FullName }
$testPath = @($preferredTests + $discoveredTests)
$pesterModule = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1

if ($null -eq $pesterModule) {
    throw 'Pester 5+ is required to run tools/tests. Install-Module Pester -Scope CurrentUser'
}

if ($pesterModule.Version.Major -lt 5) {
    throw "Pester 5+ is required to run tools/tests, but version $($pesterModule.Version) was selected."
}

Import-Module Pester -MinimumVersion 5.0.0 -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testPath
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0) {
    exit 1
}