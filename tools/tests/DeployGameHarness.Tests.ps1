Describe 'tools/deploy-game-harness.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'deploys the addon, harness config, project wiring, and agent assets to a sandbox project' {
        $gameRoot = New-RepoSandboxDirectory
        $projectPath = Join-Path $gameRoot 'project.godot'
        Set-Content -LiteralPath $projectPath -Value @'
; Engine configuration file.

config_version=5

[application]

config/name="Sandbox Game"
'@ -NoNewline

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/deploy-game-harness.ps1' -Parameters @{
            GameRoot = $gameRoot
            PassThru = $true
        }

        $result.gameRoot | Should -Be $gameRoot
        (Join-Path $gameRoot 'addons/agent_runtime_harness/plugin.cfg') | Should -Exist
        (Join-Path $gameRoot 'harness/inspection-run-config.json') | Should -Exist
        (Join-Path $gameRoot '.github/prompts/godot-evidence-triage.prompt.md') | Should -Exist
        (Join-Path $gameRoot '.github/prompts/godot-runtime-verification.prompt.md') | Should -Exist
        (Join-Path $gameRoot '.github/agents/godot-evidence-triage.agent.md') | Should -Exist
        (Join-Path $gameRoot '.github/agents/godot-runtime-verification.agent.md') | Should -Exist
        (Join-Path $gameRoot 'AGENTS.md') | Should -Exist

        $projectContent = Get-Content -LiteralPath $projectPath -Raw
        $projectContent | Should -Match '\[autoload\]'
        $projectContent | Should -Match 'ScenegraphHarness="\*res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd"'
        $projectContent | Should -Match '\[editor_plugins\]'
        $projectContent | Should -Match 'enabled=PackedStringArray\("res://addons/agent_runtime_harness/plugin.cfg"\)'
        $projectContent | Should -Match '\[harness\]'
        $projectContent | Should -Match 'inspection_run_config="res://harness/inspection-run-config.json"'

        $copilotInstructions = Get-Content -LiteralPath (Join-Path $gameRoot '.github/copilot-instructions.md') -Raw
        $copilotInstructions | Should -Match 'BEGIN AGENT_RUNTIME_HARNESS'
        $copilotInstructions | Should -Match 'evidence/scenegraph/latest/evidence-manifest.json'
    }

    It 'preserves an existing harness config file' {
        $gameRoot = New-RepoSandboxDirectory
        Set-Content -LiteralPath (Join-Path $gameRoot 'project.godot') -Value 'config_version=5' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'harness') -Force | Out-Null
        $configPath = Join-Path $gameRoot 'harness/inspection-run-config.json'
        Set-Content -LiteralPath $configPath -Value '{"scenarioId":"custom"}' -NoNewline

        Invoke-RepoScriptPassThru -ScriptPath 'tools/deploy-game-harness.ps1' -Parameters @{
            GameRoot = $gameRoot
            PassThru = $true
        } | Out-Null

        (Get-Content -LiteralPath $configPath -Raw) | Should -Be '{"scenarioId":"custom"}'
    }

    It 'reports skipped operations when run with WhatIf' {
        $gameRoot = New-RepoSandboxDirectory
        $projectPath = Join-Path $gameRoot 'project.godot'
        Set-Content -LiteralPath $projectPath -Value 'config_version=5' -NoNewline

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/deploy-game-harness.ps1' -Parameters @{
            GameRoot = $gameRoot
            PassThru = $true
            WhatIf = $true
        }

        $actions = @($result.operations | ForEach-Object { $_.action })

        $actions | Should -Contain 'skipped-copy-addon'
        $actions | Should -Contain 'skipped-create-config'
        $actions | Should -Contain 'skipped-update-project-settings'
        $actions | Should -Contain 'copilot-instructions-skipped'
        $actions | Should -Contain 'agents-skipped'
        $actions | Should -Contain 'skipped-write-prompt'
        $actions | Should -Contain 'skipped-write-runtime-prompt'
        $actions | Should -Contain 'skipped-write-agent'
        $actions | Should -Contain 'skipped-write-runtime-agent'

        (Join-Path $gameRoot 'addons/agent_runtime_harness/plugin.cfg') | Should -Not -Exist
        (Join-Path $gameRoot 'harness/inspection-run-config.json') | Should -Not -Exist
        (Join-Path $gameRoot '.github/prompts/godot-evidence-triage.prompt.md') | Should -Not -Exist
        (Join-Path $gameRoot '.github/prompts/godot-runtime-verification.prompt.md') | Should -Not -Exist
        (Join-Path $gameRoot '.github/agents/godot-evidence-triage.agent.md') | Should -Not -Exist
        (Join-Path $gameRoot '.github/agents/godot-runtime-verification.agent.md') | Should -Not -Exist
    }
}
