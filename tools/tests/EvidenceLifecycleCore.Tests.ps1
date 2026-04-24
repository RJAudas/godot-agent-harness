BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:ModulePath   = Join-Path $script:RepoRootPath 'tools/automation/RunbookOrchestration.psm1'

    Import-Module $script:ModulePath -Force
}

# ---------------------------------------------------------------------------
# T011-a: Get-RunZoneClassification returns expected map
# ---------------------------------------------------------------------------

Describe 'Get-RunZoneClassification' {
    It 'returns a non-empty hashtable' {
        $map = Get-RunZoneClassification
        $map | Should -Not -BeNullOrEmpty
        $map.GetType().Name | Should -BeIn @('Hashtable', 'OrderedDictionary')
    }

    It 'classifies .in-flight.json as marker' {
        $map = Get-RunZoneClassification
        $map['.in-flight.json'] | Should -Be 'marker'
    }

    It 'classifies run-result.json as transient' {
        $map = Get-RunZoneClassification
        $map['run-result.json'] | Should -Be 'transient'
    }

    It 'classifies lifecycle-status.json as transient' {
        $map = Get-RunZoneClassification
        $map['lifecycle-status.json'] | Should -Be 'transient'
    }

    It 'classifies evidence-manifest.json as transient' {
        $map = Get-RunZoneClassification
        $map['evidence-manifest.json'] | Should -Be 'transient'
    }

    It 'classifies *.expected.json as oracle' {
        $map = Get-RunZoneClassification
        $map['*.expected.json'] | Should -Be 'oracle'
    }

    It 'classifies trace.jsonl as transient' {
        $map = Get-RunZoneClassification
        $map['trace.jsonl'] | Should -Be 'transient'
    }
}

# ---------------------------------------------------------------------------
# T011-b: In-flight marker round-trip
# ---------------------------------------------------------------------------

Describe 'In-flight marker round-trip' {
    BeforeAll {
        $script:SandboxRoot = New-RepoSandboxDirectory
        $script:ResultsDir  = Join-Path $script:SandboxRoot 'harness/automation/results'
        New-Item -ItemType Directory -Path $script:ResultsDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:SandboxRoot) {
            Remove-Item -LiteralPath $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-RunbookInFlightMarker creates .in-flight.json with required fields' {
        $markerPath = New-RunbookInFlightMarker -ProjectRoot $script:SandboxRoot `
            -RequestId 'test-request-001' -InvokeScript 'invoke-input-dispatch.ps1'

        $markerPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $markerPath | Should -BeTrue

        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        $marker.schemaVersion  | Should -Be '1.0.0'
        $marker.requestId      | Should -Be 'test-request-001'
        $marker.invokeScript   | Should -Be 'invoke-input-dispatch.ps1'
        $marker.pid            | Should -BeGreaterThan 0
        $marker.hostname       | Should -Not -BeNullOrEmpty
        $marker.startedAt      | Should -Not -BeNullOrEmpty
    }

    It 'Assert-NoInFlightRun detects a live marker' {
        # Marker was written by the previous test
        $result = Assert-NoInFlightRun -ProjectRoot $script:SandboxRoot
        $result.Ok          | Should -BeFalse
        $result.FailureKind | Should -Be 'run-in-progress'
        $result.Diagnostics | Should -Not -BeNullOrEmpty
    }

    It 'Clear-RunbookInFlightMarker removes .in-flight.json' {
        Clear-RunbookInFlightMarker -ProjectRoot $script:SandboxRoot
        $markerPath = Join-Path $script:SandboxRoot 'harness/automation/results/.in-flight.json'
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }

    It 'Assert-NoInFlightRun returns Ok when no marker present' {
        $result = Assert-NoInFlightRun -ProjectRoot $script:SandboxRoot
        $result.Ok | Should -BeTrue
        $result.FailureKind | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# T011-c: Staleness detection on dead-PID fixtures
# ---------------------------------------------------------------------------

Describe 'Test-InFlightMarkerStaleness' {
    BeforeAll {
        $script:StaleSandbox = New-RepoSandboxDirectory
        $script:StaleResultsDir = Join-Path $script:StaleSandbox 'harness/automation/results'
        New-Item -ItemType Directory -Path $script:StaleResultsDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:StaleSandbox) {
            Remove-Item -LiteralPath $script:StaleSandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns Active=false Stale=false when no marker exists' {
        $result = Test-InFlightMarkerStaleness -ProjectRoot $script:StaleSandbox
        $result.Active | Should -BeFalse
        $result.Stale  | Should -BeFalse
        $result.Marker | Should -BeNullOrEmpty
    }

    It 'detects stale marker with dead PID' {
        $deadPid = 999999999  # astronomically unlikely to be a real PID
        $staleMarker = [ordered]@{
            schemaVersion = '1.0.0'
            requestId     = 'stale-request-001'
            invokeScript  = 'invoke-input-dispatch.ps1'
            pid           = $deadPid
            hostname      = 'DEADBOX'
            startedAt     = [DateTime]::UtcNow.AddSeconds(-300).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $markerPath = Join-Path $script:StaleResultsDir '.in-flight.json'
        $staleMarker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8

        $result = Test-InFlightMarkerStaleness -ProjectRoot $script:StaleSandbox -OrchestratorTimeoutSeconds 60
        $result.Active     | Should -BeFalse
        $result.Stale      | Should -BeTrue
        $result.Marker     | Should -Not -BeNullOrEmpty
        $result.Diagnostic | Should -Match 'stale'
    }

    It 'detects stale marker with old timestamp (even with valid-looking PID 1)' {
        $staleMarker = [ordered]@{
            schemaVersion = '1.0.0'
            requestId     = 'stale-request-002'
            invokeScript  = 'invoke-input-dispatch.ps1'
            pid           = 1
            hostname      = 'OLDBOX'
            startedAt     = [DateTime]::UtcNow.AddSeconds(-300).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $markerPath = Join-Path $script:StaleResultsDir '.in-flight.json'
        $staleMarker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8

        $result = Test-InFlightMarkerStaleness -ProjectRoot $script:StaleSandbox -OrchestratorTimeoutSeconds 60
        $result.Active | Should -BeFalse
        $result.Stale  | Should -BeTrue
    }

    It 'Assert-NoInFlightRun auto-recovers a stale marker and records diagnostic' {
        $deadPid = 999999998
        $staleMarker = [ordered]@{
            schemaVersion = '1.0.0'
            requestId     = 'stale-recovery-001'
            invokeScript  = 'invoke-input-dispatch.ps1'
            pid           = $deadPid
            hostname      = 'DEADBOX'
            startedAt     = [DateTime]::UtcNow.AddSeconds(-300).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $markerPath = Join-Path $script:StaleResultsDir '.in-flight.json'
        $staleMarker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8

        $result = Assert-NoInFlightRun -ProjectRoot $script:StaleSandbox -OrchestratorTimeoutSeconds 60
        $result.Ok              | Should -BeTrue
        $result.StaleDiagnostic | Should -Not -BeNullOrEmpty
        $result.StaleDiagnostic | Should -Match 'stale'

        # Marker should be deleted
        Test-Path -LiteralPath $markerPath | Should -BeFalse
    }
}

# ---------------------------------------------------------------------------
# T011-d: Initialize-RunbookTransientZone only deletes transient files
# ---------------------------------------------------------------------------

Describe 'Initialize-RunbookTransientZone' {
    BeforeAll {
        $script:CleanupSandbox = New-RepoSandboxDirectory
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:CleanupSandbox) {
            Remove-Item -LiteralPath $script:CleanupSandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'deletes transient files and leaves the in-flight marker intact' {
        $resultsDir  = Join-Path $script:CleanupSandbox 'harness/automation/results'
        $evidenceDir = Join-Path $script:CleanupSandbox 'evidence/automation/run-001'
        New-Item -ItemType Directory -Path $resultsDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

        # Seed transient files
        'data' | Set-Content -LiteralPath (Join-Path $resultsDir 'run-result.json')       -Encoding utf8
        'data' | Set-Content -LiteralPath (Join-Path $resultsDir 'lifecycle-status.json') -Encoding utf8
        'data' | Set-Content -LiteralPath (Join-Path $evidenceDir 'evidence-manifest.json') -Encoding utf8

        # Seed in-flight marker — must NOT be deleted
        $marker = @{ schemaVersion = '1.0.0'; requestId = 'x'; invokeScript = 'x.ps1'; pid = $PID; hostname = 'H'; startedAt = [DateTime]::UtcNow.ToString('o') }
        $marker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resultsDir '.in-flight.json') -Encoding utf8

        # Seed oracle file — must NOT be deleted
        'oracle' | Set-Content -LiteralPath (Join-Path $resultsDir 'run-result.success.expected.json') -Encoding utf8

        $cleanup = Initialize-RunbookTransientZone -ProjectRoot $script:CleanupSandbox

        $cleanup.Ok           | Should -BeTrue
        $cleanup.FailureKind  | Should -BeNullOrEmpty

        # Transient files should be gone
        Test-Path -LiteralPath (Join-Path $resultsDir 'run-result.json')       | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $resultsDir 'lifecycle-status.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $evidenceDir 'evidence-manifest.json') | Should -BeFalse

        # In-flight marker must survive
        Test-Path -LiteralPath (Join-Path $resultsDir '.in-flight.json') | Should -BeTrue

        # Oracle file must survive (it won't be in the transient dirs since it's a pester fixture path, but let's confirm)
        Test-Path -LiteralPath (Join-Path $resultsDir 'run-result.success.expected.json') | Should -BeTrue
    }

    It 'returns PlannedPaths describing deleted files' {
        $resultsDir = Join-Path $script:CleanupSandbox 'harness/automation/results'
        New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
        'data' | Set-Content -LiteralPath (Join-Path $resultsDir 'capability.json') -Encoding utf8

        $cleanup = Initialize-RunbookTransientZone -ProjectRoot $script:CleanupSandbox
        $cleanup.Ok | Should -BeTrue
        $deletedPaths = @($cleanup.PlannedPaths | Where-Object { $_.action -eq 'delete' })
        $deletedPaths.Count | Should -BeGreaterThan 0
    }

    It 'returns Ok when the transient zone is already empty' {
        $emptySandbox = New-RepoSandboxDirectory
        try {
            $cleanup = Initialize-RunbookTransientZone -ProjectRoot $emptySandbox
            $cleanup.Ok          | Should -BeTrue
            $cleanup.FailureKind | Should -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $emptySandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
