[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$SchemaPath,

    [switch]$PassThru,

    [switch]$AllowInvalid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    return (Resolve-Path -LiteralPath (Join-Path $repoRoot $Path)).Path
}

function ConvertTo-PointerToken {
    param([Parameter(Mandatory = $true)][string]$RawToken)
    return $RawToken.Replace('~1', '/').Replace('~0', '~')
}

function Resolve-JsonPointer {
    param(
        [Parameter(Mandatory = $true)] $Root,
        [Parameter(Mandatory = $true)] [string[]]$Tokens
    )

    $cursor = $Root
    foreach ($token in $Tokens) {
        if ($null -eq $cursor) { return $null }
        if ($cursor -is [System.Collections.IList] -and $cursor -isnot [string]) {
            if ($token -notmatch '^\d+$') { return $null }
            $idx = [int]$token
            if ($idx -lt 0 -or $idx -ge $cursor.Count) { return $null }
            $cursor = $cursor[$idx]
            continue
        }
        if ($cursor -is [psobject]) {
            $prop = $cursor.PSObject.Properties[$token]
            if ($null -eq $prop) { return $null }
            $cursor = $prop.Value
            continue
        }
        return $null
    }
    return $cursor
}

function Resolve-SchemaForInstancePointer {
    param(
        [Parameter(Mandatory = $true)] $RootSchema,
        [Parameter(Mandatory = $true)] [string[]]$InstanceTokens
    )

    $node = $RootSchema
    $node = Resolve-SchemaRefs -RootSchema $RootSchema -Node $node
    foreach ($token in $InstanceTokens) {
        if ($null -eq $node) { return $null }
        if ($token -match '^\d+$' -and $node.PSObject.Properties['items']) {
            $node = $node.items
        }
        elseif ($node.PSObject.Properties['properties'] -and $node.properties.PSObject.Properties[$token]) {
            $node = $node.properties.$token
        }
        else {
            return $null
        }
        $node = Resolve-SchemaRefs -RootSchema $RootSchema -Node $node
    }
    return $node
}

function Resolve-SchemaRefs {
    param(
        [Parameter(Mandatory = $true)] $RootSchema,
        $Node
    )

    $guard = 0
    while ($null -ne $Node -and $Node -is [psobject] -and $Node.PSObject.Properties['$ref']) {
        $guard++
        if ($guard -gt 16) { return $Node }
        $ref = [string]$Node.'$ref'
        if (-not $ref.StartsWith('#/')) { return $Node }
        $tokens = $ref.Substring(2).Split('/') | ForEach-Object { ConvertTo-PointerToken -RawToken $_ }
        $Node = Resolve-JsonPointer -Root $RootSchema -Tokens $tokens
    }
    return $Node
}

function Get-EnumEnrichment {
    param(
        [Parameter(Mandatory = $true)] [string]$ValidationMessage,
        [Parameter(Mandatory = $true)] [string]$InputJsonText,
        [Parameter(Mandatory = $true)] [string]$SchemaJsonText
    )

    $match = [regex]::Match($ValidationMessage, "enum at '(?<pointer>[^']*)'")
    if (-not $match.Success) { return $null }

    $pointer = $match.Groups['pointer'].Value
    $tokens = @()
    if ($pointer.StartsWith('/')) {
        $tokens = $pointer.Substring(1).Split('/') | ForEach-Object { ConvertTo-PointerToken -RawToken $_ }
    }

    $schemaRoot = $null
    $inputRoot = $null
    try {
        $schemaRoot = $SchemaJsonText | ConvertFrom-Json -Depth 100
        $inputRoot = $InputJsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        return $null
    }

    $offendingValue = Resolve-JsonPointer -Root $inputRoot -Tokens $tokens
    $subSchema = Resolve-SchemaForInstancePointer -RootSchema $schemaRoot -InstanceTokens $tokens
    if ($null -eq $subSchema -or -not ($subSchema -is [psobject]) -or -not $subSchema.PSObject.Properties['enum']) {
        return $null
    }

    $allowed = @($subSchema.enum | ForEach-Object { [string]$_ })
    $offendingDisplay = if ($null -eq $offendingValue) { '<missing>' } else { [string]$offendingValue }
    return "Property at '$pointer' has value '$offendingDisplay'; allowed values: $($allowed -join ', ')."
}

$resolvedInputPath = Resolve-RepoPath -Path $InputPath
$resolvedSchemaPath = Resolve-RepoPath -Path $SchemaPath

$isValid = $true
$validationError = $null
$jsonText = $null

try {
    $jsonText = Get-Content -LiteralPath $resolvedInputPath -Raw
    [void](ConvertFrom-Json -InputObject $jsonText -Depth 100)
    $isValid = Test-Json -Json $jsonText -SchemaFile $resolvedSchemaPath
}
catch {
    $isValid = $false
    $validationError = $_.Exception.Message
}

$result = [ordered]@{
    inputPath = $resolvedInputPath
    schemaPath = $resolvedSchemaPath
    valid = [bool]$isValid
}

if (-not $isValid) {
    $message = if ($null -ne $validationError) {
        $validationError
    }
    else {
        'JSON validation failed against the supplied schema.'
    }

    if ($null -ne $jsonText -and $message -match "enum at '") {
        try {
            $schemaText = Get-Content -LiteralPath $resolvedSchemaPath -Raw
            $enriched = Get-EnumEnrichment -ValidationMessage $message -InputJsonText $jsonText -SchemaJsonText $schemaText
            if ($null -ne $enriched) {
                $message = "$message`n$enriched"
            }
        }
        catch {
            # Enrichment is best-effort; fall through to the raw message on any failure.
        }
    }

    $result.error = $message
}

if ($PassThru) {
    [pscustomobject]$result
}
else {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
}

if (-not $isValid -and -not $AllowInvalid -and -not $PassThru) {
    exit 1
}
