Describe 'tools/scaffold-sandbox.ps1' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    It 'creates a fresh sandbox with project.godot, main scene, and a deployed harness' {
        $rootDir = New-RepoSandboxDirectory

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/scaffold-sandbox.ps1' -Parameters @{
            Name = 'demo'
            RootDir = $rootDir
            PassThru = $true
        }

        $sandboxPath = Join-Path $rootDir 'demo'
        $result.sandboxPath | Should -Be $sandboxPath
        $result.reset | Should -BeFalse

        # Seeded files
        (Join-Path $sandboxPath 'project.godot') | Should -Exist
        (Join-Path $sandboxPath 'scenes/main.tscn') | Should -Exist

        $projectContent = Get-Content -LiteralPath (Join-Path $sandboxPath 'project.godot') -Raw
        $projectContent | Should -Match 'config/name="demo"'
        $projectContent | Should -Match 'run/main_scene="res://scenes/main.tscn"'

        $sceneContent = Get-Content -LiteralPath (Join-Path $sandboxPath 'scenes/main.tscn') -Raw
        $sceneContent | Should -Match 'gd_scene format=3'
        $sceneContent | Should -Match '\[node name="Main" type="Control"\]'

        # Harness was deployed by deploy-game-harness.ps1
        (Join-Path $sandboxPath 'addons/agent_runtime_harness/plugin.cfg') | Should -Exist
        (Join-Path $sandboxPath 'harness/inspection-run-config.json') | Should -Exist
        (Join-Path $sandboxPath 'CLAUDE.md') | Should -Exist
        (Join-Path $sandboxPath 'AGENTS.md') | Should -Exist
        (Join-Path $sandboxPath '.claude/agents/godot-runtime-verification.md') | Should -Exist

        # Project settings were updated by deploy
        $projectContent | Should -Match 'ScenegraphHarness="\*res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd"'
        $projectContent | Should -Match 'enabled=PackedStringArray\("res://addons/agent_runtime_harness/plugin.cfg"\)'

        # C3 regression guard: Get-ClaudeFileContent / Get-AgentsFileContent previously
        # leaked a literal `.TrimEnd()` line into freshly-deployed CLAUDE.md / AGENTS.md
        # because the .TrimEnd() call sat outside the $() interpolation in the here-string.
        $claudeContent = Get-Content -LiteralPath (Join-Path $sandboxPath 'CLAUDE.md') -Raw
        $agentsContent = Get-Content -LiteralPath (Join-Path $sandboxPath 'AGENTS.md') -Raw
        $claudeContent | Should -Not -Match '\.TrimEnd\(\)'
        $agentsContent | Should -Not -Match '\.TrimEnd\(\)'
    }

    It 'refuses to overwrite an existing sandbox without -Force' {
        $rootDir = New-RepoSandboxDirectory
        $sandboxPath = Join-Path $rootDir 'demo'
        New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandboxPath 'sentinel.txt') -Value 'preserve me'

        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/scaffold-sandbox.ps1' -Parameters @{
                Name = 'demo'
                RootDir = $rootDir
                PassThru = $true
            }
        } | Should -Throw '*already exists*'

        # Sentinel still present, no harness deployed
        (Join-Path $sandboxPath 'sentinel.txt') | Should -Exist
        (Join-Path $sandboxPath 'addons/agent_runtime_harness/plugin.cfg') | Should -Not -Exist
    }

    It 'resets and re-scaffolds an existing sandbox when -Force is passed' {
        $rootDir = New-RepoSandboxDirectory
        $sandboxPath = Join-Path $rootDir 'demo'
        New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sandboxPath 'sentinel.txt') -Value 'should be wiped'

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/scaffold-sandbox.ps1' -Parameters @{
            Name = 'demo'
            RootDir = $rootDir
            Force = $true
            PassThru = $true
        }

        $result.reset | Should -BeTrue
        (Join-Path $sandboxPath 'sentinel.txt') | Should -Not -Exist
        (Join-Path $sandboxPath 'project.godot') | Should -Exist
        (Join-Path $sandboxPath 'addons/agent_runtime_harness/plugin.cfg') | Should -Exist
    }

    It 'uses -DisplayName for the application config name when provided' {
        $rootDir = New-RepoSandboxDirectory

        $result = Invoke-RepoScriptPassThru -ScriptPath 'tools/scaffold-sandbox.ps1' -Parameters @{
            Name = 'physics'
            DisplayName = 'Physics Probe'
            RootDir = $rootDir
            PassThru = $true
        }

        $projectContent = Get-Content -LiteralPath (Join-Path $result.sandboxPath 'project.godot') -Raw
        $projectContent | Should -Match 'config/name="Physics Probe"'

        $sceneContent = Get-Content -LiteralPath (Join-Path $result.sandboxPath 'scenes/main.tscn') -Raw
        $sceneContent | Should -Match 'text = "Physics Probe sandbox"'
    }

    It 'rejects invalid sandbox names' {
        $rootDir = New-RepoSandboxDirectory

        {
            Invoke-RepoScriptPassThru -ScriptPath 'tools/scaffold-sandbox.ps1' -Parameters @{
                Name = '../escape'
                RootDir = $rootDir
                PassThru = $true
            }
        } | Should -Throw '*invalid characters*'
    }
}
