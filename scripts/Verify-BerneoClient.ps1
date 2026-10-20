param(
    [Parameter(Mandatory)][string]$ClientDirectory,
    [switch]$AllowRuntimeFiles
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath($ClientDirectory).TrimEnd('\', '/')

function Get-SHA256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Assert-PlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Redirected path: $cursor" }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Get-ClientPath([string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains(':') -or $Relative -match '(^|[\\/])\.\.?([\\/]|$)') {
        throw 'Unsafe manifest path.'
    }
    $full = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes client.' }
    Assert-PlainPath $full
    return $full
}

Assert-PlainPath $root
$manifestPath = Get-ClientPath 'BERNEO-CLIENT-MANIFEST.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$exeHash = '312d1e3465e4a0e4b42fdebd30d000998bd3647307da90d1dd1164b6f29ab927'
if ($manifest.Schema -ne 1 -or $manifest.Endpoint -cne '127.0.0.1:10001' -or
    $manifest.ExeSHA256 -cne $exeHash -or $manifest.Files.Count -eq 0) { throw 'Unexpected Berneo client manifest.' }
$allowed = @{ 'BERNEO-CLIENT-MANIFEST.json' = $true }
foreach ($entry in $manifest.Files) {
    $relative = $entry.Path.Replace('/', '\')
    if ($allowed.ContainsKey($relative)) { throw "Duplicate manifest path: $relative" }
    $allowed[$relative] = $true
    $path = Get-ClientPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing client file: $relative" }
    # The native client can save volume settings to this original text file.
    if ($AllowRuntimeFiles -and $relative -ceq 'Karos.ini') { continue }
    if ((Get-Item -LiteralPath $path).Length -ne $entry.Size -or
        (Get-SHA256 $path) -ne $entry.SHA256) {
        throw "Client hash/size mismatch: $relative"
    }
}
foreach ($required in @('AMo.exe', 'ServerList.ten', 'LOCAL-CLIENT-MANIFEST.json')) {
    if (-not $allowed.ContainsKey($required)) { throw "Manifest omits required file: $required" }
}
if ((Get-SHA256 (Get-ClientPath 'AMo.exe')) -ne $exeHash) {
    throw 'Executable must match the exact Berneo v16 release.'
}
$ten = [IO.File]::ReadAllBytes((Get-ClientPath 'ServerList.ten'))
if ([BitConverter]::ToString($ten) -cne '73-A5-DC-0A-3A-68-98-C6-F7-04-0E-3F-6F-9F-CF-00-0D-17') {
    throw 'Client endpoint must be exactly 127.0.0.1:10001.'
}
foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -Force) {
    Assert-PlainPath $item.FullName
    if ($item.PSIsContainer) { continue }
    $relative = $item.FullName.Substring($root.Length + 1)
    if ($allowed.ContainsKey($relative)) { continue }
    $generated = $relative -ceq 'b1008-ui.ini' -or
        $relative -match '\AWeber_log\\[0-9]{4}_[0-9]{2}_[0-9]{2}\.txt\z' -or
        $relative -match '\Ashot\\[^\\]+\.(bmp|jpg|jpeg|png)\z'
    if (-not ($AllowRuntimeFiles -and $generated)) { throw "Unexpected client file: $relative" }
}
Write-Output "PASS: $($manifest.Files.Count) Berneo client payload files; endpoint 127.0.0.1:10001."
if ($AllowRuntimeFiles) { Write-Output 'Runtime mode: local volume/UI preferences, dated text logs and screenshots are not distribution-verified.' }
