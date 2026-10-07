param(
    [string]$Godot = $env:GODOT,
    [int]$Port = 27946
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$hostLog = Join-Path $logDir 'network-host.log'
$hostErrorLog = Join-Path $logDir 'network-host-error.log'
$clientLog = Join-Path $logDir 'network-client.log'
$clientErrorLog = Join-Path $logDir 'network-client-error.log'
$hostProcess = $null
$clientProcess = $null
try {
    $commonArgs = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/network_peer.gd', '--', "--port=$Port")
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=host') -WindowStyle Hidden -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrorLog -PassThru
    $readyDeadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        if ($hostProcess.HasExited) { throw 'Host exited before accepting connections.' }
        $hostReady = (Test-Path -LiteralPath $hostLog) -and ((Get-Content -LiteralPath $hostLog -Raw) -match 'NETWORK_HOST_READY')
    } until ($hostReady -or (Get-Date) -gt $readyDeadline)
    if (-not $hostReady) { throw 'Host did not become ready within 10 seconds.' }
    $clientProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=client') -WindowStyle Hidden -RedirectStandardOutput $clientLog -RedirectStandardError $clientErrorLog -PassThru
    if (-not $clientProcess.WaitForExit(25000)) { throw 'Client test timeout.' }
    if (-not $hostProcess.WaitForExit(25000)) { throw 'Host test timeout.' }
    foreach ($logPath in @($hostLog, $hostErrorLog, $clientLog, $clientErrorLog)) {
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath }
    }
    $combined = (Get-Content -LiteralPath $hostLog -Raw) + (Get-Content -LiteralPath $clientLog -Raw)
    $errors = (Get-Content -LiteralPath $hostErrorLog -Raw) + (Get-Content -LiteralPath $clientErrorLog -Raw)
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $errors -match 'ERROR|SCRIPT ERROR|WARNING.*leak' -or ([regex]::Matches($combined, 'NETWORK_TEST role=(host|client) checks=[1-9][0-9]* failures=0').Count -ne 2)) {
        throw 'Network test failed: inspect test-results network logs.'
    }
    Write-Output 'NETWORK_LOOPBACK_PASS: two processes, complete hand, private snapshots, malformed/stale actions, disconnect pause.'
} finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

