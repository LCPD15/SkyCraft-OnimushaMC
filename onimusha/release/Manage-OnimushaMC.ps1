[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Configure')][string]$Action='Install',
    [string]$GameRoot,
    [string]$Blender,
    [string]$PrismLauncher,
    [string]$Instance='OnimushaMC'
)
$ErrorActionPreference='Stop'
$packageRoot=$PSScriptRoot
. (Join-Path $packageRoot 'Package-Common.ps1')
if (-not $GameRoot) { $GameRoot=Read-Host 'OnimushaWotS game folder (contains OnimushaWotS.exe)' }
$GameRoot=[IO.Path]::GetFullPath($GameRoot.Trim('"')).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'OnimushaWotS.exe'))) { throw 'OnimushaWotS.exe not found.' }
$receiptPath=Join-Path $GameRoot 'reframework\data\onimusha_mc\package-install\receipt.json'
$backupRoot=Split-Path $receiptPath
if ($Action -eq 'Configure' -or $Action -eq 'Install') {
    if (-not $Blender) { $Blender=Read-Host 'Blender 5.2 blender.exe full path' }
    $Blender=[IO.Path]::GetFullPath($Blender.Trim('"'))
    if (-not (Test-Path -LiteralPath $Blender -PathType Leaf)) { throw 'blender.exe not found.' }
    if ([IO.Path]::GetFileName($Blender) -ne 'blender.exe') { throw 'Select blender.exe.' }
    if ($PrismLauncher) {
        $PrismLauncher=[IO.Path]::GetFullPath($PrismLauncher.Trim('"'))
        if (-not (Test-Path -LiteralPath $PrismLauncher)) { throw 'PrismLauncher executable missing.' }
    }
}
if ($Action -ne 'Configure') {
    if (Get-Process OnimushaWotS -ErrorAction SilentlyContinue) { throw 'Exit Onimusha before installing/uninstalling.' }
    if ($Action -eq 'Install') {
        if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'dinput8.dll'))) { throw 'Install REFramework for OnimushaWotS first (dinput8.dll is missing).' }
        $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'package-manifest.json') -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.files) {
            $file=Get-SafeChild $packageRoot $entry.path
            if (-not (Test-Path -LiteralPath $file) -or (Get-PackageHash $file) -ne $entry.sha256) { throw "Package checksum mismatch: $($entry.path)" }
        }
        $installed=@{}
        if (Test-Path -LiteralPath $receiptPath) {
            $old=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            foreach ($entry in $old.files) { $installed[$entry.path]=$entry }
        }
        $transaction=Join-Path $backupRoot ('transactions\'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        $changed=[Collections.Generic.List[object]]::new()
        try {
            # These older project payloads must never run beside the single loader.
            $legacy=@('onimusha_mc','onimusha_enemy_hit','onimusha_guard_probe','onimusha_combat_inventory','onimusha_native_blocks','onimusha_native_models','onimusha_soul','onimusha_npc_damage','onimusha_native_sections','onimusha_native_instances')
            $operations=@($manifest.files | Where-Object { $_.path.StartsWith('game/') } | ForEach-Object {
                [pscustomobject]@{path=$_.path.Substring(5);source=(Get-SafeChild $packageRoot $_.path);remove=$false}
            })
            foreach ($name in $legacy) {
                $rel="reframework/autorun/$name.lua"
                if (Test-Path -LiteralPath (Get-SafeChild $GameRoot $rel)) { $operations+= [pscustomobject]@{path=$rel;source=$null;remove=$true} }
            }
            foreach ($op in $operations) {
                $dest=Get-SafeChild $GameRoot $op.path
                # Preserve settings from earlier *public* installations; first import uses verified release defaults.
                if ($installed.ContainsKey($op.path) -and $op.path.EndsWith('.json') -and (Test-Path -LiteralPath $dest)) { continue }
                $had=Test-Path -LiteralPath $dest
                $save=Join-Path $transaction ($changed.Count.ToString()+'.bin')
                if ($had) { Copy-Item -LiteralPath $dest -Destination $save }
                $changed.Add([pscustomobject]@{path=$dest;had=$had;save=$save})
                if (-not $installed.ContainsKey($op.path)) {
                    $original=$null
                    if ($had) {
                        $original='original/'+[guid]::NewGuid().ToString('N')+'.bin'
                        $originalPath=Get-SafeChild $backupRoot $original
                        New-Item -ItemType Directory -Path (Split-Path $originalPath) -Force | Out-Null
                        Copy-Item -LiteralPath $dest -Destination $originalPath
                    }
                    $installed[$op.path]=[pscustomobject]@{path=$op.path;original=$original;sha256=$null}
                }
                if ($op.remove) { Remove-Item -LiteralPath $dest; $installed[$op.path].sha256=$null }
                else {
                    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
                    Copy-Item -LiteralPath $op.source -Destination $dest -Force
                    $digest=Get-PackageHash $dest
                    if ($digest -ne (Get-PackageHash $op.source)) { throw "Installed checksum mismatch: $($op.path)" }
                    $installed[$op.path].sha256=$digest
                }
            }
            Write-PackageJson $receiptPath @{version=$manifest.version;files=@($installed.Values)}
        } catch {
            for ($i=$changed.Count-1;$i -ge 0;$i--) {
                $item=$changed[$i]
                if ($item.had) { Copy-Item -LiteralPath $item.save -Destination $item.path -Force }
                elseif (Test-Path -LiteralPath $item.path) { Remove-Item -LiteralPath $item.path }
            }
            throw
        }
        Write-Output "Installed $($manifest.version). Backups: $backupRoot"
    } else {
        if (-not (Test-Path -LiteralPath $receiptPath)) { throw 'No installation receipt; no files were removed.' }
        $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach ($entry in $receipt.files) {
            $dest=Get-SafeChild $GameRoot $entry.path
            if (Test-Path -LiteralPath $dest) {
                # Keep any subsequently edited file before removing/restoring this mod's file.
                $saved=Get-SafeChild $backupRoot ('uninstall-kept/'+$entry.path)
                New-Item -ItemType Directory -Path (Split-Path $saved) -Force | Out-Null
                Copy-Item -LiteralPath $dest -Destination $saved -Force
            }
            if ($entry.original) { Copy-Item -LiteralPath (Get-SafeChild $backupRoot $entry.original) -Destination $dest -Force }
            elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest }
        }
        Move-Item -LiteralPath $receiptPath -Destination ($receiptPath+'.uninstalled-'+[guid]::NewGuid().ToString('N'))
        Write-Output 'Removed package files and restored pre-install files. Saves, cache, REFramework and other mods were kept.'
    }
}
if ($Action -eq 'Configure' -or $Action -eq 'Install') {
    Write-PackageJson (Join-Path $packageRoot 'settings.local.json') @{gameRoot=$GameRoot;blender=$Blender;prismLauncher=$PrismLauncher;instance=$Instance}
    Write-Output 'Configuration saved. Import Minecraft-instance.zip into Prism once, then start the game and run Connect-OnimushaMC.cmd.'
}
