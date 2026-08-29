[CmdletBinding()]
param(
    [string]$Source,
    [string]$Output
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $ProjectRoot 'third_party\goldberg'
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $ProjectRoot 'build\goldberg-exact'
}
$Source = [IO.Path]::GetFullPath($Source)
$Output = [IO.Path]::GetFullPath($Output)

$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $VsWhere -PathType Leaf)) {
    throw 'vswhere.exe was not found; install Visual Studio 2022 C++ build tools'
}
$VsInstall = (& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($VsInstall)) {
    throw 'A Visual Studio installation with x86/x64 C++ tools was not found'
}
$VsDevCmd = Join-Path $VsInstall 'Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path $VsDevCmd -PathType Leaf)) {
    throw "Missing Visual Studio developer environment: $VsDevCmd"
}

$BuildScript = Join-Path $PSScriptRoot 'build-goldberg-x64.cmd'
$Protobuf = Join-Path $ProjectRoot 'third_party\vcpkg\installed\x64-windows-static'
foreach ($Required in @($BuildScript, $Source, $Protobuf)) {
    if (-not (Test-Path $Required -PathType Leaf)) {
        if (-not (Test-Path $Required -PathType Container)) {
            throw "Goldberg build input is missing: $Required"
        }
    }
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
& $BuildScript $Source $Protobuf $VsDevCmd $Output
if ($LASTEXITCODE -ne 0) {
    throw "Goldberg x64 build failed with exit code $LASTEXITCODE"
}

foreach ($Name in @('steam_api64.dll', 'steamclient64.dll')) {
    $Required = Join-Path $Output $Name
    if (-not (Test-Path $Required -PathType Leaf)) {
        throw "Goldberg x64 build did not produce $Required"
    }
}
Write-Host "Goldberg experimental x64 outputs written to $Output"
