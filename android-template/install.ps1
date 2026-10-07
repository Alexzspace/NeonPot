param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..'),
    [string]$TemplateRoot = (Join-Path $env:APPDATA 'Godot\export_templates')
)

$ErrorActionPreference = 'Stop'
$engineVersion = '4.6.2.stable'
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$androidRoot = Join-Path $projectPath 'android'
$buildRoot = Join-Path $androidRoot 'build'
$templateZip = Join-Path $TemplateRoot "$engineVersion\android_source.zip"
$versionFile = Join-Path $androidRoot '.build_version'

if (-not (Test-Path -LiteralPath $templateZip)) {
    throw "Missing Godot Android source template: $templateZip"
}

if (Test-Path -LiteralPath $buildRoot) {
    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw "Refusing to overwrite an unmanaged Android build directory: $buildRoot"
    }
    $installedVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    if ($installedVersion -ne $engineVersion) {
        throw "Android build template $installedVersion does not match $engineVersion."
    }
} else {
    New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($templateZip, $buildRoot)
}

$mainManifestDir = Join-Path $buildRoot 'src\main'
New-Item -ItemType Directory -Path $mainManifestDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AndroidManifest.xml') -Destination (Join-Path $mainManifestDir 'AndroidManifest.xml') -Force
foreach ($variant in @('standardRelease', 'standardDebug')) {
    $variantManifestDir = Join-Path $buildRoot "src\$variant"
    New-Item -ItemType Directory -Path $variantManifestDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'standard-release-AndroidManifest.xml') -Destination (Join-Path $variantManifestDir 'AndroidManifest.xml') -Force
}
$obsoleteOrientationOverlay = Join-Path $buildRoot 'src\standard\AndroidManifest.xml'
if (Test-Path -LiteralPath $obsoleteOrientationOverlay) {
    Remove-Item -LiteralPath $obsoleteOrientationOverlay -Force
}
Set-Content -LiteralPath $versionFile -Value $engineVersion -Encoding ascii -NoNewline
Set-Content -LiteralPath (Join-Path $buildRoot '.gdignore') -Value '' -Encoding ascii -NoNewline

Write-Output "HYPEROS_ANDROID_TEMPLATE_READY: $buildRoot"
