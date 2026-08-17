[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AmxxRoot,

    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$amxxRootPath = (Resolve-Path -LiteralPath $AmxxRoot).Path
$scriptingDirectory = Join-Path $amxxRootPath 'addons\amxmodx\scripting'
$compiler = Join-Path $scriptingDirectory 'amxxpc.exe'
$includeDirectory = Join-Path $scriptingDirectory 'include'
$source = Join-Path $repositoryRoot 'addons\amxmodx\scripting\weapon_inspector.sma'

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "AMX Mod X compiler not found: $compiler"
}

if (-not (Test-Path -LiteralPath (Join-Path $includeDirectory 'cstrike.inc') -PathType Leaf)) {
    throw 'The Counter-Strike addon is missing. Install it over the AMX Mod X base package.'
}

$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$compiledPlugin = Join-Path $outputPath 'weapon_inspector.amxx'

& $compiler $source "-i$includeDirectory" "-o$compiledPlugin"

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $compiledPlugin -PathType Leaf)) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

$artifact = Get-Item -LiteralPath $compiledPlugin
Write-Host "Compiled $($artifact.FullName) ($($artifact.Length) bytes)."
