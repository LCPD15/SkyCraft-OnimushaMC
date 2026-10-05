[CmdletBinding()]
param([string]$ProjectRoot = 'G:\Onimusha_MC_mod')
$ErrorActionPreference = 'Stop'
$taskManifestPath = Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) 'runtime\deployment.json'
if (-not (Test-Path -LiteralPath $taskManifestPath)) { throw 'No deployment manifest was found.' }
$taskManifest = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
$taskPreserved = @()
foreach ($taskEntry in $taskManifest.Entries) {
    $taskGameRoot = [IO.Path]::GetFullPath($taskManifest.GameRoot).TrimEnd('\')
    $taskTarget = [IO.Path]::GetFullPath((Join-Path $taskGameRoot $taskEntry.Relative))
    if (-not $taskTarget.StartsWith($taskGameRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment entry escapes the recorded game directory.'
    }
    if (-not (Test-Path -LiteralPath $taskTarget)) { continue }
    if ((Get-FileHash -LiteralPath $taskTarget -Algorithm SHA256).Hash -ne $taskEntry.InstalledSHA256) {
        $taskPreserved += $taskTarget
        continue
    }
    if ($taskEntry.OriginalBackup) {
        if (-not (Test-Path -LiteralPath $taskEntry.OriginalBackup)) { throw "Missing original backup: $($taskEntry.OriginalBackup)" }
        Copy-Item -LiteralPath $taskEntry.OriginalBackup -Destination $taskTarget -Force
    } else {
        Remove-Item -LiteralPath $taskTarget
    }
}
[pscustomobject]@{Restored=$true; ModifiedFilesPreserved=$taskPreserved; RestartGame=$true; Manifest=$taskManifestPath}
