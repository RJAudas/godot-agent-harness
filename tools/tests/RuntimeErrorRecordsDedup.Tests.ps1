Describe 'issue #52: runtime-error-records dedup uses user-script frame, not engine emission point' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    }

    # Issue #52 root cause: Godot's Logger._log_error callback receives
    # `function`/`file`/`line` from the engine's C++ emission point. For
    # push_warning and push_error, that's the constant location of the C++
    # implementation (core/variant/variant_utility.cpp:1034 — the `push_warning`
    # function). Deduping on those values collapses every call site in user
    # GDScript to ONE record because the engine-side key is identical.
    #
    # The user's actual GDScript caller frame is in the `script_backtraces`
    # parameter (Array[ScriptBacktrace]). The fix consults
    # script_backtraces[0]'s frame 0 (get_function_name(0) /
    # get_function_file(0) / get_function_line(0)) and uses those for the
    # record's scriptPath/line/function. The dedup key formula is unchanged
    # because it reads from the record's fields — keying on user-frame data
    # automatically becomes per-call-site instead of per-engine-emission-site.
    #
    # This test statically verifies the source code consults script_backtraces.
    # Without it, a regression that re-introduces the underscore-prefixed
    # parameter (or stops calling get_function_*) would only surface in
    # integration testing. The full integration verification is in
    # tools/tests/fixtures/issue-52/expected-after/distinct-records.jsonl.
    It 'scenegraph_runtime.gd Logger callback consults script_backtraces[0] frame 0' {
        $sourcePath = Get-RepoPath -Path 'addons/agent_runtime_harness/runtime/scenegraph_runtime.gd'
        Test-Path -LiteralPath $sourcePath | Should -BeTrue

        $source = Get-Content -Raw -LiteralPath $sourcePath

        # The _log_error parameter list must use `script_backtraces` (no leading
        # underscore). Underscore-prefixed marks an unused parameter — that was
        # the pre-fix state.
        $source | Should -Match 'func _log_error\([^)]*script_backtraces: Array' -Because 'issue #52: the Logger must consume script_backtraces, not ignore it'
        $source | Should -Not -Match 'func _log_error\([^)]*_script_backtraces: Array' -Because 'issue #52: an underscore-prefixed param is the pre-fix unused state'

        # And it must reach into the first frame's function/file/line.
        # Godot 4.6 ScriptBacktrace API: get_frame_count + get_frame_function /
        # get_frame_file / get_frame_line (NOT the older get_function_* names
        # that some docs reference; those don't exist on this class).
        $source | Should -Match 'get_frame_count\(\)' -Because 'issue #52: must check the backtrace has at least one frame'
        $source | Should -Match 'get_frame_function\(0\)' -Because 'issue #52: extract the user GDScript caller name'
        $source | Should -Match 'get_frame_file\(0\)' -Because 'issue #52: extract the user GDScript caller file'
        $source | Should -Match 'get_frame_line\(0\)' -Because 'issue #52: extract the user GDScript caller line'
    }

    # Defense in depth: the after-evidence fixture from a real Pong run must
    # show distinct call sites as distinct records (not one collapsed record
    # with `core/variant/variant_utility.cpp` as the scriptPath). If the
    # fixture is regenerated post-regression it'll fail this check.
    It 'checked-in post-fix records show distinct user-frame call sites' {
        $recordsPath = Get-RepoPath -Path 'tools/tests/fixtures/issue-52/expected-after/distinct-records.jsonl'
        if (-not (Test-Path -LiteralPath $recordsPath)) {
            Set-ItResult -Skipped -Because 'after-evidence fixture not yet captured (run Phase C against D:/gameDev/pong)'
            return
        }
        Test-Path -LiteralPath $recordsPath | Should -BeTrue

        $records = @(Get-Content -LiteralPath $recordsPath | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_ | ConvertFrom-Json })

        $records.Count | Should -BeGreaterOrEqual 2 -Because 'multiple distinct push_warnings should produce multiple records'

        foreach ($r in $records) {
            $r.scriptPath | Should -Not -Match 'variant_utility\.cpp' -Because "issue #52: scriptPath '$($r.scriptPath)' must be a user GDScript path, not the engine C++ source"
            $r.scriptPath | Should -Match '^res://' -Because "issue #52: user GDScript paths start with res://"
            $r.function | Should -Not -Be 'push_warning' -Because "issue #52: function must be the user-frame name, not 'push_warning'"
        }

        # And distinct call sites must produce distinct records (no two with
        # identical scriptPath + line).
        $keys = $records | ForEach-Object { "$($_.scriptPath)|$($_.line)" }
        $uniqueKeys = $keys | Sort-Object -Unique
        $uniqueKeys.Count | Should -Be $records.Count -Because 'the dedup key is per-(scriptPath, line, severity); each distinct call site must own its own record'
    }
}
