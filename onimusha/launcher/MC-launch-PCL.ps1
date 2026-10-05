[CmdletBinding()]
param([string]$ProjectRoot = '', [switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $taskCandidate = [IO.DirectoryInfo]$PSScriptRoot
    while ($taskCandidate -and -not (Test-Path -LiteralPath (Join-Path $taskCandidate.FullName 'runtime\jdk-home.txt'))) { $taskCandidate = $taskCandidate.Parent }
    if (-not $taskCandidate) { throw 'Pass -ProjectRoot pointing to the Onimusha_MC_mod folder.' }
    $ProjectRoot = $taskCandidate.FullName
}
$taskLauncher = Join-Path $ProjectRoot 'runtime\minecraft\Plain Craft Launcher 2.exe'
$taskJava = Join-Path ((Get-Content -LiteralPath (Join-Path $ProjectRoot 'runtime\jdk-home.txt') -Raw).Trim()) 'bin\javaw.exe'
if (-not (Test-Path -LiteralPath $taskLauncher)) { throw 'Isolated PCL EXE is missing.' }
$taskProfile = 'OnimushaMC-26.3-Fabric-0.19.5'
if ($PrepareOnly) {
    [pscustomobject]@{ Launcher = $taskLauncher; Profile = $taskProfile; Java = $taskJava; Login = 'Sign in to your own Microsoft account inside this isolated PCL. Existing PCL account files are not copied.' }
    return
}
# PCL source exposes no verified general launch/profile CLI. Open its supported UI instead.
# A global PCL singleton may bring an already-running launcher to the front; close it first.
Start-Process -FilePath $taskLauncher -WorkingDirectory (Split-Path -Parent $taskLauncher) -WindowStyle Normal
Write-Output "In isolated PCL: select $taskProfile, choose Java 25 at $taskJava, sign in with your Microsoft account, then launch."
