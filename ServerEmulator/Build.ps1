param(
    [switch]$SkipTests,
    [string[]]$TestNames,
    [switch]$TestsOnly,
    [ValidateSet('GUI','TestHost')][string[]]$Programs = @('GUI','TestHost'),
    [string]$CompilerPath,
    [string]$SQLitePath
)
$ErrorActionPreference = 'Stop'
$allTests = @(
    'ServerSmokeTests', 'B1008ProtocolTests', 'B1008CharacterTests',
    'B1008WorldTests', 'B1008WorldStateTests', 'B1008QuestTests',
    'B1008CombatTests', 'B1008RuntimeTests', 'B1008AITests',
    'B1008LootTests', 'B1008BalanceTests', 'B1008ProfessionSessionTests',
    'B1008ProfessionEffectsTests', 'B1008FlettaProcTests',
    'B1008RatesTests', 'B1008QuickSlotTests', 'B1008BerneoTests'
)
$focused = $PSBoundParameters.ContainsKey('TestNames')
if ($SkipTests -and ($focused -or $TestsOnly)) { throw 'SkipTests cannot be combined with TestNames or TestsOnly.' }
if ($TestsOnly -and -not $focused) { throw 'TestsOnly requires explicit TestNames.' }
if ($TestsOnly -and $PSBoundParameters.ContainsKey('Programs')) { throw 'TestsOnly cannot be combined with Programs.' }
if (-not $Programs -or $Programs.Count -eq 0) { throw 'Programs must not be empty.' }
if ($focused) {
    if (-not $TestNames -or $TestNames.Count -eq 0) { throw 'TestNames must not be empty.' }
    foreach ($name in $TestNames) {
        if ($name -notin $allTests) { throw "Unknown public test suite: $name" }
    }
    $selectedTests = @($allTests | Where-Object { $_ -in $TestNames })
} else { $selectedTests = $allTests }
if (-not $CompilerPath) { $CompilerPath = (Get-Command dcc64.exe -ErrorAction Stop).Source }
if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) { throw "Delphi Win64 compiler not found: $CompilerPath" }
$CompilerPath = (Resolve-Path -LiteralPath $CompilerPath).Path
if (-not $SQLitePath) {
    $bdsRoot = Split-Path (Split-Path $CompilerPath -Parent) -Parent
    $SQLitePath = Join-Path $bdsRoot 'bin64\sqlite3.dll'
}
if (-not (Test-Path -LiteralPath $SQLitePath -PathType Leaf)) {
    throw 'SQLite x64 runtime not found. Pass -SQLitePath <path to sqlite3.dll>.'
}
$SQLitePath = (Resolve-Path -LiteralPath $SQLitePath).Path
$releaseOutput = Join-Path $PSScriptRoot 'Win64\Release'
$testOutput = Join-Path $PSScriptRoot 'Win64\Tests'
$testUnits = Join-Path $testOutput 'dcu'
New-Item -ItemType Directory -Force -Path $releaseOutput, $testOutput, $testUnits | Out-Null
Copy-Item -LiteralPath $SQLitePath -Destination (Join-Path $testOutput 'sqlite3.dll') -Force
Push-Location $PSScriptRoot
try {
    if (-not $TestsOnly) {
        foreach ($program in @('GUI','TestHost') | Where-Object { $_ -in $Programs }) {
            if ($program -eq 'GUI') {
                $source = 'KarosOldEmulator.dpr'
                $output = $releaseOutput
                $namespaces = '-NSSystem;Winapi;Vcl;System.Win'
            } else {
                $source = 'tools\B1008TestHost.dpr'
                $output = Join-Path $PSScriptRoot 'Win64\Tools'
                $namespaces = '-NSSystem;Winapi;System.Win'
            }
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Program source not found: $source" }
            New-Item -ItemType Directory -Force -Path $output | Out-Null
            Copy-Item -LiteralPath $SQLitePath -Destination (Join-Path $output 'sqlite3.dll') -Force
            $watch = [Diagnostics.Stopwatch]::StartNew()
            & $CompilerPath -B -Q $namespaces '-U.' "-E$output" "-N0$output" $source
            if ($LASTEXITCODE -ne 0) { throw "Program build failed: $program" }
            $watch.Stop()
            'CHECKTIME | program={0} compile_ms={1}' -f $program,$watch.ElapsedMilliseconds
        }
    }
    if (-not $SkipTests) {
        Push-Location (Join-Path $PSScriptRoot 'tests')
        try {
            foreach ($name in $selectedTests) {
                $watch = [Diagnostics.Stopwatch]::StartNew()
                & $CompilerPath -B -Q '-$R+' '-$Q+' '-NSSystem;Winapi;Vcl;System.Win' '-U..' "-E$testOutput" "-N0$testUnits" "$name.dpr"
                if ($LASTEXITCODE -ne 0) { throw "Test build failed: $name" }
                $compileMS = $watch.ElapsedMilliseconds
                $watch.Restart()
                & (Join-Path $testOutput "$name.exe")
                if ($LASTEXITCODE -ne 0) { throw "Tests failed: $name" }
                $watch.Stop()
                'CHECKTIME | suite={0} compile_ms={1} run_ms={2}' -f $name,$compileMS,$watch.ElapsedMilliseconds
            }
        } finally { Pop-Location }
    }
    if ($TestsOnly) { 'Focused tests passed: '+($selectedTests -join ', ') }
    else { 'Built programs: '+($Programs -join ', ') }
} finally { Pop-Location }
