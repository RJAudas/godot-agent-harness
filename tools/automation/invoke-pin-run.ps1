<#
.SYNOPSIS
    Pin the most recent transient run under a stable agent-chosen name.

.DESCRIPTION
    invoke-pin-run.ps1 copies the current transient run (evidence-manifest,
    all manifest-referenced artifacts, run-result.json, lifecycle-status.json)
    into harness/automation/pinned/<PinName>/ so it survives future automatic
    cleanups. The copy is byte-identical to the transient state at pin time.

    Emits a lifecycle envelope (specs/009-evidence-lifecycle/contracts/
    lifecycle-envelope.schema.json) on stdout with operation = "pin".

    On success:  status = "success", plannedPaths[] lists every file copied.
    On collision: status = "failure", failureKind = "pin-name-collision"
                  unless -Force is supplied.
    On no manifest: status = "failure", failureKind = "pin-source-missing".

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the project whose transient zone to pin.

.PARAMETER PinName
    Agent-chosen stable identifier for the pin. Must match
    ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$.

.PARAMETER Force
    Overwrite an existing pin with the same name.

.PARAMETER DryRun
    Compute and emit plannedPaths[] without copying anything.

.EXAMPLE
    pwsh ./tools/automation/invoke-pin-run.ps1 `
        -ProjectRoot integration-testing/pong `
        -PinName bug-repro-jumpscare

    Pins the most recent run. Emits a lifecycle envelope with plannedPaths[].

.EXAMPLE
    pwsh ./tools/automation/invoke-pin-run.ps1 `
        -ProjectRoot integration-testing/pong `
        -PinName bug-repro-jumpscare `
        -DryRun

    Previews what would be copied without touching the filesystem.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Mandatory)]
    [string]$PinName,

    [switch]$Force,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'RunbookOrchestration.psm1'
Import-Module $modulePath -Force

$resolvedRoot = Resolve-RunbookRepoPath -Path $ProjectRoot

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    Write-LifecycleEnvelope -Status 'failed' -FailureKind $Kind -Operation 'pin' `
        -DryRun $DryRun.IsPresent -Diagnostics @($Message) -PlannedPaths @() -PinName $PinName
    Write-RunbookStderrSummary "FAIL: $Kind; $Message"
    exit 1
}

$copyResult = Copy-RunToPinnedZone -ProjectRoot $resolvedRoot -PinName $PinName `
    -Force:$Force -DryRun:$DryRun

if (-not $copyResult.Ok) {
    Exit-Failure $copyResult.FailureKind ($copyResult.Diagnostics | Select-Object -First 1)
}

$dryVerb = if ($DryRun) { 'DRY-RUN' } else { 'OK' }
$envelope = Write-LifecycleEnvelope -Status 'ok' -Operation 'pin' `
    -DryRun $DryRun.IsPresent -Diagnostics @() -PlannedPaths $copyResult.PlannedPaths -PinName $PinName
$envelope
Write-RunbookStderrSummary "${dryVerb}: pinned '$PinName'; $(@($copyResult.PlannedPaths).Count) files"
exit 0
