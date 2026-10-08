[CmdletBinding()]
param([int]$HostProcessId=0)
$ErrorActionPreference='Stop'
$taskGame='F:\SteamLibrary\steamapps\common\OnimushaWotS'
if (-not $HostProcessId) {
    $taskHost=Get-Process OnimushaWotS -ErrorAction Stop
    if (@($taskHost).Count -ne 1) { throw 'Expected one Onimusha process' }
    $HostProcessId=$taskHost.Id
}
$taskStatus=Join-Path $taskGame 'reframework\data\onimusha_mc\native_models\worker.json'
if (Test-Path -LiteralPath $taskStatus) {
    $taskOld=Get-Content -LiteralPath $taskStatus -Raw | ConvertFrom-Json
    if ($taskOld.host_pid -eq $HostProcessId -and $taskOld.state -eq 'ready' -and (Get-Process -Id $taskOld.pid -ErrorAction SilentlyContinue)) {
        Write-Output "Worker already running: $($taskOld.pid)";return
    }
}
$taskStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$taskArgs=@('--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',
    ('"'+(Join-Path $PSScriptRoot 'Native-Model-Worker.py')+'"'),'--','--game',('"'+$taskGame+'"'),
    '--out','"G:\Onimusha_MC_mod\assets\native-models\live"','--host-pid',"$HostProcessId",'--addon',
    '"C:\Users\LCPD15\AppData\Roaming\Blender Foundation\Blender\5.2\scripts\addons\RE-Mesh-Editor-main"')
$taskProc=Start-Process 'D:\SteamLibrary\steamapps\common\Blender\blender.exe' -ArgumentList $taskArgs -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput "G:\Onimusha_MC_mod\logs\native-models-$taskStamp.stdout.log" `
    -RedirectStandardError "G:\Onimusha_MC_mod\logs\native-models-$taskStamp.stderr.log"
Write-Output "Native model worker PID $($taskProc.Id), host $HostProcessId"
