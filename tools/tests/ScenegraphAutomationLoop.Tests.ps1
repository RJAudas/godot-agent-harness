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

    It 'accepts a run request payload with behavior-watch overrides' {
        $payloadPath = Join-Path $TestDrive 'automation-run-request.behavior-watch.json'
        @{
            requestId = 'pong-request-watch-001'
            scenarioId = 'pong-behavior-watch'
            runId = 'pong-watch-run-001'
            targetScene = 'res://scenes/main.tscn'
            outputDirectory = 'res://evidence/automation/pong-watch-run-001'
            artifactRoot = 'examples/pong-testbed/evidence/automation/pong-watch-run-001'
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
            createdAt = '2026-04-14T00:01:00Z'
            overrides = @{
                behaviorWatchRequest = @{
                    targets = @(
                        @{
                            nodePath = '/root/Main/Ball'
                            properties = @('position', 'velocity', 'collisionState', 'lastCollider')
                        }
                    )
                    frameCount = 4
                }
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'rejects a run request payload with later-slice behavior-watch fields' {
        $payloadPath = Join-Path $TestDrive 'automation-run-request.behavior-watch.invalid.json'
        @{
            requestId = 'pong-request-watch-002'
            scenarioId = 'pong-behavior-watch'
            runId = 'pong-watch-run-002'
            targetScene = 'res://scenes/main.tscn'
            outputDirectory = 'res://evidence/automation/pong-watch-run-002'
            artifactRoot = 'examples/pong-testbed/evidence/automation/pong-watch-run-002'
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
            createdAt = '2026-04-14T00:02:00Z'
            overrides = @{
                behaviorWatchRequest = @{
                    targets = @(
                        @{
                            nodePath = '/root/Main/Ball'
                            properties = @('position')
                        }
                    )
                    frameCount = 4
                    triggers = @('wall_contact')
                }
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.valid | Should -BeFalse
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

    It 'accepts a build-failed lifecycle status payload' {
        $payloadPath = Join-Path $TestDrive 'automation-lifecycle-status.build-failure.json'
        @{
            requestId = 'pong-request-build-failure-001'
            runId = 'pong-autonomous-run-build-failure-001'
            status = 'failed'
            details = 'Detected 2 build diagnostic(s) before runtime attachment.'
            timestamp = '2026-04-12T13:10:05Z'
            failureKind = 'build'
            buildFailurePhase = 'launching'
            buildDiagnosticCount = 2
            rawBuildOutputAvailable = $true
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $payloadPath,
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts a completed lifecycle status payload' {
        $payloadPath = Join-Path $TestDrive 'automation-lifecycle-status.completed.json'
        @{
            requestId = 'pong-request-001'
            runId = 'pong-run-001'
            status = 'completed'
            details = 'Autonomous run completed.'
            timestamp = '2026-04-17T17:55:00Z'
            controlPath = 'file_broker'
            evidenceRefs = @('examples/pong-testbed/harness/expected-evidence-manifest.json')
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

    It 'accepts a build-failed run result payload' {
        $payloadPath = Join-Path $TestDrive 'automation-run-result.build-failure.json'
        @{
            requestId = 'pong-request-build-failure-001'
            runId = 'pong-autonomous-run-build-failure-001'
            finalStatus = 'failed'
            failureKind = 'build'
            buildFailurePhase = 'launching'
            buildDiagnostics = @(
                @{
                    resourcePath = 'res://scripts/build_failures/syntax_error_root.gd'
                    message = 'Script reload failed with Parse Error.'
                    severity = 'error'
                    line = $null
                    column = $null
                    sourceKind = 'script'
                    code = $null
                    rawExcerpt = 'res://scripts/build_failures/syntax_error_root.gd: Script reload failed with Parse Error.'
                }
            )
            rawBuildOutput = @(
                'res://scripts/build_failures/syntax_error_root.gd: Script reload failed with Parse Error.'
            )
            manifestPath = $null
            outputDirectory = 'res://evidence/automation/pong-build-failure-001'
            validationResult = @{
                manifestExists = $false
                artifactRefsChecked = 0
                missingArtifacts = @()
                bundleValid = $false
                notes = @('No new evidence manifest was produced because the run failed during build before runtime capture.')
                validatedAt = '2026-04-12T13:10:06Z'
            }
            terminationStatus = 'not_started'
            blockedReasons = @()
            controlPath = 'file_broker'
            completedAt = '2026-04-12T13:10:07Z'
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

    It 'accepts the build-failure run request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/run-request.build-failure.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the behavior-watch request fragment fixture with normalization defaults' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/behavior-watch-valid.json',
            '-SchemaPath', 'specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'rejects the invalid-selector behavior-watch request fragment fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-selector.json',
            '-SchemaPath', 'specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json'
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.valid | Should -BeFalse
    }

    It 'rejects the invalid-window behavior-watch request fragment fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/behavior-watch-invalid-window.json',
            '-SchemaPath', 'specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json'
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.valid | Should -BeFalse
    }

    It 'accepts the every-frame behavior-watch automation request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-frame.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'accepts the every-n behavior-watch automation request fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/requests/behavior-watch-wall-bounce.every-n.json',
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

    It 'accepts the every-frame behavior-watch run-result fixture, manifest, and trace rows' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.behavior-watch.every-frame.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $manifestValidation = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-frame/evidence-manifest.json'
        )
        $manifest = Read-RepoJson -Path 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-frame/evidence-manifest.json'
        $traceRows = @(Read-RepoJsonLines -Path 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-frame/trace.jsonl')

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        $manifestValidation.ExitCode | Should -Be 0
        $manifestValidation.ParsedOutput.bundleValid | Should -BeTrue
        Assert-BehaviorWatchAppliedWatch -AppliedWatch $manifest.appliedWatch -ExpectedRunId 'pong-behavior-watch-wall-bounce-every-frame-run-01' -ExpectedNodePath '/root/Main/Ball' -ExpectedProperties @('position', 'velocity', 'collisionState', 'lastCollider') -ExpectedMode 'every_frame' -ExpectedStartFrameOffset 12 -ExpectedFrameCount 4 -ExpectedSampleCount 4
        Assert-BehaviorWatchTraceRows -Rows $traceRows -ExpectedNodePath '/root/Main/Ball' -ExpectedProperties @('position', 'velocity', 'collisionState', 'lastCollider') -ExpectedFrames @(12, 13, 14, 15)
    }

    It 'accepts the every-n behavior-watch run-result fixture, manifest, and trace rows' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.behavior-watch.every-n.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $manifestValidation = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @(
            '-ManifestPath', 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-n/evidence-manifest.json'
        )
        $manifest = Read-RepoJson -Path 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-n/evidence-manifest.json'
        $traceRows = @(Read-RepoJsonLines -Path 'examples/pong-testbed/evidence/automation/pong-behavior-watch-wall-bounce-every-n/trace.jsonl')

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        $manifestValidation.ExitCode | Should -Be 0
        $manifestValidation.ParsedOutput.bundleValid | Should -BeTrue
        Assert-BehaviorWatchAppliedWatch -AppliedWatch $manifest.appliedWatch -ExpectedRunId 'pong-behavior-watch-wall-bounce-every-n-run-01' -ExpectedNodePath '/root/Main/Ball' -ExpectedProperties @('position', 'velocity', 'speed') -ExpectedMode 'every_n_frames' -ExpectedStartFrameOffset 20 -ExpectedFrameCount 6 -ExpectedSampleCount 3
        $manifest.appliedWatch.cadence.everyNFrames | Should -Be 2
        Assert-BehaviorWatchTraceRows -Rows $traceRows -ExpectedNodePath '/root/Main/Ball' -ExpectedProperties @('position', 'velocity', 'speed') -ExpectedFrames @(20, 22, 24)
    }

    It 'accepts the build-failure lifecycle and run-result fixtures' {
        $lifecycleResult = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/lifecycle-status.build-failure.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json'
        )
        $runResultValidation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $runResult = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.build-failure.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $lifecycleResult.ExitCode | Should -Be 0
        $lifecycleResult.ParsedOutput.valid | Should -BeTrue
        $runResultValidation.ExitCode | Should -Be 0
        $runResultValidation.ParsedOutput.valid | Should -BeTrue
        Assert-BuildFailureRunResult -Result $runResult -ExpectedPhase 'launching' -ExpectedDiagnosticCount 2
        Assert-BuildDiagnostic -Diagnostic $runResult.buildDiagnostics[0] -ExpectedResourcePath 'res://scripts/build_failures/syntax_error_root.gd' -ExpectedSourceKind 'script'
        Assert-BuildDiagnostic -Diagnostic $runResult.buildDiagnostics[1] -ExpectedResourcePath 'res://scripts/build_failures/syntax_error_child.gd' -ExpectedSourceKind 'script'
    }

    It 'accepts the completed lifecycle fixture' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/lifecycle-status.completed.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-lifecycle-status.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
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

    It 'preserves success-path compatibility by omitting build payloads from the healthy run fixture' {
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.success.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $result.failureKind | Should -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Not -Contain 'buildFailurePhase'
        $result.PSObject.Properties.Name | Should -Not -Contain 'buildDiagnostics'
        $result.PSObject.Properties.Name | Should -Not -Contain 'rawBuildOutput'
        $result.manifestPath | Should -Be 'examples/pong-testbed/harness/expected-evidence-manifest.json'
    }

    It 'preserves multiple build diagnostics for the multi-error fixture' {
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.multi-diagnostic.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.build-failure.multi-diagnostic.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $validation.ExitCode | Should -Be 0
        $validation.ParsedOutput.valid | Should -BeTrue
        Assert-BuildFailureRunResult -Result $result -ExpectedPhase 'launching' -ExpectedDiagnosticCount 3
    }

    It 'keeps stale manifests out of the build-failed result' {
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.stale-manifest.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.build-failure.stale-manifest.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $validation.ExitCode | Should -Be 0
        $validation.ParsedOutput.valid | Should -BeTrue
        $result.manifestPath | Should -BeNullOrEmpty
        $result.validationResult.notes | Should -Contain 'An existing manifest file was ignored so stale evidence would not be reported for this build-failed run.'
    }

    It 'classifies blocking resource-load failures as build failures with resource diagnostics' {
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.resource-load.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.build-failure.resource-load.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $validation.ExitCode | Should -Be 0
        $validation.ParsedOutput.valid | Should -BeTrue
        Assert-BuildFailureRunResult -Result $result -ExpectedPhase 'launching' -ExpectedDiagnosticCount 1
        Assert-BuildDiagnostic -Diagnostic $result.buildDiagnostics[0] -ExpectedResourcePath 'res://textures/missing_build_failure.png' -ExpectedSourceKind 'resource'
    }

    It 'retains partial build metadata and raw output when exact coordinates are unavailable' {
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.partial-metadata.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.build-failure.partial-metadata.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $validation.ExitCode | Should -Be 0
        $validation.ParsedOutput.valid | Should -BeTrue
        $result.buildDiagnostics[0].line | Should -BeNullOrEmpty
        $result.buildDiagnostics[0].column | Should -BeNullOrEmpty
        $result.buildDiagnostics[0].code | Should -BeNullOrEmpty
        $result.buildDiagnostics[0].rawExcerpt | Should -Not -BeNullOrEmpty
    }

    It 'keeps blocked non-build outcomes distinct from build failures' {
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.blocked-nonbuild.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )
        $result = Get-Content -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/run-result.blocked-nonbuild.expected.json') -Raw | ConvertFrom-Json -Depth 100

        $validation.ExitCode | Should -Be 0
        $validation.ParsedOutput.valid | Should -BeTrue
        $result.finalStatus | Should -Be 'blocked'
        $result.failureKind | Should -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Not -Contain 'buildDiagnostics'
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
