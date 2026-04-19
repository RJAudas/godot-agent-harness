Describe 'specs/006-input-dispatch input dispatch outcome row schema' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:SchemaPath = 'specs/006-input-dispatch/contracts/input-dispatch-outcome-row.schema.json'
        $script:SandboxRoot = New-RepoSandboxDirectory
    }

    AfterAll {
        if ($null -ne $script:SandboxRoot -and (Test-Path -LiteralPath $script:SandboxRoot)) {
            Remove-Item -LiteralPath $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a representative dispatched outcome row' {
        $rowPath = Join-Path $script:SandboxRoot 'dispatched.json'
        @{
            runId = 'pong-numpad-enter-run'
            eventIndex = 0
            declaredFrame = 30
            dispatchedFrame = 30
            kind = 'key'
            identifier = 'KP_ENTER'
            phase = 'press'
            status = 'dispatched'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rowPath -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $rowPath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'accepts a skipped_run_ended outcome with reasonCode and reasonMessage' {
        $rowPath = Join-Path $script:SandboxRoot 'skipped.json'
        @{
            runId = 'pong-numpad-enter-run'
            eventIndex = 1
            declaredFrame = 32
            dispatchedFrame = -1
            kind = 'key'
            identifier = 'KP_ENTER'
            phase = 'release'
            status = 'skipped_run_ended'
            reasonCode = 'run_terminated'
            reasonMessage = 'Run ended before event could dispatch.'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rowPath -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $rowPath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'rejects a row with an unknown status' {
        $rowPath = Join-Path $script:SandboxRoot 'invalid-status.json'
        @{
            runId = 'r'
            eventIndex = 0
            declaredFrame = 0
            dispatchedFrame = 0
            kind = 'key'
            identifier = 'ENTER'
            phase = 'press'
            status = 'queued'
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $rowPath -Encoding utf8

        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $rowPath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse
    }
}
