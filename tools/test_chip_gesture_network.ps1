param(
    [string]$Godot = $env:GODOT,
    [int]$Port = 27949
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$hostLog = Join-Path $logDir 'gesture-host.log'
$hostErrorLog = Join-Path $logDir 'gesture-host-error.log'
$clientLog = Join-Path $logDir 'gesture-client.log'
$clientErrorLog = Join-Path $logDir 'gesture-client-error.log'
$hostProcess = $null
$clientProcess = $null
try {
    $commonArgs = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_chip_gesture_network.gd', '--', "--port=$Port")
    $hostProcess = Start-Process -FilePath $Godot -ArgumentList ($commonArgs + '--role=host') -WindowStyle Hidden -RedirectStandardOutput $hostLog -RedirectStandardError $hostErrorLog -PassThru
    $readyDeadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        if ($hostProcess.HasExited) { throw 'Gesture host exited before accepting connections.' }
        $hostReady = (Test-Path -LiteralPath $hostLog) -and ((Get-Content -LiteralPath $hostLog -Raw) -match 'GESTURE_HOST_READY')
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
    $expectedRejection = '(?m)^ERROR: RPC ''_receive_chip_gesture'' is not allowed on node /root/Session from: [0-9]+\. Mode is "authority", authority is 1\.\r?\n   at: _process_rpc \(modules/multiplayer/scene_rpc_interface\.cpp:[0-9]+\)\r?\n?'
    if ([regex]::Matches($errors, $expectedRejection).Count -ne 1) {
        throw 'Expected exactly one engine-level rejection of the forged authority gesture.'
    }
    $errors = [regex]::Replace($errors, $expectedRejection, '')
    $stylePattern = '(?m)^GESTURE_STYLE hand=[0-9]+ sequence=[0-9]+ seat=[0-9]+ style=[0-4]'
    $hostStyles = @([regex]::Matches((Get-Content -LiteralPath $hostLog -Raw), $stylePattern) | ForEach-Object { $_.Value })
    $clientStyles = @([regex]::Matches((Get-Content -LiteralPath $clientLog -Raw), $stylePattern) | ForEach-Object { $_.Value })
    if ($hostStyles.Count -ne 4 -or ($hostStyles -join "`n") -cne ($clientStyles -join "`n") -or -not ($hostStyles -match 'style=4$')) {
        throw 'Host/client gesture styles differ, are incomplete, or did not include the hidden style.'
    }
    if ($hostProcess.ExitCode -ne 0 -or $clientProcess.ExitCode -ne 0 -or $errors -match 'ERROR|SCRIPT ERROR|WARNING.*leak' -or ([regex]::Matches($combined, 'CHIP_GESTURE_NETWORK role=(host|client) checks=[1-9][0-9]* failures=0').Count -ne 2)) {
        throw 'Gesture network test failed: inspect test-results/gesture-*.log.'
    }
    Write-Output 'CHIP_GESTURE_LOOPBACK_PASS: two processes, identical normal/hidden styles, forged authority RPC rejected, flood/replay rejection, full hand, disconnect.'
} finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

