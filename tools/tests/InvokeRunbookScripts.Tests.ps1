BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:ModulePath   = Join-Path $script:RepoRootPath 'tools/automation/RunbookOrchestration.psm1'
    $script:StdoutSchema = 'specs/008-agent-runbook/contracts/orchestration-stdout.schema.json'

    Import-Module $script:ModulePath -Force
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

    It 'H1: Invoke-Helper strips ANSI CSI sequences from CapturedOutput' {
        # Build a child script that emits ANSI-coloured text via Write-Error.
        # PowerShell 7's default ErrorView (ConciseView) emits CSI sequences for
        # colour, which is exactly what H1 strips out.
        $ansiScript = Join-Path $TestDrive 'emit-ansi.ps1'
        @'
param([string]$Tag = 'default')
Write-Error "boom: this should be coloured ($Tag)" -ErrorAction Continue
exit 0
'@ | Set-Content -LiteralPath $ansiScript -Encoding utf8

        InModuleScope RunbookOrchestration -Parameters @{ Path = $ansiScript } {
            param($Path)
            $result = Invoke-Helper -ScriptPath $Path -ArgumentList @('-Tag', 'h1-test')
            $result.CapturedOutput | Should -Not -Match "`e\["
            $result.CapturedOutput | Should -Match 'boom'
        }
    }
}

# ---------------------------------------------------------------------------
# C1 — Resolve-RunbookPayload validates before writing canonical path
# ---------------------------------------------------------------------------

Describe 'Resolve-RunbookPayload validate-then-rename (C1)' {
    BeforeEach {
        $script:C1Root = Join-Path $TestDrive ('c1-root-' + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $script:C1Root -Force | Out-Null
        $script:C1RequestsDir = Join-Path $script:C1Root 'harness/automation/requests'
        $script:C1Canonical   = Join-Path $script:C1RequestsDir 'run-request.json'
        $script:C1Tmp         = "$script:C1Canonical.tmp"
    }

    It 'C1: writes canonical path on a valid fixture and leaves no .tmp behind' {
        # Use a real shipped fixture which the schema accepts.
        $result = Resolve-RunbookPayload `
            -FixturePath 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json' `
            -RequestId 'runbook-input-dispatch-c1-success' `
            -ProjectRoot $script:C1Root

        $result.TempRequestPath | Should -Be $script:C1Canonical
        Test-Path -LiteralPath $script:C1Canonical | Should -BeTrue
        Test-Path -LiteralPath $script:C1Tmp       | Should -BeFalse

        # Canonical content should be the merged payload with our new requestId.
        $written = Get-Content -LiteralPath $script:C1Canonical -Raw | ConvertFrom-Json
        $written.requestId | Should -Be 'runbook-input-dispatch-c1-success'
    }

    It 'C1: throws and leaves no canonical / no .tmp when payload fails schema validation' {
        # Construct an inline payload that is missing several required fields.
        $bad = @{ requestId = 'will-be-overwritten'; runId = 'r' } | ConvertTo-Json -Depth 5

        { Resolve-RunbookPayload `
            -InlineJson $bad `
            -RequestId 'runbook-c1-schema-fail' `
            -ProjectRoot $script:C1Root
        } | Should -Throw -ExpectedMessage '*does not satisfy schema*'

        Test-Path -LiteralPath $script:C1Canonical | Should -BeFalse
        Test-Path -LiteralPath $script:C1Tmp       | Should -BeFalse
    }

    It 'C1: schema-failure diagnostic enumerates allowed values for enum violations (issue #47)' {
        # Behavior-watch fixture with a deliberately bogus property name. The orchestrator's
        # schema-validation diagnostic must now name the offending value AND list the allowed
        # set so a fixture author can correct it without leaving the diagnostic.
        $bad = @{
            requestId       = 'will-be-overwritten'
            scenarioId      = 'enrichment-test'
            runId           = 'r'
            targetScene     = 'res://scenes/main.tscn'
            outputDirectory = 'res://evidence/automation/x'
            artifactRoot    = ''
            capturePolicy   = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy      = @{ stopAfterValidation = $true }
            requestedBy     = 'enrichment-test'
            createdAt       = '2026-05-02T00:00:00Z'
            behaviorWatchRequest = @{
                targets = @(@{ nodePath = '/root/Main/Foo'; properties = @('position_xyz') })
                frameCount = 5
            }
        } | ConvertTo-Json -Depth 6

        $err = $null
        try {
            Resolve-RunbookPayload `
                -InlineJson $bad `
                -RequestId 'runbook-c1-enum-enriched' `
                -ProjectRoot $script:C1Root
        }
        catch {
            $err = $_.Exception.Message
        }

        $err | Should -Not -BeNullOrEmpty
        $err | Should -Match 'does not satisfy schema'
        $err | Should -Match "has value 'position_xyz'"
        $err | Should -Match 'allowed values:.*text.*linear_velocity'
    }

    It 'C2 follow-up: Resolve-RunbookEvidencePath joins relative paths against ProjectRoot' {
        # Evidence paths from run-result/manifest are project-relative, not repo-relative.
        # Use TestDrive so the assertion holds on any OS (Windows / macOS / Linux),
        # since [System.IO.Path]::IsPathRooted has different semantics across them.
        $projectRoot = Join-Path $TestDrive ('sandbox-' + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        $expected = Join-Path $projectRoot 'evidence/automation/runbook-x/evidence-manifest.json'
        $abs = Resolve-RunbookEvidencePath `
            -Path 'evidence/automation/runbook-x/evidence-manifest.json' `
            -ProjectRoot $projectRoot
        $abs | Should -Be $expected
    }

    It 'C2 follow-up: Resolve-RunbookEvidencePath returns absolute paths unchanged' {
        $projectRoot = Join-Path $TestDrive ('sandbox-' + [guid]::NewGuid().Guid)
        $absoluteManifestPath = Join-Path $TestDrive 'already/absolute/manifest.json'
        $abs = Resolve-RunbookEvidencePath `
            -Path $absoluteManifestPath `
            -ProjectRoot $projectRoot
        $abs | Should -Be $absoluteManifestPath
    }

    It 'C2: forces artifactRoot to empty string regardless of fixture content' {
        # press-enter.json sets artifactRoot to a fixture path under tools/tests/fixtures.
        # The runtime persists that string into manifest references and ignores it for
        # writes, breaking "manifestPath -> artifactRefs[*].path" navigation. We
        # overwrite to '' so the runtime's fallback uses outputDirectory instead.
        $result = Resolve-RunbookPayload `
            -FixturePath 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json' `
            -RequestId 'runbook-input-dispatch-c2-test' `
            -ProjectRoot $script:C1Root

        $result.Payload['artifactRoot'] | Should -Be ''

        $written = Get-Content -LiteralPath $script:C1Canonical -Raw | ConvertFrom-Json
        $written.artifactRoot | Should -Be ''
    }

    It 'B8: stamps runId = RequestId when payload omits runId (broker-can-not-fall-back-to-config invariant)' {
        # Pre-fix, an inline -RequestJson without an explicit runId let the broker fall back
        # to inspection-run-config.json's runId, so the manifest landed at the wrong path
        # and the orchestrator reported a misleading "manifest not found" failure.
        # Resolve-RunbookPayload now mirrors the requestId stamping for runId so the
        # request always carries a runId by the time it reaches the broker.
        $requestId = 'runbook-input-dispatch-b8-no-runid'
        $payloadHash = @{
            requestId        = 'will-be-overwritten'
            scenarioId       = 'b8-test-scenario'
            targetScene      = 'res://scenes/main.tscn'
            outputDirectory  = 'res://evidence/automation/$REQUEST_ID'
            artifactRoot     = 'tools/tests/fixtures/runbook/input-dispatch/evidence'
            expectationFiles = @()
            capturePolicy    = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy       = @{ stopAfterValidation = $true }
            requestedBy      = 'b8-test'
            createdAt        = '2026-04-25T00:00:00Z'
        }
        # Note: runId is intentionally NOT in the payload.
        $inline = $payloadHash | ConvertTo-Json -Depth 5

        $result = Resolve-RunbookPayload `
            -InlineJson $inline `
            -RequestId $requestId `
            -ProjectRoot $script:C1Root

        $result.Payload['runId'] | Should -Be $requestId

        $written = Get-Content -LiteralPath $script:C1Canonical -Raw | ConvertFrom-Json
        $written.runId | Should -Be $requestId
    }

    It 'B8: preserves caller-provided runId verbatim (does not clobber)' {
        # Belt-and-braces must NOT overwrite an explicit runId — fixtures and any
        # caller that wants the manifest to land at a known runId must remain in control.
        $requestId      = 'runbook-input-dispatch-b8-has-runid'
        $callerRunId    = 'caller-provided-run-id-001'
        $payloadHash = @{
            requestId        = 'will-be-overwritten'
            scenarioId       = 'b8-test-scenario'
            runId            = $callerRunId
            targetScene      = 'res://scenes/main.tscn'
            outputDirectory  = 'res://evidence/automation/$REQUEST_ID'
            artifactRoot     = 'tools/tests/fixtures/runbook/input-dispatch/evidence'
            expectationFiles = @()
            capturePolicy    = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy       = @{ stopAfterValidation = $true }
            requestedBy      = 'b8-test'
            createdAt        = '2026-04-25T00:00:00Z'
        }
        $inline = $payloadHash | ConvertTo-Json -Depth 5

        $result = Resolve-RunbookPayload `
            -InlineJson $inline `
            -RequestId $requestId `
            -ProjectRoot $script:C1Root

        $result.Payload['runId']    | Should -Be $callerRunId
        $result.Payload['requestId'] | Should -Be $requestId

        $written = Get-Content -LiteralPath $script:C1Canonical -Raw | ConvertFrom-Json
        $written.runId | Should -Be $callerRunId
    }

    It 'M6: substitutes $REQUEST_ID placeholder in outputDirectory with the resolved RequestId' {
        # Fixtures declare outputDirectory as "res://evidence/automation/$REQUEST_ID" so each
        # run lands in its own collision-free directory. Resolve-RunbookPayload must perform
        # the substitution before schema validation and before writing run-request.json.
        # (B1: the previous "<workflow>-$REQUEST_ID" pattern doubled the workflow prefix
        # because requestId already starts with "runbook-<workflow>-".)
        $requestId = 'runbook-input-dispatch-m6-test'
        $result = Resolve-RunbookPayload `
            -FixturePath 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json' `
            -RequestId $requestId `
            -ProjectRoot $script:C1Root

        $expected = "res://evidence/automation/$requestId"
        $result.Payload['outputDirectory'] | Should -Be $expected

        # The persisted run-request.json must carry the substituted value (no literal token).
        $written = Get-Content -LiteralPath $script:C1Canonical -Raw | ConvertFrom-Json
        $written.outputDirectory | Should -Be $expected
        $written.outputDirectory | Should -Not -Match '\$REQUEST_ID'
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

    It 'L2: every invoke-*.ps1 .EXAMPLE -ProjectRoot points at the canonical probe sandbox' {
        # Fresh agents copy-paste these examples verbatim. integration-testing/ is git-ignored,
        # so we cannot assert "path exists on disk" in CI; instead we pin every example to
        # ./integration-testing/probe (the scaffold-sandbox.ps1 default). Anyone running
        # `tools/scaffold-sandbox.ps1 -Name probe` will produce a directory that satisfies
        # every example without further setup.
        $scripts = Get-ChildItem -LiteralPath (Join-Path $script:RepoRootPath 'tools/automation') -Filter 'invoke-*.ps1' -File
        $allowed = @('integration-testing/probe', './integration-testing/probe')
        foreach ($script in $scripts) {
            $help = Get-Help $script.FullName -Full 2>$null
            $examples = @()
            if ($help.Examples -and $help.Examples.Example) {
                $examples = @($help.Examples.Example)
            }
            foreach ($example in $examples) {
                $code = if ($example.Code) { $example.Code } else { '' }
                $remarks = ($example.Remarks | ForEach-Object { $_.Text }) -join "`n"
                $exampleText = "$code`n$remarks"
                $rootMatches = [regex]::Matches($exampleText, '-ProjectRoot\s+([^\s`]+)')
                foreach ($m in $rootMatches) {
                    $captured = $m.Groups[1].Value.Trim()
                    $captured | Should -BeIn $allowed -Because "$($script.Name) example references '$captured' for -ProjectRoot; expected canonical probe sandbox"
                }
            }
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

# ---------------------------------------------------------------------------
# T012-T015 — US1 evidence lifecycle: clean slate before every run
# ---------------------------------------------------------------------------

Describe 'US1 lifecycle: stale files cleared before second run (T012)' {
    # Seeds a prior run-result.json, then invokes the script.
    # With the T016 pre-run cleanup wired in, the stale file is deleted
    # before the second run's capability check, so the second run's
    # envelope cannot contain values from the first run's file.
    It 'transient zone is cleared before capability check' {
        $root = New-RepoSandboxDirectory
        try {
            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/requests') -Force | Out-Null

            # Seed a prior run-result with a recognisable requestId
            $priorResult = @{ requestId = 'PRIOR-RUN-001'; runId = 'prior-run'; finalStatus = 'completed'; completedAt = '2020-01-01T00:00:00Z' }
            $priorResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resultsDir 'run-result.json') -Encoding utf8

            # Invoke the script — it will fail with editor-not-running but MUST clear the zone first
            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
                -Arguments @('-ProjectRoot', $root,
                             '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')
            $result.ExitCode | Should -Not -Be 0

            # run-result.json from the PRIOR run must be gone — Initialize-RunbookTransientZone ran
            $runResultPath = Join-Path $resultsDir 'run-result.json'
            Test-Path -LiteralPath $runResultPath | Should -BeFalse -Because 'transient cleanup must have removed the prior run-result.json'

            # The new envelope must not mention the prior requestId
            $result.Output | Should -Not -Match 'PRIOR-RUN-001'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'US1 lifecycle: concurrent invocation refused (T013)' {
    It 'script exits with run-in-progress when a live in-flight marker exists' {
        $root = New-RepoSandboxDirectory
        try {
            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/requests') -Force | Out-Null

            # Write a fake marker using the test runner's own PID — a live pwsh process
            $liveMarker = [ordered]@{
                schemaVersion = '1.0.0'
                requestId     = 'live-run-99999'
                invokeScript  = 'invoke-input-dispatch.ps1'
                pid           = $PID
                hostname      = $env:COMPUTERNAME
                startedAt     = [DateTime]::UtcNow.AddSeconds(-5).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            $liveMarker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resultsDir '.in-flight.json') -Encoding utf8

            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
                -Arguments @('-ProjectRoot', $root,
                             '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')

            $result.ExitCode | Should -Not -Be 0
            $parsed = $result.Output | ConvertFrom-Json
            # The envelope must indicate run-in-progress refusal
            $parsed.status      | Should -Be 'failure'
            $parsed.failureKind | Should -Be 'run-in-progress'
            $parsed.diagnostics | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'US1 lifecycle: stale marker auto-recovers (T014)' {
    It 'script proceeds and records stale-recovery diagnostic when marker has dead PID' {
        $root = New-RepoSandboxDirectory
        try {
            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/requests') -Force | Out-Null

            # Write a stale marker (dead PID, old timestamp)
            $staleMarker = [ordered]@{
                schemaVersion = '1.0.0'
                requestId     = 'stale-99999'
                invokeScript  = 'invoke-input-dispatch.ps1'
                pid           = 999999999
                hostname      = 'DEADBOX'
                startedAt     = [DateTime]::UtcNow.AddSeconds(-300).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            $staleMarker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resultsDir '.in-flight.json') -Encoding utf8

            # Script should NOT refuse with run-in-progress; it should recover and proceed
            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
                -Arguments @('-ProjectRoot', $root,
                             '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')

            # Script will still fail (editor not running), but NOT with run-in-progress
            $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -ne $parsed) {
                $parsed.failureKind | Should -Not -Be 'run-in-progress' -Because 'stale marker should have been auto-recovered'
            }

            # Stale marker must be deleted
            $markerPath = Join-Path $resultsDir '.in-flight.json'
            # The marker should be gone (or replaced with a fresh one that was then cleared in try/finally)
            # Either the file is absent or it has a fresh startedAt (not the old stale one)
            if (Test-Path -LiteralPath $markerPath) {
                $remaining = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
                $remaining.requestId | Should -Not -Be 'stale-99999' -Because 'stale marker should have been overwritten by the new run'
            }
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'US1 lifecycle: cleanup-blocked halts dispatch (T015)' {
    It 'script exits with cleanup-blocked when a transient file cannot be deleted' {
        $root = New-RepoSandboxDirectory
        $lockedStream = $null
        try {
            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/requests') -Force | Out-Null

            # Create a file and hold an exclusive lock on it so Remove-Item fails
            $lockedFile = Join-Path $resultsDir 'run-result.json'
            'old-data' | Set-Content -LiteralPath $lockedFile -Encoding utf8
            $lockedStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

            $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
                -Arguments @('-ProjectRoot', $root,
                             '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')

            $result.ExitCode | Should -Not -Be 0
            $parsed = $result.Output | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -ne $parsed) {
                $parsed.status      | Should -Be 'failure'
                $parsed.failureKind | Should -Be 'cleanup-blocked'
                ($parsed.diagnostics | Where-Object { $_ -match 'cleanup-blocked|locked|delete' }) | Should -Not -BeNullOrEmpty
            }
        }
        finally {
            if ($null -ne $lockedStream) {
                $lockedStream.Close()
                $lockedStream.Dispose()
            }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T020-T021 — US2 git hygiene: run output never reaches git
# ---------------------------------------------------------------------------

Describe 'US2 git hygiene: canonical runs produce zero git diff (T020)' {
    It 'harness output files are ignored by the repo .gitignore rules' {
        $root = New-RepoSandboxDirectory
        try {
            # Initialize a throwaway git repo inside the sandbox
            & git -C $root init --quiet 2>$null

            # Copy the repo-root .gitignore into the sandbox so the rules apply
            $repoGitignore = Join-Path $script:RepoRootPath '.gitignore'
            Copy-Item -LiteralPath $repoGitignore -Destination (Join-Path $root '.gitignore')
            & git -C $root add '.gitignore' 2>$null
            & git -C $root commit -m 'init' --allow-empty-message --quiet 2>$null

            # Create the canonical transient-zone output files
            $resultsDir = Join-Path $root 'harness/automation/results'
            $evidenceDir = Join-Path $root 'evidence/automation/run-001'
            New-Item -ItemType Directory -Path $resultsDir  -Force | Out-Null
            New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
            'data' | Set-Content -LiteralPath (Join-Path $resultsDir 'run-result.json')        -Encoding utf8
            'data' | Set-Content -LiteralPath (Join-Path $resultsDir 'lifecycle-status.json')  -Encoding utf8
            'data' | Set-Content -LiteralPath (Join-Path $resultsDir '.in-flight.json')        -Encoding utf8
            'data' | Set-Content -LiteralPath (Join-Path $evidenceDir 'evidence-manifest.json') -Encoding utf8

            # git status --porcelain should be empty (all files ignored)
            $status = & git -C $root status --porcelain 2>&1
            $status | Should -BeNullOrEmpty -Because 'transient-zone files must be covered by .gitignore'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'US2 git hygiene: oracle files still tracked (T021)' {
    It '*.expected.json files are NOT ignored by the .gitignore rules' {
        $root = New-RepoSandboxDirectory
        try {
            & git -C $root init --quiet 2>$null
            $repoGitignore = Join-Path $script:RepoRootPath '.gitignore'
            Copy-Item -LiteralPath $repoGitignore -Destination (Join-Path $root '.gitignore')
            & git -C $root add '.gitignore' 2>$null
            & git -C $root commit -m 'init' --allow-empty-message --quiet 2>$null

            $resultsDir = Join-Path $root 'harness/automation/results'
            New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
            $oracleFile = Join-Path $resultsDir 'run-result.success.expected.json'
            '{"status":"ok"}' | Set-Content -LiteralPath $oracleFile -Encoding utf8

            # git check-ignore should say the file is NOT ignored (exit 1 = not ignored)
            $ignored = & git -C $root check-ignore --no-index $oracleFile 2>&1
            $ignored | Should -BeNullOrEmpty -Because '*.expected.json must not be ignored'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'US2 SC-001: git status clean after canonical invocation (T024)' {
    It 'git status --porcelain is empty for harness output paths after a failed invocation' {
        $root = New-RepoSandboxDirectory
        try {
            & git -C $root init --quiet 2>$null
            $repoGitignore = Join-Path $script:RepoRootPath '.gitignore'
            Copy-Item -LiteralPath $repoGitignore -Destination (Join-Path $root '.gitignore')
            & git -C $root add '.gitignore' 2>$null
            & git -C $root commit -m 'init' --allow-empty-message --quiet 2>$null

            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/results') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'harness/automation/requests') -Force | Out-Null

            # Invoke script (will fail with editor-not-running but will write transient files)
            $null = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-input-dispatch.ps1' `
                -Arguments @('-ProjectRoot', $root,
                             '-RequestFixturePath', 'tools/tests/fixtures/runbook/input-dispatch/press-enter.json')

            $status = & git -C $root status --porcelain 2>&1
            $status | Should -BeNullOrEmpty -Because 'SC-001: git status must be empty after any orchestration invocation'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Pass 6a — Outcome shape cleanup (B14, B15, B16)
# ---------------------------------------------------------------------------

Describe 'B14: invoke-input-dispatch.ps1 drops legacy dispatchedEventCount' {
    # The legacy field equalled declaredEventCount (not actual dispatched), so
    # readers were misled. The fix removes it outright; the two truthful fields
    # actualDispatchedCount and declaredEventCount remain.
    BeforeAll {
        $script:DispatchScriptPath = Join-Path $script:RepoRootPath 'tools/automation/invoke-input-dispatch.ps1'
        $script:DispatchScriptText = Get-Content -LiteralPath $script:DispatchScriptPath -Raw
    }

    It 'invoke-input-dispatch.ps1 source contains no dispatchedEventCount references' {
        $script:DispatchScriptText | Should -Not -Match 'dispatchedEventCount'
    }

    It 'invoke-input-dispatch.ps1 emits both declaredEventCount and actualDispatchedCount' {
        $script:DispatchScriptText | Should -Match 'declaredEventCount'
        $script:DispatchScriptText | Should -Match 'actualDispatchedCount'
    }

    It 'envelope built from the new outcome shape omits dispatchedEventCount' {
        $outcome = @{
            outcomesPath          = 'C:\fake\outcomes.jsonl'
            declaredEventCount    = 2
            actualDispatchedCount = 0
            firstFailureSummary   = 'skipped_frame_unreached'
        }
        $json = Write-RunbookEnvelope -Status 'failure' -FailureKind 'runtime' `
            -ManifestPath 'C:\fake\manifest.json' -RunId 'run-001' -RequestId 'req-001' `
            -Diagnostics @('synthetic') -Outcome $outcome
        $parsed = $json | ConvertFrom-Json
        $parsed.outcome.PSObject.Properties.Name | Should -Not -Contain 'dispatchedEventCount'
        $parsed.outcome.declaredEventCount    | Should -Be 2
        $parsed.outcome.actualDispatchedCount | Should -Be 0
    }
}

Describe 'B15: invoke-behavior-watch.ps1 emits a flat warnings array' {
    # The leading-comma idiom ,@($warnings) wraps an already-plural collection
    # in another array layer, producing [[string]] in the JSON envelope and
    # breaking strongly-typed consumers (TypeScript / Pydantic). The fix drops
    # the leading comma so warnings is a flat [string] array.
    BeforeAll {
        $script:WatchScriptPath = Join-Path $script:RepoRootPath 'tools/automation/invoke-behavior-watch.ps1'
        $script:WatchScriptText = Get-Content -LiteralPath $script:WatchScriptPath -Raw
    }

    It 'invoke-behavior-watch.ps1 does not use the leading-comma array wrapper around $warnings' {
        # The exact bug: ,@($warnings). Use a relaxed pattern to also catch
        # ", @($warnings)" or whitespace variants.
        $script:WatchScriptText | Should -Not -Match ',\s*@\(\$warnings\)'
    }

    It 'envelope warnings stays flat when built from a multi-element List[string]' {
        $list = [System.Collections.Generic.List[string]]::new()
        $list.Add('target node not found or never sampled: /root/Main/Paddle')
        $list.Add('zero samples captured; check that the watched node exists in the running scene at sample time')

        $outcome = @{
            samplesPath       = $null
            sampleCount       = 0
            frameRangeCovered = $null
            warnings          = @($list)
        }
        $json = Write-RunbookEnvelope -Status 'success' `
            -ManifestPath 'C:\fake\manifest.json' -RunId 'run-001' -RequestId 'req-001' `
            -Diagnostics @() -Outcome $outcome

        $parsed = $json | ConvertFrom-Json
        @($parsed.outcome.warnings).Count | Should -Be 2
        # Each element must be a string, not an array. ConvertFrom-Json preserves
        # array nesting, so a nested [[string]] surfaces as Object[] for [0].
        $parsed.outcome.warnings[0] | Should -BeOfType [string]
        $parsed.outcome.warnings[1] | Should -BeOfType [string]
    }
}

Describe 'B16: Get-RunResultValidationDiagnostics surfaces validationResult.notes' {
    # When run-result reports failureKind=validation, validationResult.notes
    # carries the authoritative explanation. The helper extracts those notes
    # for the envelope diagnostics array, filtering the noisy "Persisted
    # artifact references were written" boilerplate.

    It 'returns empty array for $null input' {
        Get-RunResultValidationDiagnostics -RunResult $null | Should -BeNullOrEmpty
    }

    It 'returns empty array when validationResult is missing' {
        $rr = [pscustomobject]@{ failureKind = 'validation' }
        Get-RunResultValidationDiagnostics -RunResult $rr | Should -BeNullOrEmpty
    }

    It 'returns empty array when validationResult.notes is missing' {
        $rr = [pscustomobject]@{ validationResult = [pscustomobject]@{ manifestExists = $true } }
        Get-RunResultValidationDiagnostics -RunResult $rr | Should -BeNullOrEmpty
    }

    It 'returns notes verbatim and filters out the Persisted-artifact boilerplate' {
        $rr = [pscustomobject]@{
            validationResult = [pscustomobject]@{
                notes = @(
                    'Manifest runId did not match the active automation request.',
                    'Manifest scenarioId did not match the active automation request.',
                    'Persisted artifact references were written successfully. Validate the manifest schema and paths.',
                    'Persisted evidence bundle failed validation.'
                )
            }
        }
        $result = Get-RunResultValidationDiagnostics -RunResult $rr
        @($result).Count | Should -Be 3
        $result[0] | Should -Be 'Manifest runId did not match the active automation request.'
        $result[1] | Should -Be 'Manifest scenarioId did not match the active automation request.'
        $result[2] | Should -Be 'Persisted evidence bundle failed validation.'
        # Boilerplate must be filtered:
        @($result | Where-Object { $_ -match '^Persisted artifact references were written' }).Count | Should -Be 0
    }

    It 'skips null and whitespace-only entries' {
        $rr = [pscustomobject]@{
            validationResult = [pscustomobject]@{
                notes = @($null, '', '  ', 'real diagnostic')
            }
        }
        $result = Get-RunResultValidationDiagnostics -RunResult $rr
        @($result).Count | Should -Be 1
        $result[0] | Should -Be 'real diagnostic'
    }
}

Describe 'B16: invoke-* scripts pre-empt Test-RunbookManifest on validation failures' {
    # Every invoke-* script that hits Test-RunbookManifest should call
    # Get-RunResultValidationDiagnostics first so the misleading "manifest not
    # found" diagnostic never lands when the run actually failed validation.
    BeforeAll {
        $script:Pass6aScripts = @(
            'tools/automation/invoke-input-dispatch.ps1',
            'tools/automation/invoke-behavior-watch.ps1',
            'tools/automation/invoke-scene-inspection.ps1',
            'tools/automation/invoke-runtime-error-triage.ps1',
            'tools/automation/invoke-build-error-triage.ps1'
        )
    }

    It '<scriptPath> calls Get-RunResultValidationDiagnostics' -ForEach @(
        @{ scriptPath = 'tools/automation/invoke-input-dispatch.ps1' }
        @{ scriptPath = 'tools/automation/invoke-behavior-watch.ps1' }
        @{ scriptPath = 'tools/automation/invoke-scene-inspection.ps1' }
        @{ scriptPath = 'tools/automation/invoke-runtime-error-triage.ps1' }
        @{ scriptPath = 'tools/automation/invoke-build-error-triage.ps1' }
    ) {
        $abs = Join-Path $script:RepoRootPath $scriptPath
        $text = Get-Content -LiteralPath $abs -Raw
        $text | Should -Match 'Get-RunResultValidationDiagnostics'
    }

    It '<scriptPath> calls the helper before Test-RunbookManifest' -ForEach @(
        @{ scriptPath = 'tools/automation/invoke-input-dispatch.ps1' }
        @{ scriptPath = 'tools/automation/invoke-behavior-watch.ps1' }
        @{ scriptPath = 'tools/automation/invoke-scene-inspection.ps1' }
        @{ scriptPath = 'tools/automation/invoke-runtime-error-triage.ps1' }
        @{ scriptPath = 'tools/automation/invoke-build-error-triage.ps1' }
    ) {
        $abs = Join-Path $script:RepoRootPath $scriptPath
        $text = Get-Content -LiteralPath $abs -Raw
        $helperIdx   = $text.IndexOf('Get-RunResultValidationDiagnostics')
        $manifestIdx = $text.IndexOf('Test-RunbookManifest -ManifestPath')
        $helperIdx   | Should -BeGreaterThan -1
        $manifestIdx | Should -BeGreaterThan -1
        $helperIdx   | Should -BeLessThan $manifestIdx -Because 'the validation pre-empt must run before the manifest sanity check'
    }

    # Per Copilot review on PR #35: the B16 pre-empt path must emit the same
    # workflow-specific outcome keys as Exit-Failure, not an empty @{}, so
    # consumers see a stable shape on every failure path.
    It '<scriptPath> B16 pre-empt emits the workflow-specific outcome keys (not -Outcome @{})' -ForEach @(
        @{ scriptPath = 'tools/automation/invoke-input-dispatch.ps1';      requiredKey = 'declaredEventCount' }
        @{ scriptPath = 'tools/automation/invoke-behavior-watch.ps1';      requiredKey = 'samplesPath' }
        @{ scriptPath = 'tools/automation/invoke-scene-inspection.ps1';    requiredKey = 'sceneTreePath' }
        @{ scriptPath = 'tools/automation/invoke-runtime-error-triage.ps1';requiredKey = 'runtimeErrorRecordsPath' }
        @{ scriptPath = 'tools/automation/invoke-build-error-triage.ps1';  requiredKey = 'rawBuildOutputPath' }
    ) {
        $abs = Join-Path $script:RepoRootPath $scriptPath
        $text = Get-Content -LiteralPath $abs -Raw
        # Locate the pre-empt block by anchor and capture its body up to the next 'exit 1'.
        $pattern = '(?s)Get-RunResultValidationDiagnostics.*?exit 1'
        $match = [regex]::Match($text, $pattern)
        $match.Success | Should -BeTrue -Because 'the B16 pre-empt block must be present'
        $block = $match.Value
        $block | Should -Match $requiredKey -Because "the B16 pre-empt outcome must include the workflow's $requiredKey field"
        $block | Should -Not -Match '-Outcome\s+@\{\s*\}' -Because 'the B16 pre-empt must not emit an empty outcome'
    }
}

# ---------------------------------------------------------------------------
# F2 — Get-BlockedReasonDiagnostics maps blockedReasons to actionable hints
# ---------------------------------------------------------------------------

Describe 'Get-BlockedReasonDiagnostics (F2)' {

    It 'scene_already_running maps to editor-restart hint and NOT targetScene hint' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('scene_already_running') -TargetScene 'res://main.tscn'
        $hints | Should -Not -BeNullOrEmpty
        ($hints -join ' ') | Should -Match 'invoke-stop-editor'
        ($hints -join ' ') | Should -Not -Match 'Check that targetScene'
    }

    # Issue #44: target_scene_missing was overloaded across "no scene
    # configured" and "scene file does not exist" — split into two codes.
    # The old name remains as a backward-compat alias mapping to the
    # unspecified hint.
    It 'target_scene_unspecified maps to a hint pointing at the config field' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('target_scene_unspecified') -TargetScene ''
        ($hints -join ' ') | Should -Match 'inspection-run-config'
        ($hints -join ' ') | Should -Match 'application/run/main_scene'
    }

    It 'target_scene_file_not_found includes the offending scene path' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('target_scene_file_not_found') -TargetScene 'res://scenes/missing.tscn'
        ($hints -join ' ') | Should -Match 'res://scenes/missing.tscn'
        ($hints -join ' ') | Should -Match 'does not exist'
    }

    It 'target_scene_missing (deprecated alias) still maps to a usable hint' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('target_scene_missing') -TargetScene 'res://scenes/main.tscn'
        ($hints -join ' ') | Should -Match 'inspection-run-config'
        ($hints -join ' ') | Should -Not -Match 'invoke-stop-editor'
    }

    It 'harness_autoload_missing maps to plugin-enable hint' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('harness_autoload_missing')
        ($hints -join ' ') | Should -Match 'agent_runtime_harness'
        ($hints -join ' ') | Should -Match 'Plugins'
    }

    It 'run_in_progress maps to wait-or-restart hint' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('run_in_progress')
        ($hints -join ' ') | Should -Match 'in flight'
        ($hints -join ' ') | Should -Match 'invoke-stop-editor'
    }

    It 'unknown reason gets generic fallback hint' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('some_unknown_reason')
        ($hints -join ' ') | Should -Match 'some_unknown_reason'
    }

    It 'empty reasons array returns non-duplicating fallback' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @()
        $hints | Should -Not -BeNullOrEmpty
        # The caller already prepends "Run was blocked before evidence was captured."
        # so the fallback must NOT repeat that same sentence.
        ($hints -join ' ') | Should -Not -Match 'Run was blocked before evidence'
        ($hints -join ' ') | Should -Match 'No blockedReasons'
    }

    It 'multiple reasons produce one hint each' {
        $hints = Get-BlockedReasonDiagnostics -BlockedReasons @('scene_already_running', 'target_scene_file_not_found') -TargetScene 'res://x.tscn'
        @($hints).Count | Should -Be 2
        ($hints[0]) | Should -Match 'invoke-stop-editor'
        ($hints[1]) | Should -Match 'res://x.tscn'
    }
}

# ---------------------------------------------------------------------------
# B19 — Get-BlockedRunDiagnostics returns a single message string (or $null)
# without throwing PropertyNotFoundStrict on single-element blockedReasons
# arrays under Set-StrictMode -Version Latest.
#
# The regression repro is the single-element-array case — that is the exact
# shape (`@("scene_already_running")`) that caused the original
# invoke-scene-inspection.ps1 crash to bubble up as a raw PS exception
# instead of a structured envelope.
# ---------------------------------------------------------------------------

Describe 'Get-BlockedRunDiagnostics (B19)' {

    It 'returns $null when RunResult is $null' {
        Get-BlockedRunDiagnostics -RunResult $null | Should -BeNullOrEmpty
    }

    It 'returns $null when finalStatus is "completed"' {
        $rr = [pscustomobject]@{ finalStatus = 'completed'; blockedReasons = @() }
        Get-BlockedRunDiagnostics -RunResult $rr | Should -BeNullOrEmpty
    }

    It 'returns $null when finalStatus is "failed"' {
        $rr = [pscustomobject]@{ finalStatus = 'failed'; failureKind = 'runtime' }
        Get-BlockedRunDiagnostics -RunResult $rr | Should -BeNullOrEmpty
    }

    It 'returns the diagnostic string for blocked + single-element blockedReasons (B19 regression)' {
        # This is the original B19 repro: a single-element array used to
        # unwrap to a bare string under StrictMode and `.Count` then threw
        # PropertyNotFoundStrict. The leading-comma idiom inside the helper
        # forces the array shape to survive.
        Set-StrictMode -Version Latest
        $rr = [pscustomobject]@{
            finalStatus    = 'blocked'
            blockedReasons = @('scene_already_running')
        }
        $msg = Get-BlockedRunDiagnostics -RunResult $rr
        $msg | Should -Not -BeNullOrEmpty
        $msg | Should -Match 'Run was blocked before evidence was captured'
        $msg | Should -Match 'scene_already_running'
        $msg | Should -Match 'invoke-stop-editor'
    }

    It 'returns the diagnostic string for blocked + multi-element blockedReasons' {
        Set-StrictMode -Version Latest
        # Issue #44: target_scene_missing was split into two precise codes;
        # use target_scene_file_not_found for the assertion that depends on
        # the scene path appearing in the hint (the unspecified code points
        # at the config field, not at the path).
        $rr = [pscustomobject]@{
            finalStatus    = 'blocked'
            blockedReasons = @('scene_already_running', 'target_scene_file_not_found')
        }
        $msg = Get-BlockedRunDiagnostics -RunResult $rr -TargetScene 'res://main.tscn'
        $msg | Should -Match 'scene_already_running, target_scene_file_not_found'
        $msg | Should -Match 'res://main.tscn'
    }

    It 'returns the diagnostic string for blocked + empty blockedReasons array' {
        Set-StrictMode -Version Latest
        $rr = [pscustomobject]@{
            finalStatus    = 'blocked'
            blockedReasons = @()
        }
        $msg = Get-BlockedRunDiagnostics -RunResult $rr
        $msg | Should -Match 'blockedReasons: unknown'
        $msg | Should -Match 'No blockedReasons were reported'
    }

    It 'returns the diagnostic string for blocked + $null blockedReasons' {
        Set-StrictMode -Version Latest
        $rr = [pscustomobject]@{
            finalStatus    = 'blocked'
            blockedReasons = $null
        }
        $msg = Get-BlockedRunDiagnostics -RunResult $rr
        $msg | Should -Match 'blockedReasons: unknown'
    }

    It 'returns the diagnostic string when blockedReasons property is missing entirely (Copilot review on PR #39)' {
        # A malformed/older run-result could carry finalStatus="blocked" without
        # a blockedReasons property at all. Under StrictMode, the bare property
        # access would itself throw PropertyNotFoundStrict — the exact failure
        # mode B19 was meant to eliminate. The function must guard the lookup
        # and treat a missing property the same as $null/empty.
        Set-StrictMode -Version Latest
        $rr = [pscustomobject]@{ finalStatus = 'blocked' }  # no blockedReasons property
        $msg = Get-BlockedRunDiagnostics -RunResult $rr
        $msg | Should -Match 'blockedReasons: unknown'
    }
}
