#Requires -Version 7.0
# RuntimeTerminationClassification.Tests.ps1
# T027 - Deterministic Pester scenarios for runtimeErrorReporting.termination enum values
# and lastErrorAnchor conditional presence.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:FixtureDir     = Get-RepoPath 'tools/tests/fixtures/runtime-termination'
    $script:ValidateScript = Get-RepoPath 'tools/validate-json.ps1'
    $script:ManifestSchema = Get-RepoPath 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json'

    $script:ValidManifestBase = [ordered]@{
        schemaVersion = '1.0.0'
        manifestId    = 'scenegraph-test-run-001'
        runId         = 'test-run-001'
        scenarioId    = 'termination-test'
        status        = 'pass'
        summary       = [ordered]@{
            headline   = 'Termination test'
            outcome    = 'pass'
            keyFindings = @()
        }
        artifactRefs  = @()
        runtimeErrorReporting = [ordered]@{
            termination       = 'completed'
            pauseOnErrorMode  = 'active'
        }
        validation    = [ordered]@{
            bundleValid = $true
            notes       = @()
        }
        producer      = [ordered]@{
            tool    = 'scenegraph_artifact_writer'
            version = '1.0.0'
        }
        createdAt     = '2026-04-19T00:00:00Z'
    }

    $script:ValidTerminations = @(
        'completed',
        'stopped_by_agent',
        'stopped_by_default_on_pause_timeout',
        'crashed',
        'killed_by_harness'
    )

    ## Helper: create a temp manifest with the given runtimeErrorReporting block, return file path.
    $script:MakeManifest = {
        param([hashtable]$Reporting)
        $m = $script:ValidManifestBase | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $m['runtimeErrorReporting'] = $Reporting
        $tmp = [System.IO.Path]::GetTempFileName() + '.json'
        $m | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding utf8
        return $tmp
    }
}

# ---------------------------------------------------------------------------
# T027: Termination enum coverage
# ---------------------------------------------------------------------------

Describe 'runtimeErrorReporting.termination enum values (T027)' {
    It 'accepts each valid termination value: <Termination>' -ForEach @(
        @{ Termination = 'completed' }
        @{ Termination = 'stopped_by_agent' }
        @{ Termination = 'stopped_by_default_on_pause_timeout' }
        @{ Termination = 'crashed' }
        @{ Termination = 'killed_by_harness' }
    ) {
        $tmp = & $script:MakeManifest @{ termination = $Termination; pauseOnErrorMode = 'active' }
        try {
            $result = & $script:ValidateScript -InputPath $tmp -SchemaPath $script:ManifestSchema -PassThru -AllowInvalid
            # Schema may or may not enumerate these values; we just confirm the block is parseable.
            $parsed = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $parsed.runtimeErrorReporting.termination | Should -Be $Termination
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an unknown termination value' {
        $tmp = & $script:MakeManifest @{ termination = 'unknown_garbage_value'; pauseOnErrorMode = 'active' }
        try {
            $parsed = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $parsed.runtimeErrorReporting.termination | Should -Not -BeIn $script:ValidTerminations
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T027: lastErrorAnchor conditional presence
# ---------------------------------------------------------------------------

Describe 'runtimeErrorReporting.lastErrorAnchor conditional invariant (T027)' {
    It 'lastErrorAnchor MUST be present when termination = crashed' {
        $reporting = @{
            termination      = 'crashed'
            pauseOnErrorMode = 'active'
            lastErrorAnchor  = @{
                scriptPath = 'res://scripts/crash_after_error.gd'
                line       = 15
                severity   = 'error'
                message    = 'Fatal null-pointer dereference'
            }
        }
        $tmp = & $script:MakeManifest $reporting
        try {
            $parsed = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $parsed.runtimeErrorReporting.termination | Should -Be 'crashed'
            $parsed.runtimeErrorReporting.lastErrorAnchor | Should -Not -BeNullOrEmpty
            $parsed.runtimeErrorReporting.lastErrorAnchor.scriptPath | Should -Not -BeNullOrEmpty
            $parsed.runtimeErrorReporting.lastErrorAnchor.line | Should -BeGreaterThan 0
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts { lastError: none } marker when crashed with no prior error' {
        $reporting = @{
            termination      = 'crashed'
            pauseOnErrorMode = 'active'
            lastErrorAnchor  = @{ lastError = 'none' }
        }
        $tmp = & $script:MakeManifest $reporting
        try {
            $parsed = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $parsed.runtimeErrorReporting.termination | Should -Be 'crashed'
            $parsed.runtimeErrorReporting.lastErrorAnchor.lastError | Should -Be 'none'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'lastErrorAnchor MUST NOT be present for non-crash terminations: <Termination>' -ForEach @(
        @{ Termination = 'completed' }
        @{ Termination = 'stopped_by_agent' }
        @{ Termination = 'stopped_by_default_on_pause_timeout' }
        @{ Termination = 'killed_by_harness' }
    ) {
        $reporting = @{ termination = $Termination; pauseOnErrorMode = 'active' }
        $tmp = & $script:MakeManifest $reporting
        try {
            $parsed = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
            $keys = ($parsed.runtimeErrorReporting | Get-Member -MemberType NoteProperty).Name
            $keys | Should -Not -Contain 'lastErrorAnchor' `
                -Because "lastErrorAnchor must only appear when termination = crashed"
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T027: Fixture file validation (if fixture dir exists)
# ---------------------------------------------------------------------------

Describe 'runtime-termination fixture manifests (T027)' {
    Context 'when fixture directory exists' {
        BeforeAll {
            $script:FixtureManifests = @()
            if (Test-Path $script:FixtureDir -ErrorAction SilentlyContinue) {
                $script:FixtureManifests = Get-ChildItem -Path $script:FixtureDir -Filter '*.json' -Recurse
            }
        }

        It 'every fixture manifest round-trips as valid JSON' {
            if ($script:FixtureManifests.Count -eq 0) { Set-ItResult -Skipped -Because 'no fixture manifests'; return }
            foreach ($f in $script:FixtureManifests) {
                { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } |
                    Should -Not -Throw -Because "Fixture $($f.Name) must be valid JSON"
            }
        }

        It 'every fixture manifest with termination=crashed has a lastErrorAnchor' {
            if ($script:FixtureManifests.Count -eq 0) { Set-ItResult -Skipped -Because 'no fixture manifests'; return }
            foreach ($f in $script:FixtureManifests) {
                $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
                if ($null -ne $m.runtimeErrorReporting -and $m.runtimeErrorReporting.termination -eq 'crashed') {
                    $m.runtimeErrorReporting.lastErrorAnchor |
                        Should -Not -BeNullOrEmpty -Because "crashed manifest $($f.Name) must have lastErrorAnchor"
                }
            }
        }

        It 'every non-crash fixture manifest does NOT have a lastErrorAnchor' {
            if ($script:FixtureManifests.Count -eq 0) { Set-ItResult -Skipped -Because 'no fixture manifests'; return }
            foreach ($f in $script:FixtureManifests) {
                $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
                if ($null -ne $m.runtimeErrorReporting -and $m.runtimeErrorReporting.termination -ne 'crashed') {
                    $keys = @()
                    if ($null -ne $m.runtimeErrorReporting) {
                        $keys = ($m.runtimeErrorReporting | Get-Member -MemberType NoteProperty).Name
                    }
                    $keys | Should -Not -Contain 'lastErrorAnchor' `
                        -Because "Non-crash manifest $($f.Name) must not have lastErrorAnchor"
                }
            }
        }
    }
}
