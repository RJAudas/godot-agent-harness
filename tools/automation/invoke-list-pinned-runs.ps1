<#
.SYNOPSIS
    List all named pinned runs for a project.

.DESCRIPTION
    invoke-list-pinned-runs.ps1 walks harness/automation/pinned/*/pin-metadata.json
    and emits a lifecycle envelope (specs/009-evidence-lifecycle/contracts/
    lifecycle-envelope.schema.json) on stdout with operation = "list" and
    pinnedRunIndex[] populated.

    Each index entry includes: pinName, manifestPath (project-root-relative),
    scenarioId, runId, pinnedAt, status, sourceInvokeScript. Entries are sorted
    alphabetically by pinName. Pins without a pin-metadata.json are included with
    status = "unknown" (legacy-pin tolerance).

    Returns status = "success" even when the pinned zone is empty (pinnedRunIndex
    will be an empty array).

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the project to inspect.

.EXAMPLE
    pwsh ./tools/automation/invoke-list-pinned-runs.ps1 `
        -ProjectRoot ./integration-testing/probe

    Emits a lifecycle envelope with pinnedRunIndex[] listing every named pin.
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

$pinIndex = Get-PinnedRunIndex -ProjectRoot $resolvedRoot

$envelope = Write-LifecycleEnvelope -Status 'ok' -Operation 'list' `
    -DryRun $false -Diagnostics @() -PlannedPaths @() -PinnedRunIndex $pinIndex
$envelope
Write-RunbookStderrSummary "OK: $(@($pinIndex).Count) pin(s) found"
exit 0
