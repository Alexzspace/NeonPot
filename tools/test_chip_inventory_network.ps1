param(
    [string]$Godot = $env:GODOT,
    [int]$Port = 27987,
    [ValidateSet(0, 1)][int]$Dealer = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$hostLog = Join-Path $logDir 'chip-inventory-host.log'
$hostErrorLog = Join-Path $logDir 'chip-inventory-host-error.log'
$clientLog = Join-Path $logDir 'chip-inventory-client.log'
$clientErrorLog = Join-Path $logDir 'chip-inventory-client-error.log'
$hostProcess = $null
$clientProcess = $null
try {
    $commonArgs = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_chip_inventory_network.gd', '--', "--port=$Port", "--dealer=$Dealer")
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=host') -WindowStyle Hidden -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrorLog -PassThru
    $readyDeadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        if ($hostProcess.HasExited) { throw 'Chip inventory host exited before accepting connections.' }
        $hostReady = (Test-Path -LiteralPath $hostLog) -and ((Get-Content -LiteralPath $hostLog -Raw) -match 'CHIP_INVENTORY_HOST_READY')
    } until ($hostReady -or (Get-Date) -gt $readyDeadline)
    if (-not $hostReady) { throw 'Chip inventory host readiness timeout.' }
    $clientProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=client') -WindowStyle Hidden -RedirectStandardOutput $clientLog -RedirectStandardError $clientErrorLog -PassThru
    if (-not $clientProcess.WaitForExit(25000)) { throw 'Chip inventory client timeout.' }
    if (-not $hostProcess.WaitForExit(25000)) { throw 'Chip inventory host timeout.' }
    foreach ($logPath in @($hostLog, $hostErrorLog, $clientLog, $clientErrorLog)) {
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath }
    }
    $combined = (Get-Content -LiteralPath $hostLog -Raw) + (Get-Content -LiteralPath $clientLog -Raw)
    $errors = (Get-Content -LiteralPath $hostErrorLog -Raw) + (Get-Content -LiteralPath $clientErrorLog -Raw)
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $errors -match 'ERROR|SCRIPT ERROR|WARNING.*leak|still in use' -or ([regex]::Matches($combined, 'CHIP_INVENTORY_NETWORK role=(host|client) checks=[1-9][0-9]* failures=0').Count -ne 2)) {
        throw 'Chip inventory network test failed: inspect test-results/chip-inventory-*.log.'
    }
    Write-Output "CHIP_INVENTORY_LOOPBACK_PASS dealer=${Dealer}: real exchange/manual RPC, exact public inventories, stale/forged/out-of-turn rejection, private snapshots, no movement replay, disconnect."
} finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

