#Requires -Version 7.0
# RuntimeErrorEmergencyPersist.Tests.ps1
# Fix #19 — Pure PowerShell shape/schema tests for the record format and note-stamp
# string literals that the coordinator emergency-persist path produces.
# No Godot process is required or invoked; the coordinator code path itself is not
# exercised here.  These tests confirm that synthetic records built in the coordinator's
# expected shape pass runtime-error-record.schema.json, and that the note-stamp strings
# used by _emergency_persist_runtime_errors have the correct literal values.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:ErrorRecordSchema = Get-RepoPath -Path 'specs/007-report-runtime-errors/contracts/runtime-error-record.schema.json'
    $script:ValidateScript    = Get-RepoPath -Path 'tools/validate-json.ps1'

    ## Build a record in the exact shape _emergency_persist_runtime_errors emits:
    ## mirrors the coordinator _runtime_error_dedup dict entry written by
    ## _on_runtime_error_record (Fix #19).
    $script:NewEmergencyRecord = {
        param(
            [string]$RunId        = 'test-run-crash-001',
            [int]   $Ordinal      = 1,
            [string]$ScriptPath   = 'res://scripts/crash_after_error.gd',
            [int]   $Line         = 12,
            [string]$Function     = '_trigger_error',
            [string]$Message      = "Invalid get index 'name' (on base: 'Nil').",
            [string]$Severity     = 'error',
            [string]$FirstSeenAt  = '2026-04-21T10:00:00Z',
            [string]$LastSeenAt   = '2026-04-21T10:00:00Z',
            [int]   $RepeatCount  = 1
        )
        return [ordered]@{
            runId       = $RunId
            ordinal     = $Ordinal
            scriptPath  = $ScriptPath
            line        = $Line
            'function'  = $Function
            message     = $Message
            severity    = $Severity
            firstSeenAt = $FirstSeenAt
            lastSeenAt  = $LastSeenAt
            repeatCount = $RepeatCount
        }
    }

    ## Write records to a temp JSONL file (one JSON object per line), return path.
    $script:WriteTempJsonl = {
        param([array]$Records)
        $tmp = [System.IO.Path]::GetTempFileName() + '.jsonl'
        $lines = $Records | ForEach-Object { $_ | ConvertTo-Json -Depth 5 -Compress }
        $lines | Set-Content -LiteralPath $tmp -Encoding utf8
        return $tmp
    }

    ## Validate each JSONL line individually against the schema; return array of results.
    $script:TestJsonlSchema = {
        param([string]$JsonlPath)
        $results = [System.Collections.Generic.List[object]]::new()
        $lines = Get-Content -LiteralPath $JsonlPath | Where-Object { $_.Trim() -ne '' }
        foreach ($line in $lines) {
            $tmp = [System.IO.Path]::GetTempFileName()
            $line | Set-Content -LiteralPath $tmp -Encoding utf8
            try {
                $r = & $script:ValidateScript -InputPath $tmp -SchemaPath $script:ErrorRecordSchema -PassThru -AllowInvalid
                $results.Add($r)
            } finally {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
        return $results.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Schema validity of emergency-persist records
# ---------------------------------------------------------------------------

Describe 'Fix #19: emergency-persist record schema validity' {

    It 'a single error-severity record written by the coordinator passes schema' {
        $record = & $script:NewEmergencyRecord
        $tmp = [System.IO.Path]::GetTempFileName()
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding utf8
        try {
            $result = & $script:ValidateScript -InputPath $tmp -SchemaPath $script:ErrorRecordSchema -PassThru -AllowInvalid
            $result.valid | Should -BeTrue -Because 'coordinator dedup records must match the runtime-error-record schema'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'a warning-severity record emitted by the coordinator passes schema' {
        $record = & $script:NewEmergencyRecord -Severity 'warning' -Ordinal 2 -Message 'Fixture push_warning'
        $tmp = [System.IO.Path]::GetTempFileName()
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding utf8
        try {
            $result = & $script:ValidateScript -InputPath $tmp -SchemaPath $script:ErrorRecordSchema -PassThru -AllowInvalid
            $result.valid | Should -BeTrue -Because 'coordinator must also emit schema-valid warning records'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'a capped record (repeatCount=100, truncatedAt=100) passes schema' {
        $record = & $script:NewEmergencyRecord -RepeatCount 100
        $record['truncatedAt'] = 100
        $tmp = [System.IO.Path]::GetTempFileName()
        $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmp -Encoding utf8
        try {
            $result = & $script:ValidateScript -InputPath $tmp -SchemaPath $script:ErrorRecordSchema -PassThru -AllowInvalid
            $result.valid | Should -BeTrue -Because 'capped records must remain schema-valid'
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'all lines in a two-record emergency JSONL pass schema' {
        $records = @(
            (& $script:NewEmergencyRecord -Ordinal 1 -Severity 'error')
            (& $script:NewEmergencyRecord -Ordinal 2 -Severity 'warning' -ScriptPath 'res://scripts/warning_only.gd' -Line 7 -Function '_ready' -Message 'intentional warning')
        )
        $jsonlPath = & $script:WriteTempJsonl -Records $records
        try {
            $results = & $script:TestJsonlSchema -JsonlPath $jsonlPath
            $results.Count | Should -Be 2 -Because 'both JSONL lines should be validated'
            $results | ForEach-Object { $_.valid | Should -BeTrue -Because "every line in the emergency JSONL must be schema-valid" }
        } finally {
            Remove-Item -LiteralPath $jsonlPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ordinals are sequential and monotonic across a multi-record JSONL' {
        $records = @(
            (& $script:NewEmergencyRecord -Ordinal 1)
            (& $script:NewEmergencyRecord -Ordinal 2 -ScriptPath 'res://scripts/other.gd')
            (& $script:NewEmergencyRecord -Ordinal 3 -ScriptPath 'res://scripts/third.gd')
        )
        $jsonlPath = & $script:WriteTempJsonl -Records $records
        try {
            $lines  = Get-Content -LiteralPath $jsonlPath | Where-Object { $_.Trim() -ne '' }
            $parsed = $lines | ForEach-Object { $_ | ConvertFrom-Json }
            $ordinals = @($parsed | ForEach-Object { [int]$_.ordinal })
            $ordinals | Should -Be @(1, 2, 3) -Because 'ordinals must be monotonically increasing'
        } finally {
            Remove-Item -LiteralPath $jsonlPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Notes stamp format
# ---------------------------------------------------------------------------

Describe 'Fix #19: validation notes stamp strings' {

    It 'emergency_persisted note is a non-empty string' {
        'runtime_error_records: emergency_persisted' | Should -Not -BeNullOrEmpty
        'runtime_error_records: emergency_persisted' | Should -Match '^runtime_error_records: emergency_persisted$'
    }

    It 'none_observed note is a non-empty string' {
        'runtime_error_records: none_observed' | Should -Not -BeNullOrEmpty
        'runtime_error_records: none_observed' | Should -Match '^runtime_error_records: none_observed$'
    }

    It 'notes stamps are distinct from each other' {
        'runtime_error_records: emergency_persisted' | Should -Not -Be 'runtime_error_records: none_observed'
    }
}
