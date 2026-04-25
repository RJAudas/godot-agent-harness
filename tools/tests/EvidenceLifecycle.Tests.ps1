BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:ModulePath   = Join-Path $script:RepoRootPath 'tools/automation/RunbookOrchestration.psm1'

    Import-Module $script:ModulePath -Force

    # Seed a transient zone with a minimal evidence-manifest + artifact + run-result + lifecycle-status.
    function script:New-SandboxTransientZone {
        param(
            [string]$Root,
            [string]$RunId      = 'run-00000000-0000-0000-0000-000000000001',
            [string]$ScenarioId = 'test-scenario'
        )
        $resultsDir  = Join-Path $Root 'harness/automation/results'
        $evidenceDir = Join-Path $Root "evidence/automation/$RunId"
        New-Item -ItemType Directory -Path $resultsDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

        $traceFile = Join-Path $evidenceDir 'trace.jsonl'
        '{"frame":1,"nodePath":"/root"}' | Set-Content -LiteralPath $traceFile -Encoding utf8

        $manifest = [ordered]@{
            schemaVersion = '1.0.0'
            runId         = $RunId
            scenarioId    = $ScenarioId
            artifactRefs  = @(
                [ordered]@{ kind = 'behavior-trace'; path = "evidence/automation/$RunId/trace.jsonl" }
            )
        }
        $manifestFile = Join-Path $evidenceDir 'evidence-manifest.json'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestFile -Encoding utf8

        @{ finalStatus = 'completed'; runId = $RunId } | ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath (Join-Path $resultsDir 'run-result.json') -Encoding utf8

        @{ status = 'completed'; runId = $RunId } | ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath (Join-Path $resultsDir 'lifecycle-status.json') -Encoding utf8

        return @{
            Root         = $Root
            RunId        = $RunId
            ManifestPath = $manifestFile
            TracePath    = $traceFile
            ResultsDir   = $resultsDir
            EvidenceDir  = $evidenceDir
        }
    }
}

# ---------------------------------------------------------------------------
# T025 — US3: pin copies full file set
# ---------------------------------------------------------------------------

Describe 'US3 pin: copies full file set (T025)' {
    It 'copies manifest, artifact, run-result, lifecycle-status and writes pin-metadata' {
        $root = New-RepoSandboxDirectory
        try {
            $tz = New-SandboxTransientZone -Root $root

            $result = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'baseline'

            $result.Ok | Should -BeTrue -Because 'pin should succeed with valid transient zone'

            $pinRoot         = Join-Path $root 'harness/automation/pinned/baseline'
            $pinnedManifest  = Join-Path $pinRoot "evidence/$($tz.RunId)/evidence-manifest.json"
            $pinnedTrace     = Join-Path $pinRoot "evidence/$($tz.RunId)/trace.jsonl"
            $pinnedResult    = Join-Path $pinRoot 'results/run-result.json'
            $pinnedLifecycle = Join-Path $pinRoot 'results/lifecycle-status.json'
            $pinnedMeta      = Join-Path $pinRoot 'pin-metadata.json'

            Test-Path -LiteralPath $pinnedManifest  | Should -BeTrue  -Because 'pinned evidence-manifest.json must exist'
            Test-Path -LiteralPath $pinnedTrace     | Should -BeTrue  -Because 'pinned trace.jsonl must exist'
            Test-Path -LiteralPath $pinnedResult    | Should -BeTrue  -Because 'pinned run-result.json must exist'
            Test-Path -LiteralPath $pinnedLifecycle | Should -BeTrue  -Because 'pinned lifecycle-status.json must exist'
            Test-Path -LiteralPath $pinnedMeta      | Should -BeTrue  -Because 'pin-metadata.json must exist'

            # Byte-identical check via SHA256
            (Get-FileHash -LiteralPath $pinnedManifest).Hash |
                Should -Be (Get-FileHash -LiteralPath $tz.ManifestPath).Hash -Because 'manifest must be byte-identical'
            (Get-FileHash -LiteralPath $pinnedTrace).Hash |
                Should -Be (Get-FileHash -LiteralPath $tz.TracePath).Hash    -Because 'trace must be byte-identical'

            # pin-metadata must be parseable with expected fields
            $meta = Get-Content -LiteralPath $pinnedMeta -Raw | ConvertFrom-Json -Depth 10
            $meta.pinName       | Should -Be 'baseline'
            $meta.sourceRunId   | Should -Be $tz.RunId
            $meta.schemaVersion | Should -Not -BeNullOrEmpty
            $meta.pinnedAt      | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T026 — US3: pin-name collision refused
# ---------------------------------------------------------------------------

Describe 'US3 pin: collision refused (T026)' {
    It 'returns pin-name-collision when the same pin name already exists without -Force' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null

            $first = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'my-pin'
            $first.Ok | Should -BeTrue -Because 'first pin should succeed'

            $second = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'my-pin'
            $second.Ok          | Should -BeFalse              -Because 'second pin without -Force must fail'
            $second.FailureKind | Should -Be 'pin-name-collision'
            @($second.PlannedPaths).Count | Should -Be 0       -Because 'collision must not mutate anything'

            # Confirm the original pin is still intact
            $pinnedMeta = Join-Path $root 'harness/automation/pinned/my-pin/pin-metadata.json'
            Test-Path -LiteralPath $pinnedMeta | Should -BeTrue -Because 'original pin must survive collision refusal'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T027 — US3: pin -Force overwrites
# ---------------------------------------------------------------------------

Describe 'US3 pin: -Force overwrites existing pin (T027)' {
    It 'replaces pin contents with updated source and returns populated plannedPaths' {
        $root = New-RepoSandboxDirectory
        try {
            $tz = New-SandboxTransientZone -Root $root

            $first = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'overwrite-me'
            $first.Ok | Should -BeTrue

            # Mutate the source trace artifact
            'updated content' | Set-Content -LiteralPath $tz.TracePath -Encoding utf8

            $second = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'overwrite-me' -Force
            $second.Ok | Should -BeTrue -Because '-Force overwrite must succeed'
            @($second.PlannedPaths).Count | Should -BeGreaterThan 0 -Because 'plannedPaths must reflect what was copied'

            # The overwritten trace should now match the updated source
            $pinnedTrace = Join-Path $root "harness/automation/pinned/overwrite-me/evidence/$($tz.RunId)/trace.jsonl"
            (Get-FileHash -LiteralPath $pinnedTrace).Hash |
                Should -Be (Get-FileHash -LiteralPath $tz.TracePath).Hash -Because 'overwritten pin must reflect the new source content'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T028 — US3: list emits pinned-run-index sorted alphabetically
# ---------------------------------------------------------------------------

Describe 'US3 list: emits pinned-run-index (T028)' {
    It 'returns three records sorted by pinName and each record has required fields' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'gamma' | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'alpha' | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'beta'  | Out-Null

            $index = Get-PinnedRunIndex -ProjectRoot $root
            @($index).Count | Should -Be 3 -Because 'three pins must be listed'

            @($index)[0]['pinName'] | Should -Be 'alpha' -Because 'must be sorted alphabetically'
            @($index)[1]['pinName'] | Should -Be 'beta'
            @($index)[2]['pinName'] | Should -Be 'gamma'

            foreach ($rec in @($index)) {
                $rec.Keys | Should -Contain 'pinName'
                $rec.Keys | Should -Contain 'manifestPath'
                $rec.Keys | Should -Contain 'scenarioId'
                $rec.Keys | Should -Contain 'runId'
                $rec.Keys | Should -Contain 'pinnedAt'
                $rec.Keys | Should -Contain 'status'
                $rec.Keys | Should -Contain 'sourceInvokeScript'
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# B11 — Write-LifecycleEnvelope must emit pinnedRunIndex as JSON array
# even when only one pin exists. Without the leading-comma wrap the
# if-expression auto-unrolls a single-element array into a bare object.
# ---------------------------------------------------------------------------

Describe 'Write-LifecycleEnvelope: pinnedRunIndex array shape (B11)' {
    It 'serializes pinnedRunIndex as a JSON array when one pin exists' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'solo' | Out-Null

            $index = Get-PinnedRunIndex -ProjectRoot $root
            @($index).Count | Should -Be 1

            $json = Write-LifecycleEnvelope -Status 'ok' -Operation 'list' `
                -DryRun $false -Diagnostics @() -PlannedPaths @() -PinnedRunIndex $index
            $parsed = $json | ConvertFrom-Json

            # PowerShell ConvertFrom-Json yields object[] for JSON arrays. A bare
            # object would yield a single PSCustomObject with no array semantics.
            $parsed.pinnedRunIndex.GetType().IsArray | Should -BeTrue -Because 'pinnedRunIndex must be an array even with a single pin'
            @($parsed.pinnedRunIndex).Count | Should -Be 1
            $parsed.pinnedRunIndex[0].pinName | Should -Be 'solo'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'serializes pinnedRunIndex as a JSON array when two pins exist' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'one' | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'two' | Out-Null

            $index = Get-PinnedRunIndex -ProjectRoot $root
            $json = Write-LifecycleEnvelope -Status 'ok' -Operation 'list' `
                -DryRun $false -Diagnostics @() -PlannedPaths @() -PinnedRunIndex $index
            $parsed = $json | ConvertFrom-Json

            $parsed.pinnedRunIndex.GetType().IsArray | Should -BeTrue
            @($parsed.pinnedRunIndex).Count | Should -Be 2
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T029 — US3: unpin -DryRun mutates nothing; real unpin removes pin
# ---------------------------------------------------------------------------

Describe 'US3 unpin: -DryRun and real removal (T029)' {
    It '-DryRun returns planned delete paths and leaves pin on disk' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'dry-target' | Out-Null

            $dry = Remove-PinnedRun -ProjectRoot $root -PinName 'dry-target' -DryRun
            $dry.Ok | Should -BeTrue
            @($dry.PlannedPaths) | Where-Object { $_['action'] -eq 'delete' } |
                Should -Not -BeNullOrEmpty -Because '-DryRun must list delete paths'

            $pinRoot = Join-Path $root 'harness/automation/pinned/dry-target'
            Test-Path -LiteralPath $pinRoot | Should -BeTrue -Because '-DryRun must not delete anything'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'real unpin removes the pin directory' {
        $root = New-RepoSandboxDirectory
        try {
            New-SandboxTransientZone -Root $root | Out-Null
            Copy-RunToPinnedZone -ProjectRoot $root -PinName 'real-target' | Out-Null

            $result = Remove-PinnedRun -ProjectRoot $root -PinName 'real-target'
            $result.Ok | Should -BeTrue

            $pinRoot = Join-Path $root 'harness/automation/pinned/real-target'
            Test-Path -LiteralPath $pinRoot | Should -BeFalse -Because 'pin directory must be gone after unpin'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T030 — US3: pin refuses when manifest absent
# ---------------------------------------------------------------------------

Describe 'US3 pin: refuses when manifest absent (T030)' {
    It 'returns pin-source-missing when evidence-manifest.json is not in the transient zone' {
        $root = New-RepoSandboxDirectory
        try {
            # Seed results only — no evidence-manifest.json anywhere
            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            @{ status = 'completed' } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $resultsDir 'lifecycle-status.json') -Encoding utf8

            $result = Copy-RunToPinnedZone -ProjectRoot $root -PinName 'no-manifest'
            $result.Ok          | Should -BeFalse              -Because 'pin must fail when no manifest exists'
            $result.FailureKind | Should -Be 'pin-source-missing'

            $pinRoot = Join-Path $root 'harness/automation/pinned/no-manifest'
            Test-Path -LiteralPath $pinRoot | Should -BeFalse -Because 'no pin directory must be created on refusal'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T035 — US4: no ad-hoc cleanup advice in recipe docs or AGENTS.md (SC-006)
# ---------------------------------------------------------------------------

Describe 'US4 static-check: no ad-hoc cleanup advice in docs (T035)' {
    It 'docs/runbook/ markdown files contain no Remove-Item/rm -rf against harness or evidence paths' {
        $repoRoot     = $script:RepoRootPath
        $runbookDir   = Join-Path $repoRoot 'docs/runbook'
        $agentsMd     = Join-Path $repoRoot 'AGENTS.md'

        $forbiddenPatterns = @(
            'Remove-Item.*(?:harness|evidence)',
            'rm\s+-rf.*(?:harness|evidence)',
            'rm\s+-r.*(?:harness|evidence)'
        )

        $filesToCheck = @(Get-ChildItem -LiteralPath $runbookDir -Filter '*.md' -ErrorAction SilentlyContinue)
        if (Test-Path -LiteralPath $agentsMd) { $filesToCheck += Get-Item -LiteralPath $agentsMd }

        $violations = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $filesToCheck) {
            $lines = Get-Content -LiteralPath $file.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                foreach ($pat in $forbiddenPatterns) {
                    if ($lines[$i] -match $pat) {
                        $violations.Add("$($file.Name):$($i+1): $($lines[$i].Trim())")
                    }
                }
            }
        }

        $violations | Should -BeNullOrEmpty -Because "SC-006: recipe docs must not instruct agents to delete harness/evidence paths manually"
    }
}

# ---------------------------------------------------------------------------
# T036 — US4: RUNBOOK.md lists every lifecycle script exactly once
# ---------------------------------------------------------------------------

Describe 'US4 static-check: RUNBOOK.md lists all lifecycle scripts (T036)' {
    It 'invoke-pin-run.ps1 appears in RUNBOOK.md' {
        $content = Get-Content -LiteralPath (Join-Path $script:RepoRootPath 'RUNBOOK.md') -Raw
        ([regex]::Matches($content, 'invoke-pin-run\.ps1')).Count |
            Should -Be 1 -Because 'invoke-pin-run.ps1 must appear exactly once in RUNBOOK.md'
    }

    It 'invoke-unpin-run.ps1 appears in RUNBOOK.md' {
        $content = Get-Content -LiteralPath (Join-Path $script:RepoRootPath 'RUNBOOK.md') -Raw
        ([regex]::Matches($content, 'invoke-unpin-run\.ps1')).Count |
            Should -Be 1 -Because 'invoke-unpin-run.ps1 must appear exactly once in RUNBOOK.md'
    }

    It 'invoke-list-pinned-runs.ps1 appears in RUNBOOK.md' {
        $content = Get-Content -LiteralPath (Join-Path $script:RepoRootPath 'RUNBOOK.md') -Raw
        ([regex]::Matches($content, 'invoke-list-pinned-runs\.ps1')).Count |
            Should -Be 1 -Because 'invoke-list-pinned-runs.ps1 must appear exactly once in RUNBOOK.md'
    }
}
