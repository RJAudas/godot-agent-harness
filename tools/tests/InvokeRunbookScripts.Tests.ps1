BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:ModulePath   = Join-Path $script:RepoRootPath 'tools/automation/RunbookOrchestration.psm1'
    $script:StdoutSchema = 'specs/008-agent-runbook/contracts/orchestration-stdout.schema.json'

    Import-Module $script:ModulePath -Force

    # Shared fake run-result used by multiple test suites
    $script:FakeRunResultSuccess = @{
        requestId   = 'REPLACED-BY-TEST'
        runId       = 'runbook-test-run-001'
        finalStatus = 'completed'
        failureKind = $null
        completedAt = '2026-04-22T14:45:08.123Z'
        manifestPath = 'tools/tests/fixtures/pong-testbed/evidence/automation/pong-autonomous-run-001/evidence-manifest.json'
    }

    $script:FakeRunResultBuildFailure = @{
        requestId   = 'REPLACED-BY-TEST'
        runId       = 'runbook-test-run-002'
        finalStatus = 'failed'
        failureKind = 'build'
        completedAt = '2026-04-22T14:45:08.123Z'
        manifestPath = $null
    }

    $script:FakeRunResultRuntimeFailure = @{
        requestId   = 'REPLACED-BY-TEST'
        runId       = 'runbook-test-run-003'
        finalStatus = 'failed'
        failureKind = 'runtime'
        completedAt = '2026-04-22T14:45:08.123Z'
        manifestPath = 'tools/tests/fixtures/pong-testbed/evidence/automation/pong-autonomous-run-001/evidence-manifest.json'
    }
}

# ---------------------------------------------------------------------------
# Smoke test: module imports cleanly
# ---------------------------------------------------------------------------

Describe 'RunbookOrchestration module' {
    It 'imports the orchestration module' {
        $exported = Get-Command -Module RunbookOrchestration | Select-Object -ExpandProperty Name
        $exported | Should -Contain 'New-RunbookRequestId'
        $exported | Should -Contain 'Test-RunbookCapability'
        $exported | Should -Contain 'Resolve-RunbookPayload'
        $exported | Should -Contain 'Invoke-RunbookRequest'
        $exported | Should -Contain 'Write-RunbookEnvelope'
    }

    It 'New-RunbookRequestId returns correct format' {
        $id = New-RunbookRequestId -Workflow 'input-dispatch'
        $id | Should -Match '^runbook-input-dispatch-\d{8}T\d{6}Z-[a-f0-9]{6}$'
    }

    It 'Write-RunbookEnvelope emits valid JSON' {
        $json = Write-RunbookEnvelope -Status 'success' -ManifestPath 'C:\fake\manifest.json' `
            -RunId 'run-001' -RequestId 'req-001' -Diagnostics @() `
            -Outcome @{ sceneTreePath = 'C:\fake\scene-tree.json'; nodeCount = 5 }
        $parsed = $json | ConvertFrom-Json
        $parsed.status | Should -Be 'success'
        $parsed.failureKind | Should -BeNullOrEmpty
        $parsed.outcome.nodeCount | Should -Be 5
    }

    It 'Write-RunbookEnvelope failure envelope validates against schema' {
        $json = Write-RunbookEnvelope -Status 'failure' -FailureKind 'editor-not-running' `
            -ManifestPath $null -RunId 'run-001' -RequestId 'req-001' `
            -Diagnostics @('Editor not running') -Outcome @{}
        $tmpPath = Join-Path $TestDrive 'envelope-failure.json'
        $json | Set-Content -LiteralPath $tmpPath -Encoding utf8

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath,
            '-SchemaPath', $script:StdoutSchema
        )
        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'Write-RunbookEnvelope success envelope validates against schema' {
        $json = Write-RunbookEnvelope -Status 'success' -ManifestPath 'C:\fake\manifest.json' `
            -RunId 'run-001' -RequestId 'req-001' -Diagnostics @() -Outcome @{ foo = 'bar' }
        $tmpPath = Join-Path $TestDrive 'envelope-success.json'
        $json | Set-Content -LiteralPath $tmpPath -Encoding utf8

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath,
            '-SchemaPath', $script:StdoutSchema
        )
        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'Resolve-RunbookPayload throws on mutual exclusion' {
        { Resolve-RunbookPayload -FixturePath 'some/path.json' -InlineJson '{}' -RequestId 'req' -ProjectRoot $TestDrive } | Should -Throw
    }

    It 'Resolve-RunbookPayload throws when neither is supplied' {
        { Resolve-RunbookPayload -RequestId 'req' -ProjectRoot $TestDrive } | Should -Throw
    }
}

# ---------------------------------------------------------------------------
# RUNBOOK static checks (T007)
# ---------------------------------------------------------------------------

Describe 'RUNBOOK static checks' {
    BeforeAll {
        $script:RunbookPath = Join-Path $script:RepoRootPath 'RUNBOOK.md'
        $script:RunbookContent = Get-Content -LiteralPath $script:RunbookPath -Raw

        # Parse the workflow table rows (skip header and separator lines).
        # TrimEnd() is required so CRLF-encoded files don't break the separator regex.
        $tableLines = ($script:RunbookContent -split "`n" | ForEach-Object { $_.TrimEnd() }) |
            Where-Object { $_ -match '^\|' -and $_ -notmatch '^\|[-| ]+\|$' -and $_ -notmatch '\| Workflow \|' }

        $script:ParsedRows = $tableLines | ForEach-Object {
            $cols = $_ -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            if ($cols.Count -ge 5) {
                [pscustomobject]@{
                    Workflow            = $cols[0]
                    Description         = $cols[1]
                    OrchestrationScript = $cols[2] -replace '`', ''
                    Fixture             = $cols[3] -replace '`', ''
                    Recipe              = if ($cols[4] -match '\[.*?\]\((.*?)\)') { $Matches[1] } else { $cols[4] }
                }
            }
        } | Where-Object { $null -ne $_ }
    }

    It 'RUNBOOK.md exists' {
        Test-Path -LiteralPath $script:RunbookPath | Should -BeTrue
    }

    It 'RUNBOOK.md has exactly 5 workflow rows' {
        $script:ParsedRows.Count | Should -Be 5
    }

    It 'workflow rows appear in required order' {
        $expectedOrder = @('Input dispatch', 'Scene inspection', 'Behavior watch', 'Build-error triage', 'Runtime-error triage')
        for ($i = 0; $i -lt $expectedOrder.Count; $i++) {
            $script:ParsedRows[$i].Workflow | Should -Be $expectedOrder[$i]
        }
    }

    It 'every orchestration script path exists' {
        foreach ($row in $script:ParsedRows) {
            $scriptPath = Join-Path $script:RepoRootPath $row.OrchestrationScript
            Test-Path -LiteralPath $scriptPath | Should -BeTrue -Because "Row '$($row.Workflow)' references '$($row.OrchestrationScript)'"
        }
    }

    It 'every fixture path exists (or is "no payload")' {
        foreach ($row in $script:ParsedRows) {
            if ($row.Fixture -eq 'no payload') { continue }
            $fixturePath = Join-Path $script:RepoRootPath $row.Fixture
            Test-Path -LiteralPath $fixturePath | Should -BeTrue -Because "Row '$($row.Workflow)' references fixture '$($row.Fixture)'"
        }
    }

    It 'every recipe path exists' {
        foreach ($row in $script:ParsedRows) {
            $recipePath = Join-Path $script:RepoRootPath $row.Recipe
            Test-Path -LiteralPath $recipePath | Should -BeTrue -Because "Row '$($row.Workflow)' references recipe '$($row.Recipe)'"
        }
    }

    It 'each RUNBOOK row validates against runbook-entry schema' {
        foreach ($row in $script:ParsedRows) {
            $entryObj = [ordered]@{
                workflow            = $row.Workflow
                description         = $row.Description
                orchestrationScript = $row.OrchestrationScript
                fixture             = $row.Fixture
                recipe              = $row.Recipe
            }
            $tmpPath = Join-Path $TestDrive "runbook-entry-$($row.Workflow -replace ' ', '-').json"
            $entryObj | ConvertTo-Json | Set-Content -LiteralPath $tmpPath -Encoding utf8
            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $tmpPath,
                '-SchemaPath', 'specs/008-agent-runbook/contracts/runbook-entry.schema.json'
            )
            $result.ParsedOutput.valid | Should -BeTrue -Because "Row '$($row.Workflow)' should satisfy the runbook-entry schema"
        }
    }

    It 'SC-002: recipe files do not reference addon source outside the do-not-read marker' {
        $recipeFiles = Get-ChildItem -LiteralPath (Join-Path $script:RepoRootPath 'docs/runbook') -Filter '*.md' -File
        foreach ($file in $recipeFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            # Strip out the canonical marker blocks — anything inside is allowed
            $stripped = [regex]::Replace(
                $content,
                '<!--\s*runbook:do-not-read-addon-source\s*-->.*?<!--\s*/runbook:do-not-read-addon-source\s*-->',
                '',
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )
            $stripped | Should -Not -Match 'addons/agent_runtime_harness/' -Because "File '$($file.Name)' references addon source outside the canonical marker block (SC-002)"
        }
    }

    It 'SC-002: godot-runtime-verification prompt does not reference addon source outside the do-not-read marker' {
        $promptFile = Join-Path $script:RepoRootPath '.github/prompts/godot-runtime-verification.prompt.md'
        if (-not (Test-Path -LiteralPath $promptFile)) { Set-ItResult -Skipped -Because 'prompt file not found'; return }
        $content = Get-Content -LiteralPath $promptFile -Raw
        $stripped = [regex]::Replace(
            $content,
            '<!--\s*runbook:do-not-read-addon-source\s*-->.*?<!--\s*/runbook:do-not-read-addon-source\s*-->',
            '',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $stripped | Should -Not -Match 'addons/agent_runtime_harness/' -Because 'SC-002'
    }

    It 'SC-002: godot-evidence-triage agent does not reference addon source outside the do-not-read marker' {
        $agentFile = Join-Path $script:RepoRootPath '.github/agents/godot-evidence-triage.agent.md'
        if (-not (Test-Path -LiteralPath $agentFile)) { Set-ItResult -Skipped -Because 'agent file not found'; return }
        $content = Get-Content -LiteralPath $agentFile -Raw
        $stripped = [regex]::Replace(
            $content,
            '<!--\s*runbook:do-not-read-addon-source\s*-->.*?<!--\s*/runbook:do-not-read-addon-source\s*-->',
            '',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $stripped | Should -Not -Match 'addons/agent_runtime_harness/' -Because 'SC-002'
    }

    It 'SC-006: every invoke-*.ps1 script has Get-Help synopsis and description' {
        $scripts = Get-ChildItem -LiteralPath (Join-Path $script:RepoRootPath 'tools/automation') -Filter 'invoke-*.ps1' -File
        foreach ($script in $scripts) {
            $help = Get-Help $script.FullName -Full 2>$null
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$($script.Name) must have .SYNOPSIS"
            $help.Description | Should -Not -BeNullOrEmpty -Because "$($script.Name) must have .DESCRIPTION"
        }
    }

    It 'input-dispatch fixtures validate against their upstream schema' {
        $fixtureDir = Join-Path $script:RepoRootPath 'tools/tests/fixtures/runbook/input-dispatch'
        $fixtures = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.json' -File
        foreach ($fixture in $fixtures) {
            # Extract inputDispatchScript field and validate it
            $payload = Get-Content -LiteralPath $fixture.FullName -Raw | ConvertFrom-Json
            $dispatchScript = $payload.inputDispatchScript
            if ($null -ne $dispatchScript) {
                $tmpPath = Join-Path $TestDrive "dispatch-$($fixture.Name)"
                $dispatchScript | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpPath -Encoding utf8
                $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                    '-InputPath', $tmpPath,
                    '-SchemaPath', 'specs/006-input-dispatch/contracts/input-dispatch-script.schema.json'
                )
                $result.ParsedOutput.valid | Should -BeTrue -Because "Fixture '$($fixture.Name)' inputDispatchScript should satisfy its schema"
            }
        }
    }

    It 'behavior-watch fixtures validate against their upstream schema' {
        $fixtureDir = Join-Path $script:RepoRootPath 'tools/tests/fixtures/runbook/behavior-watch'
        $fixtures = Get-ChildItem -LiteralPath $fixtureDir -Filter '*.json' -File
        foreach ($fixture in $fixtures) {
            $payload = Get-Content -LiteralPath $fixture.FullName -Raw | ConvertFrom-Json
            $watchRequest = $payload.behaviorWatchRequest
            if ($null -ne $watchRequest) {
                $tmpPath = Join-Path $TestDrive "watch-$($fixture.Name)"
                $watchRequest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpPath -Encoding utf8
                $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                    '-InputPath', $tmpPath,
                    '-SchemaPath', 'specs/005-behavior-watch-sampling/contracts/behavior-watch-request.schema.json'
                )
                $result.ParsedOutput.valid | Should -BeTrue -Because "Fixture '$($fixture.Name)' behaviorWatchRequest should satisfy its schema"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# US1 — invoke-input-dispatch.ps1
# ---------------------------------------------------------------------------

Describe 'invoke-input-dispatch.ps1' {
    BeforeAll {
        $script:InputDispatchScript = Join-Path $script:RepoRootPath 'tools/automation/invoke-input-dispatch.ps1'
        $script:FakeProjectRoot = Join-Path $TestDrive 'fake-project'
        New-Item -ItemType Directory -Path $script:FakeProjectRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot 'harness/automation/results') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot 'harness/automation/requests') -Force | Out-Null
    }

    It 'exits non-zero when neither -RequestFixturePath nor -RequestJson is supplied' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot)
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed) {
            $parsed.failureKind | Should -Be 'request-invalid'
        }
    }

    It 'exits non-zero when both -RequestFixturePath and -RequestJson are supplied' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json',
                         '-RequestJson', '{"requestId":"x"}')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed) {
            $parsed.failureKind | Should -Be 'request-invalid'
        }
    }

    It 'returns editor-not-running when capability.json is missing' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json',
                         '-MaxCapabilityAgeSeconds', '300')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.status | Should -Be 'failure'
        $parsed.failureKind | Should -Be 'editor-not-running'
    }

    It 'editor-not-running envelope validates against stdout schema' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')
        $tmpPath = Join-Path $TestDrive 'dispatch-not-running.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath, '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }

    It 'returns stale-capability editor-not-running when capability.json is outdated' {
        $capabilityDir = Join-Path $script:FakeProjectRoot 'harness/automation/results'
        $capPath = Join-Path $capabilityDir 'capability.json'
        '{"checkedAt":"2020-01-01T00:00:00Z","singleTargetReady":false}' | Set-Content -LiteralPath $capPath
        (Get-Item -LiteralPath $capPath).LastWriteTime = (Get-Date).AddSeconds(-500)

        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json',
                         '-MaxCapabilityAgeSeconds', '300')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.failureKind | Should -Be 'editor-not-running'
    }
}

# ---------------------------------------------------------------------------
# US2 — invoke-scene-inspection.ps1
# ---------------------------------------------------------------------------

Describe 'invoke-scene-inspection.ps1' {
    BeforeAll {
        $script:FakeProjectRoot2 = Join-Path $TestDrive 'fake-project-scene'
        New-Item -ItemType Directory -Path $script:FakeProjectRoot2 -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot2 'harness/automation/results') -Force | Out-Null
    }

    It 'returns editor-not-running (no payload required)' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-scene-inspection.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot2)
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.status | Should -Be 'failure'
        $parsed.failureKind | Should -Be 'editor-not-running'
    }

    It 'editor-not-running envelope validates against stdout schema' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-scene-inspection.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot2)
        $tmpPath = Join-Path $TestDrive 'scene-not-running.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath, '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# US3 — invoke-build-error-triage.ps1
# ---------------------------------------------------------------------------

Describe 'invoke-build-error-triage.ps1' {
    BeforeAll {
        $script:FakeProjectRoot3 = Join-Path $TestDrive 'fake-project-build'
        New-Item -ItemType Directory -Path $script:FakeProjectRoot3 -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot3 'harness/automation/results') -Force | Out-Null
    }

    It 'exits non-zero when neither -RequestFixturePath nor -RequestJson is supplied' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-build-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot3)
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed) {
            $parsed.failureKind | Should -Be 'request-invalid'
        }
    }

    It 'returns editor-not-running when capability.json is missing' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-build-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot3,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.failureKind | Should -Be 'editor-not-running'
    }

    It 'editor-not-running envelope validates against stdout schema' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-build-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot3,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/build-error-triage/build-then-capture.json')
        $tmpPath = Join-Path $TestDrive 'build-not-running.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath, '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# US3 — invoke-runtime-error-triage.ps1
# ---------------------------------------------------------------------------

Describe 'invoke-runtime-error-triage.ps1' {
    BeforeAll {
        $script:FakeProjectRoot4 = Join-Path $TestDrive 'fake-project-runtime'
        New-Item -ItemType Directory -Path $script:FakeProjectRoot4 -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot4 'harness/automation/results') -Force | Out-Null
    }

    It 'exits non-zero when neither -RequestFixturePath nor -RequestJson is supplied' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-runtime-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot4)
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed) {
            $parsed.failureKind | Should -Be 'request-invalid'
        }
    }

    It 'returns editor-not-running when capability.json is missing' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-runtime-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot4,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.failureKind | Should -Be 'editor-not-running'
    }

    It 'editor-not-running envelope validates against stdout schema' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-runtime-error-triage.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot4,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/runtime-error-triage/run-and-watch-for-errors.json')
        $tmpPath = Join-Path $TestDrive 'runtime-not-running.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath, '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# US4 — invoke-behavior-watch.ps1
# ---------------------------------------------------------------------------

Describe 'invoke-behavior-watch.ps1' {
    BeforeAll {
        $script:FakeProjectRoot5 = Join-Path $TestDrive 'fake-project-watch'
        New-Item -ItemType Directory -Path $script:FakeProjectRoot5 -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:FakeProjectRoot5 'harness/automation/results') -Force | Out-Null
    }

    It 'exits non-zero when neither -RequestFixturePath nor -RequestJson is supplied' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-behavior-watch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot5)
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -ne $parsed) {
            $parsed.failureKind | Should -Be 'request-invalid'
        }
    }

    It 'returns editor-not-running when capability.json is missing' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-behavior-watch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot5,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/behavior-watch/single-property-window.json')
        $result.ExitCode | Should -Not -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.failureKind | Should -Be 'editor-not-running'
    }

    It 'editor-not-running envelope validates against stdout schema' {
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-behavior-watch.ps1' `
            -Arguments @('-ProjectRoot', $script:FakeProjectRoot5,
                         '-RequestFixturePath', 'tools/tests/fixtures/runbook/behavior-watch/single-property-window.json')
        $tmpPath = Join-Path $TestDrive 'watch-not-running.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath, '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }
}
