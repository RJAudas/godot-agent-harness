Describe 'tools/evidence/artifact-registry.ps1 input-dispatch entry' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        . (Get-RepoPath -Path 'tools/evidence/artifact-registry.ps1')
    }

    It 'advertises the input-dispatch-outcomes artifact kind' {
        $kinds = Get-EvidenceArtifactKinds
        $kinds | Should -Contain 'input-dispatch-outcomes'
    }

    It 'defines the input-dispatch-outcomes filename and media type' {
        $definition = Get-EvidenceArtifactDefinitions | Where-Object { $_.kind -eq 'input-dispatch-outcomes' }
        $definition | Should -Not -BeNullOrEmpty
        $definition.file | Should -Be 'input-dispatch-outcomes.jsonl'
        $definition.mediaType | Should -Be 'application/jsonl'
        $definition.description | Should -Not -BeNullOrEmpty
    }
}
