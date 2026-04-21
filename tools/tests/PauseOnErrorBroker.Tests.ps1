#Requires -Version 7.0
# PauseOnErrorBroker.Tests.ps1
# T019/T020 - Deterministic Pester scenarios for pause-decision-log.jsonl invariants.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:SchemaPath     = Get-RepoPath 'specs/007-report-runtime-errors/contracts/pause-decision-record.schema.json'
    $script:RequestSchema  = Get-RepoPath 'specs/007-report-runtime-errors/contracts/pause-decision-request.schema.json'
    $script:FixtureDir     = Get-RepoPath 'tools/tests/fixtures/pause-decision-log'
    $script:ValidateScript = Get-RepoPath 'tools/validate-json.ps1'
    $script:Validate = {
        param([string]$Json)
        $tmp = New-TemporaryFile
        try {
            Set-Content -Path $tmp.FullName -Value $Json -Encoding utf8
            return (& $script:ValidateScript -InputPath $tmp.FullName -SchemaPath $script:SchemaPath -PassThru -AllowInvalid)
        } finally {
            Remove-Item -Path $tmp.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'pause-decision-log JSONL fixtures schema + uniqueness (T019)' {
    Context 'when fixture directory exists' {
        BeforeAll {
            $script:Rows = @()
            if (Test-Path $script:FixtureDir -ErrorAction SilentlyContinue) {
                Get-ChildItem -Path $script:FixtureDir -Filter '*.jsonl' -Recurse | ForEach-Object {
                    $f = $_; Get-Content $f.FullName | ForEach-Object {
                        $line = $_.Trim()
                        if ($line -ne '') { $script:Rows += [PSCustomObject]@{ File = $f.Name; Content = $line } }
                    }
                }
            }
        }
        It 'every row validates against the schema' {
            if ($script:Rows.Count -eq 0) { Set-ItResult -Skipped -Because 'no JSONL fixtures'; return }
            foreach ($row in $script:Rows) {
                $r = & $script:Validate $row.Content
                $r.valid | Should -Be $true -Because "Row in $($row.File): $($r.errors -join '; ')"
            }
        }
        It '(runId,pauseId) unique per fixture' {
            if ($script:Rows.Count -eq 0) { Set-ItResult -Skipped -Because 'no JSONL fixtures'; return }
            $seen = @{}
            foreach ($row in $script:Rows) {
                $obj = $row.Content | ConvertFrom-Json
                $key = "$($obj.runId)|$($obj.pauseId)"
                $key | Should -Not -BeIn $seen.Keys; $seen[$key] = $true
            }
        }
    }
}

Describe 'pause-decision-record inline schema fixtures (T019)' {
    It 'accepts continued/agent' {
        $r = & $script:Validate (@{ runId='r1';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=42;function='_p';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='continued';decisionSource='agent';recordedAt='2025-01-01T00:00:01Z';latencyMs=100 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $true
    }
    It 'accepts stopped/agent' {
        $r = & $script:Validate (@{ runId='r1';pauseId=1;cause='unhandled_exception';scriptPath='res://s.gd';line=$null;function=$null;message='oob';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='stopped';decisionSource='agent';recordedAt='2025-01-01T00:00:01Z';latencyMs=100 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $true
    }
    It 'accepts timeout_default_applied/timeout_default' {
        $r = & $script:Validate (@{ runId='r2';pauseId=0;cause='paused_at_user_breakpoint';scriptPath='res://s.gd';line=$null;function=$null;message='';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='timeout_default_applied';decisionSource='timeout_default';recordedAt='2025-01-01T00:00:30Z';latencyMs=30000 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $true
    }
    It 'accepts stopped_by_disconnect/disconnect' {
        $r = & $script:Validate (@{ runId='r3';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=5;function='_r';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='stopped_by_disconnect';decisionSource='disconnect';recordedAt='2025-01-01T00:00:05Z';latencyMs=5000 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $true
    }
    It 'accepts resolved_by_run_end/run_end' {
        $r = & $script:Validate (@{ runId='r4';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=99;function='_pp';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='resolved_by_run_end';decisionSource='run_end';recordedAt='2025-01-01T00:00:02Z';latencyMs=2000 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $true
    }
    It 'rejects missing runId' {
        $r = & $script:Validate (@{ pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=1;function='_r';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='continued';decisionSource='agent';recordedAt='2025-01-01T00:00:01Z';latencyMs=50 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $false -Because 'runId required'
    }
    It 'rejects invalid decision enum' {
        $r = & $script:Validate (@{ runId='rx';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=1;function='_r';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='denied';decisionSource='agent';recordedAt='2025-01-01T00:00:01Z';latencyMs=50 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $false -Because 'denied not in enum'
    }
    It 'rejects invalid cause enum' {
        $r = & $script:Validate (@{ runId='rx';pauseId=0;cause='bad_cause';scriptPath='res://s.gd';line=1;function='_r';message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='continued';decisionSource='agent';recordedAt='2025-01-01T00:00:01Z';latencyMs=50 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $false -Because 'bad_cause not in enum'
    }
}

Describe 'pause-decision broker invariants (T020)' {
    It 'pause-decision-request schema exists' { Test-Path $script:RequestSchema | Should -Be $true }
    It 'rejects continued/timeout_default mismatch' {
        $r = & $script:Validate (@{ runId='rz';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=1;function=$null;message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='continued';decisionSource='timeout_default';recordedAt='2025-01-01T00:00:01Z';latencyMs=50 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $false
    }
    It 'rejects timeout_default_applied/agent mismatch' {
        $r = & $script:Validate (@{ runId='rz';pauseId=0;cause='runtime_error';scriptPath='res://s.gd';line=1;function=$null;message='m';processFrame=1;raisedAt='2025-01-01T00:00:00Z';decision='timeout_default_applied';decisionSource='agent';recordedAt='2025-01-01T00:00:30Z';latencyMs=30000 } | ConvertTo-Json -Compress)
        $r.valid | Should -Be $false
    }
}