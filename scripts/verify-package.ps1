[CmdletBinding()]
param(
    [string]$Package
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Package)) {
    $Package = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\game-lan'
}
$Package = [IO.Path]::GetFullPath($Package)
$Manifest = Join-Path $Package 'SHA256SUMS.txt'
if (-not (Test-Path $Manifest -PathType Leaf)) {
    throw "Missing manifest: $Manifest"
}

$Forbidden = @(
    'SmartSteamEmu.dll',
    'SmartSteamEmu64.dll',
    'SmartSteamLoader_x64.exe',
    'OnlineFix64.dll',
    'steam_api64.of',
    'DLC.txt',
    'force_DLC.txt',
    'force_language.txt',
    'disable_lan_only.txt'
)
foreach ($Name in $Forbidden) {
    if (Get-ChildItem $Package -Recurse -File -Filter $Name) {
        throw "Forbidden closed-source/backup file found in package: $Name"
    }
}

$ManifestEntries = @{}
foreach ($Line in Get-Content $Manifest) {
    if ($Line -notmatch '^([0-9a-f]{64})  (.+)$') {
        throw "Invalid manifest line: $Line"
    }
    $Expected = $Matches[1]
    $Relative = $Matches[2]
    if ($ManifestEntries.ContainsKey($Relative)) {
        throw "Duplicate manifest entry: $Relative"
    }
    $ManifestEntries[$Relative] = $Expected
    $Path = Join-Path $Package $Relative
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Manifest file missing: $Relative"
    }
    $Actual = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) {
        throw "Hash mismatch for $Relative"
    }
}

$AllowedRuntimeBinaries = @('game-lan-launcher.exe', 'steam_api64.dll', 'steamclient64.dll')
foreach ($File in Get-ChildItem $Package -Recurse -File) {
    $Relative = $File.FullName.Substring($Package.Length).TrimStart('\', '/').Replace('\', '/')
    if ($Relative -ne 'SHA256SUMS.txt' -and -not $ManifestEntries.ContainsKey($Relative)) {
        throw "File is not covered by the manifest: $Relative"
    }
    if (($File.Extension -eq '.dll' -or $File.Extension -eq '.exe') -and
        $AllowedRuntimeBinaries -notcontains $File.Name) {
        throw "Unexpected runtime binary: $Relative"
    }
}

$Ini = Join-Path $Package 'game-lan.ini'
if (-not (Test-Path $Ini -PathType Leaf)) {
    throw "Launcher configuration is missing: $Ini"
}
$InLauncherSection = $false
$ConfiguredAppId = $null
foreach ($Line in Get-Content -LiteralPath $Ini) {
    $Text = $Line.Trim()
    if ($Text -match '^\[([^]]+)\]$') {
        $InLauncherSection = $Matches[1] -ieq 'launcher'
        continue
    }
    if ($InLauncherSection -and $Text -match '^app_id\s*=\s*([0-9]+)\s*$') {
        $ConfiguredAppId = $Matches[1]
        break
    }
}
if ([string]::IsNullOrWhiteSpace($ConfiguredAppId)) {
    throw "Missing numeric [launcher] app_id in $Ini"
}
if ((Get-Content (Join-Path $Package 'steam_settings\steam_appid.txt') -Raw).Trim() -ne $ConfiguredAppId) {
    throw 'Packaged steam_appid.txt does not match game-lan.ini'
}
$RequiredPackageFiles = @(
    'configure-player.cmd',
    'launch-game-lan.cmd',
    'USAGE.zh-CN.txt',
    'README.md',
    'README.zh-CN.md',
    'game-lan.ini',
    'configure-player.ps1',
    'configure-interactive.ps1',
    'steam_settings\player_setup_required.txt'
)
foreach ($Relative in $RequiredPackageFiles) {
    if (-not (Test-Path (Join-Path $Package $Relative) -PathType Leaf)) {
        throw "Convenience package file is missing: $Relative"
    }
}
Write-Host "Package verified: $Package"
