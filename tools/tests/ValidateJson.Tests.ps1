Describe 'tools/validate-json.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'accepts a valid JSON fixture against its schema' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json',
            '-SchemaPath', 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
        $result.ParsedOutput.inputPath | Should -Match 'evidence-manifest.valid.json$'
    }

    It 'accepts absolute input and schema paths' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', (Get-RepoPath -Path 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json'),
            '-SchemaPath', (Get-RepoPath -Path 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json')
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeTrue
    }

    It 'reports schema failures when AllowInvalid is set' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json',
            '-SchemaPath', 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json',
            '-AllowInvalid'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeFalse
        $result.ParsedOutput.error | Should -Not -BeNullOrEmpty
    }

    It 'exits non-zero when validation fails without AllowInvalid' {
        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json',
            '-SchemaPath', 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json'
        )

        $result.ExitCode | Should -Be 1
        $result.ParsedOutput.valid | Should -BeFalse
    }

    It 'reports malformed JSON content' {
        $jsonPath = Join-Path $TestDrive 'broken.json'
        $schemaPath = Join-Path $TestDrive 'schema.json'

        Set-Content -LiteralPath $jsonPath -Value '{"schemaVersion":' -NoNewline
        Set-Content -LiteralPath $schemaPath -Value @'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object"
}
'@

        $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $jsonPath,
            '-SchemaPath', $schemaPath,
            '-AllowInvalid'
        )

        $result.ExitCode | Should -Be 0
        $result.ParsedOutput.valid | Should -BeFalse
        $result.ParsedOutput.error | Should -Match 'JSON|Unexpected end'
    }

    It 'returns a pass-through object for in-process callers' {
        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/validate-json.ps1' -Parameters @{
            InputPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.valid.json'
            SchemaPath = 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json'
            PassThru = $true
        }

        $result.valid | Should -BeTrue
        $result.schemaPath | Should -Match 'evidence-manifest.schema.json$'
    }

    It 'returns an invalid pass-through object without terminating the caller' {
        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/validate-json.ps1' -Parameters @{
            InputPath = 'tools/evals/fixtures/001-agent-tooling-foundation/evidence-manifest.invalid.json'
            SchemaPath = 'specs/001-agent-tooling-foundation/contracts/evidence-manifest.schema.json'
            PassThru = $true
        }

        $result.valid | Should -BeFalse
        $result.error | Should -Not -BeNullOrEmpty
    }

    Context 'enum-violation enrichment' {
        BeforeAll {
            $script:EnrichSchema = @'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "props": {
      "type": "array",
      "items": { "type": "string", "enum": ["a", "b", "c"] }
    },
    "ref": { "$ref": "#/$defs/refTarget" }
  },
  "$defs": {
    "refTarget": { "type": "string", "enum": ["alpha", "beta"] }
  }
}
'@
        }

        It 'appends offending value and allowed values when an enum is violated' {
            $jsonPath = Join-Path $TestDrive 'enum-bad.json'
            $schemaPath = Join-Path $TestDrive 'enum-schema.json'
            Set-Content -LiteralPath $jsonPath -Value '{"props":["a","x","b"]}' -NoNewline
            Set-Content -LiteralPath $schemaPath -Value $script:EnrichSchema -NoNewline

            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $jsonPath,
                '-SchemaPath', $schemaPath,
                '-AllowInvalid'
            )

            $result.ParsedOutput.valid | Should -BeFalse
            $result.ParsedOutput.error | Should -Match "Property at '/props/1' has value 'x'"
            $result.ParsedOutput.error | Should -Match 'allowed values: a, b, c'
        }

        It 'walks $ref into $defs to find the enum' {
            $jsonPath = Join-Path $TestDrive 'enum-ref-bad.json'
            $schemaPath = Join-Path $TestDrive 'enum-ref-schema.json'
            Set-Content -LiteralPath $jsonPath -Value '{"ref":"gamma"}' -NoNewline
            Set-Content -LiteralPath $schemaPath -Value $script:EnrichSchema -NoNewline

            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $jsonPath,
                '-SchemaPath', $schemaPath,
                '-AllowInvalid'
            )

            $result.ParsedOutput.valid | Should -BeFalse
            $result.ParsedOutput.error | Should -Match "Property at '/ref' has value 'gamma'"
            $result.ParsedOutput.error | Should -Match 'allowed values: alpha, beta'
        }

        It 'leaves non-enum failures unenriched' {
            $jsonPath = Join-Path $TestDrive 'type-bad.json'
            $schemaPath = Join-Path $TestDrive 'type-schema.json'
            Set-Content -LiteralPath $jsonPath -Value '{"props":42}' -NoNewline
            Set-Content -LiteralPath $schemaPath -Value $script:EnrichSchema -NoNewline

            $result = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
                '-InputPath', $jsonPath,
                '-SchemaPath', $schemaPath,
                '-AllowInvalid'
            )

            $result.ParsedOutput.valid | Should -BeFalse
            $result.ParsedOutput.error | Should -Not -Match 'allowed values:'
        }
    }
}