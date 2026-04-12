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
        $runtimePath = Join-Path $TestDrive 'runtime-sample'
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

    It 'fails when summary.json is missing' {
        $runtimePath = Join-Path $TestDrive 'runtime-without-summary'
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

    It 'rejects invalid status values' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                OutputPath = (Join-Path $TestDrive 'invalid-status.json')
                Status = 'broken'
                PassThru = $true
            }
        } | Should -Throw '*Cannot validate argument*'
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