BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
}


Describe 'specs/003-editor-evidence-loop automation schemas' {
    It 'accepts a ready automation capability payload' {
        $payloadPath = Join-Path $TestDrive 'automation-capability.json'
        @{
            checkedAt = '2026-04-12T12:00:00Z'
            projectIdentifier = 'tools/tests/fixtures/pong-testbed'
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
            artifactRoot = 'tools/tests/fixtures/pong-testbed/evidence/automation/pong-run-001'
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
            evidenceRefs = @('tools/tests/fixtures/pong-testbed/harness/automation/results/lifecycle-status.json')
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
            manifestPath = 'tools/tests/fixtures/pong-testbed/evidence/automation/pong-run-001/evidence-manifest.json'
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

Describe 'tools/tests/fixtures/pong-testbed automation fixtures' {
    It 'accepts the ready capability fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/results/capability-ready.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the blocked capability fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/results/capability-blocked.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the healthy run request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.healthy.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the blocked run request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/requests/run-request.blocked.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the capability options fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/results/capability-options.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the success run result fixture and its referenced manifest' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.success.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $manifestValidation = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'tools/tests/fixtures/pong-testbed/harness/expected-evidence-manifest.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        $manifestValidation.ExitCode | Should -Be 0
        $manifestValidation.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'accepts each failure and blocked run result fixture' {
        $fixturePaths = @(
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.attachment-failure.expected.json',
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.capture-failure.expected.json',
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.validation-failure.expected.json',
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.shutdown-failure.expected.json',
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.gameplay-failure.expected.json',
            'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.blocked.expected.json'
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

    It 'accepts the build-failure lifecycle status fixture' {
        $fixturePath = 'tools/tests/fixtures/pong-testbed/harness/automation/results/lifecycle-status.build-failure.expected.json'

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $fixturePath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json'
        )
        $status = Get-Content -LiteralPath (Get-RepoPath -Path $fixturePath) -Raw | ConvertFrom-Json -Depth 20

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        Assert-BuildFailureLifecycleStatus -Status $status -ExpectedPhase 'launching' -MinimumDiagnosticCount 2
    }

    It 'accepts each build-failure run result fixture' {
        $fixtures = @(
            @{ Path = 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.build-failure.expected.json'; Phase = 'launching'; Count = 2 },
            @{ Path = 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.build-failure.multi-diagnostic.expected.json'; Phase = 'launching'; Count = 3 },
            @{ Path = 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.build-failure.partial-metadata.expected.json'; Phase = 'awaiting_runtime'; Count = 1 },
            @{ Path = 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.build-failure.resource-load.expected.json'; Phase = 'launching'; Count = 1 },
            @{ Path = 'tools/tests/fixtures/pong-testbed/harness/automation/results/run-result.build-failure.stale-manifest.expected.json'; Phase = 'awaiting_runtime'; Count = 1 }
        )

        foreach ($fixture in $fixtures) {
            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $fixture.Path,
                '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
            )
            $runResult = Get-Content -LiteralPath (Get-RepoPath -Path $fixture.Path) -Raw | ConvertFrom-Json -Depth 20

            $result.ExitCode | Should -Be 0
            $result.ParsedOutput.valid | Should -BeTrue
            Assert-BuildFailureRunResult -Result $runResult -ExpectedPhase $fixture.Phase -ExpectedDiagnosticCount $fixture.Count
        }
    }
}

Describe 'inspection-run config automation defaults' {
    It 'defines automation paths and target-scene defaults for the example project' {
        $config = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/harness/inspection-run-config.json') -Raw | ConvertFrom-Json -Depth 20

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

Describe 'Fix #18: stopAfterValidation=false deferred-failure contract' {
    # These tests lock in the schema-level invariants for the fixed coordinator
    # behavior: when validation fails with stopAfterValidation=false the run
    # must ultimately be recorded as failed (not stuck at terminationStatus
    # "running") and the terminationStatus must reflect the actual session end.
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'the soft-validation-then-error request fixture is schema-valid' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/tests/fixtures/runtime-error-loop/soft-validation-then-error.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'the soft-validation-then-error fixture has stopAfterValidation=false' {
        $fixture = Get-Content -LiteralPath (Get-RepoPath -Path 'tools/tests/fixtures/runtime-error-loop/soft-validation-then-error.json') -Raw | ConvertFrom-Json -Depth 20

        $fixture.stopPolicy.stopAfterValidation | Should -BeFalse -Because 'this fixture must exercise the deferred-failure path'
    }

    It 'a deferred-validation-failure run result with terminationStatus=already_closed is schema-valid' {
        # The fixed coordinator finalizes with finalStatus=failed, failureKind=validation,
        # and terminationStatus=already_closed (game already stopped) instead of the
        # broken terminationStatus=running produced before the fix.
        $payloadPath = Join-Path $TestDrive 'deferred-validation-run-result.json'
        @{
            requestId        = 'runtime-error-loop-soft-validation-then-error-001'
            runId            = 'runtime-error-loop-soft-validation-then-error-run-001'
            finalStatus      = 'failed'
            failureKind      = 'validation'
            manifestPath     = 'integration-testing/runtime-error-loop/evidence/automation/runtime-error-loop-soft-validation-then-error-run-001/evidence-manifest.json'
            outputDirectory  = 'res://evidence/automation/runtime-error-loop-soft-validation-then-error-run-001'
            validationResult = @{
                manifestExists       = $true
                artifactRefsChecked  = 1
                missingArtifacts     = @()
                bundleValid          = $false
                notes                = @(
                    'Persisted evidence bundle failed validation.'
                    'runId in manifest does not match the active run.'
                )
                validatedAt          = '2026-04-21T00:00:00Z'
            }
            terminationStatus = 'already_closed'
            blockedReasons    = @()
            controlPath       = 'file_broker'
            completedAt       = '2026-04-21T00:00:00Z'
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'terminationStatus="running" is schema-valid but must NOT appear when stopAfterValidation=false ends in validation failure' {
        # This test documents the pre-fix incorrect output shape so reviewers can
        # confirm the schema does not block either value — the behavioral constraint
        # is enforced by the coordinator, not the schema.
        $payloadPath = Join-Path $TestDrive 'broken-running-run-result.json'
        @{
            requestId        = 'runtime-error-loop-soft-validation-then-error-001'
            runId            = 'runtime-error-loop-soft-validation-then-error-run-001'
            finalStatus      = 'failed'
            failureKind      = 'validation'
            manifestPath     = $null
            outputDirectory  = 'res://evidence/automation/runtime-error-loop-soft-validation-then-error-run-001'
            validationResult = @{
                manifestExists       = $false
                artifactRefsChecked  = 0
                missingArtifacts     = @()
                bundleValid          = $false
                notes                = @('Persisted evidence bundle failed validation.')
                validatedAt          = '2026-04-21T00:00:00Z'
            }
            terminationStatus = 'running'
            blockedReasons    = @()
            controlPath       = 'file_broker'
            completedAt       = '2026-04-21T00:00:00Z'
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        # Schema accepts both shapes — the behavioral fix ensures "running" never
        # appears here in practice.
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue -Because 'the schema permits terminationStatus=running; behavioral correctness is the coordinator fix'
    }
}
