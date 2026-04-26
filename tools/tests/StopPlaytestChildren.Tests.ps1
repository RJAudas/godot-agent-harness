BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    $script:HelperPath = 'addons/agent_runtime_harness/editor/scripts/Stop-PlaytestChildren.ps1'
}

Describe 'Stop-PlaytestChildren.ps1 — B18 reaper helper' {

    Context 'on Windows' -Skip:(-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {

        It 'returns empty killedPids and exit 0 when no Godot* descendants exist' {
            $result = Invoke-RepoPowerShell -ScriptPath $script:HelperPath `
                -Arguments @('-EditorPid', "$PID", '-Json')
            $result.ExitCode | Should -Be 0
            $parsed = $result.Output | ConvertFrom-Json -Depth 4
            @($parsed.killedPids).Count | Should -Be 0
            @($parsed.survivorPids).Count | Should -Be 0
            @($parsed.errors).Count | Should -Be 0
        }

        It 'stays safe and exits 0 when EditorPid is not alive' {
            # Pick a high PID very unlikely to be assigned. The helper either
            # reports skipped:editor_pid_not_found, or finds the PID alive but
            # with no Godot* children. Both outcomes confirm safety.
            $bogusPid = 4194302
            $result = Invoke-RepoPowerShell -ScriptPath $script:HelperPath `
                -Arguments @('-EditorPid', "$bogusPid", '-Json')
            $result.ExitCode | Should -Be 0
            $parsed = $result.Output | ConvertFrom-Json -Depth 4
            @($parsed.killedPids).Count | Should -Be 0
        }

        It 'kills Godot-named children of the supplied EditorPid and the editor itself survives' {
            # Stage a self-contained stub whose process name matches the WMI
            # filter 'Name LIKE Godot%'. ping.exe is a System32 binary that
            # runs from any path (DLL deps are all in the global loader
            # search path) AND blocks long enough for our test without
            # invoking a shell interpreter — avoiding PATH collisions with
            # MSYS / git-bash's own timeout/sleep utilities.
            $pingSource = Join-Path $env:WINDIR 'System32/ping.exe'
            (Test-Path -LiteralPath $pingSource) | Should -BeTrue
            $stubPath = Join-Path $TestDrive 'GodotPlaytestStub.exe'
            Copy-Item -LiteralPath $pingSource -Destination $stubPath

            # Start-Process -NoNewWindow makes the current pwsh ($PID) the
            # WMI ParentProcessId of the stub, which is what the helper
            # filters on. ping -n 60 127.0.0.1 ≈ 60 seconds wall clock.
            $stub = Start-Process -FilePath $stubPath -PassThru -NoNewWindow `
                -ArgumentList @('-n', '60', '127.0.0.1')
            $stubPid = $stub.Id
            try {
                # Give WMI a beat to register the new process.
                Start-Sleep -Milliseconds 500
                $stub.HasExited | Should -BeFalse

                # Confirm pre-state: the stub is a Godot*-named child of $PID.
                $wmiChild = Get-CimInstance Win32_Process `
                    -Filter "ProcessId=$stubPid AND Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
                $wmiChild | Should -Not -BeNullOrEmpty

                $result = Invoke-RepoPowerShell -ScriptPath $script:HelperPath `
                    -Arguments @('-EditorPid', "$PID", '-Json')
                $result.ExitCode | Should -Be 0
                $parsed = $result.Output | ConvertFrom-Json -Depth 4

                @($parsed.killedPids) | Should -Contain $stubPid
                @($parsed.survivorPids).Count | Should -Be 0

                # Confirm the stub is actually gone in the OS view.
                Start-Sleep -Milliseconds 250
                $aliveAfter = Get-Process -Id $stubPid -ErrorAction SilentlyContinue
                $aliveAfter | Should -BeNullOrEmpty

                # The editor (the Pester pwsh) survives.
                $self = Get-Process -Id $PID -ErrorAction Stop
                $self | Should -Not -BeNullOrEmpty
            } finally {
                if (-not $stub.HasExited) {
                    try { Stop-Process -Id $stubPid -Force -ErrorAction SilentlyContinue } catch { }
                }
            }
        }

        It 'is idempotent — re-invocation with no surviving children is a no-op' {
            $result = Invoke-RepoPowerShell -ScriptPath $script:HelperPath `
                -Arguments @('-EditorPid', "$PID", '-Json')
            $result.ExitCode | Should -Be 0
            $parsed = $result.Output | ConvertFrom-Json -Depth 4
            @($parsed.killedPids).Count | Should -Be 0
        }
    }

    Context 'on non-Windows hosts' -Skip:($IsWindows -or $env:OS -eq 'Windows_NT') {

        It 'returns skipped:non_windows and exit 0' {
            $result = Invoke-RepoPowerShell -ScriptPath $script:HelperPath `
                -Arguments @('-EditorPid', '1', '-Json')
            $result.ExitCode | Should -Be 0
            $parsed = $result.Output | ConvertFrom-Json -Depth 4
            $parsed.skipped | Should -Be 'non_windows'
            @($parsed.killedPids).Count | Should -Be 0
        }
    }
}
