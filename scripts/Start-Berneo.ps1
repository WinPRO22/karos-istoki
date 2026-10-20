param([Parameter(Mandatory)][string]$ClientDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../ServerEmulator'))
$hostExe = Join-Path $project 'Win64/Tools/B1008TestHost.exe'
$client = [IO.Path]::GetFullPath($ClientDirectory).TrimEnd('\', '/')
if ($client.Contains('"')) { throw 'Invalid client directory.' }
if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf)) { throw 'Build the exported TestHost program or unpack the emulator ZIP first.' }
& (Join-Path $PSScriptRoot 'Verify-BerneoClient.ps1') -ClientDirectory $client -AllowRuntimeFiles
$runs = Join-Path $project 'artifacts/runs'
$statePath = Join-Path $runs 'active.json'
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $existing = Get-Process -Id $previous.HostPid -ErrorAction SilentlyContinue
    if ($existing -and $existing.Path -eq $hostExe -and
        $existing.StartTime.ToUniversalTime().ToString('o') -eq $previous.HostStartedUTC) {
        throw 'This Berneo server is already running. Use Stop-Berneo.ps1 first.'
    }
}
$run = Join-Path $runs ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$arguments = '"' + $run + '" --player-speed=1 "--client-dir=' + $client + '"'
$serverProcess = Start-Process -FilePath $hostExe -ArgumentList $arguments -WorkingDirectory $project -WindowStyle Hidden -PassThru
$state = [ordered]@{
    Schema = 1; HostPid = $serverProcess.Id
    HostStartedUTC = $serverProcess.StartTime.ToUniversalTime().ToString('o')
    HostExecutable = $hostExe; ClientExecutable = (Join-Path $client 'AMo.exe')
    ClientPid = 0; ClientStartedUTC = ''; RunDirectory = $run
}
# Store ownership immediately: Stop-Berneo can stop a host even if startup fails.
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
$readyPath = Join-Path $run 'ready.json'
$timer = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
    $serverProcess.Refresh()
    if ($serverProcess.HasExited) {
        $log = Join-Path $run 'server.log'
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 12 | Write-Output }
        throw "Berneo server exited during startup (code $($serverProcess.ExitCode))."
    }
    if ($timer.Elapsed.TotalSeconds -gt 30) {
        [IO.File]::WriteAllText((Join-Path $run 'stop.request'), '')
        throw "Startup timed out; graceful stop requested. Inspect $run"
    }
    Start-Sleep -Milliseconds 150
}
$ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
if ($ready.hostPid -ne $serverProcess.Id -or $ready.port -ne 10001 -or $ready.playerSpeedMultiplier -ne 1) {
    [IO.File]::WriteAllText((Join-Path $run 'stop.request'), '')
    throw 'Unexpected server startup contract; graceful stop requested.'
}
$game = Get-Process -Id $ready.clientPid -ErrorAction Stop
if ($game.Path -ne $state.ClientExecutable) {
    [IO.File]::WriteAllText((Join-Path $run 'stop.request'), '')
    throw 'Unexpected client process path; graceful server stop requested.'
}
$state.ClientPid = $game.Id
$state.ClientStartedUTC = $game.StartTime.ToUniversalTime().ToString('o')
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output 'Berneo is ready at 127.0.0.1:10001, player speed x1. Use the game window normally.'
Write-Output "Server log: $(Join-Path $run 'server.log')"
Write-Output 'Use scripts/Stop-Berneo.ps1 to close this run.'
