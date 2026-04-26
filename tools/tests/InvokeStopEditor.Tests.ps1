BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:RepoRootPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
    $script:StdoutSchema = 'specs/008-agent-runbook/contracts/orchestration-stdout.schema.json'
}

Describe 'invoke-stop-editor.ps1 — envelope schema' {

    It 'failure envelope (missing ProjectRoot) validates against orchestration-stdout schema' {
        $bogus = Join-Path $TestDrive 'does-not-exist'
        $result = Invoke-RepoPowerShell -ScriptPath 'tools/automation/invoke-stop-editor.ps1' `
            -Arguments @('-ProjectRoot', $bogus)
        $tmpPath = Join-Path $TestDrive 'stop-editor-failure-envelope.json'
        $result.Output | Set-Content -LiteralPath $tmpPath -Encoding utf8
        $validation = Invoke-RepoJsonScript -ScriptPath 'tools/validate-json.ps1' -Arguments @(
            '-InputPath', $tmpPath,
            '-SchemaPath', $script:StdoutSchema
        )
        $validation.ParsedOutput.valid | Should -BeTrue
    }
}
