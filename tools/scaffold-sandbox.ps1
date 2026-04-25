[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$RootDir,

    [string]$DisplayName,

    [string]$TargetScene = 'res://scenes/main.tscn',

    [switch]$Force,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if ($Name -match '[\\/:\*\?"<>\|]' -or $Name.StartsWith('.')) {
    throw "Sandbox name '$Name' contains invalid characters or starts with '.'."
}

$repoRoot = Get-RepoRoot

if (-not $RootDir) {
    $RootDir = Join-Path $repoRoot 'integration-testing'
}

if (-not (Test-Path -LiteralPath $RootDir)) {
    if ($PSCmdlet.ShouldProcess($RootDir, 'Create integration-testing root')) {
        New-Item -ItemType Directory -Path $RootDir -Force | Out-Null
    }
}

$sandboxPath = Join-Path $RootDir $Name
$existed = Test-Path -LiteralPath $sandboxPath

if ($existed -and -not $Force) {
    throw "Sandbox '$Name' already exists at '$sandboxPath'. Pass -Force to reset it."
}

if ($existed -and $Force) {
    if ($PSCmdlet.ShouldProcess($sandboxPath, 'Remove existing sandbox')) {
        Remove-Item -LiteralPath $sandboxPath -Recurse -Force
    }
}

if ($PSCmdlet.ShouldProcess($sandboxPath, 'Create sandbox directory')) {
    New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null
}

if (-not $DisplayName) {
    $DisplayName = $Name
}

$projectGodot = @"
; Engine configuration file.

config_version=5

[application]

config/name="$DisplayName"
run/main_scene="$TargetScene"
config/features=PackedStringArray("4.6")
"@

$projectFile = Join-Path $sandboxPath 'project.godot'
if ($PSCmdlet.ShouldProcess($projectFile, 'Write project.godot')) {
    Write-Utf8NoBomFile -Path $projectFile -Content ($projectGodot + [Environment]::NewLine)
}

$mainScene = @"
[gd_scene format=3]

[node name="Main" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Label" type="Label" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
horizontal_alignment = 1
vertical_alignment = 1
text = "$DisplayName sandbox"
"@

$mainScenePath = Join-Path $sandboxPath 'scenes/main.tscn'
if ($PSCmdlet.ShouldProcess($mainScenePath, 'Write scenes/main.tscn')) {
    Write-Utf8NoBomFile -Path $mainScenePath -Content ($mainScene + [Environment]::NewLine)
}

$deployScript = Join-Path $repoRoot 'tools/deploy-game-harness.ps1'
$deployResult = & $deployScript -GameRoot $sandboxPath -TargetScene $TargetScene -PassThru

$result = [ordered]@{
    name = $Name
    sandboxPath = $sandboxPath
    projectFile = $projectFile
    mainScenePath = $mainScenePath
    targetScene = $TargetScene
    reset = ($existed -and $Force.IsPresent)
    deploy = $deployResult
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}
