param(
    [string]$Godot = $env:GODOT,
    [int]$Port = 27981
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$hostLog = Join-Path $logDir 'table-prop-host.log'
$hostErrorLog = Join-Path $logDir 'table-prop-host-error.log'
$clientLog = Join-Path $logDir 'table-prop-client.log'
$clientErrorLog = Join-Path $logDir 'table-prop-client-error.log'
$hostProcess = $null
$clientProcess = $null
try {
    $commonArgs = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_table_prop_network.gd', '--', "--port=$Port")
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=host') -WindowStyle Hidden -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrorLog -PassThru
    $readyDeadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        if ($hostProcess.HasExited) { throw 'Gesture host exited before accepting connections.' }
        $hostReady = (Test-Path -LiteralPath $hostLog) -and ((Get-Content -LiteralPath $hostLog -Raw) -match 'PROP_HOST_READY')
    } until ($hostReady -or (Get-Date) -gt $readyDeadline)
    if (-not $hostReady) { throw 'Gesture host did not become ready within 10 seconds.' }
    $clientProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=client') -WindowStyle Hidden -RedirectStandardOutput $clientLog -RedirectStandardError $clientErrorLog -PassThru
    if (-not $clientProcess.WaitForExit(25000)) { throw 'Gesture client timeout.' }
    if (-not $hostProcess.WaitForExit(25000)) { throw 'Gesture host timeout.' }
    foreach ($logPath in @($hostLog, $hostErrorLog, $clientLog, $clientErrorLog)) {
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath }
    }
    $combined = (Get-Content -LiteralPath $hostLog -Raw) + (Get-Content -LiteralPath $clientLog -Raw)
    $errors = (Get-Content -LiteralPath $hostErrorLog -Raw) + (Get-Content -LiteralPath $clientErrorLog -Raw)
    # The fixture deliberately sends one forbidden authority RPC. Require that precise rejection,
    # then continue treating every other engine error as a failure.
    $expectedRejection = '(?m)^ERROR: RPC ''_receive_table_prop_gesture'' is not allowed on node /root/Session from: [0-9]+\. Mode is "authority", authority is 1\.\r?\n   at: _process_rpc \(modules/multiplayer/scene_rpc_interface\.cpp:[0-9]+\)\r?\n?'
    if ([regex]::Matches($errors, $expectedRejection).Count -ne 1) {
        throw 'Expected exactly one engine-level rejection of the forged authority gesture.'
    }
    $errors = [regex]::Replace($errors, $expectedRejection, '')
    $eventPattern = '(?m)^PROP_EVENT .+'
    $hostEvents = @([regex]::Matches((Get-Content -LiteralPath $hostLog -Raw), $eventPattern) | ForEach-Object { $_.Value.Trim() })
    $clientEvents = @([regex]::Matches((Get-Content -LiteralPath $clientLog -Raw), $eventPattern) | ForEach-Object { $_.Value.Trim() })
    if ($hostEvents.Count -ne 21 -or ($hostEvents -join "`n") -cne ($clientEvents -join "`n")) {
        throw 'Host/client table prop events differ or are incomplete.'
    }
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $errors -match 'ERROR|SCRIPT ERROR|WARNING.*leak' -or ([regex]::Matches($combined, 'TABLE_PROP_NETWORK role=(host|client) checks=[1-9][0-9]* failures=0').Count -ne 2)) {
        throw 'Table prop network test failed: inspect test-results/table-prop-*.log.'
    }
    Write-Output 'TABLE_PROP_LOOPBACK_PASS: two processes, identical pot/deck events, authority forgery rejected, unthrottled rapid taps, replay, immutable private snapshots, new hand, disconnect.'
} finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

