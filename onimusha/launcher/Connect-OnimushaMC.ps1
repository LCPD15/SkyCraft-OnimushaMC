[CmdletBinding()]
param([string]$ProjectRoot = 'G:\Onimusha_MC_mod', [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$taskLauncher = Join-Path $ProjectRoot 'tools\MC-launch-dev.ps1'
$taskWorld = 'OnimushaMC-XYZ-v2'
$taskWorldPath = Join-Path $ProjectRoot "runtime\minecraft\.minecraft\saves\$taskWorld"
if (-not (Test-Path -LiteralPath $taskWorldPath)) { throw "Existing bridge world is missing: $taskWorldPath" }
if ($PrepareOnly) {
    & $taskLauncher -ProjectRoot $ProjectRoot -WorldName $taskWorld -ShowWindow -QuitWithHost -SwordBlocking -PrepareOnly
    return
}
$taskHosts = @(Get-Process OnimushaWotS -ErrorAction SilentlyContinue)
if ($taskHosts.Count -ne 1) { throw 'Start Onimusha and enter a playable scene, then run this shortcut again.' }
$taskPidFile = Join-Path $ProjectRoot 'runtime\minecraft\minecraft-dev.pid'
$taskAlreadyRunning = $false
if (Test-Path -LiteralPath $taskPidFile) {
    $taskMcId = [int](Get-Content -LiteralPath $taskPidFile -Raw).Trim()
    $taskMc = Get-CimInstance Win32_Process -Filter "ProcessId=$taskMcId" -ErrorAction SilentlyContinue
    $taskJava = Join-Path ((Get-Content -LiteralPath (Join-Path $ProjectRoot 'runtime\jdk-home.txt') -Raw).Trim()) 'bin\java.exe'
    $taskArgs = Join-Path $ProjectRoot 'runtime\minecraft\launch-dev.args'
    $taskAlreadyRunning = $taskMc -and $taskMc.ExecutablePath -eq $taskJava -and $taskMc.CommandLine -and
        $taskMc.CommandLine.IndexOf($taskArgs, [StringComparison]::OrdinalIgnoreCase) -ge 0
}
if ($taskAlreadyRunning) {
    & (Join-Path $ProjectRoot 'source\SkyCraft\onimusha\tools\Start-NativeModelWorker.ps1') -HostProcessId $taskHosts[0].Id
    Write-Host "Minecraft is already running (PID $taskMcId); reusing it."
} else {
    & $taskLauncher -ProjectRoot $ProjectRoot -WorldName $taskWorld -LogPrefix ('manual-'+(Get-Date -Format 'yyyyMMdd-HHmmss')) -ShowWindow -QuitWithHost -SwordBlocking
    $taskMcId = [int](Get-Content -LiteralPath $taskPidFile -Raw).Trim()
}
$taskStatus = 'F:\SteamLibrary\steamapps\common\OnimushaWotS\reframework\data\onimusha_mc_status.json'
$taskUntil = [DateTime]::UtcNow.AddSeconds(50)
do {
    try {
        $taskState = Get-Content -LiteralPath $taskStatus -Raw | ConvertFrom-Json
        $taskFresh = [DateTime]::UtcNow - (Get-Item -LiteralPath $taskStatus).LastWriteTimeUtc -lt [TimeSpan]::FromSeconds(10)
        if ($taskFresh -and $taskState.native.connected -and $taskState.native.mc_pid -eq $taskMcId -and $taskState.control_gate.valid_hp) {
            Write-Host 'Connected. Switch to Onimusha, close its pause menu, then press F10.'
            Write-Host 'T or /: Minecraft chat. E: inventory. F10 again: return to Onimusha.'
            return
        }
    } catch { }
    Start-Sleep -Milliseconds 500
} while ([DateTime]::UtcNow -lt $taskUntil)
Write-Host 'Minecraft is still starting or Onimusha is not in a playable scene. Keep both open; the bridge connects automatically.'
Write-Host ('Logs: '+(Join-Path $ProjectRoot 'logs'))
