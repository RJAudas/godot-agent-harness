#Requires -Version 7.0
# RuntimeErrorReadyCapture.Tests.ps1
#
# B10 (pass 6b) — Pester unit tests for the runtime-error-triage outcome
# projection extracted into Get-RunbookRuntimeErrorOutcome. Pre-fix, the
# orchestrator's projection was inlined into invoke-runtime-error-triage.ps1
# and indirectly tested only through full live-editor runs. This suite
# fences the projection contract end-to-end without spawning an editor.
#
# The full _ready-time runtime-error capture path requires a live editor
# and is verified manually (see prd/06b-runtime-semantic-correctness.md
# verification section).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module (Get-RepoPath -Path 'tools/automation/RunbookOrchestration.psm1') -Force

    $script:NewSandbox = {
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("b10-projection-" + [System.Guid]::NewGuid().ToString('N'))
        $artifactDir = Join-Path $sandbox 'evidence/run-001'
        New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
        return [pscustomobject]@{
            Root        = $sandbox
            ArtifactDir = $artifactDir
            ManifestPath = Join-Path $artifactDir 'evidence-manifest.json'
            JsonlPath    = Join-Path $artifactDir 'runtime-error-records.jsonl'
        }
    }

    $script:WriteManifest = {
        param([string]$Path, [bool]$WithRuntimeErrorRecords = $true, [string]$Termination = 'completed')
        $artifactRefs = @(
            [ordered]@{
                kind = 'scenegraph-snapshot'
                path = 'evidence/run-001/scenegraph-snapshot.json'
                mediaType = 'application/json'
                description = 'Latest scenegraph snapshot for the session.'
            }
        )
        if ($WithRuntimeErrorRecords) {
            $artifactRefs += [ordered]@{
                kind = 'runtime-error-records'
                path = 'evidence/run-001/runtime-error-records.jsonl'
                mediaType = 'application/jsonl'
                description = 'Deduplicated runtime error and warning records captured after the runtime harness attaches.'
            }
        }
        $manifest = [ordered]@{
            schemaVersion = '1.0.0'
            manifestId = 'scenegraph-b10-projection-test'
            runId = 'b10-projection-test'
            scenarioId = 'b10-projection-test-scenario'
            status = 'unknown'
            summary = [ordered]@{ headline = 'Projection test fixture.'; outcome = 'unknown'; keyFindings = @() }
            artifactRefs = $artifactRefs
            runtimeErrorReporting = [ordered]@{
                runtimeErrorRecordsArtifact = 'evidence/run-001/runtime-error-records.jsonl'
                pauseOnErrorMode = 'active'
                termination = $Termination
            }
            validation = [ordered]@{ bundleValid = $true; notes = @() }
            producer = [ordered]@{ surface = 'scenegraph_harness_runtime'; toolingArtifactId = 'scenegraph_automation_broker' }
            createdAt = '2026-04-25T00:00:00Z'
        }
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
    }

    $script:WriteJsonl = {
        param([string]$Path, [array]$Records)
        if ($Records.Count -eq 0) {
            Set-Content -LiteralPath $Path -Value '' -Encoding utf8 -NoNewline
            return
        }
        $lines = $Records | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }
        Set-Content -LiteralPath $Path -Value ($lines -join "`n") -Encoding utf8
    }

    $script:NewErrorRecord = {
        param(
            [string]$ScriptPath = 'res://scripts/error_main.gd',
            [int]$Line = 4,
            [string]$Message = "Attempt to call function 'get_name' in base 'null instance' on a null instance",
            [int]$Ordinal = 1
        )
        return [ordered]@{
            runId       = 'b10-projection-test'
            ordinal     = $Ordinal
            scriptPath  = $ScriptPath
            line        = $Line
            'function'  = '_ready'
            message     = $Message
            severity    = 'error'
            firstSeenAt = '2026-04-25T00:00:00Z'
            lastSeenAt  = '2026-04-25T00:00:00Z'
            repeatCount = 1
        }
    }
}

Describe 'B10: Get-RunbookRuntimeErrorOutcome projection contract' {

    Context 'manifest absent or empty path' {
        It 'returns null path / null summary / completed termination when ManifestPath is empty' {
            $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath '' -ProjectRoot ([System.IO.Path]::GetTempPath())
            $outcome.runtimeErrorRecordsPath | Should -BeNullOrEmpty
            $outcome.latestErrorSummary | Should -BeNullOrEmpty
            $outcome.terminationReason | Should -Be 'completed'
        }

        It 'returns the same defaults when ManifestPath does not exist on disk' {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N') + '.json')
            $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $missing -ProjectRoot ([System.IO.Path]::GetTempPath())
            $outcome.runtimeErrorRecordsPath | Should -BeNullOrEmpty
            $outcome.latestErrorSummary | Should -BeNullOrEmpty
            $outcome.terminationReason | Should -Be 'completed'
        }
    }

    Context 'manifest present but no runtime-error-records artifactRef (pre-B10 shape)' {
        It 'returns null records path and null summary, but propagates termination' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $false -Termination 'crashed'
                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.runtimeErrorRecordsPath | Should -BeNullOrEmpty -Because "no artifactRef of kind runtime-error-records means no path to project"
                $outcome.latestErrorSummary | Should -BeNullOrEmpty
                $outcome.terminationReason | Should -Be 'crashed'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'B10: manifest with always-emitted artifactRef and EMPTY records file' {
        It 'returns the records path but null latestErrorSummary' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @()

                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.runtimeErrorRecordsPath | Should -Not -BeNullOrEmpty -Because "B10 always emits the artifactRef so consumers can verify the pipeline ran"
                Test-Path -LiteralPath $outcome.runtimeErrorRecordsPath | Should -BeTrue
                $outcome.latestErrorSummary | Should -BeNullOrEmpty -Because "an empty JSONL means no errors fired"
                $outcome.terminationReason | Should -Be 'completed'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'B10: manifest with single runtime-error record (canonical _ready-time deref)' {
        It 'projects file/line/message into latestErrorSummary' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true
                $rec = & $script:NewErrorRecord
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @($rec)

                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.runtimeErrorRecordsPath | Should -Not -BeNullOrEmpty
                $outcome.latestErrorSummary | Should -Not -BeNullOrEmpty
                $outcome.latestErrorSummary.file | Should -Be 'res://scripts/error_main.gd'
                $outcome.latestErrorSummary.line | Should -Be 4
                $outcome.latestErrorSummary.message | Should -Match 'get_name'
                $outcome.terminationReason | Should -Be 'completed'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'returns the LAST record when JSONL has multiple rows (most recent error)' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true
                $first  = & $script:NewErrorRecord -ScriptPath 'res://scripts/early.gd' -Line 7 -Message 'first error' -Ordinal 1
                $second = & $script:NewErrorRecord -ScriptPath 'res://scripts/late.gd'  -Line 99 -Message 'late error'  -Ordinal 2
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @($first, $second)

                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.latestErrorSummary.file | Should -Be 'res://scripts/late.gd' -Because "last record is most recent"
                $outcome.latestErrorSummary.line | Should -Be 99
                $outcome.latestErrorSummary.message | Should -Be 'late error'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'IncludeFullStack switch' {
        It 'appends stackTrace to message when -IncludeFullStack is set and stackTrace is present' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true
                $rec = & $script:NewErrorRecord
                $rec['stackTrace'] = "  at _ready (error_main.gd:4)`n  at <anonymous>"
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @($rec)

                $outcomeNoStack = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcomeNoStack.latestErrorSummary.message | Should -Not -Match 'at _ready'

                $outcomeFull = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root -IncludeFullStack
                $outcomeFull.latestErrorSummary.message | Should -Match 'get_name'
                $outcomeFull.latestErrorSummary.message | Should -Match 'at _ready'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'malformed records JSONL' {
        It 'returns null latestErrorSummary when the last line is not valid JSON' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true
                Set-Content -LiteralPath $sb.JsonlPath -Value 'not-json' -Encoding utf8
                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.runtimeErrorRecordsPath | Should -Not -BeNullOrEmpty
                $outcome.latestErrorSummary | Should -BeNullOrEmpty -Because "garbage line should not poison the envelope"
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'B10/B17 (pass 7a): orchestrator elevation contract' {
        # invoke-runtime-error-triage.ps1 elevates to status=failure /
        # failureKind=runtime when latestErrorSummary is non-null, regardless
        # of rr.finalStatus. This Context locks in the projection contract
        # the elevation reads:
        #   - terminationReason="completed" + JSONL with at least one record
        #     MUST yield a non-null latestErrorSummary so the orchestrator
        #     elevates and exits 1 with failureKind=runtime.
        # The full elevation behavior is verified by the live-editor pass-7
        # matrix re-run; this test prevents the projection from regressing
        # to "$null when terminationReason=completed" which would silently
        # disable the elevation.
        It 'projection emits non-null latestErrorSummary even when termination=completed' {
            $sb = & $script:NewSandbox
            try {
                # Mirrors the post-7a coordinator state on a _ready-time crash:
                # broker writes finalStatus=completed (the playtest exited via
                # the harness's deferred-stop path), but the JSONL has the
                # error record the coordinator persisted via the new choke point.
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true -Termination 'completed'
                $rec = & $script:NewErrorRecord
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @($rec)

                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.terminationReason | Should -Be 'completed' -Because "the broker finalized as completed; the elevation must rely on latestErrorSummary, not terminationReason"
                $outcome.latestErrorSummary | Should -Not -BeNullOrEmpty -Because "the orchestrator's elevation conditions on latestErrorSummary being non-null"
                $outcome.latestErrorSummary.file | Should -Be 'res://scripts/error_main.gd'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'B10 (pass 8a): matrix-6c JSONL shape produced by the runtime OS Logger' {
        # Locks in the projection for the exact JSONL shape the post-pass-8a
        # runtime emits via _RuntimeErrorLogger -> _record_runtime_error_from_logger
        # -> _append_runtime_error_record_to_disk. The capture path is verified
        # live against integration-testing/probe (matrix row 6c); this test
        # fences the projection-side contract so a regression in
        # Get-RunbookRuntimeErrorOutcome's parsing of the on-disk row would
        # turn a real failure back into a silent success.
        It 'projects the exact Logger-captured _ready null-deref into latestErrorSummary' {
            $sb = & $script:NewSandbox
            try {
                & $script:WriteManifest -Path $sb.ManifestPath -WithRuntimeErrorRecords $true -Termination 'completed'
                # Shape mirrors what _record_runtime_error_from_logger writes:
                # function=null (the engine Logger callback does not provide one),
                # line is an integer (artifact writer's read-merge normalizes
                # JSON-reparsed floats back to int), message is the engine's
                # "Cannot call method 'X' on a null value." text.
                $row = [ordered]@{
                    runId       = 'b10-projection-test'
                    ordinal     = 1
                    scriptPath  = 'res://scripts/broken.gd'
                    line        = 4
                    'function'  = $null
                    message     = "Cannot call method 'get_name' on a null value."
                    severity    = 'error'
                    firstSeenAt = '2026-04-26T19:01:47Z'
                    lastSeenAt  = '2026-04-26T19:01:47Z'
                    repeatCount = 1
                }
                & $script:WriteJsonl -Path $sb.JsonlPath -Records @($row)

                $outcome = Get-RunbookRuntimeErrorOutcome -ManifestPath $sb.ManifestPath -ProjectRoot $sb.Root
                $outcome.latestErrorSummary | Should -Not -BeNullOrEmpty
                $outcome.latestErrorSummary.file | Should -Be 'res://scripts/broken.gd'
                $outcome.latestErrorSummary.line | Should -Be 4
                $outcome.latestErrorSummary.message | Should -Match 'null'
            }
            finally { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
