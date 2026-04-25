<#
.SYNOPSIS
    Remove a named pinned run from harness/automation/pinned/.

.DESCRIPTION
    invoke-unpin-run.ps1 deletes the directory for a named pin, releasing the
    preserved evidence. Use -DryRun to preview which files would be removed
    without touching the filesystem.

    Emits a lifecycle envelope (specs/009-evidence-lifecycle/contracts/
    lifecycle-envelope.schema.json) on stdout with operation = "unpin".

    On success:   status = "ok", plannedPaths[] lists every file removed.
    On precondition refusal (pin not found, invalid pin name): status = "refused"
    with failureKind = "pin-target-not-found" / "pin-name-invalid".
    On -DryRun:   status = "ok", plannedPaths[] lists what would be removed;
                  no files are deleted.
    On unexpected I/O error: status = "failed" with failureKind = "io-error".

.PARAMETER ProjectRoot
    Repo-relative or absolute path to the project whose pinned zone to modify.

.PARAMETER PinName
    Name of the pin to remove. Must match ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$.

.PARAMETER DryRun
    Preview which files would be removed without deleting anything.

.EXAMPLE
    pwsh ./tools/automation/invoke-unpin-run.ps1 `
        -ProjectRoot integration-testing/pong `
        -PinName bug-repro-jumpscare

    Removes the named pin and emits a lifecycle envelope.

.EXAMPLE
    pwsh ./tools/automation/invoke-unpin-run.ps1 `
        -ProjectRoot integration-testing/pong `
        -PinName bug-repro-jumpscare `
        -DryRun

    Lists what would be removed without touching the filesystem.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Mandatory)]
    [string]$PinName,

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
    Write-LifecycleEnvelope -Status $status -FailureKind $Kind -Operation 'unpin' `
        -DryRun $DryRun.IsPresent -Diagnostics @($Message) -PlannedPaths @() -PinName $PinName
    $label = $status.ToUpperInvariant()
    Write-RunbookStderrSummary "${label}: $Kind; $Message"
    # Exit 0 for `refused` -- the script ran successfully and correctly declined a
    # precondition (e.g. pin-target-not-found). Exit 1 only for unexpected failures
    # the caller should investigate. Envelope `status` field is the authoritative
    # signal in either case.
    if ($status -eq 'refused') { exit 0 } else { exit 1 }
}

$removeResult = Remove-PinnedRun -ProjectRoot $resolvedRoot -PinName $PinName -DryRun:$DryRun

if (-not $removeResult.Ok) {
    Exit-Failure $removeResult.FailureKind ($removeResult.Diagnostics | Select-Object -First 1)
}

$dryVerb = if ($DryRun) { 'DRY-RUN' } else { 'OK' }
$envelope = Write-LifecycleEnvelope -Status 'ok' -Operation 'unpin' `
    -DryRun $DryRun.IsPresent -Diagnostics @() -PlannedPaths $removeResult.PlannedPaths -PinName $PinName
$envelope
Write-RunbookStderrSummary "${dryVerb}: unpinned '$PinName'; $(@($removeResult.PlannedPaths).Count) files"
exit 0
