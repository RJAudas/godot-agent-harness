Describe 'specs/002-inspect-scene-tree scenegraph snapshot schema' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts the healthy snapshot fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/expected-live-scenegraph.json',
            '-SchemaPath', 'specs/002-inspect-scene-tree/contracts/scenegraph-snapshot.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts a manual capture variant of the healthy snapshot fixture' {
        $snapshotPath = Join-Path $TestDrive 'manual-scenegraph-snapshot.json'
        $snapshot = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/harness/expected-live-scenegraph.json') -Raw | ConvertFrom-Json -Depth 100
        $snapshot.snapshot_id = 'scenegraph-session-001-manual-01'
        $snapshot.trigger.trigger_type = 'manual'
        $snapshot.trigger.reason = 'manual_request'
        $snapshot | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $snapshotPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $snapshotPath,
            '-SchemaPath', 'specs/002-inspect-scene-tree/contracts/scenegraph-snapshot.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }
}

Describe 'specs/002-inspect-scene-tree scenegraph diagnostics schema' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts the missing-node diagnostics fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/evidence/scenegraph-diagnostics.json',
            '-SchemaPath', 'specs/002-inspect-scene-tree/contracts/scenegraph-diagnostics.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }
}

Describe 'scenegraph evidence manifest integration' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts the persisted scenegraph manifest fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.schemaValid | Should -BeTrue
        $result.ParsedOutput.bundleValid | Should -BeTrue
        @($result.ParsedOutput.unsupportedArtifactKinds).Count | Should -Be 0
    }

    It 'adds scenegraph artifact kinds when they exist in the runtime artifact directory' {
        $sandboxPath = New-RepoSandboxDirectory
        $runtimePath = Join-Path $sandboxPath 'runtime-sample'

        try {
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/runtime-sample') -Destination $runtimePath -Recurse
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/evidence/scenegraph-snapshot.json') -Destination (Join-Path $runtimePath 'scenegraph-snapshot.json')
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/evidence/scenegraph-diagnostics.json') -Destination (Join-Path $runtimePath 'scenegraph-diagnostics.json')
            Copy-Item -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/evidence/scenegraph-summary.json') -Destination (Join-Path $runtimePath 'scenegraph-summary.json')

            $outputPath = Join-Path $TestDrive 'scenegraph-generated-manifest.json'
            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/evidence/new-evidence-manifest.ps1' -Parameters @{
                RuntimeArtifactsPath = $runtimePath
                OutputPath = $outputPath
                PassThru = $true
            }

            $manifest = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
            $artifactKinds = @($manifest.artifactRefs | ForEach-Object { $_.kind })

            $result.artifactCount | Should -Be 8
            $artifactKinds | Should -Contain 'scenegraph-snapshot'
            $artifactKinds | Should -Contain 'scenegraph-diagnostics'
            $artifactKinds | Should -Contain 'scenegraph-summary'
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects unsupported artifact kinds' {
        $manifestPath = Join-Path $TestDrive 'unsupported-kind-manifest.json'
        $manifest = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json') -Raw | ConvertFrom-Json -Depth 100
        $manifest.artifactRefs[0].kind = 'scenegraph-unknown'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifestPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', $manifestPath
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.bundleValid | Should -BeFalse
        $result.ParsedOutput.unsupportedArtifactKinds | Should -Contain 'scenegraph-unknown'
    }
}