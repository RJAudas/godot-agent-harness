BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}


Describe 'specs/003-editor-evidence-loop automation schemas' {
    It 'accepts a ready automation capability payload' {
        $payloadPath = Join-Path $TestDrive 'automation-capability.json'
        @{
            checkedAt = '2026-04-12T12:00:00Z'
            projectIdentifier = 'examples/pong-testbed'
            singleTargetReady = $true
            launchControlAvailable = $true
            runtimeBridgeAvailable = $true
            captureControlAvailable = $true
            persistenceAvailable = $true
            validationAvailable = $true
            shutdownControlAvailable = $true
            blockedReasons = @()
            recommendedControlPath = 'file_broker'
            notes = @('Ready for autonomous editor evidence runs.')
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts a run request payload with request-scoped overrides' {
        $payloadPath = Join-Path $TestDrive 'automation-run-request.json'
        @{
            requestId = 'pong-request-001'
            scenarioId = 'pong-scenegraph-happy-path'
            runId = 'pong-run-001'
            targetScene = 'res://scenes/main.tscn'
            outputDirectory = 'res://evidence/automation/pong-run-001'
            artifactRoot = 'examples/pong-testbed/evidence/automation/pong-run-001'
            expectationFiles = @('res://harness/expectations/common.json')
            capturePolicy = @{
                startup = $true
                manual = $true
                failure = $true
            }
            stopPolicy = @{
                stopAfterValidation = $true
            }
            requestedBy = 'scenegraph-automation-test'
            createdAt = '2026-04-12T12:01:00Z'
            overrides = @{
                outputDirectory = 'res://evidence/automation/pong-run-override'
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts a lifecycle status payload' {
        $payloadPath = Join-Path $TestDrive 'automation-lifecycle-status.json'
        @{
            requestId = 'pong-request-001'
            runId = 'pong-run-001'
            status = 'awaiting_runtime'
            details = 'Waiting for the runtime debugger session to attach.'
            timestamp = '2026-04-12T12:02:00Z'
            sessionId = 'automation-session-001'
            controlPath = 'file_broker'
            evidenceRefs = @('examples/pong-testbed/harness/automation/results/lifecycle-status.json')
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts a completed run result payload' {
        $payloadPath = Join-Path $TestDrive 'automation-run-result.json'
        @{
            requestId = 'pong-request-001'
            runId = 'pong-run-001'
            finalStatus = 'completed'
            failureKind = $null
            manifestPath = 'examples/pong-testbed/evidence/automation/pong-run-001/evidence-manifest.json'
            outputDirectory = 'res://evidence/automation/pong-run-001'
            validationResult = @{
                manifestExists = $true
                artifactRefsChecked = 3
                missingArtifacts = @()
                bundleValid = $true
                notes = @('Manifest and referenced scenegraph artifacts passed validation.')
                validatedAt = '2026-04-12T12:03:00Z'
            }
            terminationStatus = 'stopped_cleanly'
            blockedReasons = @()
            controlPath = 'file_broker'
            completedAt = '2026-04-12T12:03:30Z'
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }
}

Describe 'examples/pong-testbed automation fixtures' {
    It 'accepts the ready capability fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/capability-ready.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the blocked capability fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/capability-blocked.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the healthy run request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/run-request.healthy.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the blocked run request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/run-request.blocked.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the capability options fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/capability-options.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the success run result fixture and its referenced manifest' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.success.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $manifestValidation = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'examples/pong-testbed/harness/expected-evidence-manifest.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        $manifestValidation.ExitCode | Should -Be 0
        $manifestValidation.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'accepts each failure and blocked run result fixture' {
        $fixturePaths = @(
            'examples/pong-testbed/harness/automation/results/run-result.attachment-failure.expected.json',
            'examples/pong-testbed/harness/automation/results/run-result.capture-failure.expected.json',
            'examples/pong-testbed/harness/automation/results/run-result.validation-failure.expected.json',
            'examples/pong-testbed/harness/automation/results/run-result.shutdown-failure.expected.json',
            'examples/pong-testbed/harness/automation/results/run-result.gameplay-failure.expected.json',
            'examples/pong-testbed/harness/automation/results/run-result.blocked.expected.json'
        )

        foreach ($fixturePath in $fixturePaths) {
            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $fixturePath,
                '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
            )

            $result.ExitCode | Should -Be 0
            $result.ParsedOutput.valid | Should -BeTrue
        }
    }
}

Describe 'inspection-run config automation defaults' {
    It 'defines automation paths and target-scene defaults for the example project' {
        $config = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/inspection-run-config.json') -Raw | ConvertFrom-Json -Depth 20

        $config.targetScene | Should -Be 'res://scenes/main.tscn'
        $config.automation.requestPath | Should -Be 'res://harness/automation/requests/run-request.json'
        $config.automation.resultsDirectory | Should -Be 'res://harness/automation/results'
        $config.defaultRequestOverrides.stopPolicy.stopAfterValidation | Should -BeTrue
    }

    It 'defines automation paths in the template harness config' {
        $config = Get-Content -LiteralPath (Get-RepoPath -Path 'addons/agent_runtime_harness/templates/project_root/harness/inspection-run-config.json') -Raw | ConvertFrom-Json -Depth 20

        $config.automation.requestPath | Should -Be 'res://harness/automation/requests/run-request.json'
        $config.automation.capabilityResultPath | Should -Be 'res://harness/automation/results/capability.json'
        $config.defaultRequestOverrides.capturePolicy.startup | Should -BeTrue
    }
}
