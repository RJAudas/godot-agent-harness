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

    # Copilot PR #58 review caught two additional sites that the initial fix
    # missed: play_custom_scene (which reads from _active_request and would
    # have launched with an empty string), and _collect_build_failure_payload
    # (which would have skipped diagnostic collection for fallback-resolved
    # requests). The first is fixed by baking the resolution into
    # _resolve_request so _active_request carries the resolved path; the
    # second by calling resolve_target_scene directly. These tests guard
    # against either site reverting to a raw String() extraction.
    It 'coordinator._resolve_request bakes the fallback into the resolved targetScene' {
        $coordinatorPath = Get-RepoPath -Path 'addons/agent_runtime_harness/editor/scenegraph_run_coordinator.gd'
        $source = Get-Content -Raw -LiteralPath $coordinatorPath

        # The resolved dict's targetScene must be normalized through the
        # helper after the _pick_scalar merge, so play_custom_scene and any
        # other consumer that reads _active_request.targetScene see the
        # fallback-resolved value. Without this, capability passes (broker
        # uses the helper) but the launch passes an empty string.
        $source | Should -Match 'resolved\["targetScene"\]\s*=\s*ScenegraphAutomationBroker\.resolve_target_scene\(resolved\)' -Because 'issue #43: _resolve_request must bake the fallback into _active_request so play_custom_scene gets the resolved path'
    }

    It 'broker._collect_build_failure_payload calls resolve_target_scene' {
        $brokerPath = Get-RepoPath -Path 'addons/agent_runtime_harness/editor/scenegraph_automation_broker.gd'
        $source = Get-Content -Raw -LiteralPath $brokerPath

        # The build-failure collector takes a request dict directly; without
        # the fallback, a request that omits targetScene and relies on
        # application/run/main_scene would skip diagnostic collection on a
        # compile/load failure, degrading a real build error into a generic
        # attachment timeout.
        $source | Should -Match 'func _collect_build_failure_payload\([^)]+\) -> Dictionary:[\s\S]{0,600}var target_scene := resolve_target_scene\(request\)' -Because 'issue #43: _collect_build_failure_payload must use the helper so build diagnostics are collected for fallback-resolved scenes'
    }
}
