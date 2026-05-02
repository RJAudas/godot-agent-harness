Describe 'issue #46: behavior-watch + stopAfterValidation cross-field gate' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:RequestSchemaPath = 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
    }

    # The cross-field rule "stopAfterValidation=true requires minRuntimeFrames >=
    # startFrameOffset + frameCount when behaviorWatchRequest is present" is
    # enforced inside Godot by behavior_watch_request_validator.normalize_request,
    # NOT by JSON Schema. These Pester tests assert the schema layer is
    # intentionally permissive so that the GDScript validator's diagnostic
    # (failureKind=request-invalid, code=incompatible_stop_policy) is the single
    # source of truth for this constraint. The actual rejection is exercised by
    # the live-editor integration tests (see tools/tests/fixtures/issue-46/).
    It 'schema accepts the bad combination (rejection lives in GDScript validator)' {
        $payload = @{
            requestId            = 'issue-46-schema-permissive'
            scenarioId           = 'issue-46'
            runId                = 'issue-46-run'
            targetScene          = 'res://scenes/main.tscn'
            outputDirectory      = 'res://evidence/automation/x'
            artifactRoot         = ''
            expectationFiles     = @()
            capturePolicy        = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy           = @{ stopAfterValidation = $true }
            requestedBy          = 'issue-46'
            createdAt            = '2026-05-02T00:00:00Z'
            behaviorWatchRequest = @{
                targets    = @(@{ nodePath = '/root/Main/Ball'; properties = @('linear_velocity') })
                frameCount = 30
            }
        } | ConvertTo-Json -Depth 8

        $tmpPath = Join-Path $TestDrive 'issue-46-schema-bad-combo.json'
        Set-Content -LiteralPath $tmpPath -Value $payload -NoNewline -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $tmpPath -SchemaPath $script:RequestSchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'schema accepts the minRuntimeFrames remediation' {
        $payload = @{
            requestId            = 'issue-46-min-runtime-frames'
            scenarioId           = 'issue-46'
            runId                = 'issue-46-run'
            targetScene          = 'res://scenes/main.tscn'
            outputDirectory      = 'res://evidence/automation/x'
            artifactRoot         = ''
            expectationFiles     = @()
            capturePolicy        = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy           = @{ stopAfterValidation = $true; minRuntimeFrames = 30 }
            requestedBy          = 'issue-46'
            createdAt            = '2026-05-02T00:00:00Z'
            behaviorWatchRequest = @{
                targets    = @(@{ nodePath = '/root/Main/Ball'; properties = @('linear_velocity') })
                frameCount = 30
            }
        } | ConvertTo-Json -Depth 8

        $tmpPath = Join-Path $TestDrive 'issue-46-schema-fixed-min-runtime.json'
        Set-Content -LiteralPath $tmpPath -Value $payload -NoNewline -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $tmpPath -SchemaPath $script:RequestSchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'schema accepts startFrameOffset > 0 with matching minRuntimeFrames' {
        $payload = @{
            requestId            = 'issue-46-with-offset'
            scenarioId           = 'issue-46'
            runId                = 'issue-46-run'
            targetScene          = 'res://scenes/main.tscn'
            outputDirectory      = 'res://evidence/automation/x'
            artifactRoot         = ''
            expectationFiles     = @()
            capturePolicy        = @{ startup = $true; manual = $true; failure = $true }
            stopPolicy           = @{ stopAfterValidation = $true; minRuntimeFrames = 16 }
            requestedBy          = 'issue-46'
            createdAt            = '2026-05-02T00:00:00Z'
            behaviorWatchRequest = @{
                targets           = @(@{ nodePath = '/root/Main/Ball'; properties = @('linear_velocity') })
                startFrameOffset  = 12
                frameCount        = 4
            }
        } | ConvertTo-Json -Depth 8

        $tmpPath = Join-Path $TestDrive 'issue-46-schema-fixed-offset.json'
        Set-Content -LiteralPath $tmpPath -Value $payload -NoNewline -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $tmpPath -SchemaPath $script:RequestSchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'every shipped behavior-watch fixture satisfies the lifetime constraint' {
        # Defense in depth: scan every fixture that ships with a behaviorWatchRequest
        # and assert the lifetime constraint holds, so a future fixture author
        # cannot reintroduce the silent-truncation bug without breaking this test.
        $repoRoot = $script:RepoRoot
        $fixtureRoots = @(
            (Join-Path $repoRoot 'tools/tests/fixtures/runbook/behavior-watch'),
            (Join-Path $repoRoot 'tools/tests/fixtures/pong-testbed/harness/automation/requests'),
            (Join-Path $repoRoot 'tools/tests/fixtures/issue-46'),
            (Join-Path $repoRoot 'tools/tests/fixtures/issue-47')
        )

        $offending = New-Object System.Collections.Generic.List[string]
        foreach ($root in $fixtureRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -Filter '*.json' -Recurse -File | ForEach-Object {
                # Skip envelope-style fixtures under expected-before/expected-after dirs;
                # those describe orchestrator outputs, not requests.
                if ($_.FullName -match '\\expected-(before|after)\\') { return }
                $raw = Get-Content -LiteralPath $_.FullName -Raw
                $obj = $null
                try { $obj = $raw | ConvertFrom-Json -Depth 20 } catch { return }
                if ($null -eq $obj) { return }
                $watch = $null
                if ($obj.PSObject.Properties['behaviorWatchRequest']) { $watch = $obj.behaviorWatchRequest }
                elseif ($obj.PSObject.Properties['overrides'] -and $obj.overrides.PSObject.Properties['behaviorWatchRequest']) { $watch = $obj.overrides.behaviorWatchRequest }
                if ($null -eq $watch) { return }
                $frameCount = if ($watch.PSObject.Properties['frameCount']) { [int]$watch.frameCount } else { 0 }
                if ($frameCount -le 0) { return }
                $startOffset = if ($watch.PSObject.Properties['startFrameOffset']) { [int]$watch.startFrameOffset } else { 0 }
                $required = $startOffset + $frameCount
                $stopAfter = $true
                $minRuntime = 0
                if ($obj.PSObject.Properties['stopPolicy']) {
                    if ($obj.stopPolicy.PSObject.Properties['stopAfterValidation']) { $stopAfter = [bool]$obj.stopPolicy.stopAfterValidation }
                    if ($obj.stopPolicy.PSObject.Properties['minRuntimeFrames']) { $minRuntime = [int]$obj.stopPolicy.minRuntimeFrames }
                }
                # The deliberate truncation-repro fixture is the one expected
                # offender — it exists to demonstrate the rejection diagnostic.
                if ($_.Name -eq 'truncation-repro-pong.json') { return }
                if ($stopAfter -and $minRuntime -lt $required) {
                    $offending.Add(("{0} (required={1}, minRuntimeFrames={2}, stopAfterValidation=true)" -f $_.FullName, $required, $minRuntime))
                }
            }
        }

        $offending | Should -BeNullOrEmpty -Because 'shipped behavior-watch fixtures must either set stopAfterValidation=false OR minRuntimeFrames >= startFrameOffset + frameCount, otherwise they silently truncate the watch window'
    }
}
