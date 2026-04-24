[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,

    [switch]$SkipAgentAssets,

    [switch]$SkipProjectSettings,

    [switch]$AddonOnly,

    [string]$TargetScene,

    [switch]$PassThru
)

if ($AddonOnly) {
    $SkipAgentAssets = $true
    $SkipProjectSettings = $true
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-TemplateRoot {
    return Join-Path (Get-RepoRoot) 'addons/agent_runtime_harness/templates/project_root'
}

$script:ResolvedHarnessRoot = ''

function Get-TemplateContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $templatePath = Join-Path (Get-TemplateRoot) $RelativePath
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template '$RelativePath' was not found at '$templatePath'."
    }

    $content = Get-Content -LiteralPath $templatePath -Raw
    if ($script:ResolvedHarnessRoot) {
        $content = $content.Replace('{{HARNESS_REPO_ROOT}}', $script:ResolvedHarnessRoot)
    }
    return $content
}

function Resolve-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    Ensure-Directory -Path $parent

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Set-OrAppendManagedBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$MarkerName,

        [Parameter(Mandatory = $true)]
        [string]$BlockContent
    )

    $beginMarker = "<!-- BEGIN $MarkerName -->"
    $endMarker = "<!-- END $MarkerName -->"
    $managedBlock = @(
        $beginMarker
        $BlockContent.TrimEnd()
        $endMarker
        ''
    ) -join [Environment]::NewLine

    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        $pattern = [regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker)
        if ([regex]::IsMatch($existing, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
            $updated = [regex]::Replace($existing, $pattern, $managedBlock.TrimEnd(), [System.Text.RegularExpressions.RegexOptions]::Singleline)
            Write-Utf8NoBomFile -Path $Path -Content ($updated.TrimEnd() + [Environment]::NewLine)
            return 'updated'
        }

        $separator = if ($existing.EndsWith([Environment]::NewLine)) { '' } else { [Environment]::NewLine }
        Write-Utf8NoBomFile -Path $Path -Content ($existing + $separator + $managedBlock)
        return 'appended'
    }

    Write-Utf8NoBomFile -Path $Path -Content $managedBlock
    return 'created'
}

function Set-FileContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    Write-Utf8NoBomFile -Path $Path -Content ($Content.TrimEnd() + [Environment]::NewLine)
}

function Add-Operation {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Operations,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    $Operations.Add([ordered]@{ path = $Path; action = $Action })
}

function Set-IniProperty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Content -split "`r?`n")) {
        $lines.Add($line)
    }

    $sectionHeader = "[$SectionName]"
    $sectionIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq $sectionHeader) {
            $sectionIndex = $index
            break
        }
    }

    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') {
            $lines.Add('')
        }
        $lines.Add($sectionHeader)
        $lines.Add('')
        $lines.Add("$Key=$Value")
        return ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
    }

    $insertIndex = $lines.Count
    for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\[.+\]$') {
            $insertIndex = $index
            break
        }
    }

    for ($index = $sectionIndex + 1; $index -lt $insertIndex; $index++) {
        if ($lines[$index] -match ('^' + [regex]::Escape($Key) + '=')) {
            $lines[$index] = "$Key=$Value"
            return ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
        }
    }

    $targetIndex = $sectionIndex + 1
    if ($targetIndex -lt $lines.Count -and $lines[$targetIndex] -eq '') {
        $targetIndex++
    }
    $lines.Insert($targetIndex, "$Key=$Value")
    return ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
}

function Add-PackedStringArrayValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $sectionHeader = "[$SectionName]"
    $lines = $Content -split "`r?`n"
    $sectionIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq $sectionHeader) {
            $sectionIndex = $index
            break
        }
    }

    if ($sectionIndex -lt 0) {
        return Set-IniProperty -Content $Content -SectionName $SectionName -Key $Key -Value ("PackedStringArray(`"$Value`")")
    }

    $sectionEnd = $lines.Count
    for ($index = $sectionIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\[.+\]$') {
            $sectionEnd = $index
            break
        }
    }

    for ($index = $sectionIndex + 1; $index -lt $sectionEnd; $index++) {
        if ($lines[$index] -notmatch ('^' + [regex]::Escape($Key) + '=')) {
            continue
        }

        $line = $lines[$index]
        $existingValues = [System.Collections.Generic.List[string]]::new()
        $matchCollection = [regex]::Matches($line, '"([^"]+)"')
        foreach ($match in $matchCollection) {
            $existingValues.Add($match.Groups[1].Value)
        }

        if ($Value -notin $existingValues) {
            $existingValues.Add($Value)
        }

        $joinedValues = ($existingValues | ForEach-Object { '"{0}"' -f $_ }) -join ', '
        $lines[$index] = "$Key=PackedStringArray($joinedValues)"
        return ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
    }

    return Set-IniProperty -Content $Content -SectionName $SectionName -Key $Key -Value ("PackedStringArray(`"$Value`")")
}

function Get-CopilotInstructionsBlock {
    return (Get-TemplateContent -RelativePath '.github/copilot-instructions.runtime-harness.md')
}

function Get-AgentsFileContent {
    return @"
# AGENTS.md

$(Get-AgentsBlockContent).TrimEnd()
"@
}

function Get-AgentsBlockContent {
    return (Get-TemplateContent -RelativePath 'AGENTS.runtime-harness.md')
}

function Get-TriagePromptContent {
    return (Get-TemplateContent -RelativePath '.github/prompts/godot-evidence-triage.prompt.md')
}

function Get-TriageAgentContent {
    return (Get-TemplateContent -RelativePath '.github/agents/godot-evidence-triage.agent.md')
}

function Get-RuntimeVerificationPromptContent {
    return (Get-TemplateContent -RelativePath '.github/prompts/godot-runtime-verification.prompt.md')
}

function Get-RuntimeVerificationAgentContent {
    return (Get-TemplateContent -RelativePath '.github/agents/godot-runtime-verification.agent.md')
}

function Get-ClaudeInstructionsBlock {
    return (Get-TemplateContent -RelativePath 'CLAUDE.runtime-harness.md')
}

function Get-ClaudeFileContent {
    return @"
# CLAUDE.md

$(Get-ClaudeInstructionsBlock).TrimEnd()
"@
}

function Get-ClaudeRuntimeVerificationAgentContent {
    return (Get-TemplateContent -RelativePath '.claude/agents/godot-runtime-verification.md')
}

function Get-ClaudeEvidenceTriageAgentContent {
    return (Get-TemplateContent -RelativePath '.claude/agents/godot-evidence-triage.md')
}

function Get-InspectionRunConfigContent {
    return (Get-TemplateContent -RelativePath 'harness/inspection-run-config.json')
}

function Set-InspectionConfigTargetScene {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetScene
    )

    $configJson = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 100
    if (-not ($configJson.PSObject.Properties.Name -contains 'targetScene')) {
        Add-Member -InputObject $configJson -MemberType NoteProperty -Name 'targetScene' -Value $TargetScene -Force
    }
    else {
        $configJson.targetScene = $TargetScene
    }
    Set-FileContent -Path $ConfigPath -Content (($configJson | ConvertTo-Json -Depth 100) + "`n")
}

$repoRoot = Get-RepoRoot
$script:ResolvedHarnessRoot = $repoRoot.Replace('\', '/')
$resolvedGameRoot = Resolve-AbsolutePath -Path $GameRoot
$projectFilePath = Join-Path $resolvedGameRoot 'project.godot'

if (-not (Test-Path -LiteralPath $resolvedGameRoot)) {
    throw "Game root '$resolvedGameRoot' does not exist."
}

if (-not (Test-Path -LiteralPath $projectFilePath)) {
    throw "Game root '$resolvedGameRoot' does not contain project.godot."
}

$operations = [System.Collections.Generic.List[object]]::new()

$addonSourcePath = Join-Path $repoRoot 'addons/agent_runtime_harness'
$addonDestinationRoot = Join-Path $resolvedGameRoot 'addons'
$addonDestinationPath = Join-Path $addonDestinationRoot 'agent_runtime_harness'

Ensure-Directory -Path $addonDestinationRoot
if ($PSCmdlet.ShouldProcess($addonDestinationPath, 'Copy harness addon')) {
    Copy-Item -Path $addonSourcePath -Destination $addonDestinationRoot -Recurse -Force
    $copyAddonAction = 'copied-addon'
}
else {
    $copyAddonAction = 'skipped-copy-addon'
}
Add-Operation -Operations $operations -Path $addonDestinationPath -Action $copyAddonAction

$configPath = Join-Path $resolvedGameRoot 'harness/inspection-run-config.json'
if (-not $AddonOnly) {
    Ensure-Directory -Path (Join-Path $resolvedGameRoot 'harness')
    Ensure-Directory -Path (Join-Path $resolvedGameRoot 'evidence/scenegraph/latest')

    $harnessSourcePath = Join-Path $resolvedGameRoot 'harness/harness-source.json'
    $harnessSourceContent = [ordered]@{ harnessRepoRoot = $script:ResolvedHarnessRoot } | ConvertTo-Json
    if ($PSCmdlet.ShouldProcess($harnessSourcePath, 'Write harness source config')) {
        Set-FileContent -Path $harnessSourcePath -Content $harnessSourceContent
        $harnessSourceAction = 'wrote-harness-source'
    }
    else {
        $harnessSourceAction = 'skipped-harness-source'
    }
    Add-Operation -Operations $operations -Path $harnessSourcePath -Action $harnessSourceAction

    if (-not (Test-Path -LiteralPath $configPath)) {
        if ($PSCmdlet.ShouldProcess($configPath, 'Create harness inspection config')) {
            Set-FileContent -Path $configPath -Content (Get-InspectionRunConfigContent)
            if ($PSBoundParameters.ContainsKey('TargetScene') -and -not [string]::IsNullOrWhiteSpace($TargetScene)) {
                Set-InspectionConfigTargetScene -ConfigPath $configPath -TargetScene $TargetScene
            }
            $configAction = 'created-config'
        }
        else {
            $configAction = 'skipped-create-config'
        }
        Add-Operation -Operations $operations -Path $configPath -Action $configAction
    }
    else {
        if ($PSBoundParameters.ContainsKey('TargetScene') -and -not [string]::IsNullOrWhiteSpace($TargetScene)) {
            if ($PSCmdlet.ShouldProcess($configPath, 'Update inspection config targetScene')) {
                Set-InspectionConfigTargetScene -ConfigPath $configPath -TargetScene $TargetScene
                Add-Operation -Operations $operations -Path $configPath -Action 'updated-config-target-scene'
            }
        }
        else {
            Add-Operation -Operations $operations -Path $configPath -Action 'preserved-config'
        }
    }
}

if (-not $SkipProjectSettings) {
    $projectContent = Get-Content -LiteralPath $projectFilePath -Raw
    $projectContent = Set-IniProperty -Content $projectContent -SectionName 'autoload' -Key 'ScenegraphHarness' -Value '"*res://addons/agent_runtime_harness/runtime/scenegraph_autoload.gd"'
    $projectContent = Add-PackedStringArrayValue -Content $projectContent -SectionName 'editor_plugins' -Key 'enabled' -Value 'res://addons/agent_runtime_harness/plugin.cfg'
    $projectContent = Set-IniProperty -Content $projectContent -SectionName 'harness' -Key 'inspection_run_config' -Value '"res://harness/inspection-run-config.json"'
    if ($PSCmdlet.ShouldProcess($projectFilePath, 'Update project.godot harness wiring')) {
        Set-FileContent -Path $projectFilePath -Content $projectContent
        $projectSettingsAction = 'updated-project-settings'
    }
    else {
        $projectSettingsAction = 'skipped-update-project-settings'
    }
    Add-Operation -Operations $operations -Path $projectFilePath -Action $projectSettingsAction
}

if (-not $SkipAgentAssets) {
    $copilotInstructionsPath = Join-Path $resolvedGameRoot '.github/copilot-instructions.md'
    if ($PSCmdlet.ShouldProcess($copilotInstructionsPath, 'Install runtime harness Copilot instructions')) {
        $copilotAction = Set-OrAppendManagedBlock -Path $copilotInstructionsPath -MarkerName 'AGENT_RUNTIME_HARNESS' -BlockContent (Get-CopilotInstructionsBlock)
    }
    else {
        $copilotAction = 'skipped'
    }
    Add-Operation -Operations $operations -Path $copilotInstructionsPath -Action "copilot-instructions-$copilotAction"

    $agentsPath = Join-Path $resolvedGameRoot 'AGENTS.md'
    if (Test-Path -LiteralPath $agentsPath) {
        if ($PSCmdlet.ShouldProcess($agentsPath, 'Install runtime harness AGENTS block')) {
            $agentsAction = Set-OrAppendManagedBlock -Path $agentsPath -MarkerName 'AGENT_RUNTIME_HARNESS' -BlockContent (Get-AgentsBlockContent)
        }
        else {
            $agentsAction = 'skipped'
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($agentsPath, 'Write AGENTS.md')) {
            Set-FileContent -Path $agentsPath -Content (Get-AgentsFileContent)
            $agentsAction = 'created'
        }
        else {
            $agentsAction = 'skipped'
        }
    }
    Add-Operation -Operations $operations -Path $agentsPath -Action "agents-$agentsAction"

    $promptPath = Join-Path $resolvedGameRoot '.github/prompts/godot-evidence-triage.prompt.md'
    if ($PSCmdlet.ShouldProcess($promptPath, 'Write Godot evidence triage prompt')) {
        Set-FileContent -Path $promptPath -Content (Get-TriagePromptContent)
        $promptAction = 'wrote-prompt'
    }
    else {
        $promptAction = 'skipped-write-prompt'
    }
    Add-Operation -Operations $operations -Path $promptPath -Action $promptAction

    $runtimePromptPath = Join-Path $resolvedGameRoot '.github/prompts/godot-runtime-verification.prompt.md'
    if ($PSCmdlet.ShouldProcess($runtimePromptPath, 'Write Godot runtime verification prompt')) {
        Set-FileContent -Path $runtimePromptPath -Content (Get-RuntimeVerificationPromptContent)
        $runtimePromptAction = 'wrote-runtime-prompt'
    }
    else {
        $runtimePromptAction = 'skipped-write-runtime-prompt'
    }
    Add-Operation -Operations $operations -Path $runtimePromptPath -Action $runtimePromptAction

    $agentPath = Join-Path $resolvedGameRoot '.github/agents/godot-evidence-triage.agent.md'
    if ($PSCmdlet.ShouldProcess($agentPath, 'Write Godot evidence triage agent')) {
        Set-FileContent -Path $agentPath -Content (Get-TriageAgentContent)
        $agentAction = 'wrote-agent'
    }
    else {
        $agentAction = 'skipped-write-agent'
    }
    Add-Operation -Operations $operations -Path $agentPath -Action $agentAction

    $runtimeAgentPath = Join-Path $resolvedGameRoot '.github/agents/godot-runtime-verification.agent.md'
    if ($PSCmdlet.ShouldProcess($runtimeAgentPath, 'Write Godot runtime verification agent')) {
        Set-FileContent -Path $runtimeAgentPath -Content (Get-RuntimeVerificationAgentContent)
        $runtimeAgentAction = 'wrote-runtime-agent'
    }
    else {
        $runtimeAgentAction = 'skipped-write-runtime-agent'
    }
    Add-Operation -Operations $operations -Path $runtimeAgentPath -Action $runtimeAgentAction

    # Claude Code assets (CLAUDE.md + .claude/agents/*.md). Claude Code reads
    # CLAUDE.md and AGENTS.md natively; the subagents under .claude/agents/
    # give it the same delegation surface Copilot gets from .github/agents/.
    $claudePath = Join-Path $resolvedGameRoot 'CLAUDE.md'
    if (Test-Path -LiteralPath $claudePath) {
        if ($PSCmdlet.ShouldProcess($claudePath, 'Install runtime harness CLAUDE.md block')) {
            $claudeAction = Set-OrAppendManagedBlock -Path $claudePath -MarkerName 'AGENT_RUNTIME_HARNESS' -BlockContent (Get-ClaudeInstructionsBlock)
        }
        else {
            $claudeAction = 'skipped'
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($claudePath, 'Write CLAUDE.md')) {
            Set-FileContent -Path $claudePath -Content (Get-ClaudeFileContent)
            $claudeAction = 'created'
        }
        else {
            $claudeAction = 'skipped'
        }
    }
    Add-Operation -Operations $operations -Path $claudePath -Action "claude-md-$claudeAction"

    $claudeRuntimeAgentPath = Join-Path $resolvedGameRoot '.claude/agents/godot-runtime-verification.md'
    if ($PSCmdlet.ShouldProcess($claudeRuntimeAgentPath, 'Write Claude runtime-verification subagent')) {
        Set-FileContent -Path $claudeRuntimeAgentPath -Content (Get-ClaudeRuntimeVerificationAgentContent)
        $claudeRuntimeAgentAction = 'wrote-claude-runtime-agent'
    }
    else {
        $claudeRuntimeAgentAction = 'skipped-write-claude-runtime-agent'
    }
    Add-Operation -Operations $operations -Path $claudeRuntimeAgentPath -Action $claudeRuntimeAgentAction

    $claudeTriageAgentPath = Join-Path $resolvedGameRoot '.claude/agents/godot-evidence-triage.md'
    if ($PSCmdlet.ShouldProcess($claudeTriageAgentPath, 'Write Claude evidence-triage subagent')) {
        Set-FileContent -Path $claudeTriageAgentPath -Content (Get-ClaudeEvidenceTriageAgentContent)
        $claudeTriageAgentAction = 'wrote-claude-triage-agent'
    }
    else {
        $claudeTriageAgentAction = 'skipped-write-claude-triage-agent'
    }
    Add-Operation -Operations $operations -Path $claudeTriageAgentPath -Action $claudeTriageAgentAction
}

$result = [ordered]@{
    gameRoot = $resolvedGameRoot
    addonPath = $addonDestinationPath
    configPath = $configPath
    projectSettingsUpdated = (-not $SkipProjectSettings)
    agentAssetsInstalled = (-not $SkipAgentAssets)
    operations = @($operations)
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}
