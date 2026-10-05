[CmdletBinding()]
param([string]$ProjectRoot = 'G:\Onimusha_MC_mod', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$taskRepo = Join-Path $ProjectRoot 'source\SkyCraft'
$taskJavaHome = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'runtime\jdk-home.txt') -Raw).Trim()
$env:JAVA_HOME = $taskJavaHome
$env:GRADLE_USER_HOME = Join-Path $ProjectRoot 'build\gradle-cache'
$taskVswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$taskVS = & $taskVswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $taskVS) { throw 'Visual Studio C++ x64 build tools are required.' }
$taskCMake = Join-Path $taskVS 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $taskCMake)) { throw 'CMake was not found in Visual Studio.' }
Push-Location (Join-Path $taskRepo 'fabric')
try {
    $taskGradleArgs = @('build', '--no-daemon')
    if ($SkipTests) { $taskGradleArgs += @('-x','test') }
    & '.\gradlew.bat' @taskGradleArgs
    if ($LASTEXITCODE -ne 0) { throw 'Fabric build failed.' }
} finally { Pop-Location }
& $taskCMake -S (Join-Path $taskRepo 'onimusha') -B (Join-Path $ProjectRoot 'build\native') -A x64
if ($LASTEXITCODE -ne 0) { throw 'Native configure failed.' }
& $taskCMake --build (Join-Path $ProjectRoot 'build\native') --config Release
if ($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
if (-not $SkipTests) {
    $taskCTest = Join-Path ([IO.Path]::GetDirectoryName($taskCMake)) 'ctest.exe'
    & $taskCTest --test-dir (Join-Path $ProjectRoot 'build\native') -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Native tests failed.' }
}
