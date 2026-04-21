Describe 'tools/evidence/new-evidence-manifest.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'generates a manifest from the seeded runtime sample' {
        $outputPath = Join-Path $TestDrive 'generated-manifest.json'

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
            OutputPath = $outputPath
            PassThru = $true
        }

        $manifest = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100

        $result.manifestPath | Should -Be $outputPath
        $result.artifactCount | Should -Be 5
        $manifest.scenarioId | Should -Be 'pong-wall-bounce-left-001'
        $manifest.runId | Should -Be 'pong-wall-bounce-left-001-run-01'
        $manifest.status | Should -Be 'fail'
        $manifest.validation.bundleValid | Should -BeFalse
    }

    It 'respects explicit scenario, run, and status overrides' {
        $outputPath = Join-Path $TestDrive 'override-manifest.json'

        Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
            OutputPath = $outputPath
            ScenarioId = 'scenario-override'
            RunId = 'run-override'
            Status = 'pass'
            PassThru = $true
        } | Out-Null

        $manifest = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
        $manifest.scenarioId | Should -Be 'scenario-override'
        $manifest.runId | Should -Be 'run-override'
        $manifest.status | Should -Be 'pass'
        $manifest.manifestId | Should -Be 'evidence-run-override'
    }

    It 'creates parent directories for the output path' {
        $outputPath = Join-Path $TestDrive 'nested\reports\manifest.json'

        Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
            OutputPath = $outputPath
            PassThru = $true
        } | Out-Null

        $outputPath | Should -Exist
    }

    It 'reduces artifactCount when optional artifacts are absent' {
        $sandboxPath = New-RepoSandboxDirectory
        $runtimePath = Join-Path $sandboxPath 'runtime-sample'

        try {
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample') -Destination $runtimePath -Recurse
            Remove-Item -LiteralPath (Join-Path $runtimePath 'invariants.json') -Force

            $outputPath = Join-Path $TestDrive 'partial-manifest.json'
            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                RuntimeArtifactsPath = $runtimePath
                OutputPath = $outputPath
                PassThru = $true
            }

            $manifest = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
            $result.artifactCount | Should -Be 4
            @($manifest.invariants).Count | Should -Be 0
            @($manifest.artifactRefs).Count | Should -Be 4
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails when summary.json is missing' {
        $sandboxPath = New-RepoSandboxDirectory
        $runtimePath = Join-Path $sandboxPath 'runtime-sample'

        try {
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample') -Destination $runtimePath -Recurse
            Remove-Item -LiteralPath (Join-Path $runtimePath 'summary.json') -Force

            {
                Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                    RuntimeArtifactsPath = $runtimePath
                    OutputPath = (Join-Path $TestDrive 'missing-summary.json')
                    PassThru = $true
                }
            } | Should -Throw '*summary file not found*'
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects invalid status values' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                OutputPath = (Join-Path $TestDrive 'invalid-status.json')
                Status = 'broken'
                PassThru = $true
            }
        } | Should -Throw '*Cannot validate argument*'
    }

    It 'rejects runtime artifact roots outside the repository' {
        $runtimePath = Join-Path $TestDrive 'external-runtime-sample'
        New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtimePath 'summary.json') -Value '{"scenarioId":"outside","runId":"outside","status":"fail","headline":"h","outcome":"o","keyFindings":[]}'

        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                RuntimeArtifactsPath = $runtimePath
                OutputPath = (Join-Path $TestDrive 'outside-runtime.json')
                PassThru = $true
            }
        } | Should -Throw '*resolves outside the repository root*'
    }
}

Describe 'tools/evidence/validate-evidence-manifest.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts the canonical valid fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.schemaValid | Should -BeTrue
        $result.ParsedOutput.bundleValid | Should -BeTrue
        @($result.ParsedOutput.missingArtifactPaths).Count | Should -Be 0
    }

    It 'fails for the canonical invalid fixture' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json'
        )

        $result.ExitCode | Should -Be 1
    }

    It 'reports missing artifact paths in an otherwise valid manifest' {
        $manifestPath = Join-Path $TestDrive 'missing-artifact-manifest.json'
        $manifest = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json') -Raw | ConvertFrom-Json -Depth 100
        $manifest.artifactRefs[0].path = 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/does-not-exist.json'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifestPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', $manifestPath
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.schemaValid | Should -BeTrue
        $result.ParsedOutput.bundleValid | Should -BeFalse
        $result.ParsedOutput.missingArtifactPaths | Should -Contain 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample/does-not-exist.json'
    }

    It 'rejects artifact paths that resolve outside the repository root' {
        $manifestPath = Join-Path $TestDrive 'outside-repo-manifest.json'
        $manifest = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json') -Raw | ConvertFrom-Json -Depth 100
        $manifest.artifactRefs[0].path = '..\..\outside-repo.json'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifestPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', $manifestPath
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.bundleValid | Should -BeFalse
        $result.ParsedOutput.missingArtifactPaths | Should -Contain '..\..\outside-repo.json'
    }
}

# ---------------------------------------------------------------------------
# T028: runtimeErrorReporting block invariants in validate-evidence-manifest.ps1
# ---------------------------------------------------------------------------

Describe 'validate-evidence-manifest.ps1 runtimeErrorReporting invariants (T028)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:ValidScript = Get-RepoPath 'tools/evidence/validate-evidence-manifest.ps1'

        ## Helper: write a minimal manifest with the given runtimeErrorReporting block to $TestDrive
        $script:WriteManifest = {
            param([string]$FileName, [hashtable]$Reporting)
            $m = [ordered]@{
                schemaVersion = '1.0.0'
                manifestId    = 'test-manifest'
                runId         = 'test-run'
                scenarioId    = 'test-scenario'
                status        = 'pass'
                summary       = @{ headline = 'h'; outcome = 'pass'; keyFindings = @() }
                artifactRefs  = @()
                runtimeErrorReporting = $Reporting
                validation    = @{ bundleValid = $true; notes = @() }
                producer      = @{ toolingArtifactId = 'test'; surface = 'test' }
                createdAt     = '2026-04-19T00:00:00Z'
            }
            $path = Join-Path $TestDrive $FileName
            $m | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
            return $path
        }
    }

    It 'passes when runtimeErrorReporting has valid completed termination' {
        $path = & $script:WriteManifest 'rer-completed.json' @{
            termination = 'completed'; pauseOnErrorMode = 'active'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.runtimeReportingViolations | Should -BeNullOrEmpty
        $result.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'fails when termination enum value is unrecognized' {
        $path = & $script:WriteManifest 'rer-bad-termination.json' @{
            termination = 'exploded'; pauseOnErrorMode = 'active'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.bundleValid | Should -BeFalse
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*termination*exploded*' }).Count |
            Should -BeGreaterThan 0
    }

    It 'fails when pauseOnErrorMode enum value is unrecognized' {
        $path = & $script:WriteManifest 'rer-bad-mode.json' @{
            termination = 'completed'; pauseOnErrorMode = 'broken_mode'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.bundleValid | Should -BeFalse
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*pauseOnErrorMode*broken_mode*' }).Count |
            Should -BeGreaterThan 0
    }

    It 'fails when termination=crashed but lastErrorAnchor is absent' {
        $path = & $script:WriteManifest 'rer-crashed-no-anchor.json' @{
            termination = 'crashed'; pauseOnErrorMode = 'active'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.bundleValid | Should -BeFalse
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*lastErrorAnchor*required*' }).Count |
            Should -BeGreaterThan 0
    }

    It 'passes when termination=crashed with a full anchor shape' {
        $path = & $script:WriteManifest 'rer-crashed-full-anchor.json' @{
            termination     = 'crashed'
            pauseOnErrorMode = 'active'
            lastErrorAnchor = @{
                scriptPath = 'res://scripts/crash.gd'
                line       = 10
                severity   = 'error'
                message    = 'fatal error'
            }
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.runtimeReportingViolations | Should -BeNullOrEmpty
        $result.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'passes when termination=crashed with { lastError: none } marker' {
        $path = & $script:WriteManifest 'rer-crashed-none-marker.json' @{
            termination     = 'crashed'
            pauseOnErrorMode = 'active'
            lastErrorAnchor = @{ lastError = 'none' }
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.runtimeReportingViolations | Should -BeNullOrEmpty
        $result.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'fails when termination=completed but lastErrorAnchor is present' {
        $path = & $script:WriteManifest 'rer-completed-spurious-anchor.json' @{
            termination     = 'completed'
            pauseOnErrorMode = 'active'
            lastErrorAnchor = @{ scriptPath = 'res://x.gd'; line = 1; severity = 'error'; message = 'oops' }
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.bundleValid | Should -BeFalse
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*lastErrorAnchor*must not be present*' }).Count |
            Should -BeGreaterThan 0
    }
}