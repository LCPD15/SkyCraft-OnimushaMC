[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Onimusha_MC_mod',
    [string]$GameRoot = 'F:\SteamLibrary\steamapps\common\OnimushaWotS',
    [switch]$ProbeOnly,
    [switch]$IncludeExperimentalColliderAsset
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'OnimushaWotS.exe'))) {
    throw 'This installer targets OnimushaWotS only. The game executable was not found.'
}
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'dinput8.dll'))) {
    throw 'Install a compatible REFramework first; this script never replaces dinput8.dll.'
}
if (-not $ProbeOnly -and (Get-Process -Name OnimushaWotS -ErrorAction SilentlyContinue)) {
    throw 'Exit OnimushaWotS before replacing its bridge DLL.'
}
$taskRepo = Join-Path $ProjectRoot 'source\SkyCraft'
$taskEntries = @()
if ($ProbeOnly) {
    $taskEntries += @{Source=(Join-Path $taskRepo 'onimusha\adapter\onimusha_mc_probe.lua'); Relative='reframework\autorun\onimusha_mc_probe.lua'}
} else {
    $taskEntries += @{Source=(Join-Path $ProjectRoot 'build\native\Release\OnimushaMC.dll'); Relative='reframework\plugins\OnimushaMC.dll'}
    $taskEntries += @{Source=(Join-Path $taskRepo 'onimusha\adapter\onimusha_mc.lua'); Relative='reframework\autorun\onimusha_mc.lua'}
    if ($IncludeExperimentalColliderAsset) {
        $taskEntries += @{Source=(Join-Path $taskRepo 'onimusha\assets\natives\stm\mod\onimusha_mc\unit_box.rcol.37'); Relative='natives\stm\mod\onimusha_mc\unit_box.rcol.37'}
    }
    # Retain tuning preferences while returning the runtime to read-only stage A.
    $taskSafeConfig = Get-Content -LiteralPath (Join-Path $taskRepo 'onimusha\config\onimusha_mc_config.stage-A.json') -Raw | ConvertFrom-Json
    $taskExistingConfigPath = Join-Path $GameRoot 'reframework\data\onimusha_mc_config.json'
    if (Test-Path -LiteralPath $taskExistingConfigPath) {
        $taskExistingConfig = Get-Content -LiteralPath $taskExistingConfigPath -Raw | ConvertFrom-Json
        foreach ($taskPreference in $taskSafeConfig.PSObject.Properties) {
            if ($taskPreference.Name -in @('runtime_stage','enabled','diagnostic_only','install_control_hooks','enable_native_block_colliders','enable_block_collider_tests','enable_health_hook_tests','enable_terrain_queries')) { continue }
            $taskOldPreference = $taskExistingConfig.PSObject.Properties[$taskPreference.Name]
            if ($taskOldPreference) { $taskPreference.Value = $taskOldPreference.Value }
        }
    }
    # Identity XYZ basis: the tested native camera looks along local -Z.
    # Old reflection-basis angle tuning must not survive the coordinate migration.
    $taskSafeConfig.camera_yaw_sign = -1.0
    $taskSafeConfig.camera_yaw_offset = 180.0
    $taskSafeConfig.camera_pitch_sign = -1.0
    $taskSafeConfigPath = Join-Path $ProjectRoot 'runtime\installation-config.json'
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($taskSafeConfigPath)) -Force | Out-Null
    $taskSafeConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskSafeConfigPath -Encoding UTF8
    $taskEntries += @{Source=$taskSafeConfigPath; Relative='reframework\data\onimusha_mc_config.json'}
}
foreach ($taskEntry in $taskEntries) {
    if (-not (Test-Path -LiteralPath $taskEntry.Source -PathType Leaf)) { throw "Missing build/source: $($taskEntry.Source)" }
}
$taskManifestPath = Join-Path $ProjectRoot 'runtime\deployment.json'
$taskManifest = @{GameRoot=$GameRoot; Entries=@()}
if (Test-Path -LiteralPath $taskManifestPath) {
    $taskPrior = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
    if ($taskPrior.GameRoot -ne $GameRoot) { throw 'The deployment manifest belongs to a different game folder.' }
    $taskManifest.Entries = @($taskPrior.Entries)
}
foreach ($taskEntry in $taskEntries) {
    $taskTarget = Join-Path $GameRoot $taskEntry.Relative
    $taskRecord = $taskManifest.Entries | Where-Object { $_.Relative -eq $taskEntry.Relative } | Select-Object -First 1
    if (-not $taskRecord) {
        $taskBackup = $null
        if (Test-Path -LiteralPath $taskTarget) {
            $taskBackup = Join-Path $ProjectRoot ('runtime\deployment-backup\' + [Guid]::NewGuid().ToString() + '\' + [IO.Path]::GetFileName($taskTarget))
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($taskBackup)) -Force | Out-Null
            Copy-Item -LiteralPath $taskTarget -Destination $taskBackup
        }
        $taskRecord = [pscustomobject]@{Relative=$taskEntry.Relative; OriginalBackup=$taskBackup; InstalledSHA256=''}
        $taskManifest.Entries += $taskRecord
    }
    $taskHash = (Get-FileHash -LiteralPath $taskEntry.Source -Algorithm SHA256).Hash
    if (-not (Test-Path -LiteralPath $taskTarget) -or (Get-FileHash -LiteralPath $taskTarget -Algorithm SHA256).Hash -ne $taskHash) {
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($taskTarget)) -Force | Out-Null
        Copy-Item -LiteralPath $taskEntry.Source -Destination $taskTarget -Force
    }
    $taskRecord.InstalledSHA256 = $taskHash
    $taskManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskManifestPath -Encoding UTF8
}
[pscustomobject]@{
    Installed = $true
    Files = $taskEntries.Relative
    GameRunning = [bool](Get-Process -Name OnimushaWotS -ErrorAction SilentlyContinue)
    NextStep = if ($ProbeOnly) { 'Reset Scripts in REFramework, then enter a playable scene.' } else { 'Start the game in read-only stage A. Follow the staged validation record before enabling takeover.' }
    Manifest = $taskManifestPath
}
