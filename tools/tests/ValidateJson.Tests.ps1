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
}