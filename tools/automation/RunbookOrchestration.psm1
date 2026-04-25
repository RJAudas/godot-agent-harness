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
    .SYNOPSIS
        Thin wrapper around external script invocations. Mockable in Pester.

    .DESCRIPTION
        Captures stderr/stdout so callers can include diagnostics on failure.
        Returns a PSCustomObject with ExitCode and CapturedOutput so callers
        can decide whether a non-zero exit is fatal (e.g. critical path) or
        tolerable (e.g. bootstrap capability probe that checks a file next). #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][array]$ArgumentList
    )

    $resolvedScript = Resolve-RunbookRepoPath -Path $ScriptPath
    $captured = & pwsh -NoProfile -File $resolvedScript @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    $capturedText = if ($null -ne $captured) {
        ($captured | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    } else {
        ''
    }

    # H1: strip ANSI CSI sequences. PowerShell 7 colors Write-Error output by default,
    # and that text gets embedded verbatim into the JSON envelope's diagnostics[].
    # Escapes break downstream JSON consumers and grep-friendly display.
    if (-not [string]::IsNullOrEmpty($capturedText)) {
        $capturedText = [regex]::Replace($capturedText, "`e\[[0-?]*[ -/]*[@-~]", '')
    }

    return [pscustomobject]@{
        ExitCode       = $exitCode
        CapturedOutput = $capturedText
    }
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

    $ts = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
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
    # The capability probe is tolerate-and-check: if the helper fails we still
    # fall through to the file-age check below, which produces the canonical
    # "editor-not-running" diagnostic.
    $null = Invoke-Helper -ScriptPath $capabilityScript -ArgumentList @('-ProjectRoot', $ProjectRoot)

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

    # Schema requires expectationFiles, but runbook fixtures typically omit it
    # because they declare their expectations via capturePolicy + outcome
    # artifacts. Default to empty so schema validation passes without forcing
    # every fixture to repeat the boilerplate.
    if (-not $payload.ContainsKey('expectationFiles')) {
        $payload['expectationFiles'] = @()
    }

    # Write to the canonical request path the editor broker watches. The addon
    # defaults (inspection-run-config.json -> automation.requestPath) point at
    # res://harness/automation/requests/run-request.json; a dynamic per-request
    # filename would never be picked up.
    $requestsDir = Join-Path $ProjectRoot 'harness/automation/requests'
    if (-not (Test-Path -LiteralPath $requestsDir)) {
        New-Item -ItemType Directory -Path $requestsDir -Force | Out-Null
    }
    $canonicalPath = Join-Path $requestsDir 'run-request.json'

    # C1: validate-then-rename. The editor broker watches $canonicalPath with
    # FileSystemWatcher and consumes (deletes) the file the moment it appears.
    # Previously the orchestrator wrote $canonicalPath and then asked the schema
    # validator to read it back -- but the broker had already moved/removed it,
    # so every successful run looked like failureKind=request-invalid. Fix: write
    # the JSON to <canonical>.tmp first, run schema validation against the temp
    # path (which the broker is not watching), and only on success atomic-rename
    # into place. The broker never sees an unvalidated file.
    $tmpPath = "$canonicalPath.tmp"
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmpPath -Encoding utf8

    $schemaPath = 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
    $validation = Invoke-Helper -ScriptPath 'tools/validate-json.ps1' -ArgumentList @(
        '-InputPath', $tmpPath,
        '-SchemaPath', $schemaPath,
        '-AllowInvalid'
    )
    try {
        if ($validation.ExitCode -ne 0) {
            throw "Schema validator could not run (exit $($validation.ExitCode)): $($validation.CapturedOutput)"
        }
        $parsedValidation = $validation.CapturedOutput | ConvertFrom-Json -Depth 20
        if (-not $parsedValidation.valid) {
            $errDetail = if ($null -ne $parsedValidation.PSObject.Properties['error']) { $parsedValidation.error } else { 'schema validation failed' }
            throw "Run request does not satisfy schema '$schemaPath': $errDetail"
        }
        Move-Item -LiteralPath $tmpPath -Destination $canonicalPath -Force
    }
    catch {
        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        throw
    }

    return [pscustomobject]@{
        Payload         = $payload
        TempRequestPath = $canonicalPath
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

    # NOTE: schema validation moved upstream into Resolve-RunbookPayload (and the
    # inline-write block in invoke-scene-inspection.ps1). The broker consumes the
    # canonical request the moment it appears, so by the time we get here the
    # file may already be gone. Validating after the broker has acted produced
    # spurious request-invalid envelopes for runs that completed cleanly.

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
        completedAt  = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        diagnostics  = @($Diagnostics | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        outcome      = $Outcome
    }

    $envelope | ConvertTo-Json -Depth 20 -Compress:$false
}

function Test-RunbookManifest {
    <#
    .SYNOPSIS
        Validate an evidence manifest at the given absolute path.

    .OUTPUTS
        PSCustomObject: { Ok [bool], Diagnostic [string|null] }. When Ok=$false,
        Diagnostic is a single-line summary suitable for inclusion in the
        envelope's diagnostics array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath
    )

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        return [pscustomobject]@{ Ok = $false; Diagnostic = 'manifestPath is null or empty' }
    }
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return [pscustomobject]@{ Ok = $false; Diagnostic = "manifest not found at '$ManifestPath'" }
    }

    $repoRoot = Get-RunbookRepoRoot
    $validator = Join-Path $repoRoot 'tools/evidence/validate-evidence-manifest.ps1'
    if (-not (Test-Path -LiteralPath $validator)) {
        return [pscustomobject]@{ Ok = $false; Diagnostic = "validate-evidence-manifest.ps1 not found at '$validator'" }
    }

    $stdoutTmp = [System.IO.Path]::GetTempFileName()
    $stderrTmp = [System.IO.Path]::GetTempFileName()
    try {
        $procArgs = @('-NoProfile', '-File', $validator, '-ManifestPath', $ManifestPath)
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList $procArgs `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutTmp `
            -RedirectStandardError $stderrTmp
        if ($proc.ExitCode -ne 0) {
            $errText = (Get-Content -LiteralPath $stderrTmp -Raw)
            if ([string]::IsNullOrWhiteSpace($errText)) {
                $errText = (Get-Content -LiteralPath $stdoutTmp -Raw)
            }
            $first = ($errText -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
            return [pscustomobject]@{ Ok = $false; Diagnostic = "manifest validation failed: $($first.Trim())" }
        }
        return [pscustomobject]@{ Ok = $true; Diagnostic = $null }
    }
    finally {
        Remove-Item -LiteralPath $stdoutTmp -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrTmp -ErrorAction SilentlyContinue
    }
}

function Write-RunbookStderrSummary {
    <#
    .SYNOPSIS
        Emit a single-line human-readable summary to stderr (does not affect
        the JSON envelope on stdout).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

# ---------------------------------------------------------------------------
# Evidence Lifecycle — Zone Classification (T004)
# ---------------------------------------------------------------------------

function Get-RunZoneClassification {
    <#
    .SYNOPSIS
        Returns the FR-001 zone classification table as a hashtable.

    .DESCRIPTION
        Keys are filename globs (matched case-insensitively). Values are one of:
        "transient", "editor-state", "pinned", "oracle", "input", or "marker".

        "transient"    files are cleared by Initialize-RunbookTransientZone.
        "editor-state" files (capability.json) are owned by the editor's
                       heartbeat loop and PRESERVED by cleanup — wiping them
                       creates a window where invoke scripts mis-report
                       editor-not-running.
        "marker"       (.in-flight.json) is transient but explicitly SKIPPED
                       by cleanup and cleared on orchestration exit.

    .OUTPUTS
        Hashtable of glob -> zone-enum string.
    #>
    [CmdletBinding()]
    param()

    return [ordered]@{
        '.in-flight.json'            = 'marker'
        'capability.json'            = 'editor-state'
        'lifecycle-status.json'      = 'transient'
        'run-result.json'            = 'transient'
        'run-request.json'           = 'transient'
        'evidence-manifest.json'     = 'transient'
        'trace.jsonl'                = 'transient'
        'scenegraph-snapshot.json'   = 'transient'
        'scenegraph-diagnostics.json' = 'transient'
        'scenegraph-summary.json'    = 'transient'
        'input-dispatch-outcomes.jsonl' = 'transient'
        'runtime-error-records.jsonl' = 'transient'
        'pause-decision-log.jsonl'   = 'transient'
        'last-error-anchor.json'     = 'transient'
        'build-errors.jsonl'         = 'transient'
        '*.expected.json'            = 'oracle'
    }
}

# ---------------------------------------------------------------------------
# Evidence Lifecycle — In-Flight Marker (T005)
# ---------------------------------------------------------------------------

function New-RunbookInFlightMarker {
    <#
    .SYNOPSIS
        Writes .in-flight.json into the transient zone before cleanup runs.

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .PARAMETER RequestId
        The GUID/request ID of the current orchestration call.

    .PARAMETER InvokeScript
        Basename of the calling invoke-*.ps1 script.

    .OUTPUTS
        Absolute path to the marker file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$InvokeScript
    )

    $resultsDir = Join-Path $ProjectRoot 'harness/automation/results'
    if (-not (Test-Path -LiteralPath $resultsDir)) {
        New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    }

    $markerPath = Join-Path $resultsDir '.in-flight.json'
    $marker = [ordered]@{
        schemaVersion = '1.0.0'
        requestId     = $RequestId
        invokeScript  = $InvokeScript
        pid           = $PID
        hostname      = $env:COMPUTERNAME
        startedAt     = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    $marker | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding utf8
    return $markerPath
}

function Clear-RunbookInFlightMarker {
    <#
    .SYNOPSIS
        Removes .in-flight.json from the transient zone. Called in try/finally.

    .PARAMETER ProjectRoot
        Absolute path to the target project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $markerPath = Join-Path $ProjectRoot 'harness/automation/results/.in-flight.json'
    if (Test-Path -LiteralPath $markerPath) {
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-InFlightMarkerStaleness {
    <#
    .SYNOPSIS
        Checks whether an existing .in-flight.json is stale (dead PID or old timestamp).

    .DESCRIPTION
        Returns a PSCustomObject with:
          Active [bool]      — true = live run in progress, false = stale/absent
          Stale  [bool]      — true = marker existed but was stale
          Marker [object]    — parsed marker content when present, else $null
          Diagnostic [string]

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .PARAMETER OrchestratorTimeoutSeconds
        The timeout horizon used by the orchestrator (default 60). Staleness is
        declared when startedAt is older than 2× this value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [int]$OrchestratorTimeoutSeconds = 60
    )

    $markerPath = Join-Path $ProjectRoot 'harness/automation/results/.in-flight.json'
    if (-not (Test-Path -LiteralPath $markerPath)) {
        return [pscustomobject]@{ Active = $false; Stale = $false; Marker = $null; Diagnostic = $null }
    }

    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json -Depth 10
    }
    catch {
        # Corrupt marker — treat as stale
        return [pscustomobject]@{
            Active     = $false
            Stale      = $true
            Marker     = $null
            Diagnostic = "Corrupt .in-flight.json (parse error); treating as stale and recovering."
        }
    }

    # Check PID liveness
    $pidAlive = $false
    try {
        $proc = Get-Process -Id $marker.pid -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            $name = $proc.ProcessName
            $pidAlive = ($name -eq 'pwsh' -or $name -eq 'powershell')
        }
    }
    catch { }

    # Check timestamp horizon
    $startedAt = [DateTime]::MinValue
    try { $startedAt = [DateTime]::Parse($marker.startedAt).ToUniversalTime() } catch { }
    $ageSeconds = ([DateTime]::UtcNow - $startedAt).TotalSeconds
    $horizonSeconds = 2 * $OrchestratorTimeoutSeconds
    $timestampStale = ($ageSeconds -gt $horizonSeconds)

    if ($pidAlive -and -not $timestampStale) {
        return [pscustomobject]@{
            Active     = $true
            Stale      = $false
            Marker     = $marker
            Diagnostic = "Run in progress: requestId=$($marker.requestId) pid=$($marker.pid) startedAt=$($marker.startedAt)"
        }
    }

    $reason = if (-not $pidAlive) { "PID $($marker.pid) is no longer a pwsh process" } else { "marker is $([int]$ageSeconds)s old (horizon ${horizonSeconds}s)" }
    return [pscustomobject]@{
        Active     = $false
        Stale      = $true
        Marker     = $marker
        Diagnostic = "Stale in-flight marker recovered ($reason). Prior requestId=$($marker.requestId)."
    }
}

function Assert-NoInFlightRun {
    <#
    .SYNOPSIS
        Fails fast if a live in-flight marker exists in the target project.

    .DESCRIPTION
        Returns a PSCustomObject:
          Ok         [bool]
          FailureKind [string|null]
          Diagnostics [string[]]
          StaleDiagnostic [string|null]   — set when a stale marker was auto-recovered
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [int]$OrchestratorTimeoutSeconds = 60
    )

    $check = Test-InFlightMarkerStaleness -ProjectRoot $ProjectRoot -OrchestratorTimeoutSeconds $OrchestratorTimeoutSeconds

    if ($check.Active) {
        return [pscustomobject]@{
            Ok           = $false
            FailureKind  = 'run-in-progress'
            Diagnostics  = @($check.Diagnostic)
            StaleDiagnostic = $null
        }
    }

    if ($check.Stale) {
        # Auto-recover: delete the stale marker
        $markerPath = Join-Path $ProjectRoot 'harness/automation/results/.in-flight.json'
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Ok           = $true
            FailureKind  = $null
            Diagnostics  = @()
            StaleDiagnostic = $check.Diagnostic
        }
    }

    return [pscustomobject]@{
        Ok           = $true
        FailureKind  = $null
        Diagnostics  = @()
        StaleDiagnostic = $null
    }
}

# ---------------------------------------------------------------------------
# Evidence Lifecycle — Transient Zone Cleanup (T006)
# ---------------------------------------------------------------------------

function Initialize-RunbookTransientZone {
    <#
    .SYNOPSIS
        Clears transient-zone files from a prior run in the target project.

    .DESCRIPTION
        Enumerates files classified as "transient" by Get-RunZoneClassification,
        deletes them one-by-one with a 50 ms retry on failure, and skips
        .in-flight.json explicitly. Partial cleanup surfaces into Diagnostics[]
        (FR-010 — never silent).

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .OUTPUTS
        PSCustomObject: { Ok [bool], FailureKind [string|null], Diagnostics [string[]], PlannedPaths [array] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $classification = Get-RunZoneClassification
    $diagnostics    = [System.Collections.Generic.List[string]]::new()
    $plannedPaths   = [System.Collections.Generic.List[hashtable]]::new()
    $blocked        = $false
    $blockedPath    = $null

    # Transient files live in two locations
    $transientDirs = @(
        (Join-Path $ProjectRoot 'harness/automation/results'),
        (Join-Path $ProjectRoot 'evidence/automation')
    )

    foreach ($dir in $transientDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        $files = Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $name = $file.Name
            $relPath = $file.FullName.Replace($ProjectRoot, '').TrimStart('\', '/')

            # Skip the in-flight marker
            if ($name -eq '.in-flight.json') { continue }

            # Determine zone
            $zone = $null
            foreach ($glob in $classification.Keys) {
                if ($name -like $glob) {
                    $zone = $classification[$glob]
                    break
                }
            }
            # Skip editor-owned state (heartbeated by the editor on its own cadence).
            # Wiping these creates a window where invoke scripts mis-report editor-not-running.
            if ($zone -eq 'editor-state') { continue }
            # Unmatched files in the transient directories are also cleared
            if ($null -eq $zone -or $zone -eq 'transient') {
                # Attempt delete with one retry
                $deleted = $false
                for ($attempt = 0; $attempt -lt 2; $attempt++) {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        $deleted = $true
                        break
                    }
                    catch {
                        if ($attempt -eq 0) { Start-Sleep -Milliseconds 50 }
                    }
                }

                if ($deleted) {
                    $plannedPaths.Add(@{ path = $relPath; action = 'delete' })
                }
                else {
                    $blocked    = $true
                    $blockedPath = $relPath
                    $diagnostics.Add("cleanup-blocked: could not delete '$relPath' after 2 attempts (file may be locked).")
                    $plannedPaths.Add(@{ path = $relPath; action = 'skip' })
                }
            }
        }

        # Also remove now-empty subdirectories (best effort)
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Recurse -Directory -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    $children = Get-ChildItem -LiteralPath $_.FullName -ErrorAction SilentlyContinue
                    if ($null -eq $children -or @($children).Count -eq 0) {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
        }
    }

    if ($blocked) {
        return [pscustomobject]@{
            Ok           = $false
            FailureKind  = 'cleanup-blocked'
            Diagnostics  = @($diagnostics)
            PlannedPaths = @($plannedPaths)
        }
    }

    return [pscustomobject]@{
        Ok           = $true
        FailureKind  = $null
        Diagnostics  = @($diagnostics)
        PlannedPaths = @($plannedPaths)
    }
}

# ---------------------------------------------------------------------------
# Evidence Lifecycle — Lifecycle Envelope Writer (T007)
# ---------------------------------------------------------------------------

function Write-LifecycleEnvelope {
    <#
    .SYNOPSIS
        Emits a lifecycle-envelope.schema.json-conformant JSON envelope on stdout.

    .PARAMETER Status
        "ok", "refused", or "failed".

    .PARAMETER Operation
        "cleanup", "pin", "unpin", or "list".

    .PARAMETER DryRun
        Whether this is a dry-run (no filesystem mutations occurred).

    .PARAMETER PlannedPaths
        Array of hashtables with "path" and "action" keys.

    .PARAMETER FailureKind
        One of the lifecycle failureKind values; null on success.

    .PARAMETER PinName
        Pin name for pin/unpin responses; null otherwise.

    .PARAMETER PinnedRunIndex
        Array of pin records for list responses; null otherwise.

    .PARAMETER Diagnostics
        Zero or more diagnostic strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ok', 'refused', 'failed')][string]$Status,
        [Parameter(Mandatory)][ValidateSet('cleanup', 'pin', 'unpin', 'list')][string]$Operation,
        [bool]$DryRun = $false,
        [array]$PlannedPaths = @(),
        [string]$FailureKind,
        [string]$PinName,
        [array]$PinnedRunIndex,
        [string[]]$Diagnostics = @()
    )

    $envelope = [ordered]@{
        status        = $Status
        failureKind   = if ($PSBoundParameters.ContainsKey('FailureKind')) { $FailureKind } else { $null }
        operation     = $Operation
        dryRun        = $DryRun
        plannedPaths  = @($PlannedPaths | Where-Object { $null -ne $_ })
        pinName       = if ($PSBoundParameters.ContainsKey('PinName')) { $PinName } else { $null }
        pinnedRunIndex = if ($PSBoundParameters.ContainsKey('PinnedRunIndex') -and $null -ne $PinnedRunIndex) { $PinnedRunIndex } else { $null }
        diagnostics   = @($Diagnostics | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        completedAt   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        manifestPath  = $null
    }

    $envelope | ConvertTo-Json -Depth 20 -Compress:$false
}

# ---------------------------------------------------------------------------
# Evidence Lifecycle — Pin / Unpin / List helpers (T031)
# ---------------------------------------------------------------------------

$script:PinNamePattern = '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'

function Copy-RunToPinnedZone {
    <#
    .SYNOPSIS
        Copies the current transient run to harness/automation/pinned/<PinName>/.

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .PARAMETER PinName
        Agent-chosen pin identifier (validated against pin-name regex).

    .PARAMETER Force
        Overwrite an existing pin with the same name.

    .PARAMETER DryRun
        If true, compute plannedPaths without copying anything.

    .OUTPUTS
        PSCustomObject: { Ok, FailureKind, Diagnostics, PlannedPaths }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$PinName,
        [switch]$Force,
        [switch]$DryRun
    )

    if ($PinName -notmatch $script:PinNamePattern) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-name-invalid'
            Diagnostics = @("Pin name '$PinName' is invalid. Must match ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$.")
            PlannedPaths = @()
        }
    }

    $pinRoot = Join-Path $ProjectRoot "harness/automation/pinned/$PinName"
    if ((Test-Path -LiteralPath $pinRoot) -and -not $Force) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-name-collision'
            Diagnostics = @("A pin named '$PinName' already exists. Use -Force to overwrite.")
            PlannedPaths = @()
        }
    }

    # Locate manifest in transient zone
    $evidenceRoot   = Join-Path $ProjectRoot 'evidence/automation'
    $resultsRoot    = Join-Path $ProjectRoot 'harness/automation/results'

    $manifestPath = $null
    if (Test-Path -LiteralPath $evidenceRoot) {
        $manifests = Get-ChildItem -LiteralPath $evidenceRoot -Recurse -Filter 'evidence-manifest.json' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($null -ne $manifests -and @($manifests).Count -gt 0) {
            $manifestPath = @($manifests)[0].FullName
        }
    }

    if ($null -eq $manifestPath) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-source-missing'
            Diagnostics = @("No evidence-manifest.json found in transient zone. Run a workflow before pinning.")
            PlannedPaths = @()
        }
    }

    # Parse manifest to find referenced artifacts + runId
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 20
    }
    catch {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-source-missing'
            Diagnostics = @("Could not parse evidence-manifest.json: $($_.Exception.Message)")
            PlannedPaths = @()
        }
    }

    $runId = if ($manifest.PSObject.Properties['runId']) { $manifest.runId } else { [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($manifestPath)) }
    $scenarioId = if ($manifest.PSObject.Properties['scenarioId']) { $manifest.scenarioId } else { 'unknown' }

    # Build list of source files to copy
    $sourceFiles = [System.Collections.Generic.List[hashtable]]::new()

    # evidence-manifest.json itself
    $sourceFiles.Add(@{
        Source = $manifestPath
        Dest   = Join-Path $pinRoot "evidence/$runId/evidence-manifest.json"
    })

    # artifact refs from manifest
    if ($manifest.PSObject.Properties['artifactRefs']) {
        foreach ($ref in $manifest.artifactRefs) {
            if ($null -ne $ref.path) {
                $absArtifact = if ([System.IO.Path]::IsPathRooted($ref.path)) { $ref.path } else { Join-Path $ProjectRoot $ref.path }
                if (Test-Path -LiteralPath $absArtifact) {
                    $artifactName = [System.IO.Path]::GetFileName($absArtifact)
                    $sourceFiles.Add(@{
                        Source = $absArtifact
                        Dest   = Join-Path $pinRoot "evidence/$runId/$artifactName"
                    })
                }
            }
        }
    }

    # run-result.json and lifecycle-status.json from results/
    foreach ($resultFile in @('run-result.json', 'lifecycle-status.json')) {
        $src = Join-Path $resultsRoot $resultFile
        if (Test-Path -LiteralPath $src) {
            $sourceFiles.Add(@{
                Source = $src
                Dest   = Join-Path $pinRoot "results/$resultFile"
            })
        }
    }

    # Compute planned paths (project-root-relative)
    $plannedPaths = @($sourceFiles | ForEach-Object {
        @{ path = $_.Dest.Replace($ProjectRoot, '').TrimStart('\', '/'); action = 'copy' }
    })
    $metaRelPath = "harness/automation/pinned/$PinName/pin-metadata.json"
    $plannedPaths += @{ path = $metaRelPath; action = 'create' }

    if ($DryRun) {
        return [pscustomobject]@{
            Ok           = $true
            FailureKind  = $null
            Diagnostics  = @()
            PlannedPaths = $plannedPaths
        }
    }

    # Get status from run-result.json
    $runStatus = 'unknown'
    $runResultPath = Join-Path $resultsRoot 'run-result.json'
    if (Test-Path -LiteralPath $runResultPath) {
        try {
            $rr = Get-Content -LiteralPath $runResultPath -Raw | ConvertFrom-Json -Depth 10
            if ($rr.PSObject.Properties['finalStatus']) {
                $raw = [string]$rr.finalStatus
                $runStatus = switch ($raw) {
                    'completed' { 'pass' }
                    'failed'    { 'fail' }
                    default     { 'unknown' }
                }
            }
        }
        catch { }
    }

    # Perform the copy (overwrite if -Force)
    if ((Test-Path -LiteralPath $pinRoot) -and $Force) {
        Remove-Item -LiteralPath $pinRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($entry in $sourceFiles) {
        $destDir = [System.IO.Path]::GetDirectoryName($entry.Dest)
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $entry.Source -Destination $entry.Dest -Force
    }

    # Write pin-metadata.json
    $invokeScript = $null
    $markerPath = Join-Path $resultsRoot '.in-flight.json'
    # marker is already cleared by now; check run-result instead
    $invokeScript = $null

    $pinMeta = [ordered]@{
        schemaVersion   = '1.0.0'
        pinName         = $PinName
        pinnedAt        = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        sourceRunId     = $runId
        sourceScenarioId = $scenarioId
        status          = $runStatus
    }
    $metaPath = Join-Path $pinRoot 'pin-metadata.json'
    $pinMeta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metaPath -Encoding utf8

    return [pscustomobject]@{
        Ok           = $true
        FailureKind  = $null
        Diagnostics  = @()
        PlannedPaths = $plannedPaths
    }
}

function Remove-PinnedRun {
    <#
    .SYNOPSIS
        Removes a named pin from the pinned zone.

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .PARAMETER PinName
        Name of the pin to remove.

    .PARAMETER DryRun
        If true, compute plannedPaths without deleting anything.

    .OUTPUTS
        PSCustomObject: { Ok, FailureKind, Diagnostics, PlannedPaths }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$PinName,
        [switch]$DryRun
    )

    if ($PinName -notmatch $script:PinNamePattern) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-name-invalid'
            Diagnostics = @("Pin name '$PinName' is invalid.")
            PlannedPaths = @()
        }
    }

    $pinRoot = Join-Path $ProjectRoot "harness/automation/pinned/$PinName"
    if (-not (Test-Path -LiteralPath $pinRoot)) {
        return [pscustomobject]@{
            Ok          = $false
            FailureKind = 'pin-target-not-found'
            Diagnostics = @("No pin named '$PinName' found at '$pinRoot'.")
            PlannedPaths = @()
        }
    }

    $files = Get-ChildItem -LiteralPath $pinRoot -Recurse -File -ErrorAction SilentlyContinue
    $plannedPaths = @($files | ForEach-Object {
        @{ path = $_.FullName.Replace($ProjectRoot, '').TrimStart('\', '/'); action = 'delete' }
    })

    if ($DryRun) {
        return [pscustomobject]@{
            Ok           = $true
            FailureKind  = $null
            Diagnostics  = @()
            PlannedPaths = $plannedPaths
        }
    }

    Remove-Item -LiteralPath $pinRoot -Recurse -Force
    return [pscustomobject]@{
        Ok           = $true
        FailureKind  = $null
        Diagnostics  = @()
        PlannedPaths = $plannedPaths
    }
}

function Get-PinnedRunIndex {
    <#
    .SYNOPSIS
        Returns a pinned-run index array by walking harness/automation/pinned/*/pin-metadata.json.

    .PARAMETER ProjectRoot
        Absolute path to the target project.

    .OUTPUTS
        Array of pin-record hashtables sorted alphabetically by pinName.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $pinnedRoot = Join-Path $ProjectRoot 'harness/automation/pinned'
    $records    = [System.Collections.Generic.List[object]]::new()

    if (-not (Test-Path -LiteralPath $pinnedRoot)) {
        return @()
    }

    $pinDirs = Get-ChildItem -LiteralPath $pinnedRoot -Directory -ErrorAction SilentlyContinue
    foreach ($pinDir in $pinDirs) {
        $metaPath = Join-Path $pinDir.FullName 'pin-metadata.json'
        if (-not (Test-Path -LiteralPath $metaPath)) {
            $records.Add([ordered]@{
                pinName           = $pinDir.Name
                manifestPath      = $null
                scenarioId        = 'unknown'
                runId             = 'unknown'
                pinnedAt          = $null
                status            = 'unknown'
                sourceInvokeScript = $null
            })
            continue
        }

        try {
            $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json -Depth 10
        }
        catch {
            $records.Add([ordered]@{
                pinName           = $pinDir.Name
                manifestPath      = $null
                scenarioId        = 'unknown'
                runId             = 'unknown'
                pinnedAt          = $null
                status            = 'unknown'
                sourceInvokeScript = $null
            })
            continue
        }

        $runId    = if ($meta.PSObject.Properties['sourceRunId']) { $meta.sourceRunId } else { 'unknown' }
        $scenario = if ($meta.PSObject.Properties['sourceScenarioId']) { $meta.sourceScenarioId } else { 'unknown' }
        $pinnedAt = if ($meta.PSObject.Properties['pinnedAt']) { $meta.pinnedAt } else { $null }
        $status   = if ($meta.PSObject.Properties['status']) { $meta.status } else { 'unknown' }
        $invokeScript = if ($meta.PSObject.Properties['sourceInvokeScript']) { $meta.sourceInvokeScript } else { $null }

        $manifestRelPath = "harness/automation/pinned/$($pinDir.Name)/evidence/$runId/evidence-manifest.json"
        $manifestAbsPath = Join-Path $ProjectRoot $manifestRelPath
        $resolvedManifest = if (Test-Path -LiteralPath $manifestAbsPath) { $manifestRelPath } else { $null }

        $records.Add([ordered]@{
            pinName           = $pinDir.Name
            manifestPath      = $resolvedManifest
            scenarioId        = $scenario
            runId             = $runId
            pinnedAt          = $pinnedAt
            status            = $status
            sourceInvokeScript = $invokeScript
        })
    }

    return @($records | Sort-Object { $_['pinName'] })
}

Export-ModuleMember -Function @(
    'New-RunbookRequestId',
    'Test-RunbookCapability',
    'Resolve-RunbookPayload',
    'Invoke-RunbookRequest',
    'Write-RunbookEnvelope',
    'Write-LifecycleEnvelope',
    'Test-RunbookManifest',
    'Write-RunbookStderrSummary',
    'Invoke-Helper',
    'Get-RunbookRepoRoot',
    'Resolve-RunbookRepoPath',
    'Get-RunZoneClassification',
    'New-RunbookInFlightMarker',
    'Clear-RunbookInFlightMarker',
    'Test-InFlightMarkerStaleness',
    'Assert-NoInFlightRun',
    'Initialize-RunbookTransientZone',
    'Copy-RunToPinnedZone',
    'Remove-PinnedRun',
    'Get-PinnedRunIndex'
)
