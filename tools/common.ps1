# Shared Windows tooling: use Godot 4.6.2's console executable for synchronous logs.
function Resolve-GodotConsole {
    param([string]$Requested = $env:GODOT)
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    else { $candidates += @('godot_console.exe', 'godot4_console.exe', 'Godot_v4.6.2-stable_win64_console.exe') }
    foreach ($candidate in $candidates) {
        $resolved = $null
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolved = (Resolve-Path -LiteralPath $candidate).Path }
        else {
            $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) { $resolved = $command.Source }
        }
        if (-not $resolved) { continue }
        if ($resolved -notmatch '_console\.exe$') {
            $consoleSibling = [IO.Path]::Combine([IO.Path]::GetDirectoryName($resolved), [IO.Path]::GetFileNameWithoutExtension($resolved) + '_console.exe')
            if (Test-Path -LiteralPath $consoleSibling -PathType Leaf) { $resolved = $consoleSibling }
            else { throw "Use the Windows Godot console executable (with its matching main .exe beside it): $resolved" }
        }
        $mainExe = $resolved -replace '_console\.exe$', '.exe'
        if (-not (Test-Path -LiteralPath $mainExe -PathType Leaf)) { throw "Missing Godot executable beside console launcher: $mainExe" }
        return $resolved
    }
    throw 'Godot 4.6.2 console executable was not found. Pass -Godot <full-path-to-console.exe>, set GODOT, or put the Godot console executable on PATH.'
}
