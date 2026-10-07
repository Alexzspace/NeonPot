param(
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $Godot)) { throw "Missing Godot console: $Godot" }
$outputRoot = Join-Path $projectPath 'builds/windows'
$outputDir = Join-Path $outputRoot 'NeonPot-v2.0.0-English'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$exe = Join-Path $outputDir 'NeonPot.exe'
$exportLog = Join-Path $outputRoot 'export.log'
$errorLog = Join-Path $outputRoot 'export-error.log'
$process = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', ('"' + $projectPath + '"'), '--export-release', '"Windows Desktop"', ('"' + $exe + '"')) -WindowStyle Hidden -RedirectStandardOutput $exportLog -RedirectStandardError $errorLog -PassThru
if (-not $process.WaitForExit(120000)) {
    Stop-Process -Id $process.Id
    throw "Windows export timed out. Inspect $errorLog"
}
$errors = Get-Content -LiteralPath $errorLog -Raw
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe) -or $errors -match 'SCRIPT ERROR|ERROR:') {
    if ($errors) { Write-Output $errors }
    throw "Windows export failed. Inspect $exportLog"
}
$header = [IO.File]::OpenRead($exe)
try {
    if ($header.ReadByte() -ne 77 -or $header.ReadByte() -ne 90) { throw 'Output is not a Windows executable.' }
} finally { $header.Dispose() }
$readme = @'
Neon Pot V2.0.0 - English default

Launch NeonPot.exe. Mouse input acts as one finger: press, drag and release.
For local multiplayer, connect to the same Wi-Fi; one player hosts and others search.
If Windows asks, allow the game on your current private network.
Extract the entire folder before launching.

A fresh installation starts in English. Switch between English and Chinese in Settings.
Existing saved language preferences are preserved.
Play solo against AI, or with 2-6 players on the same local network.
Virtual chips only. No real-money transactions.

Source code is MIT-licensed. Bundled third-party assets keep their own terms;
see LICENSE, THIRD_PARTY_NOTICES.md and licenses/ for details.
'@
Set-Content -LiteralPath (Join-Path $outputDir 'README.txt') -Value $readme -Encoding utf8
foreach ($notice in @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses')) {
    $noticeSource = Join-Path $projectPath $notice
    if (Test-Path -LiteralPath $noticeSource) {
        Copy-Item -LiteralPath $noticeSource -Destination $outputDir -Recurse -Force
    }
}
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $outputDir 'NeonPot.exe.sha256') -Value "$hash  NeonPot.exe" -Encoding ascii
$archive = Join-Path $outputRoot 'NeonPot-v2.0.0-English-Windows.zip'
Compress-Archive -LiteralPath $outputDir -DestinationPath $archive -Force
$zipHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($archive + '.sha256') -Value "$zipHash  NeonPot-v2.0.0-English-Windows.zip" -Encoding ascii
Write-Output "WINDOWS_BUILD_PASS: $exe"
Write-Output "WINDOWS_SHARE_ZIP: $archive"
Write-Output "SHA256: $hash"

