function Get-PackageHash([string]$Path) {
    $algorithm=[Security.Cryptography.SHA256]::Create()
    $stream=[IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','') }
    finally { $stream.Dispose();$algorithm.Dispose() }
}
function Get-SafeChild([string]$Root,[string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Expected a relative package path.' }
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes package directory.' }
    return $path
}
function Write-PackageJson([string]$Path,$Value) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    $temporary=$Path+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
