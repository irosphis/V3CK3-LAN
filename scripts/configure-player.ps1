[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [string]$SteamId,

    [switch]$RegenerateSteamId,

    [switch]$AllowNonPrivateNetwork,

    [ValidateRange(1024, 65535)]
    [int]$Port = 47584,

    [string]$Config,

    [string]$Destination
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Config)) {
    $Config = Join-Path $PSScriptRoot 'game-lan.ini'
}

function Get-LauncherSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DefaultValue,
        [switch]$Required
    )

    $InLauncherSection = $false
    foreach ($Line in Get-Content -LiteralPath $Path) {
        $Text = $Line.Trim()
        if ($Text.Length -eq 0 -or $Text.StartsWith(';') -or $Text.StartsWith('#')) {
            continue
        }
        if ($Text -match '^\[([^]]+)\]$') {
            $InLauncherSection = $Matches[1] -ieq 'launcher'
            continue
        }
        if ($InLauncherSection -and $Text -match '^([^=]+)=(.*)$' -and
            $Matches[1].Trim() -ieq $Name) {
            return $Matches[2].Trim()
        }
    }

    if ($Required) {
        throw "Missing required [launcher] setting '$Name' in $Path"
    }
    return $DefaultValue
}

$Config = [IO.Path]::GetFullPath($Config)
if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    throw "Launcher configuration not found: $Config"
}

$AppIdText = Get-LauncherSetting -Path $Config -Name 'app_id' -Required
[UInt32]$AppId = 0
if (-not [UInt32]::TryParse($AppIdText, [ref]$AppId) -or $AppId -eq 0) {
    throw "[launcher] app_id must be an unsigned 32-bit decimal integer: '$AppIdText'"
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $ConfiguredSettings = Get-LauncherSetting `
        -Path $Config `
        -Name 'steam_settings' `
        -DefaultValue 'steam_settings'
    if ([IO.Path]::IsPathRooted($ConfiguredSettings)) {
        $Destination = $ConfiguredSettings
    }
    else {
        $Destination = Join-Path (Split-Path -Parent $Config) $ConfiguredSettings
    }
}
$Destination = [IO.Path]::GetFullPath($Destination)
$SetupMarker = Join-Path $Destination 'player_setup_required.txt'

if ($Name.Contains("`r") -or $Name.Contains("`n")) {
    throw 'Player name must be a single line'
}
$Utf8 = New-Object System.Text.UTF8Encoding($false)
if ($Utf8.GetByteCount($Name) -gt 31) {
    throw 'Player name must be at most 31 bytes when encoded as UTF-8'
}

[UInt64]$SteamIdValue = 0
$ExistingSteamId = Join-Path $Destination 'force_steamid.txt'
if ([string]::IsNullOrWhiteSpace($SteamId) -and -not $RegenerateSteamId -and
    -not (Test-Path $SetupMarker -PathType Leaf) -and
    (Test-Path $ExistingSteamId -PathType Leaf)) {
    $ExistingText = (Get-Content $ExistingSteamId -Raw).Trim()
    if ([UInt64]::TryParse($ExistingText, [ref]$SteamIdValue) -and
        $SteamIdValue -ge [UInt64]76561197960265729 -and
        $SteamIdValue -le [UInt64]76561202255233023) {
        $SteamId = $SteamIdValue.ToString()
    }
}

if ([string]::IsNullOrWhiteSpace($SteamId)) {
    $Bytes = New-Object byte[] 4
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        do {
            $Generator.GetBytes($Bytes)
            $AccountId = [BitConverter]::ToUInt32($Bytes, 0)
        } while ($AccountId -eq 0)
    }
    finally {
        $Generator.Dispose()
    }
    $SteamIdValue = [UInt64]76561197960265728 + [UInt64]$AccountId
}
else {
    if (-not [UInt64]::TryParse($SteamId, [ref]$SteamIdValue)) {
        throw "SteamId must be an unsigned decimal SteamID64: '$SteamId'"
    }
    if ($SteamIdValue -lt [UInt64]76561197960265729 -or
        $SteamIdValue -gt [UInt64]76561202255233023) {
        throw "SteamId is outside the individual-account SteamID64 range: '$SteamId'"
    }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Value)
    [IO.File]::WriteAllText($Path, "$Value`r`n", $Utf8)
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Write-Utf8NoBom (Join-Path $Destination 'steam_appid.txt') $AppId.ToString()
Write-Utf8NoBom (Join-Path $Destination 'force_account_name.txt') $Name
Write-Utf8NoBom (Join-Path $Destination 'force_steamid.txt') $SteamIdValue.ToString()
Write-Utf8NoBom (Join-Path $Destination 'force_listen_port.txt') $Port.ToString()
$ForcedLanguage = Join-Path $Destination 'force_language.txt'
if (Test-Path -LiteralPath $ForcedLanguage -PathType Leaf) {
    Remove-Item -LiteralPath $ForcedLanguage -Force
}
$LanOnlyOverride = Join-Path $Destination 'disable_lan_only.txt'
if ($AllowNonPrivateNetwork) {
    Write-Utf8NoBom $LanOnlyOverride 'enabled by player configuration'
}
elseif (Test-Path $LanOnlyOverride -PathType Leaf) {
    Remove-Item -Force $LanOnlyOverride
}
if (Test-Path $SetupMarker -PathType Leaf) {
    Remove-Item -Force $SetupMarker
}

Write-Host "Player configuration written to $Destination"
Write-Host "App ID: $AppId"
Write-Host "Name: $Name"
Write-Host "SteamID64: $SteamIdValue"
Write-Host "UDP listen port: $Port"
Write-Host "Virtual-LAN compatibility: $($AllowNonPrivateNetwork.IsPresent)"
