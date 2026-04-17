[CmdletBinding()]
param(
    [string]$ProjectRoot = 'examples/pong-testbed',
    [string]$ConfigPath,
    [string]$RequestPath,
    [string]$RequestFixturePath,
    [string]$BehaviorWatchRequestFixturePath,
    [string]$RequestId,
    [string]$ScenarioId,
    [string]$RunId,
    [string]$TargetScene,
    [string]$OutputDirectory,
    [string]$ArtifactRoot,
    [string[]]$ExpectationFiles = @(),
    [string]$RequestedBy = 'vscode-agent',
    [bool]$StopAfterValidation = $true,
    [string]$BoundaryArtifactId,
    [string]$BoundaryPath = 'tools/automation/write-boundaries.json',
    [string]$BoundaryEditType = 'update',
    [switch]$WriteRunRecord,
    [string]$RunRecordArtifactId,
    [string]$RunRecordBoundaryId,
    [string]$RunRecordOutputPath = 'tools/automation/run-records/latest-editor-evidence-request.json',
    [ValidateSet('autonomous', 'simulated')]
    [string]$RunRecordMode = 'simulated',
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
}

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$CreateParent
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = $Path
    }
    else {
        $resolvedPath = Join-Path (Get-RepoRoot) $Path
    }

    if ($CreateParent) {
        $parentPath = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
    }

    return $resolvedPath
}

function Resolve-ProjectResourcePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRootPath,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$CreateParent
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = $Path
    }
    elseif ($Path.StartsWith('res://', [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $Path.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $resolvedPath = Join-Path $ProjectRootPath $relativePath
    }
    else {
        $resolvedPath = Resolve-RepoPath -Path $Path
    }

    if ($CreateParent) {
        $parentPath = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -LiteralPath $parentPath)) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
    }

    return $resolvedPath
}

function Convert-ToStringArray {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return ,@()
    }

    if ($Value -is [string]) {
        return ,@($Value)
    }

    return ,@($Value | ForEach-Object { [string]$_ })
}

function Get-ValidationMessage {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$SuccessMessage,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    if ($Passed) {
        return $SuccessMessage
    }

    return $FailureMessage
}

function Get-OptionalPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($PropertyName)) {
            return $InputObject[$PropertyName]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

$resolvedProjectRoot = Resolve-RepoPath -Path $ProjectRoot
$resolvedConfigPath = if ($PSBoundParameters.ContainsKey('ConfigPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $ConfigPath
}
else {
    Join-Path $resolvedProjectRoot 'harness/inspection-run-config.json'
}

$config = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json -Depth 100
$defaultRequest = if ($PSBoundParameters.ContainsKey('RequestFixturePath')) {
    $fixturePath = Resolve-RepoPath -Path $RequestFixturePath
    Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -Depth 100
}
else {
    [pscustomobject]@{}
}
$behaviorWatchRequest = if ($PSBoundParameters.ContainsKey('BehaviorWatchRequestFixturePath')) {
    $fixturePath = Resolve-RepoPath -Path $BehaviorWatchRequestFixturePath
    Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json -Depth 100
}
else {
    $null
}
$defaultRequestId = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'requestId'
$defaultScenarioId = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'scenarioId'
$defaultRunId = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'runId'
$defaultTargetScene = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'targetScene'
$defaultOutputDirectory = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'outputDirectory'
$defaultArtifactRoot = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'artifactRoot'
$defaultExpectationFiles = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'expectationFiles'
$defaultCapturePolicy = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'capturePolicy'
$defaultOverrides = Get-OptionalPropertyValue -InputObject $defaultRequest -PropertyName 'overrides'

$requestDocument = [ordered]@{
    requestId = if ($PSBoundParameters.ContainsKey('RequestId')) { $RequestId } elseif ($defaultRequestId) { $defaultRequestId } else { [guid]::NewGuid().Guid }
    scenarioId = if ($PSBoundParameters.ContainsKey('ScenarioId')) { $ScenarioId } elseif ($defaultScenarioId) { $defaultScenarioId } else { $config.scenarioId }
    runId = if ($PSBoundParameters.ContainsKey('RunId')) { $RunId } elseif ($defaultRunId) { $defaultRunId } else { ('run-' + [guid]::NewGuid().Guid) }
    targetScene = if ($PSBoundParameters.ContainsKey('TargetScene')) { $TargetScene } elseif ($defaultTargetScene) { $defaultTargetScene } else { $config.targetScene }
    outputDirectory = if ($PSBoundParameters.ContainsKey('OutputDirectory')) { $OutputDirectory } elseif ($defaultOutputDirectory) { $defaultOutputDirectory } else { $config.outputDirectory }
    artifactRoot = if ($PSBoundParameters.ContainsKey('ArtifactRoot')) { $ArtifactRoot } elseif ($defaultArtifactRoot) { $defaultArtifactRoot } else { $config.artifactRoot }
    expectationFiles = if ($ExpectationFiles.Count -gt 0) { Convert-ToStringArray $ExpectationFiles } elseif ($defaultExpectationFiles) { Convert-ToStringArray $defaultExpectationFiles } else { Convert-ToStringArray $config.expectationFiles }
    capturePolicy = if ($defaultCapturePolicy) { $defaultCapturePolicy } else { $config.capturePolicy }
    stopPolicy = [ordered]@{ stopAfterValidation = $StopAfterValidation }
    requestedBy = $RequestedBy
    createdAt = [DateTime]::UtcNow.ToString('o')
}

if ($null -ne $defaultOverrides) {
    $requestDocument.overrides = $defaultOverrides | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -AsHashtable
}

if ($null -ne $behaviorWatchRequest) {
    if (-not $requestDocument.Contains('overrides')) {
        $requestDocument.overrides = [ordered]@{}
    }
    $requestDocument.overrides.behaviorWatchRequest = $behaviorWatchRequest
}

$resolvedRequestPath = if ($PSBoundParameters.ContainsKey('RequestPath')) {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $RequestPath -CreateParent
}
else {
    Resolve-ProjectResourcePath -ProjectRootPath $resolvedProjectRoot -Path $config.automation.requestPath -CreateParent
}

$writeBoundaryValidation = $null
if ($PSBoundParameters.ContainsKey('BoundaryArtifactId')) {
    $writeBoundaryValidation = & (Join-Path $PSScriptRoot 'validate-write-boundary.ps1') -ArtifactId $BoundaryArtifactId -RequestedPath $resolvedRequestPath -RequestedEditType $BoundaryEditType -BoundaryPath $BoundaryPath -PassThru -AllowViolation
    if (-not $writeBoundaryValidation.requestAllowed) {
        throw "Resolved request path '$resolvedRequestPath' did not pass boundary validation for artifact '$BoundaryArtifactId'."
    }
}

$requestDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedRequestPath
$validation = & (Join-Path $PSScriptRoot '..\validate-json.ps1') -InputPath $resolvedRequestPath -SchemaPath 'specs/003-editor-evidence-loop/contracts/automation-run-request.schema.json' -PassThru -AllowInvalid

$runRecordPath = $null
if ($WriteRunRecord) {
    $effectiveRunRecordArtifactId = if ($PSBoundParameters.ContainsKey('RunRecordArtifactId')) { $RunRecordArtifactId } else { $BoundaryArtifactId }
    $effectiveRunRecordBoundaryId = if ($PSBoundParameters.ContainsKey('RunRecordBoundaryId')) { $RunRecordBoundaryId } elseif ($null -ne $writeBoundaryValidation) { $writeBoundaryValidation.boundaryId } else { $null }
    if ([string]::IsNullOrWhiteSpace($effectiveRunRecordArtifactId)) {
        throw 'RunRecordArtifactId or BoundaryArtifactId is required when WriteRunRecord is set.'
    }
    if ([string]::IsNullOrWhiteSpace($effectiveRunRecordBoundaryId)) {
        throw 'RunRecordBoundaryId is required when WriteRunRecord is set and no boundary validation was performed.'
    }

    $validationNames = @('request-schema-validation')
    $validationStatuses = @(if ($validation.valid) { 'passed' } else { 'failed' })
    $validationDetails = @(
        (Get-ValidationMessage -Passed ([bool]$validation.valid) -SuccessMessage 'Generated automation request passed schema validation.' -FailureMessage 'Generated automation request failed schema validation.')
    )

    if ($null -ne $writeBoundaryValidation) {
        $validationNames = @('write-boundary-validation') + $validationNames
        $validationStatuses = @('passed') + $validationStatuses
        $validationDetails = @('Resolved request path passed declared write-boundary validation.') + $validationDetails
    }

    $runRecord = & (Join-Path $PSScriptRoot 'new-autonomous-run-record.ps1') -ArtifactId $effectiveRunRecordArtifactId -WriteBoundaryId $effectiveRunRecordBoundaryId -RequestSummary "Write automation request artifact to $resolvedRequestPath" -OutputPath $RunRecordOutputPath -Mode $RunRecordMode -Status $(if ($validation.valid) { 'success' } else { 'failed' }) -OperationPath $resolvedRequestPath -OperationEditType $BoundaryEditType -OperationStatus 'performed' -ValidationName $validationNames -ValidationStatus $validationStatuses -ValidationDetails $validationDetails -PassThru
    $runRecordPath = $runRecord.recordPath
}

$result = [ordered]@{
    projectRoot = $resolvedProjectRoot
    configPath = $resolvedConfigPath
    requestPath = $resolvedRequestPath
    requestId = $requestDocument.requestId
    runId = $requestDocument.runId
    schemaValid = [bool]$validation.valid
    writeBoundaryValidated = [bool]($null -ne $writeBoundaryValidation -and $writeBoundaryValidation.requestAllowed)
    writeBoundaryId = if ($null -ne $writeBoundaryValidation) { $writeBoundaryValidation.boundaryId } else { $null }
    runRecordPath = $runRecordPath
}

if (-not $result.schemaValid) {
    throw 'Generated automation run request did not pass schema validation.'
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 10
}
