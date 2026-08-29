[CmdletBinding()]
param(
    [string]$ReferenceDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'binaries')
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Lock = Get-Content (Join-Path $ProjectRoot 'SOURCE_LOCK.json') -Raw | ConvertFrom-Json
$ReferenceDirectory = [IO.Path]::GetFullPath($ReferenceDirectory)

$Expected = @{
    'steam_api64.dll' = $Lock.goldberg.reference_sha256.'experimental/steam_api64.dll'
    'steamclient64.dll' = $Lock.goldberg.reference_sha256.'experimental/steamclient64.dll'
}
foreach ($Entry in $Expected.GetEnumerator()) {
    $Path = Join-Path $ReferenceDirectory $Entry.Key
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Reference file is missing: $Path"
    }
    $Actual = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Actual -ne $Entry.Value) {
        throw "Reference hash mismatch for $($Entry.Key): expected $($Entry.Value), got $Actual"
    }
    Write-Host "matched Goldberg CI artifact: $($Entry.Key)  $Actual"
}

$JobFile = Join-Path $ReferenceDirectory 'job_id'
if (Test-Path $JobFile -PathType Leaf) {
    $Job = (Get-Content $JobFile -Raw).Trim()
    if ($Job -ne $Lock.goldberg.reference_ci_job.ToString()) {
        throw "Reference job_id mismatch: expected $($Lock.goldberg.reference_ci_job), got $Job"
    }
    Write-Host "matched Goldberg CI job: $Job"
}
