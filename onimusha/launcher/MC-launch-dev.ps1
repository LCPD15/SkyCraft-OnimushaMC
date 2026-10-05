[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [ValidatePattern('^[A-Za-z0-9_]{1,16}$')][string]$Username = 'LCPD15',
    [string]$MappingName = 'Local\OnimushaMC_v1',
    [ValidatePattern('^[A-Za-z0-9_-]{1,80}$')][string]$WorldName = 'OnimushaMC',
    [ValidatePattern('^[A-Za-z0-9_-]{1,80}$')][string]$LogPrefix = 'minecraft-dev',
    [switch]$ShowWindow,
    [switch]$StartHidden,
    [switch]$QuitWithHost,
    [switch]$PrepareOnly,
    [switch]$Wait
)
$ErrorActionPreference = 'Stop'
if ($MappingName -eq 'Local\OnimushaMC_Smoke' -and -not $PSBoundParameters.ContainsKey('WorldName')) {
    $WorldName = 'OnimushaMC-Smoke'
}

# A Fabric developer profile, not a replacement for Microsoft authentication or online play.
# Production users should launch the isolated profile through PCL and sign in there themselves.
if (-not $ProjectRoot) {
    $taskCandidate = [IO.DirectoryInfo]$PSScriptRoot
    while ($taskCandidate -and -not (Test-Path -LiteralPath (Join-Path $taskCandidate.FullName 'runtime\jdk-home.txt'))) {
        $taskCandidate = $taskCandidate.Parent
    }
    if (-not $taskCandidate) { throw 'Pass -ProjectRoot pointing to the Onimusha_MC_mod folder.' }
    $ProjectRoot = $taskCandidate.FullName
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$taskGameRoot = Join-Path $ProjectRoot 'runtime\minecraft\.minecraft'
$taskLibraries = Join-Path $taskGameRoot 'libraries'
$taskNatives = Join-Path $taskGameRoot 'natives\26.3'
$taskJdkHome = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'runtime\jdk-home.txt') -Raw).Trim()
$taskJava = Join-Path $taskJdkHome 'bin\java.exe'
$taskBasePath = Join-Path $taskGameRoot 'versions\26.3\26.3.json'
$taskLoaderPath = Join-Path $taskGameRoot 'versions\OnimushaMC-26.3-Fabric-0.19.5\OnimushaMC-26.3-Fabric-0.19.5.json'
$taskBase = Get-Content -LiteralPath $taskBasePath -Raw | ConvertFrom-Json
$taskLoader = Get-Content -LiteralPath $taskLoaderPath -Raw | ConvertFrom-Json

function Test-WindowsLibrary($taskLibrary) {
    if ($taskLibrary.name -match ':natives-' -and $taskLibrary.name -notmatch ':natives-windows$') { return $false }
    if (-not $taskLibrary.rules) { return $true }
    $taskAllowed = $false
    foreach ($taskRule in $taskLibrary.rules) {
        $taskMatches = $true
        if ($taskRule.os.name -and $taskRule.os.name -ne 'windows') { $taskMatches = $false }
        if ($taskRule.os.arch -and $taskRule.os.arch -notin @('x86_64', 'amd64')) { $taskMatches = $false }
        if ($taskRule.features) { $taskMatches = $false }
        if ($taskMatches) { $taskAllowed = $taskRule.action -eq 'allow' }
    }
    return $taskAllowed
}
function Get-MavenPath([string]$taskName) {
    $taskParts = $taskName.Split(':')
    $taskSuffix = if ($taskParts.Count -gt 3) { '-' + $taskParts[3] } else { '' }
    return $taskParts[0].Replace('.', '/') + '/' + $taskParts[1] + '/' + $taskParts[2] + '/' + $taskParts[1] + '-' + $taskParts[2] + $taskSuffix + '.jar'
}

$taskClasspath = [Collections.Generic.List[string]]::new()
$taskSeen = [Collections.Generic.HashSet[string]]::new()
foreach ($taskLibrary in @($taskLoader.libraries) + @($taskBase.libraries)) {
    if (-not (Test-WindowsLibrary $taskLibrary)) { continue }
    $taskRelative = if ($taskLibrary.downloads.artifact.path) { $taskLibrary.downloads.artifact.path } else { Get-MavenPath $taskLibrary.name }
    $taskFile = Join-Path $taskLibraries $taskRelative
    if (-not (Test-Path -LiteralPath $taskFile)) { throw "Missing library: $taskFile" }
    $taskIdentity = ($taskLibrary.name.Split(':') | Select-Object -First 2) -join ':'
    if ($taskLibrary.name.Split(':').Count -gt 3) { $taskIdentity += ':' + $taskLibrary.name.Split(':')[3] }
    if ($taskSeen.Add($taskIdentity)) { $taskClasspath.Add($taskFile) }
}
$taskClient = Join-Path $taskGameRoot 'versions\26.3\26.3.jar'
$taskClasspath.Add($taskClient)
foreach ($taskFile in @($taskJava, $taskClient, (Join-Path $taskGameRoot 'assets\indexes\34.json'),
    (Join-Path $taskGameRoot 'mods\skycraft-onimusha-0.1.0-dev.jar'),
    (Join-Path $taskGameRoot 'mods\fabric-api-0.161.0+26.3.jar'))) {
    if (-not (Test-Path -LiteralPath $taskFile)) { throw "Missing runtime file: $taskFile" }
}

# The same stable UUID calculation Minecraft uses for an offline development player.
$taskMd5 = [Security.Cryptography.MD5]::Create()
try { $taskUuidBytes = $taskMd5.ComputeHash([Text.Encoding]::UTF8.GetBytes('OfflinePlayer:' + $Username)) }
finally { $taskMd5.Dispose() }
$taskUuidBytes[6] = ($taskUuidBytes[6] -band 0x0F) -bor 0x30
$taskUuidBytes[8] = ($taskUuidBytes[8] -band 0x3F) -bor 0x80
$taskUuid = ([BitConverter]::ToString($taskUuidBytes)).Replace('-', '').ToLowerInvariant()
$taskAssets = Join-Path $taskGameRoot 'assets'
$taskArgs = @(
    '-Xms512M', '-Xmx4G', '--enable-native-access=ALL-UNNAMED',
    '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED', '-XX:StackShadowPages=32',
    "-Djava.library.path=$taskNatives", "-Dorg.lwjgl.librarypath=$taskNatives",
    "-Djna.tmpdir=$taskNatives\jna", "-Dorg.lwjgl.system.SharedLibraryExtractPath=$taskNatives\lwjgl",
    "-Dio.netty.native.workdir=$taskNatives\netty", '-Dminecraft.launcher.brand=OnimushaMC-Dev',
    '-Dminecraft.launcher.version=0.1.0-dev', ('-Dskycraft.quitWithSkyrim=' + $QuitWithHost.IsPresent.ToString().ToLowerInvariant()),
    "-Donimusha.link=$MappingName", "-Donimusha.worldName=$WorldName", '-Donimusha.unitsPerBlock=1.0',
    '-cp', ($taskClasspath -join ';'), 'net.fabricmc.loader.impl.launch.knot.KnotClient',
    '--username', $Username, '--version', 'OnimushaMC-26.3-Fabric-0.19.5',
    '--gameDir', $taskGameRoot, '--assetsDir', $taskAssets, '--assetIndex', '34',
    '--uuid', $taskUuid, '--accessToken', '0', '--clientId', '0', '--xuid', '0',
    '--versionType', 'OnimushaMC development', '--width', '1280', '--height', '720'
)
$taskArgs = @($taskLoader.arguments.jvm | Where-Object { $_ -is [string] -and $_.StartsWith('-DFabricMcEmu=') }) + $taskArgs
if ($ShowWindow) { $taskArgs = @('-Dskycraft.showWindow=true') + $taskArgs }
if ($StartHidden) { $taskArgs = @('-Dskycraft.startHidden=true') + $taskArgs }
function ConvertTo-JavaArgfileToken([string]$taskValue) {
    # Java argfiles have their own escaping; never use shell interpolation for these arguments.
    return '"' + $taskValue.Replace('\', '\\').Replace('"', '\"') + '"'
}
$taskArgfile = Join-Path $ProjectRoot 'runtime\minecraft\launch-dev.args'
$taskTokens = $taskArgs | ForEach-Object { ConvertTo-JavaArgfileToken $_ }
[IO.File]::WriteAllLines($taskArgfile, $taskTokens, [Text.UTF8Encoding]::new($false))
$taskLogRoot = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Path $taskLogRoot -Force | Out-Null
if ($PrepareOnly) {
    [pscustomobject]@{ Prepared = $true; Argfile = $taskArgfile; Java = $taskJava; GameDirectory = $taskGameRoot; WorldName = $WorldName; ClasspathEntries = $taskClasspath.Count; Authentication = 'Developer profile only; no account credentials' }
    return
}
$taskExistingPidFile = Join-Path $ProjectRoot 'runtime\minecraft\minecraft-dev.pid'
if (Test-Path -LiteralPath $taskExistingPidFile) {
    $taskOldPid = [int](Get-Content -LiteralPath $taskExistingPidFile -Raw).Trim()
    if (Get-Process -Id $taskOldPid -ErrorAction SilentlyContinue) { throw "Developer Minecraft already running (PID $taskOldPid)." }
}
$taskProcess = Start-Process -FilePath $taskJava -ArgumentList ('@' + $taskArgfile) -WorkingDirectory $taskGameRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $taskLogRoot "$LogPrefix.stdout.log") -RedirectStandardError (Join-Path $taskLogRoot "$LogPrefix.stderr.log")
Set-Content -LiteralPath $taskExistingPidFile -Value $taskProcess.Id -Encoding ascii
[pscustomobject]@{ Started = $true; PID = $taskProcess.Id; GameDirectory = $taskGameRoot; WorldName = $WorldName; Authentication = 'Developer profile only' }
if ($Wait) { $taskProcess.WaitForExit(); exit $taskProcess.ExitCode }
