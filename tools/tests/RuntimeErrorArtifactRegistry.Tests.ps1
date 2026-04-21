Describe 'tools/evidence/artifact-registry.ps1 runtime-error-reporting entries' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        . (Get-RepoPath -Path 'tools/evidence/artifact-registry.ps1')
    }

    It 'advertises the runtime-error-records artifact kind' {
        $kinds = Get-EvidenceArtifactKinds
        $kinds | Should -Contain 'runtime-error-records'
    }

    It 'defines runtime-error-records filename and media type' {
        $definition = Get-EvidenceArtifactDefinitions | Where-Object { $_.kind -eq 'runtime-error-records' }
        $definition | Should -Not -BeNullOrEmpty
        $definition.file | Should -Be 'runtime-error-records.jsonl'
        $definition.mediaType | Should -Be 'application/jsonl'
        $definition.description | Should -Not -BeNullOrEmpty
    }

    It 'advertises the pause-decision-log artifact kind' {
        $kinds = Get-EvidenceArtifactKinds
        $kinds | Should -Contain 'pause-decision-log'
    }

    It 'defines pause-decision-log filename and media type' {
        $definition = Get-EvidenceArtifactDefinitions | Where-Object { $_.kind -eq 'pause-decision-log' }
        $definition | Should -Not -BeNullOrEmpty
        $definition.file | Should -Be 'pause-decision-log.jsonl'
        $definition.mediaType | Should -Be 'application/jsonl'
        $definition.description | Should -Not -BeNullOrEmpty
    }
}
