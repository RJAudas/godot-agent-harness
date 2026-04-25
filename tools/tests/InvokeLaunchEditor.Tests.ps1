BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:LaunchScript = Join-Path $script:RepoRootPath 'tools/automation/invoke-launch-editor.ps1'
    $script:StopScript   = Join-Path $script:RepoRootPath 'tools/automation/invoke-stop-editor.ps1'
    $script:StdoutSchema = 'specs/008-agent-runbook/contracts/orchestration-stdout.schema.json'
}

Describe 'invoke-launch-editor.ps1' {

    It 'fails with failureKind=internal when ProjectRoot does not exist' {
        $bogus = Join-Path $TestDrive 'does-not-exist'
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-launch-editor.ps1' `
            -Arguments @('-ProjectRoot', $bogus)
        $result.ExitCode | Should -Be 1
        $envelope = $result.Output | ConvertFrom-Json
        $envelope.status      | Should -Be 'failure'
        $envelope.failureKind | Should -Be 'internal'
        $envelope.diagnostics[0] | Should -Match 'does not exist'
    }

    It 'fails with failureKind=internal when ProjectRoot has no project.godot' {
        $emptyDir = Join-Path $TestDrive ('empty-' + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-launch-editor.ps1' `
            -Arguments @('-ProjectRoot', $emptyDir)
        $result.ExitCode | Should -Be 1
        $envelope = $result.Output | ConvertFrom-Json
        $envelope.status      | Should -Be 'failure'
        $envelope.failureKind | Should -Be 'internal'
        $envelope.diagnostics[0] | Should -Match 'project\.godot'
    }

    It 'failure envelope validates against the orchestration-stdout schema' {
        $bogus = Join-Path $TestDrive 'does-not-exist'
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-launch-editor.ps1' `
            -Arguments @('-ProjectRoot', $bogus)
        $tmpPath = Join-Path $TestDrive 'launch-editor-failure-envelope.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath,
            '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }

    Context 'live launch (opt-in via $env:HARNESS_LIVE_TESTS=1)' {
        # These tests spawn a real Godot editor and are slow (~30-60s cold start).
        # They are intentionally OFF by default -- run them with:
        #   $env:HARNESS_LIVE_TESTS = '1'; $env:GODOT_BIN = '<godot.exe>'
        #   pwsh ./tools/tests/run-tool-tests.ps1
        # The plain `pwsh ./tools/tests/run-tool-tests.ps1` invocation skips them.

        BeforeAll {
            $script:LiveTestsEnabled = ($env:HARNESS_LIVE_TESTS -eq '1') `
                -and (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) `
                -and (Test-Path -LiteralPath $env:GODOT_BIN)
            $script:LiveSandbox = if ($script:LiveTestsEnabled) {
                $name = 'launch-test-' + [guid]::NewGuid().Guid.Substring(0, 6)
                pwsh -NoProfile -File (Join-Path $script:RepoRootPath 'tools/scaffold-sandbox.ps1') `
                    -Name $name -Force -PassThru | Out-Null
                Join-Path (Join-Path $script:RepoRootPath 'integration-testing') $name
            } else { $null }
        }

        AfterAll {
            if ($script:LiveSandbox -and (Test-Path -LiteralPath $script:LiveSandbox)) {
                pwsh -NoProfile -File (Join-Path $script:RepoRootPath 'tools/automation/invoke-stop-editor.ps1') `
                    -ProjectRoot $script:LiveSandbox -ErrorAction SilentlyContinue | Out-Null
                Start-Sleep -Milliseconds 500
                Remove-Item -LiteralPath $script:LiveSandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'launches an editor and reports a fresh capability.json (live)' {
            if (-not $script:LiveTestsEnabled) {
                Set-ItResult -Skipped -Because '$env:HARNESS_LIVE_TESTS not set to 1; live editor test skipped'
                return
            }

            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-launch-editor.ps1' `
                -Arguments @('-ProjectRoot', $script:LiveSandbox, '-ReadyTimeoutSeconds', '120')
            $result.ExitCode | Should -Be 0
            $envelope = $result.Output | ConvertFrom-Json
            $envelope.status                       | Should -Be 'success'
            $envelope.outcome.editorPid            | Should -BeGreaterThan 0
            $envelope.outcome.capabilityAgeSeconds | Should -BeGreaterOrEqual 0
            Test-Path -LiteralPath $envelope.outcome.capabilityPath | Should -BeTrue
        }

        It 'is idempotent — second call reuses the live editor (live)' {
            if (-not $script:LiveTestsEnabled) {
                Set-ItResult -Skipped -Because '$env:HARNESS_LIVE_TESTS not set to 1; live editor test skipped'
                return
            }

            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-launch-editor.ps1' `
                -Arguments @('-ProjectRoot', $script:LiveSandbox)
            $result.ExitCode | Should -Be 0
            $envelope = $result.Output | ConvertFrom-Json
            $envelope.status                       | Should -Be 'success'
            $envelope.outcome.reusedExistingEditor | Should -BeTrue
        }

        It 'invoke-stop-editor.ps1 reports the stopped PIDs (live)' {
            if (-not $script:LiveTestsEnabled) {
                Set-ItResult -Skipped -Because '$env:HARNESS_LIVE_TESTS not set to 1; live editor test skipped'
                return
            }

            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-stop-editor.ps1' `
                -Arguments @('-ProjectRoot', $script:LiveSandbox)
            $result.ExitCode | Should -Be 0
            $envelope = $result.Output | ConvertFrom-Json
            $envelope.status                | Should -Be 'success'
            @($envelope.outcome.remainingPids).Count | Should -Be 0
        }
    }
}

Describe 'invoke-stop-editor.ps1' {

    It 'fails with failureKind=internal when ProjectRoot does not exist' {
        $bogus = Join-Path $TestDrive 'does-not-exist'
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-stop-editor.ps1' `
            -Arguments @('-ProjectRoot', $bogus)
        $result.ExitCode | Should -Be 1
        $envelope = $result.Output | ConvertFrom-Json
        $envelope.status      | Should -Be 'failure'
        $envelope.failureKind | Should -Be 'internal'
    }

    It 'returns success with noopReason when no editor matches' {
        $emptyProject = Join-Path $TestDrive ('empty-' + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $emptyProject -Force | Out-Null
        # Doesn't need project.godot — stop helper just checks the dir exists
        # before scanning processes.
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-stop-editor.ps1' `
            -Arguments @('-ProjectRoot', $emptyProject)
        $result.ExitCode | Should -Be 0
        $envelope = $result.Output | ConvertFrom-Json
        $envelope.status                  | Should -Be 'success'
        @($envelope.outcome.stoppedPids).Count | Should -Be 0
        $envelope.outcome.noopReason       | Should -Be 'no-matching-editor'
    }
}
