Describe 'specs/006-input-dispatch input dispatch script fixtures' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        $script:SchemaPath = 'specs/006-input-dispatch/contracts/input-dispatch-script.schema.json'
        $script:FixtureRoot = Get-RepoPath -Path 'tools/tests/fixtures/pong-testbed/harness/automation/requests/input-dispatch'
    }

    It 'accepts the numpad-Enter reproduction fixture' {
        $fixturePath = Join-Path $script:FixtureRoot 'valid-numpad-enter.json'
        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $fixturePath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    It 'accepts the action-based ui_accept fixture' {
        $fixturePath = Join-Path $script:FixtureRoot 'valid-action-ui-accept.json'
        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $fixturePath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeTrue
    }

    $invalidCases = @(
        @{ Name = 'invalid-missing-events.json'; Reason = 'minItems' },
        @{ Name = 'invalid-phase.json'; Reason = 'phase enum' },
        @{ Name = 'invalid-frame.json'; Reason = 'frame minimum' },
        @{ Name = 'invalid-later-slice-field.json'; Reason = 'additionalProperties on event' },
        @{ Name = 'invalid-missing-field.json'; Reason = 'missing required identifier' },
        @{ Name = 'invalid-unsupported-field.json'; Reason = 'additionalProperties on event' },
        @{ Name = 'invalid-script-too-long.json'; Reason = 'maxItems' }
    )

    It 'rejects schema-invalid fixture <Name>' -ForEach $invalidCases {
        $fixturePath = Join-Path $script:FixtureRoot $Name
        $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $fixturePath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
        $result.valid | Should -BeFalse
    }

    # invalid-unmatched-release.json, invalid-unsupported-identifier.json, and
    # invalid-duplicate-event.json are schema-valid by design — they are rejected
    # by the validator's semantic checks (unmatched_release, unsupported_identifier,
    # duplicate_event), not by the JSON Schema itself. They run inside Godot.
    It 'treats semantic-only invalid fixtures as schema-valid (validator handles them)' {
        foreach ($name in @('invalid-unmatched-release.json', 'invalid-unsupported-identifier.json', 'invalid-duplicate-event.json')) {
            $fixturePath = Join-Path $script:FixtureRoot $name
            $result = & (Get-RepoPath -Path 'tools/validate-json.ps1') -InputPath $fixturePath -SchemaPath $script:SchemaPath -PassThru -AllowInvalid
            $result.valid | Should -BeTrue -Because "$name is schema-valid; validator catches it semantically"
        }
    }
}
