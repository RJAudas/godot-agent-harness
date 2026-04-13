Describe 'tools/automation/validate-write-boundary.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts an in-bound relative request' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'godot-evidence-triage.agent',
            '-RequestedPath', 'tools/evals/001-agent-tooling-foundation/us3-validation-results.json',
            '-RequestedEditType', 'update'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.requestAllowed | Should -BeTrue
        @($result.ParsedOutput.violations).Count | Should -Be 0
    }

    It 'accepts an in-bound absolute request path' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'godot-evidence-triage.agent',
            '-RequestedPath', (Get-RepoPath -Path 'tools/automation/run-records/godot-evidence-triage-validation.json'),
            '-RequestedEditType', 'update'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.requestAllowed | Should -BeTrue
    }

    It 'reports violations for out-of-bound requests when AllowViolation is set' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'godot-evidence-triage.agent',
            '-RequestedPath', 'addons/agent_runtime_harness/plugin.gd',
            '-RequestedEditType', 'update',
            '-AllowViolation'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.requestAllowed | Should -BeFalse
        @($result.ParsedOutput.violations).Count | Should -Be 1
        $result.ParsedOutput.violations[0].reason | Should -Match 'outside the declared write boundary'
    }

    It 'exits non-zero for out-of-bound requests without AllowViolation' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'godot-evidence-triage.agent',
            '-RequestedPath', 'addons/agent_runtime_harness/plugin.gd',
            '-RequestedEditType', 'update'
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.requestAllowed | Should -BeFalse
    }

    It 'rejects unknown artifact identifiers' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'unknown-artifact',
            '-RequestedPath', 'tools/evals/001-agent-tooling-foundation/us3-validation-results.json',
            '-RequestedEditType', 'update'
        )

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "No write boundary found for artifact 'unknown-artifact'"
    }

    It 'rejects mismatched path and edit-type counts' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                RequestedPath = @(
                    'tools/evals/001-agent-tooling-foundation/us3-validation-results.json',
                    'tools/automation/run-records/godot-evidence-triage-validation.json'
                )
                RequestedEditType = @('update', 'create', 'delete')
                PassThru = $true
            }
        } | Should -Throw '*RequestedEditType must contain either one shared edit type or one edit type per requested path*'
    }

    It 'treats absolute paths outside the repository as violations' {
        $outsidePath = Join-Path $TestDrive 'outside-repo.json'
        Set-Content -LiteralPath $outsidePath -Value '{}' -NoNewline

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/automation/validate-write-boundary.ps1' -Arguments @(
            '-ArtifactId', 'godot-evidence-triage.agent',
            '-RequestedPath', $outsidePath,
            '-RequestedEditType', 'update',
            '-AllowViolation'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.requestAllowed | Should -BeFalse
        $result.ParsedOutput.violations[0].reason | Should -Match 'resolves outside the repository root'
    }
}

Describe 'tools/automation/new-autonomous-run-record.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'generates a valid minimal run record with default values' {
        $outputPath = Join-Path $TestDrive 'run-record.json'

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
            ArtifactId = 'godot-evidence-triage.agent'
            WriteBoundaryId = 'godot-evidence-triage-first-release'
            RequestSummary = 'Validate tooling script coverage.'
            OutputPath = $outputPath
            PassThru = $true
        }

        $record = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
        $validationResult = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $outputPath,
            '-SchemaPath', 'tools/automation/autonomous-run-record.schema.json'
        )

        $result.recordPath | Should -Be $outputPath
        $result.operationCount | Should -Be 0
        $result.validationCount | Should -Be 0
        $record.mode | Should -Be 'simulated'
        $record.status | Should -Be 'success'
        $validationResult.ExitCode | Should -Be 0
        $validationResult.ParsedOutput.valid | Should -BeTrue
    }

    It 'creates parent directories for nested output paths' {
        $outputPath = Join-Path $TestDrive 'nested\run-records\record.json'

        Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
            ArtifactId = 'godot-evidence-triage.agent'
            WriteBoundaryId = 'godot-evidence-triage-first-release'
            RequestSummary = 'Create a nested output record.'
            OutputPath = $outputPath
            PassThru = $true
        } | Out-Null

        $outputPath | Should -Exist
    }

    It 'applies default operation and validation field values' {
        $outputPath = Join-Path $TestDrive 'defaults-record.json'

        Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
            ArtifactId = 'godot-evidence-triage.agent'
            WriteBoundaryId = 'godot-evidence-triage-first-release'
            RequestSummary = 'Exercise default operation values.'
            OutputPath = $outputPath
            OperationPath = @('tools/evals/001-agent-tooling-foundation/us3-validation-results.json')
            ValidationName = @('write-boundary-check')
            PassThru = $true
        } | Out-Null

        $record = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
        $record.operations[0].editType | Should -Be 'read-only'
        $record.operations[0].status | Should -Be 'performed'
        $record.validations[0].status | Should -Be 'info'
        $record.validations[0].details | Should -Be 'No additional details recorded.'
    }

    It 'rejects mismatched operation edit types' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                WriteBoundaryId = 'godot-evidence-triage-first-release'
                RequestSummary = 'Mismatch operation edit types.'
                OutputPath = (Join-Path $TestDrive 'mismatch-edit.json')
                OperationPath = @('a', 'b')
                OperationEditType = @('update')
                PassThru = $true
            }
        } | Should -Throw '*OperationEditType must contain 2 entries*'
    }

    It 'rejects mismatched operation statuses' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                WriteBoundaryId = 'godot-evidence-triage-first-release'
                RequestSummary = 'Mismatch operation statuses.'
                OutputPath = (Join-Path $TestDrive 'mismatch-status.json')
                OperationPath = @('a', 'b')
                OperationStatus = @('performed')
                PassThru = $true
            }
        } | Should -Throw '*OperationStatus must contain 2 entries*'
    }

    It 'rejects mismatched operation notes' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                WriteBoundaryId = 'godot-evidence-triage-first-release'
                RequestSummary = 'Mismatch operation notes.'
                OutputPath = (Join-Path $TestDrive 'mismatch-note.json')
                OperationPath = @('a', 'b')
                OperationNote = @('note')
                PassThru = $true
            }
        } | Should -Throw '*OperationNote must contain 2 entries*'
    }

    It 'rejects mismatched validation statuses' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                WriteBoundaryId = 'godot-evidence-triage-first-release'
                RequestSummary = 'Mismatch validation statuses.'
                OutputPath = (Join-Path $TestDrive 'mismatch-validation-status.json')
                ValidationName = @('a', 'b')
                ValidationStatus = @('pass')
                PassThru = $true
            }
        } | Should -Throw '*ValidationStatus must contain 2 entries*'
    }

    It 'rejects mismatched validation details' {
        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/new-autonomous-run-record.ps1' -Parameters @{
                ArtifactId = 'godot-evidence-triage.agent'
                WriteBoundaryId = 'godot-evidence-triage-first-release'
                RequestSummary = 'Mismatch validation details.'
                OutputPath = (Join-Path $TestDrive 'mismatch-validation-details.json')
                ValidationName = @('a', 'b')
                ValidationDetails = @('detail')
                PassThru = $true
            }
        } | Should -Throw '*ValidationDetails must contain 2 entries*'
    }
}

Describe 'tools/automation/get-editor-evidence-capability.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'reads and validates a capability artifact for a sandbox project' {
        $sandboxPath = New-RepoSandboxDirectory

        try {
            $harnessPath = Join-Path $sandboxPath 'harness'
            $resultsPath = Join-Path $harnessPath 'automation\results'
            New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null
            Copy-Item -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/inspection-run-config.json') -Destination (Join-Path $harnessPath 'inspection-run-config.json')
            Copy-Item -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/automation/results/capability-ready.expected.json') -Destination (Join-Path $resultsPath 'capability.json')

            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/get-editor-evidence-capability.ps1' -Parameters @{
                ProjectRoot = $sandboxPath
                PassThru = $true
            }

            $result.exists | Should -BeTrue
            $result.schemaValid | Should -BeTrue
            $result.capability.recommendedControlPath | Should -Be 'file_broker'
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'tools/automation/request-editor-evidence-run.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'writes a schema-valid request artifact for a sandbox project' {
        $sandboxPath = New-RepoSandboxDirectory

        try {
            $harnessPath = Join-Path $sandboxPath 'harness'
            New-Item -ItemType Directory -Path $harnessPath -Force | Out-Null
            Copy-Item -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/inspection-run-config.json') -Destination (Join-Path $harnessPath 'inspection-run-config.json')

            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/request-editor-evidence-run.ps1' -Parameters @{
                ProjectRoot = $sandboxPath
                RequestFixturePath = 'examples/pong-testbed/harness/automation/requests/run-request.healthy.json'
                RequestedBy = 'automation-tools-test'
                PassThru = $true
            }

            $result.schemaValid | Should -BeTrue
            $request = Get-Content -LiteralPath $result.requestPath -Raw | ConvertFrom-Json -Depth 100
            $request.requestedBy | Should -Be 'automation-tools-test'
            $request.stopPolicy.stopAfterValidation | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a schema-valid build-failure request artifact for a sandbox project' {
        $sandboxPath = New-RepoSandboxDirectory

        try {
            $harnessPath = Join-Path $sandboxPath 'harness'
            New-Item -ItemType Directory -Path $harnessPath -Force | Out-Null
            Copy-Item -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/inspection-run-config.json') -Destination (Join-Path $harnessPath 'inspection-run-config.json')

            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/request-editor-evidence-run.ps1' -Parameters @{
                ProjectRoot = $sandboxPath
                RequestFixturePath = 'examples/pong-testbed/harness/automation/requests/run-request.build-failure.json'
                RequestedBy = 'automation-tools-build-failure-test'
                PassThru = $true
            }

            $result.schemaValid | Should -BeTrue
            $request = Get-Content -LiteralPath $result.requestPath -Raw | ConvertFrom-Json -Depth 100
            $request.requestedBy | Should -Be 'automation-tools-build-failure-test'
            $request.targetScene | Should -Be 'res://scenes/build_failure_missing_dependencies_case.tscn'
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'optionally validates the write boundary and emits an audit record' {
        $sandboxPath = New-RepoSandboxDirectory
        $runRecordPath = Join-Path $TestDrive 'editor-evidence-run-request-record.json'

        try {
            $harnessPath = Join-Path $sandboxPath 'harness'
            New-Item -ItemType Directory -Path $harnessPath -Force | Out-Null
            Copy-Item -LiteralPath (Get-RepoPath -Path 'examples/pong-testbed/harness/inspection-run-config.json') -Destination (Join-Path $harnessPath 'inspection-run-config.json')

            $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/request-editor-evidence-run.ps1' -Parameters @{
                ProjectRoot = $sandboxPath
                RequestFixturePath = 'examples/pong-testbed/harness/automation/requests/run-request.healthy.json'
                BoundaryArtifactId = 'editor-evidence-run-request.helper'
                WriteRunRecord = $true
                RunRecordArtifactId = 'editor-evidence-run-request.helper'
                RunRecordBoundaryId = 'editor-evidence-run-request-helper'
                RunRecordOutputPath = $runRecordPath
                PassThru = $true
            }

            $result.writeBoundaryValidated | Should -BeTrue
            $result.writeBoundaryId | Should -Be 'editor-evidence-run-request-helper'
            $result.runRecordPath | Should -Be $runRecordPath

            $runRecord = Get-Content -LiteralPath $runRecordPath -Raw | ConvertFrom-Json -Depth 100
            $runRecord.artifactId | Should -Be 'editor-evidence-run-request.helper'
            $runRecord.writeBoundaryId | Should -Be 'editor-evidence-run-request-helper'
            $runRecord.validations.name | Should -Contain 'write-boundary-validation'
            $runRecord.validations.name | Should -Contain 'request-schema-validation'
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'schema-consuming tool compatibility' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'keeps build-failure run-result fixtures compatible with the shared JSON validator' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'examples/pong-testbed/harness/automation/results/run-result.build-failure.expected.json',
            '-SchemaPath', 'specs/003-editor-evidence-loop/contracts/automation-run-result.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }
}
