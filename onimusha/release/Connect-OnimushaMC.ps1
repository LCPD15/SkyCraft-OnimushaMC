[CmdletBinding()]
param([switch]$WorkerOnly)
$ErrorActionPreference='Stop'
$packageRoot=$PSScriptRoot
. (Join-Path $packageRoot 'Package-Common.ps1')
$settings=Get-Content -LiteralPath (Join-Path $packageRoot 'settings.local.json') -Raw | ConvertFrom-Json
$taskHost=@(Get-Process OnimushaWotS -ErrorAction SilentlyContinue)
if ($taskHost.Count -ne 1) { throw 'Start OnimushaWotS and enter a playable scene first.' }
if ([IO.Path]::GetDirectoryName($taskHost[0].Path) -ne $settings.gameRoot) { throw 'Running game differs from configured game folder.' }
$hostProcessId=$taskHost[0].Id
$statusPath=Join-Path $settings.gameRoot 'reframework\data\onimusha_mc\native_models\worker.json'
$already=$false
if (Test-Path -LiteralPath $statusPath) {
    try {
        $status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $existing=Get-Process -Id $status.pid -ErrorAction SilentlyContinue
        $already=($status.host_pid -eq $hostProcessId -and $status.state -eq 'ready' -and $existing -and $existing.ProcessName -eq 'blender')
    } catch { $already=$false }
}
if (-not $already) {
    $worker=Join-Path $packageRoot 'worker\Native-Model-Worker.py'
    $addon=Join-Path $packageRoot 'third-party\RE-Mesh-Editor'
    $cache=Join-Path $packageRoot 'cache\native-models'
    $logs=Join-Path $packageRoot 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $argv=@('--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',('"'+$worker+'"'),'--','--game',('"'+$settings.gameRoot+'"'),'--out',('"'+$cache+'"'),'--host-pid',"$hostProcessId",'--addon',('"'+$addon+'"'))
    $process=Start-Process -FilePath $settings.blender -ArgumentList $argv -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs ($stamp+'.stdout.log')) -RedirectStandardError (Join-Path $logs ($stamp+'.stderr.log'))
    $ready=$false
    for ($i=0;$i -lt 80;$i++) {
        Start-Sleep -Milliseconds 250
        if ($process.HasExited) { throw "Converter exited; see $logs" }
        if (Test-Path -LiteralPath $statusPath) {
            try {
                $status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
                if ($status.pid -eq $process.Id -and $status.state -eq 'ready') { $ready=$true;break }
            } catch { }
        }
    }
    if (-not $ready) { throw "Converter did not become ready within 20 seconds; see $logs" }
}
Write-Output 'Native-lighting converter is ready. Its local cache is reused on later launches.'
if (-not $WorkerOnly) {
    if ($settings.prismLauncher) {
        $clients=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'onimusha\.worldName|skycraft-onimusha' })
        if ($clients.Count) { Write-Output 'An OnimushaMC client is already running; not launching another.' }
        else { Start-Process -FilePath $settings.prismLauncher -ArgumentList @('--launch',('"'+$settings.instance+'"')) | Out-Null }
    } else { Write-Output 'Now launch the imported OnimushaMC instance in Prism/PCL. Keep the Minecraft window open.' }
}
Write-Output 'After Minecraft connects and loads its mirror world, focus Onimusha and press F10 to take over. F10 again restores the original game.'
