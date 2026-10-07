param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [string]$FFmpeg = 'ffmpeg'
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$outputPath = Join-Path $projectPath 'assets\startup\intro.ogv'
if (-not (Test-Path -LiteralPath $FFmpeg)) {
    $ffmpegCommand = Get-Command $FFmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ffmpegCommand) { throw 'Pass -FFmpeg with the ffmpeg executable path, or add ffmpeg to PATH.' }
    $FFmpeg = $ffmpegCommand.Source
}
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
& $FFmpeg -hide_banner -nostdin -y -i $sourcePath -map 0:v:0 -map 0:a:0 -map_metadata -1 -vf 'scale=1280:720:flags=lanczos,setsar=1' -r 30 -c:v libtheora -q:v 8 -pix_fmt yuv420p -c:a libvorbis -q:a 5 -ar 48000 $outputPath
if ($LASTEXITCODE -ne 0) { throw 'Intro conversion failed.' }
if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Source video changed unexpectedly.' }
Write-Output "OUTPUT_BYTES $((Get-Item -LiteralPath $outputPath).Length)"
Write-Output "OUTPUT_SHA256 $((Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash)"
Write-Output "SOURCE_SHA256 $sourceHash"

