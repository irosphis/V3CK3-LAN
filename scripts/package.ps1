[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PackageRoot = Join-Path $ProjectRoot 'dist\game-lan'
$Launcher = Join-Path $ProjectRoot 'build\launcher\Release\game-lan-launcher.exe'
$SteamApi = Join-Path $ProjectRoot 'build\goldberg-exact\steam_api64.dll'
$SteamClient = Join-Path $ProjectRoot 'build\goldberg-exact\steamclient64.dll'

foreach ($Required in @($Launcher, $SteamApi, $SteamClient)) {
    if (-not (Test-Path $Required -PathType Leaf)) {
        throw "Missing build output: $Required. Run scripts\build.ps1 first."
    }
}

if (Test-Path $PackageRoot) {
    Remove-Item -Recurse -Force $PackageRoot
}
New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot 'steam_settings') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot 'LICENSES') | Out-Null

Copy-Item $Launcher $PackageRoot
Copy-Item $SteamApi $PackageRoot
Copy-Item $SteamClient $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'config\game-lan.ini') $PackageRoot
Copy-Item (Join-Path $PSScriptRoot 'configure-player.ps1') $PackageRoot
Copy-Item (Join-Path $PSScriptRoot 'configure-interactive.ps1') $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'package\*') $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'config\steam_settings\*') (Join-Path $PackageRoot 'steam_settings')
Copy-Item (Join-Path $ProjectRoot 'README.md') $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'README.zh-CN.md') $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'SOURCE_LOCK.json') $PackageRoot
Copy-Item (Join-Path $ProjectRoot 'THIRD_PARTY_NOTICES.md') $PackageRoot
$BuildProvenance = Join-Path $ProjectRoot 'build\BUILD_PROVENANCE.txt'
if (Test-Path $BuildProvenance -PathType Leaf) {
    Copy-Item $BuildProvenance $PackageRoot
}
Copy-Item (Join-Path $ProjectRoot 'LICENSE') (Join-Path $PackageRoot 'LICENSES\game-lan-launcher-MIT.txt')
Copy-Item (Join-Path $ProjectRoot 'third_party\goldberg\LICENSE') (Join-Path $PackageRoot 'LICENSES\Goldberg-LGPL-3.0.txt')
Copy-Item (Join-Path $ProjectRoot 'third_party\goldberg\Readme_experimental.txt') (Join-Path $PackageRoot 'LICENSES\Goldberg-Readme.txt')
Copy-Item (Join-Path $ProjectRoot 'licenses\*') (Join-Path $PackageRoot 'LICENSES')
$ProtobufCopyright = Join-Path $ProjectRoot 'third_party\vcpkg\installed\x64-windows-static\share\protobuf\copyright'
if (-not (Test-Path $ProtobufCopyright -PathType Leaf)) {
    throw "Missing protobuf license installed by vcpkg: $ProtobufCopyright"
}
Copy-Item $ProtobufCopyright (Join-Path $PackageRoot 'LICENSES\Protobuf-BSD-3-Clause.txt')

$Utf8 = New-Object System.Text.UTF8Encoding($false)
$SetupMarker = Join-Path $PackageRoot 'steam_settings\player_setup_required.txt'
[IO.File]::WriteAllText(
    $SetupMarker,
    "Run the player setup CMD on each computer before launching.`r`n",
    $Utf8
)

$Manifest = Join-Path $PackageRoot 'SHA256SUMS.txt'
$Lines = Get-ChildItem $PackageRoot -Recurse -File |
    Where-Object { $_.FullName -ne $Manifest } |
    Sort-Object FullName |
    ForEach-Object {
        $Relative = $_.FullName.Substring($PackageRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $Hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $Relative"
    }
[IO.File]::WriteAllLines($Manifest, $Lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Clean package created at $PackageRoot"
Write-Host 'The package intentionally contains no SmartSteamEmu or OnlineFix files.'
Write-Host 'Copy all package files next to the configured game executable, then run configure-player.cmd.'
