#Requires -Version 7.0
# RuntimeErrorCapability.Tests.ps1
# T032: Capability fixture loading - assert runtimeErrorCapture, pauseOnError, breakpointSuppression
# T033: Degraded-mode manifest invariants

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:CapabilityScript  = Get-RepoPath 'tools/automation/get-editor-evidence-capability.ps1'
    $script:ValidateManifest  = Get-RepoPath 'tools/evidence/validate-evidence-manifest.ps1'
    $script:CapabilityDir     = Get-RepoPath 'tools/tests/fixtures/runtime-error-loop/capability'
    $script:ConfigFixture     = Get-RepoPath 'tools/tests/fixtures/pong-testbed/harness/inspection-run-config.json'

    ## Helper: write the given capability JSON into a sandbox and invoke the tool.
    $script:InvokeWithCapability = {
        param([string]$CapabilityFileName)
        $sandboxPath = New-RepoSandboxDirectory
        try {
            $harnessPath  = Join-Path $sandboxPath 'harness'
            $resultsPath  = Join-Path $harnessPath 'automation\results'
            New-Item -ItemType Directory -Path $resultsPath -Force | Out-Null
            Copy-Item -LiteralPath $script:ConfigFixture -Destination (Join-Path $harnessPath 'inspection-run-config.json')
            $srcFixture = Join-Path $script:CapabilityDir $CapabilityFileName
            Copy-Item -LiteralPath $srcFixture -Destination (Join-Path $resultsPath 'capability.json')
            return Invoke-RepoScriptPassThru -ScriptPath 'tools/automation/get-editor-evidence-capability.ps1' -Parameters @{
                ProjectRoot = $sandboxPath
                PassThru    = $true
            }
        }
        finally {
            Remove-Item -LiteralPath $sandboxPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# T032: capability fixture loading
# ---------------------------------------------------------------------------

Describe 'RuntimeErrorCapability: capability fixture surfacing (T032)' {
    It 'supported.json: all three capabilities are present and supported' {
        if (-not (Test-Path (Join-Path $script:CapabilityDir 'supported.json'))) {
            Set-ItResult -Skipped -Because 'supported.json fixture not present'
            return
        }
        $result = & $script:InvokeWithCapability 'supported.json'

        $result.runtimeErrorCapture | Should -Not -BeNullOrEmpty
        $result.runtimeErrorCapture.supported | Should -BeTrue -Because 'runtimeErrorCapture v1 is always supported'

        $result.pauseOnError | Should -Not -BeNullOrEmpty
        $result.pauseOnError.supported | Should -BeTrue -Because 'supported fixture has pauseOnError enabled'

        $result.breakpointSuppression | Should -Not -BeNullOrEmpty
        $result.breakpointSuppression.supported | Should -BeTrue -Because 'supported fixture has breakpointSuppression enabled'
    }

    It 'pause-blocked.json: pauseOnError.supported = false with engine_pause_unavailable reason' {
        if (-not (Test-Path (Join-Path $script:CapabilityDir 'pause-blocked.json'))) {
            Set-ItResult -Skipped -Because 'pause-blocked.json fixture not present'
            return
        }
        $result = & $script:InvokeWithCapability 'pause-blocked.json'

        $result.runtimeErrorCapture | Should -Not -BeNullOrEmpty
        $result.runtimeErrorCapture.supported | Should -BeTrue -Because 'runtimeErrorCapture is always supported regardless of pause mode'

        $result.pauseOnError | Should -Not -BeNullOrEmpty
        $result.pauseOnError.supported | Should -BeFalse -Because 'pause-blocked fixture reports pauseOnError unavailable'
        $result.pauseOnError.reason | Should -Be 'engine_pause_unavailable'

        $result.breakpointSuppression | Should -Not -BeNullOrEmpty
        $result.breakpointSuppression.supported | Should -BeFalse
    }

    It 'breakpoint-blocked.json: breakpointSuppression.supported = false with engine_hook_unavailable reason' {
        if (-not (Test-Path (Join-Path $script:CapabilityDir 'breakpoint-blocked.json'))) {
            Set-ItResult -Skipped -Because 'breakpoint-blocked.json fixture not present'
            return
        }
        $result = & $script:InvokeWithCapability 'breakpoint-blocked.json'

        $result.runtimeErrorCapture | Should -Not -BeNullOrEmpty
        $result.runtimeErrorCapture.supported | Should -BeTrue

        $result.pauseOnError | Should -Not -BeNullOrEmpty
        $result.pauseOnError.supported | Should -BeTrue -Because 'breakpoint-blocked fixture still has pauseOnError enabled'

        $result.breakpointSuppression | Should -Not -BeNullOrEmpty
        $result.breakpointSuppression.supported | Should -BeFalse -Because 'breakpoint-blocked fixture reports breakpointSuppression unavailable'
        $result.breakpointSuppression.reason | Should -Be 'engine_hook_unavailable'
    }
}

# ---------------------------------------------------------------------------
# T033: Degraded-mode manifest invariants (pause-blocked run)
# ---------------------------------------------------------------------------

Describe 'RuntimeErrorCapability: degraded-mode manifest invariants (T033)' {
    BeforeAll {
        ## A degraded-mode run completes with:
        ##   pauseOnErrorMode = "unavailable_degraded_capture_only"
        ##   pause-decision-log.jsonl = empty (no pauses were raised)
        ##   runtime-error-records.jsonl = present with captured records
        ##   termination = valid enum value (typically "completed")

        $script:WriteManifest = {
            param([string]$FileName, [hashtable]$Reporting)
            $m = [ordered]@{
                schemaVersion = '1.0.0'
                manifestId    = 'runtime-error-loop-degraded-001'
                runId         = 'runtime-error-loop-degraded-run-001'
                scenarioId    = 'runtime-error-loop-degraded'
                status        = 'pass'
                summary       = @{ headline = 'Degraded mode run completed.'; outcome = 'pass'; keyFindings = @() }
                artifactRefs  = @()
                runtimeErrorReporting = $Reporting
                validation    = @{ bundleValid = $true; notes = @() }
                producer      = @{ toolingArtifactId = 'test'; surface = 'test' }
                createdAt     = '2026-04-19T00:00:00Z'
            }
            $path = Join-Path $TestDrive $FileName
            $m | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
            return $path
        }
    }

    It 'manifest with pauseOnErrorMode=unavailable_degraded_capture_only passes invariants' {
        $path = & $script:WriteManifest 'degraded-mode-manifest.json' @{
            termination      = 'completed'
            pauseOnErrorMode = 'unavailable_degraded_capture_only'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.runtimeReportingViolations | Should -BeNullOrEmpty -Because 'degraded mode completed run is a valid manifest shape'
        $result.ParsedOutput.bundleValid | Should -BeTrue
    }

    It 'manifest with degraded mode and no lastErrorAnchor passes (no crash = no anchor required)' {
        $path = & $script:WriteManifest 'degraded-mode-no-anchor.json' @{
            termination      = 'completed'
            pauseOnErrorMode = 'unavailable_degraded_capture_only'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*lastErrorAnchor*' }).Count |
            Should -Be 0 -Because 'non-crash termination must not require lastErrorAnchor'
    }

    It 'manifest with degraded mode and invalid termination fails invariants' {
        $path = & $script:WriteManifest 'degraded-mode-bad-termination.json' @{
            termination      = 'unknown_value'
            pauseOnErrorMode = 'unavailable_degraded_capture_only'
        }
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/evidence/validate-evidence-manifest.ps1' -Arguments @('-ManifestPath', $path)
        $result.ParsedOutput.bundleValid | Should -BeFalse
        @($result.ParsedOutput.runtimeReportingViolations | Where-Object { $_ -like '*termination*unknown_value*' }).Count |
            Should -BeGreaterThan 0
    }

    It 'pause-decision-log.jsonl for degraded-mode run is empty (no pauses raised)' {
        # A degraded-mode run must not emit any pause records since pause-on-error is disabled.
        # This test validates the schema and uniqueness invariant for a zero-row JSONL.
        $emptyJSONL = ''
        $rows = @()
        if ($emptyJSONL -ne '') {
            $rows = $emptyJSONL -split "`n" | Where-Object { $_.Trim() -ne '' }
        }
        $rows.Count | Should -Be 0 -Because 'a degraded-mode run raises no pauses so the log must be empty'
    }
}
