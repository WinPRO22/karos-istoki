param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../ServerEmulator'))
$runs = Join-Path $project 'artifacts/runs'
$statePath = Join-Path $runs 'active.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { Write-Output 'No Berneo run is recorded.'; return }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$hostExe = Join-Path $project 'Win64/Tools/B1008TestHost.exe'
$run = [IO.Path]::GetFullPath($state.RunDirectory)
if ($state.Schema -ne 1 -or $state.HostExecutable -ne $hostExe -or
    -not $run.StartsWith($runs + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unexpected run state.'
}
function Get-OwnedProcess([int]$ProcessId, [string]$Executable, [string]$StartedUTC) {
    if ($ProcessId -le 0) { return $null }
    $item = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($item -and $item.Path -eq $Executable -and
        $item.StartTime.ToUniversalTime().ToString('o') -eq $StartedUTC) { return $item }
    return $null
}
$game = Get-OwnedProcess $state.ClientPid $state.ClientExecutable $state.ClientStartedUTC
if ($game) {
    $null = $game.CloseMainWindow()
    if (-not $game.WaitForExit(10000)) { throw 'The game is still open. Close its window and run Stop-Berneo.ps1 again.' }
}
$serverProcess = Get-OwnedProcess $state.HostPid $hostExe $state.HostStartedUTC
if ($serverProcess) {
    [IO.File]::WriteAllText((Join-Path $run 'stop.request'), '')
    if (-not $serverProcess.WaitForExit(15000)) { throw 'The server has not finished its graceful stop. Inspect the server log.' }
}
Remove-Item -LiteralPath $statePath
Write-Output 'Berneo client and server stopped; character progress is preserved.'
