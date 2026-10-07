param(
    [string]$GameRoot='F:\SteamLibrary\steamapps\common\OnimushaWotS',
    [int]$TimeoutSeconds=20
)
$ErrorActionPreference='Stop'
$data=Join-Path $GameRoot 'reframework\data'
$statusPath=Join-Path $data 'onimusha_reload_status.json'
if(-not (Test-Path -LiteralPath $statusPath)){throw 'Project reload loader is not active. Install it and load once before requesting reload.'}
$id=[Guid]::NewGuid().ToString('N')
$utf8=New-Object System.Text.UTF8Encoding($false)
$path=Join-Path $data 'onimusha_reload_control.json'
$temp=Join-Path $data ('onimusha_reload_control.'+$id+'.tmp')
$request=@{id=$id;action='reload'}|ConvertTo-Json -Compress
[IO.File]::WriteAllText($temp,$request,$utf8)
if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,($path+'.previous'))}else{[IO.File]::Move($temp,$path)}
$until=[DateTime]::UtcNow.AddSeconds([Math]::Min(60,[Math]::Max(1,$TimeoutSeconds)))
do {
    Start-Sleep -Milliseconds 250
    try {$s=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json} catch {continue}
    if($s.id -eq $id -and $s.phase -ne 'disabling_takeover'){
        $s|ConvertTo-Json -Depth 6
        if($s.phase -ne 'loaded'){throw ('Project reload failed: '+$s.phase+' '+$s.error)}
        return
    }
}while([DateTime]::UtcNow -lt $until)
throw ('No completion receipt yet for '+$id+'. Inspect status before sending another request; do not assume reload succeeded.')
