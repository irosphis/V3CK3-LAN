$ErrorActionPreference = 'Stop'
$Settings = Join-Path $PSScriptRoot 'steam_settings'
$Configure = Join-Path $PSScriptRoot 'configure-player.ps1'

Write-Host 'Game LAN player setup'
Write-Host '---------------------'
do {
    $PlayerName = Read-Host 'Player name (required)'
} while ([string]::IsNullOrWhiteSpace($PlayerName))

$SteamId = Read-Host 'SteamID64 (leave blank to generate a unique local ID)'
$PortText = Read-Host 'LAN UDP port (leave blank for 47584)'
$Compatibility = Read-Host 'Enable 25.x/26.x/100.x virtual-LAN compatibility? [y/N]'

$Arguments = @{
    Name = $PlayerName
    Destination = $Settings
    RegenerateSteamId = [string]::IsNullOrWhiteSpace($SteamId)
}
if (-not [string]::IsNullOrWhiteSpace($SteamId)) {
    $Arguments.SteamId = $SteamId
}
if (-not [string]::IsNullOrWhiteSpace($PortText)) {
    $Port = 0
    if (-not [int]::TryParse($PortText, [ref]$Port) -or $Port -lt 1024 -or $Port -gt 65535) {
        throw "Port must be an integer from 1024 through 65535: '$PortText'"
    }
    $Arguments.Port = $Port
}
if ($Compatibility -match '^(?i:y|yes)$') {
    $Arguments.AllowNonPrivateNetwork = $true
}

& $Configure @Arguments
Write-Host ''
Write-Host 'Setup complete. Run launch-game-lan.cmd to start the configured game.'
