<#
.SYNOPSIS
    Shared orchestration helpers for all tools/automation/invoke-<workflow>.ps1 scripts.

.DESCRIPTION
    RunbookOrchestration.psm1 exports the five shared functions used by every
    invoke-*.ps1 script, plus the internal Invoke-Helper function that Pester
    tests can Mock to avoid needing a live Godot editor.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RunbookRepoRoot {
    <#
    .SYNOPSIS Returns the repository root path. #>
    return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
}

function Resolve-RunbookRepoPath {
    <#
    .SYNOPSIS Resolves a repo-relative or absolute path to an absolute path. #>
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path (Get-RunbookRepoRoot) $Path
}

# ---------------------------------------------------------------------------
# Internal helper indirection — mock this in Pester with:
#   Mock -CommandName 'Invoke-Helper' -ModuleName 'RunbookOrchestration' -MockWith { ... }
# ---------------------------------------------------------------------------
function Invoke-Helper {
    <#
    .SYNOPSIS Thin wrapper around external script invocations. Mockable in Pester. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][array]$ArgumentList
    )

    $resolvedScript = Resolve-RunbookRepoPath -Path $ScriptPath
    # Suppress all output (stdout+stderr) from helper scripts so it doesn't
    # pollute the envelope. Side effects (files written) are all that matter.
    $null = & pwsh -NoProfile -File $resolvedScript @ArgumentList 2>&1
    return $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Exported functions
# ---------------------------------------------------------------------------

function New-RunbookRequestId {
    <#
    .SYNOPSIS
        Generates a fresh request ID for a runbook orchestration invocation.

    .PARAMETER Workflow
        Short workflow name slug used in the ID (e.g. "input-dispatch").

    .OUTPUTS
        String of the form "runbook-<workflow>-<YYYYMMDDTHHmmssZ>-<short-rand>".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Workflow
    )

    $ts = (Get-Date -Format 'yyyyMMddTHHmmssZ').Replace('+', 'Z')
    $rand = ([System.Guid]::NewGuid().ToString('N').Substring(0, 6))
    return "runbook-$Workflow-$ts-$rand"
}

function Test-RunbookCapability {
    <#
    .SYNOPSIS
        Invokes get-editor-evidence-capability.ps1 and checks whether the
        resulting capability.json is fresh enough.

    .PARAMETER ProjectRoot
        Resolved absolute path to the integration-testing sandbox.

    .PARAMETER MaxAgeSeconds
        Maximum allowed age (in seconds) of capability.json mtime. Default 300.

    .OUTPUTS
        PSCustomObject: { Ok [bool], FailureKind [string|null], Diagnostic [string|null] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [int]$MaxAgeSeconds = 300
    )

    $capabilityScript = 'tools/automation/get-editor-evidence-capability.ps1'
    Invoke-Helper -ScriptPath $capabilityScript -ArgumentList @('-ProjectRoot', $ProjectRoot) | Out-Null

    $capabilityPath = Join-Path $ProjectRoot 'harness/automation/results/capability.json'
    if (-not (Test-Path -LiteralPath $capabilityPath)) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'editor-not-running'
            Diagnostic  = "capability.json not found at '$capabilityPath'. Launch the editor with: godot --editor --path $ProjectRoot"
        }
    }

    $ageSeconds = (Get-Date) - (Get-Item -LiteralPath $capabilityPath).LastWriteTime
    if ($ageSeconds.TotalSeconds -gt $MaxAgeSeconds) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'editor-not-running'
            Diagnostic  = "capability.json is $([int]$ageSeconds.TotalSeconds)s old (max $MaxAgeSeconds s). Re-launch the editor with: godot --editor --path $ProjectRoot"
        }
    }

    return [pscustomobject]@{
        Ok          = $true
        FailureKind = $null
        Diagnostic  = $null
    }
}

function Resolve-RunbookPayload {
    <#
    .SYNOPSIS
        Loads and materializes a request payload from a fixture file or inline JSON,
        overrides its requestId, writes it to a temp file, and returns the result.

    .PARAMETER FixturePath
        Repo-relative or absolute path to a fixture JSON. Mutually exclusive with InlineJson.

    .PARAMETER InlineJson
        Inline JSON string. Mutually exclusive with FixturePath.

    .PARAMETER RequestId
        The freshly generated requestId to inject into the payload.

    .PARAMETER ProjectRoot
        Resolved absolute project root path. Temp request file is written under
        <ProjectRoot>/harness/automation/requests/.

    .OUTPUTS
        PSCustomObject: { Payload [hashtable], TempRequestPath [string] }
        Throws on mutual-exclusion violation or parse error.
    #>
    [CmdletBinding()]
    param(
        [string]$FixturePath,
        [string]$InlineJson,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $hasFixture = $PSBoundParameters.ContainsKey('FixturePath') -and -not [string]::IsNullOrWhiteSpace($FixturePath)
    $hasInline  = $PSBoundParameters.ContainsKey('InlineJson') -and -not [string]::IsNullOrWhiteSpace($InlineJson)

    if ($hasFixture -and $hasInline) {
        throw [System.ArgumentException]::new('-RequestFixturePath and -RequestJson are mutually exclusive. Supply exactly one.')
    }
    if (-not $hasFixture -and -not $hasInline) {
        throw [System.ArgumentException]::new('Exactly one of -RequestFixturePath or -RequestJson must be supplied.')
    }

    $json = if ($hasFixture) {
        $resolved = Resolve-RunbookRepoPath -Path $FixturePath
        Get-Content -LiteralPath $resolved -Raw
    }
    else {
        $InlineJson
    }

    $payload = $json | ConvertFrom-Json -Depth 20 -AsHashtable
    $payload['requestId'] = $RequestId

    $requestsDir = Join-Path $ProjectRoot 'harness/automation/requests'
    if (-not (Test-Path -LiteralPath $requestsDir)) {
        New-Item -ItemType Directory -Path $requestsDir -Force | Out-Null
    }
    $tempPath = Join-Path $requestsDir "$RequestId.json"
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding utf8

    return [pscustomobject]@{
        Payload         = $payload
        TempRequestPath = $tempPath
    }
}

function Invoke-RunbookRequest {
    <#
    .SYNOPSIS
        Delivers a request to the editor broker, polls run-result.json until complete,
        and returns the parsed run result.

    .PARAMETER ProjectRoot
        Resolved absolute path to the integration-testing sandbox.

    .PARAMETER RequestPath
        Absolute path to the temp request file to deliver.

    .PARAMETER ExpectedRequestId
        The requestId that must appear in run-result.json to confirm round-trip freshness.

    .PARAMETER TimeoutSeconds
        Wall-clock budget before returning a timeout failure. Default 60.

    .PARAMETER PollIntervalMilliseconds
        Polling interval when reading run-result.json. Default 250.

    .OUTPUTS
        PSCustomObject: { Ok [bool], FailureKind [string|null], Diagnostic [string|null], RunResult [object|null] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][string]$ExpectedRequestId,
        [int]$TimeoutSeconds = 60,
        [int]$PollIntervalMilliseconds = 250
    )

    $requestScript = 'tools/automation/request-editor-evidence-run.ps1'
    Invoke-Helper -ScriptPath $requestScript -ArgumentList @('-ProjectRoot', $ProjectRoot, '-RequestPath', $RequestPath) | Out-Null

    $runResultPath = Join-Path $ProjectRoot 'harness/automation/results/run-result.json'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $PollIntervalMilliseconds

        if (-not (Test-Path -LiteralPath $runResultPath)) {
            continue
        }

        try {
            $runResult = Get-Content -LiteralPath $runResultPath -Raw | ConvertFrom-Json -Depth 20
        }
        catch {
            continue
        }

        if ($runResult.requestId -eq $ExpectedRequestId -and -not [string]::IsNullOrWhiteSpace($runResult.completedAt)) {
            return [pscustomobject]@{
                Ok          = $true
                FailureKind = $null
                Diagnostic  = $null
                RunResult   = $runResult
            }
        }
    }

    return [pscustomobject]@{
        Ok          = $false
        FailureKind = 'timeout'
        Diagnostic  = "Timed out after ${TimeoutSeconds}s waiting for requestId '$ExpectedRequestId' in run-result.json."
        RunResult   = $null
    }
}

function Write-RunbookEnvelope {
    <#
    .SYNOPSIS
        Emits the stable stdout JSON envelope for all invoke-*.ps1 scripts.

    .PARAMETER Status
        "success" or "failure".

    .PARAMETER FailureKind
        One of the harness failureKind values; null on success.

    .PARAMETER ManifestPath
        Absolute path to the evidence manifest; null when no manifest was produced.

    .PARAMETER RunId
        The run ID from the run-result, or the generated ID on early failure.

    .PARAMETER RequestId
        The freshly generated request ID for this invocation.

    .PARAMETER Diagnostics
        Zero or more diagnostic strings. Must be non-empty on failure.

    .PARAMETER Outcome
        Workflow-specific outcome hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('success', 'failure')][string]$Status,
        [string]$FailureKind,
        [string]$ManifestPath,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RequestId,
        [string[]]$Diagnostics = @(),
        [Parameter(Mandatory)][hashtable]$Outcome
    )

    $envelope = [ordered]@{
        status       = $Status
        failureKind  = if ($PSBoundParameters.ContainsKey('FailureKind')) { $FailureKind } else { $null }
        manifestPath = if ($PSBoundParameters.ContainsKey('ManifestPath') -and -not [string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath } else { $null }
        runId        = $RunId
        requestId    = $RequestId
        completedAt  = (Get-Date -Format 'o')
        diagnostics  = @($Diagnostics | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        outcome      = $Outcome
    }

    $envelope | ConvertTo-Json -Depth 20 -Compress:$false
}

Export-ModuleMember -Function @(
    'New-RunbookRequestId',
    'Test-RunbookCapability',
    'Resolve-RunbookPayload',
    'Invoke-RunbookRequest',
    'Write-RunbookEnvelope',
    'Invoke-Helper',
    'Get-RunbookRepoRoot',
    'Resolve-RunbookRepoPath'
)
