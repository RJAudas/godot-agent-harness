BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:ModulePath   = Join-Path $script:RepoRootPath 'tools/automation/RunbookOrchestration.psm1'

    Import-Module $script:ModulePath -Force
}

Describe 'Initialize-RunbookTransientZone (Pass 3 hardening)' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('zone-' + [guid]::NewGuid().Guid)
        $script:RequestsDir = Join-Path $script:Root 'harness/automation/requests'
        $script:ResultsDir  = Join-Path $script:Root 'harness/automation/results'
        $script:EvidenceDir = Join-Path $script:Root 'evidence/automation'
        New-Item -ItemType Directory -Path $script:RequestsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:ResultsDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:EvidenceDir -Force | Out-Null
    }

    It 'M1: deletes a stale run-request.json from harness/automation/requests' {
        $stale = Join-Path $script:RequestsDir 'run-request.json'
        '{"requestId":"stale-001","scenarioId":"x","runId":"r","targetScene":"res://x.tscn"}' |
            Set-Content -LiteralPath $stale -Encoding utf8

        $result = Initialize-RunbookTransientZone -ProjectRoot $script:Root

        $result.Ok | Should -BeTrue
        Test-Path -LiteralPath $stale | Should -BeFalse

        # The deletion should be recorded in PlannedPaths so the diagnostic
        # surface explains what cleanup did rather than silently mutating disk.
        $deletePaths = @($result.PlannedPaths | Where-Object { $_.action -eq 'delete' } | ForEach-Object { $_.path })
        ($deletePaths | Where-Object { $_ -match 'run-request\.json$' }) | Should -Not -BeNullOrEmpty
    }

    It 'M1: also sweeps a leftover run-request.json.tmp from a crashed atomic rename' {
        # Pass 1's C1 fix uses validate-then-rename: write <canonical>.tmp,
        # validate, then Move-Item. If the orchestrator crashes between write
        # and rename, the .tmp leaks into the requests dir. M1 cleanup must
        # sweep these too (they fall through the unclassified-fallback branch).
        $leftover = Join-Path $script:RequestsDir 'run-request.json.tmp'
        '{"partial":"crash"}' | Set-Content -LiteralPath $leftover -Encoding utf8

        $result = Initialize-RunbookTransientZone -ProjectRoot $script:Root

        $result.Ok | Should -BeTrue
        Test-Path -LiteralPath $leftover | Should -BeFalse
    }

    It 'M4: emits a cleanup-unclassified diagnostic when deleting an unknown file' {
        # Drop a file the classification table doesn't know about. It still
        # gets deleted (otherwise unknown junk accumulates), but the diagnostic
        # is what tells a future developer that their new artifact kind needs
        # to be added to Get-RunZoneClassification.
        $mystery = Join-Path $script:ResultsDir 'mystery.dat'
        'unknown payload' | Set-Content -LiteralPath $mystery -Encoding utf8

        $result = Initialize-RunbookTransientZone -ProjectRoot $script:Root

        $result.Ok | Should -BeTrue
        Test-Path -LiteralPath $mystery | Should -BeFalse

        $unclassified = @($result.Diagnostics | Where-Object { $_ -match 'cleanup-unclassified' })
        $unclassified | Should -Not -BeNullOrEmpty
        $unclassified[0] | Should -Match 'mystery\.dat'
        $unclassified[0] | Should -Match 'Get-RunZoneClassification'
    }

    It 'M4: classified transient files are deleted WITHOUT the cleanup-unclassified diagnostic' {
        # Negative control. run-result.json is in the classification table as
        # transient, so it should be deleted but NOT emit the unclassified
        # diagnostic -- otherwise the diagnostic becomes noise on every run.
        $known = Join-Path $script:ResultsDir 'run-result.json'
        '{"requestId":"x","runId":"x","finalStatus":"completed","completedAt":"2026-01-01T00:00:00Z"}' |
            Set-Content -LiteralPath $known -Encoding utf8

        $result = Initialize-RunbookTransientZone -ProjectRoot $script:Root

        $result.Ok | Should -BeTrue
        Test-Path -LiteralPath $known | Should -BeFalse

        $unclassified = @($result.Diagnostics | Where-Object { $_ -match 'cleanup-unclassified' })
        $unclassified | Should -BeNullOrEmpty
    }

    It 'M4: capability.json is preserved (editor-state zone), no diagnostic emitted' {
        # capability.json is heartbeated by the editor; wiping it creates a
        # window where invoke scripts mis-report editor-not-running. Confirm
        # the zone-skip path triggers cleanly and emits no diagnostic.
        $cap = Join-Path $script:ResultsDir 'capability.json'
        '{"singleTargetReady":true}' | Set-Content -LiteralPath $cap -Encoding utf8

        $result = Initialize-RunbookTransientZone -ProjectRoot $script:Root

        $result.Ok | Should -BeTrue
        Test-Path -LiteralPath $cap | Should -BeTrue
        @($result.Diagnostics | Where-Object { $_ -match 'cleanup-unclassified' }) | Should -BeNullOrEmpty
    }
}
