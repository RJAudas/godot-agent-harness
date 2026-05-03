Describe 'issue #46: behavior-watch lifetime cross-field gate' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:RequestSchemaPath = 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json'
    }

    # The cross-field rule "minRuntimeFrames >= startFrameOffset + frameCount
    # when behaviorWatchRequest is present" is enforced inside Godot by
    # behavior_watch_request_validator.normalize_request, NOT by JSON Schema.
    # The constraint is independent of stopAfterValidation: the B18 fix in
    # scenegraph_run_coordinator.gd:295-304 made the post-validation stop
    # unconditional, so minRuntimeFrames is the only knob that actually grants
    # the playtest enough frames to fill the watch window. These Pester tests
    # assert the schema layer is intentionally permissive so that the GDScript
    # validator's diagnostic (code=incompatible_stop_policy) is the single
    # source of truth. The actual rejection is exercised by the live-editor
    # integration tests (see tools/tests/fixtures/issue-46/).
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
            (Join-Path $repoRoot 'tools/tests/fixtures/issue-45'),
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
                # Resolve behaviorWatchRequest with the same precedence as
                # _resolve_request in scenegraph_run_coordinator.gd: overrides
                # take precedence over the top-level request fields.
                $watch = $null
                if ($obj.PSObject.Properties['overrides'] -and $obj.overrides.PSObject.Properties['behaviorWatchRequest']) { $watch = $obj.overrides.behaviorWatchRequest }
                elseif ($obj.PSObject.Properties['behaviorWatchRequest']) { $watch = $obj.behaviorWatchRequest }
                if ($null -eq $watch) { return }
                $frameCount = if ($watch.PSObject.Properties['frameCount']) { [int]$watch.frameCount } else { 0 }
                if ($frameCount -le 0) { return }
                $startOffset = if ($watch.PSObject.Properties['startFrameOffset']) { [int]$watch.startFrameOffset } else { 0 }
                $required = $startOffset + $frameCount
                # Same precedence for stopPolicy: overrides > top-level. The
                # coordinator merges nested overrides at scenegraph_run_coordinator.gd:932-940
                # so the audit must look in both places to match what the
                # validator will actually see at runtime.
                $minRuntime = 0
                if ($obj.PSObject.Properties['stopPolicy'] -and $obj.stopPolicy.PSObject.Properties['minRuntimeFrames']) {
                    $minRuntime = [int]$obj.stopPolicy.minRuntimeFrames
                }
                if ($obj.PSObject.Properties['overrides'] -and $obj.overrides.PSObject.Properties['stopPolicy'] -and $obj.overrides.stopPolicy.PSObject.Properties['minRuntimeFrames']) {
                    $minRuntime = [int]$obj.overrides.stopPolicy.minRuntimeFrames
                }
                # The deliberate truncation-repro fixture is the one expected
                # offender — it exists to demonstrate the rejection diagnostic.
                if ($_.Name -eq 'truncation-repro-pong.json') { return }
                if ($minRuntime -lt $required) {
                    $offending.Add(("{0} (required={1}, minRuntimeFrames={2})" -f $_.FullName, $required, $minRuntime))
                }
            }
        }

        $offending | Should -BeNullOrEmpty -Because 'shipped behavior-watch fixtures must set minRuntimeFrames >= startFrameOffset + frameCount, otherwise the GDScript validator will reject them at runtime (incompatible_stop_policy) — see the corrected rule in behavior_watch_request_validator.gd'
    }
}

Describe 'issue #53: behavior-watch trace frame-counter is the physics-tick counter' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    # The fix at scenegraph_runtime.gd:271 changed the frame argument passed to
    # BehaviorWatchSampler.capture_frame from Engine.get_process_frames() (the
    # render-frame counter) to Engine.get_physics_frames() (the physics-tick
    # counter). The trace's `frame` field is now guaranteed contiguous when
    # cadence is every_frame, and single-physics-tick events are always
    # captured. This test asserts that invariant on a checked-in trace fixture
    # captured against D:/gameDev/pong post-fix.
    #
    # The fixture is real evidence — if a future regression re-introduces the
    # render-frame-counter behavior, anyone re-recording the trace and checking
    # it in will see this test fail. (We can't run a real Godot session in
    # Pester, but the static check captures the invariant the fix enforces.)
    It 'checked-in post-fix trace has fully contiguous frame numbers' {
        $tracePath = Get-RepoPath -Path 'tools/tests/fixtures/issue-53/expected-after/contiguous-trace.jsonl'
        Test-Path -LiteralPath $tracePath | Should -BeTrue

        $frames = Get-Content -LiteralPath $tracePath | ForEach-Object {
            $row = $_ | ConvertFrom-Json
            [int]$row.frame
        }

        $frames.Count | Should -BeGreaterThan 30 -Because 'the fixture should have a meaningful number of rows'

        for ($i = 1; $i -lt $frames.Count; $i++) {
            $delta = $frames[$i] - $frames[$i - 1]
            $delta | Should -Be 1 -Because "row $i transitions from frame $($frames[$i - 1]) to frame $($frames[$i]); contiguous physics-tick semantics require delta=1 (issue #53)"
        }

        $first = $frames[0]
        $last = $frames[-1]
        ($last - $first + 1) | Should -Be $frames.Count
    }

    # The fixture-contiguity check above only fires if someone re-records the
    # trace after a regression. This source-level check catches a regression
    # immediately: assert the sampler-call line in scenegraph_runtime.gd uses
    # Engine.get_physics_frames() (and only that). Together the two tests form
    # belt-and-braces coverage of the issue-53 fix.
    It 'scenegraph_runtime.gd invokes the sampler with Engine.get_physics_frames()' {
        $sourcePath = Get-RepoPath -Path 'addons/agent_runtime_harness/runtime/scenegraph_runtime.gd'
        Test-Path -LiteralPath $sourcePath | Should -BeTrue

        $samplerCallLines = @(Get-Content -LiteralPath $sourcePath | Where-Object { $_ -match '_behavior_watch_sampler\.capture_frame\(' })
        $samplerCallLines.Count | Should -BeGreaterOrEqual 1 -Because 'the sampler call site must exist'

        foreach ($line in $samplerCallLines) {
            $line | Should -Match 'Engine\.get_physics_frames\(\)' -Because 'issue #53: the sampler runs in _physics_process and must report the physics-tick counter'
            $line | Should -Not -Match 'Engine\.get_process_frames\(\)' -Because 'issue #53: reporting the render-frame counter from inside _physics_process produces non-contiguous traces'
        }
    }
}
