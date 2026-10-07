param(
    [string]$Godot = $env:GODOT,
    [int]$Port = 27962
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDir = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$processes = @()
try {
    foreach ($role in @('host', 'client_a', 'client_b')) {
        $stdout = Join-Path $logDir "mixed-$role.log"
        $stderr = Join-Path $logDir "mixed-$role-error.log"
        $arguments = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/mixed_lan_peer.gd', '--', "--port=$Port", "--role=$role")
        $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $processes += @{ Process = $process; Role = $role; Out = $stdout; Error = $stderr }
        if ($role -eq 'host') {
            $deadline = (Get-Date).AddSeconds(10)
            do {
                Start-Sleep -Milliseconds 100
                if ($process.HasExited) { throw 'Mixed host exited before ready.' }
                $ready = (Test-Path -LiteralPath $stdout) -and ((Get-Content -LiteralPath $stdout -Raw) -match 'MIXED_HOST_READY')
            } until ($ready -or (Get-Date) -gt $deadline)
            if (-not $ready) { throw 'Mixed host readiness timeout.' }
        }
    }
    foreach ($entry in $processes) {
        if (-not $entry.Process.WaitForExit(25000)) { throw "Mixed network timeout: $($entry.Role)" }
    }
    foreach ($entry in $processes) {
        $output = (Get-Content -LiteralPath $entry.Out -Raw) + (Get-Content -LiteralPath $entry.Error -Raw)
        Write-Output $output
        if ($entry.Process.ExitCode -ne 0 -or $output -match 'ERROR:|SCRIPT ERROR|leaked|still in use' -or $output -notmatch "MIXED_NETWORK_SUMMARY role=$($entry.Role) checks=[1-9][0-9]* failures=0") {
            throw "Mixed network failed: $($entry.Role)"
        }
    }
    Write-Output 'MIXED_LAN_LOOPBACK_PASS: three human processes plus two host bots, lobby leave/rejoin, per-bot settings, complete hand, private snapshots, forged bot action rejection, disconnect pause.'
} finally {
    foreach ($entry in $processes) {
        if (-not $entry.Process.HasExited) { Stop-Process -Id $entry.Process.Id }
    }
}

