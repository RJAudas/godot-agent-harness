Describe 'specs/006-input-dispatch capability advertisement' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:SchemaPath = 'specs/003-editor-evidence-loop/contracts/automation-capability.schema.json'
        $script:SandboxRoot = New-RepoSandboxDirectory
    }

    AfterAll {
        if ($null -ne $script:SandboxRoot -and (Test-Path -LiteralPath $script:SandboxRoot)) {
            Remove-Item -LiteralPath $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a capability payload that advertises inputDispatch' {
        $capabilityPath = Join-Path $script:SandboxRoot 'capability-with-input-dispatch.json'
        @{
            checkedAt = '2026-04-15T00:00:00Z'
            projectIdentifier = 'res://'
            singleTargetReady = $true
            launchControlAvailable = $true
            runtimeBridgeAvailable = $true
            captureControlAvailable = $true
            persistenceAvailable = $true
            validationAvailable = $true
            shutdownControlAvailable = $true
            blockedReasons = @()
            recommendedControlPath = 'file_broker'
            inputDispatch = @{
                supported = $true
                maxEvents = 256
                supportedKinds = @('key', 'action')
                supportedPhases = @('press', 'release')
                laterSliceFields = @('mouse', 'touch', 'gamepad', 'recordedReplay', 'physicalKeycode', 'physicsFrame')
                blockedReasons = @()
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $capabilityPath -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $capabilityPath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'still accepts a capability payload without inputDispatch (additive)' {
        $capabilityPath = Join-Path $script:SandboxRoot 'capability-without-input-dispatch.json'
        @{
            checkedAt = '2026-04-15T00:00:00Z'
            projectIdentifier = 'res://'
            singleTargetReady = $true
            launchControlAvailable = $true
            runtimeBridgeAvailable = $true
            captureControlAvailable = $true
            persistenceAvailable = $true
            validationAvailable = $true
            shutdownControlAvailable = $true
            blockedReasons = @()
            recommendedControlPath = 'file_broker'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $capabilityPath -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $capabilityPath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }
}
