[CmdletBinding()]
param(
    [switch]$SkipFetch,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildRoot = Join-Path $ProjectRoot 'build'
$GoldbergSource = Join-Path $ProjectRoot 'third_party\goldberg'
$VcpkgRoot = Join-Path $ProjectRoot 'third_party\vcpkg'

function Invoke-Native {
    param(
        [string]$Program,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE"
    }
}

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    throw 'The build must run on Windows with Visual Studio C++ tools installed'
}

if (-not $SkipFetch) {
    & (Join-Path $PSScriptRoot 'fetch-sources.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Source fetch failed' }
}

foreach ($Required in @($GoldbergSource, $VcpkgRoot)) {
    if (-not (Test-Path $Required)) {
        throw "Missing $Required. Run scripts\fetch-sources.ps1 first."
    }
}

if ($Clean -and (Test-Path $BuildRoot)) {
    Remove-Item -Recurse -Force $BuildRoot
}
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

$Bootstrap = Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'
$Vcpkg = Join-Path $VcpkgRoot 'vcpkg.exe'
if (-not (Test-Path $Vcpkg)) {
    Invoke-Native -Program $Bootstrap -Arguments @('-disableMetrics')
}
Invoke-Native -Program $Vcpkg -Arguments @(
    'install',
    'protobuf:x64-windows-static',
    '--clean-after-build'
)

$LauncherBuild = Join-Path $BuildRoot 'launcher'
Invoke-Native -Program 'cmake' -Arguments @('-S', $ProjectRoot, '-B', $LauncherBuild, '-A', 'x64')
Invoke-Native -Program 'cmake' -Arguments @(
    '--build', $LauncherBuild, '--config', 'Release', '--target', 'game-lan-launcher'
)

& (Join-Path $PSScriptRoot 'build-goldberg.ps1') `
    -Source $GoldbergSource `
    -Output (Join-Path $BuildRoot 'goldberg-exact')

Write-Host 'Build complete. Run scripts\package.ps1 to create a clean game-lan directory.'
