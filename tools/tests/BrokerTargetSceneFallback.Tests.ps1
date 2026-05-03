Describe 'issue #43: targetScene falls back to project.godot application/run/main_scene' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    # Issue #43 root cause: harness/inspection-run-config.json shipped with
    # `targetScene: ""`, and both the broker (capability evaluation) and the
    # coordinator (run-start check) read that field directly without any
    # fallback. Result: every harness call returned `target_scene_missing` in
    # blockedReasons, even when application/run/main_scene was set in
    # project.godot — costing real onboarding time before being diagnosed.
    #
    # The fix introduces `ScenegraphAutomationBroker.resolve_target_scene(source)`
    # — a static helper that reads `targetScene` from a config or request dict
    # and falls back to ProjectSettings.get_setting("application/run/main_scene")
    # when empty. Both check sites consult the helper so the fallback is
    # applied uniformly. The cryptic `target_scene_missing` diagnostic only
    # fires when BOTH sources are empty (a real misconfiguration).
    #
    # This test statically verifies the source code defines the helper and
    # both check sites use it. The functional behavior is verified live
    # against D:/gameDev/pong (see plan and PR description).
    It 'broker defines the resolve_target_scene helper that consults application/run/main_scene' {
        $brokerPath = Get-RepoPath -Path 'addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd'
        Test-Path -LiteralPath $brokerPath | Should -BeTrue

        $source = Get-Content -Raw -LiteralPath $brokerPath

        $source | Should -Match 'static func resolve_target_scene\(' -Because 'issue #43: the broker must expose a static helper that other classes can reuse'
        $source | Should -Match 'application/run/main_scene' -Because 'issue #43: the helper must consult Godot''s default-scene project setting'
        $source | Should -Match 'ProjectSettings\.get_setting\(\s*"application/run/main_scene"' -Because 'issue #43: read the setting via ProjectSettings (no string-key typos)'
    }

    It 'broker.evaluate_capability calls resolve_target_scene (not raw config.get)' {
        $brokerPath = Get-RepoPath -Path 'addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd'
        $source = Get-Content -Raw -LiteralPath $brokerPath

        # The fallback is only useful if evaluate_capability actually calls
        # the helper. A regression that re-introduces the raw String()
        # extraction would silently re-introduce the bug.
        $source | Should -Match 'var target_scene := resolve_target_scene\(config\)' -Because 'issue #43: evaluate_capability must use the fallback helper'
    }

    It 'coordinator.run-start blocked-reasons check calls the broker helper' {
        $coordinatorPath = Get-RepoPath -Path 'addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd'
        Test-Path -LiteralPath $coordinatorPath | Should -BeTrue

        $source = Get-Content -Raw -LiteralPath $coordinatorPath

        # The coordinator's _collect_blocked_reasons must agree with the
        # broker — without this, capability could pass (fallback applied) but
        # run-start re-fails (raw check) on the same input.
        $source | Should -Match 'ScenegraphAutomationBroker\.resolve_target_scene\(_active_request\)' -Because 'issue #43: coordinator and broker must use the same fallback path'
    }
}
