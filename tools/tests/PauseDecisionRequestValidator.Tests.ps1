Describe 'pause-decision-request.schema.json fixture validation' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:SchemaPath = 'specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json'
        $script:FixtureRoot = Get-RepoPath -Path 'tools/tests/fixtures/runtime-error-loop'
        $script:RejectionsRoot = Join-Path $script:FixtureRoot 'rejections'
        $script:ValidateScript = Get-RepoPath -Path 'tools/validate-json.ps1'
    }

    # ------------------------------------------------------------------
    # Valid fixtures — must pass schema validation
    # ------------------------------------------------------------------

    It 'pause-decision-continue.json is schema-valid' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:FixtureRoot 'pause-decision-continue.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue -Because "pause-decision-continue is a well-formed pause decision"
    }

    It 'pause-decision-stop.json is schema-valid' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:FixtureRoot 'pause-decision-stop.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue -Because "pause-decision-stop is a well-formed pause decision"
    }

    # ------------------------------------------------------------------
    # Rejection fixtures
    # ------------------------------------------------------------------

    It 'missing_field.json fails schema validation (no decision field)' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:RejectionsRoot 'missing_field.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse -Because "decision field is missing"
    }

    It 'unsupported_field.json fails schema validation (extra field)' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:RejectionsRoot 'unsupported_field.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse -Because "unknownExtraField is not allowed"
    }

    It 'invalid_decision.json fails schema validation (bad enum value)' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:RejectionsRoot 'invalid_decision.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse -Because "'skip' is not a valid decision enum value"
    }

    It 'unknown_pause.json is schema-valid (semantic rejection only)' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:RejectionsRoot 'unknown_pause.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue -Because "unknown_pause has valid shape; rejection is semantic"
    }

    It 'decision_already_recorded.json fails schema validation (extra _note field)' {
        $result = & $script:ValidateScript `
            -InputPath (Join-Path $script:RejectionsRoot 'decision_already_recorded.json') `
            -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse -Because "_note is not allowed by additionalProperties"
    }
}
