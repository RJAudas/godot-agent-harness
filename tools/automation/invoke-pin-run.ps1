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

    On success:    status = "ok", plannedPaths[] lists every file copied.
    On precondition refusal (name collision without -Force, invalid pin name,
    or no manifest to pin): status = "refused" with failureKind set to
    "pin-name-collision" / "pin-name-invalid" / "pin-source-missing".
    On unexpected I/O error: status = "failed" with failureKind = "io-error"
    (or the underlying refusal kind when the helper surfaces one late).

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
        -ProjectRoot ./integration-testing/probe `
        -PinName bug-repro-jumpscare

    Pins the most recent run. Emits a lifecycle envelope with plannedPaths[].

.EXAMPLE
    pwsh ./tools/automation/invoke-pin-run.ps1 `
        -ProjectRoot ./integration-testing/probe `
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

$script:RefusalFailureKinds = @('pin-name-collision', 'pin-name-invalid', 'pin-source-missing', 'pin-target-not-found', 'run-in-progress')

function Exit-Failure {
    param([string]$Kind, [string]$Message)
    $status = if ($script:RefusalFailureKinds -contains $Kind) { 'refused' } else { 'failed' }
    Write-LifecycleEnvelope -Status $status -FailureKind $Kind -Operation 'pin' `
        -DryRun $DryRun.IsPresent -Diagnostics @($Message) -PlannedPaths @() -PinName $PinName
    $label = $status.ToUpperInvariant()
    Write-RunbookStderrSummary "${label}: $Kind; $Message"
    # Exit 0 for `refused` -- the script ran successfully and correctly declined a
    # precondition (e.g. pin-name-collision). Exit 1 only for unexpected failures
    # the caller should investigate. Envelope `status` field is the authoritative
    # signal in either case.
    if ($status -eq 'refused') { exit 0 } else { exit 1 }
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
