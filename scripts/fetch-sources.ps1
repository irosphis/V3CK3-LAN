[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Lock = Get-Content (Join-Path $ProjectRoot 'SOURCE_LOCK.json') -Raw | ConvertFrom-Json
$ThirdParty = Join-Path $ProjectRoot 'third_party'

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }
}

function Sync-PinnedRepository {
    param(
        [string]$Name,
        [string]$Repository,
        [string]$Commit
    )

    $Destination = Join-Path $ThirdParty $Name
    if (-not (Test-Path (Join-Path $Destination '.git'))) {
        if (Test-Path $Destination) {
            throw "$Destination exists but is not a Git checkout"
        }
        Invoke-Git clone --filter=blob:none $Repository $Destination
    }

    $Origin = (& git -C $Destination remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $Origin -ne $Repository) {
        throw "$Name origin mismatch. Expected '$Repository', got '$Origin'"
    }

    $Dirty = & git -C $Destination status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect $Name checkout"
    }
    if ($Dirty -and -not $Force) {
        throw "$Destination has local changes. Re-run with -Force only after reviewing them."
    }

    Invoke-Git -C $Destination fetch --no-tags --depth 1 origin $Commit
    Invoke-Git -C $Destination checkout --detach --force $Commit

    $Resolved = (& git -C $Destination rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $Resolved -ne $Commit) {
        throw "$Name resolved to '$Resolved', expected '$Commit'"
    }
    Write-Host "$Name pinned at $Resolved"
}

New-Item -ItemType Directory -Force -Path $ThirdParty | Out-Null
Sync-PinnedRepository -Name 'goldberg' -Repository $Lock.goldberg.repository -Commit $Lock.goldberg.commit
Sync-PinnedRepository -Name 'vcpkg' -Repository $Lock.vcpkg.repository -Commit $Lock.vcpkg.commit
