param([string]$Godot = $env:GODOT)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$hostLog = Join-Path $logDir 'discovery-host.log'
$hostError = Join-Path $logDir 'discovery-host-error.log'
$clientLog = Join-Path $logDir 'discovery-client.log'
$clientError = Join-Path $logDir 'discovery-client-error.log'
$hostProcess = $null
$clientProcess = $null
try {
    $common = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_lan_discovery.gd', '--')
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=host') -WindowStyle Hidden -RedirectStandardOutput $hostLog -RedirectStandardError $hostError -PassThru
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        if ($hostProcess.HasExited) { throw 'Discovery host exited before ready.' }
        $ready = (Test-Path -LiteralPath $hostLog) -and ((Get-Content -LiteralPath $hostLog -Raw) -match 'DISCOVERY_HOST_READY')
    } until ($ready -or (Get-Date) -gt $deadline)
    if (-not $ready) { throw 'Discovery host ready timeout.' }
    $clientProcess = Start-Process -FilePath $Godot -ArgumentList ($common + '--role=client') -WindowStyle Hidden -RedirectStandardOutput $clientLog -RedirectStandardError $clientError -PassThru
    if (-not $clientProcess.WaitForExit(20000)) { throw 'Discovery client timeout.' }
    if (-not $hostProcess.WaitForExit(1000)) { throw 'Discovery host did not stop.' }
    $combined = ''
    foreach ($log in @($hostLog, $hostError, $clientLog, $clientError)) {
        $content = Get-Content -LiteralPath $log -Raw
        Write-Output $content
        $combined += $content
    }
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $combined -match 'ERROR|WARNING.*leak' -or ([regex]::Matches($combined, 'DISCOVERY_TEST role=(host|client) checks=[1-9][0-9]* failures=0').Count -ne 2)) {
        throw 'Discovery two-process test failed; inspect test-results/discovery logs.'
    }
    Write-Output 'DISCOVERY_BROADCAST_PASS: separate host/client, broadcast-only search, metadata update, TTL expiry.'
} finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

