param(
    [string]$Godot = $env:GODOT,
    [string]$ToolchainRoot = (Join-Path $env:LOCALAPPDATA 'VelvetHoldemToolchain'),
    [string]$TemplateRoot = (Join-Path $env:APPDATA 'Godot/export_templates'),
    [string]$JavaSdk = $env:JAVA_HOME,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$GradleTemp = (Join-Path $env:SystemDrive 'NeonPotTemp')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $JavaSdk) { $JavaSdk = Join-Path $ToolchainRoot 'java/jdk-17.0.20.1+1' }
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $ToolchainRoot 'android-sdk' }
foreach ($required in @($Godot, (Join-Path $JavaSdk 'bin/java.exe'), (Join-Path $JavaSdk 'bin/keytool.exe'), (Join-Path $AndroidSdk 'platform-tools/adb.exe'), (Join-Path $AndroidSdk 'build-tools/35.0.1/apksigner.bat'), (Join-Path $TemplateRoot '4.6.2.stable/android_debug.apk'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing build dependency: $required. See docs/BUILDING.md." }
}
$templateInstaller = Join-Path $projectPath 'android-template/install.ps1'
if (-not (Test-Path -LiteralPath $templateInstaller)) { throw "Missing HyperOS Android template installer: $templateInstaller" }
& $templateInstaller -ProjectRoot $projectPath -TemplateRoot $TemplateRoot
if (-not $?) { throw 'Could not prepare the HyperOS Android build template.' }
$portableRoot = Join-Path $ToolchainRoot 'godot-export'
$editorData = Join-Path $portableRoot 'editor_data'
New-Item -ItemType Directory -Force -Path $editorData | Out-Null
$portableExe = Join-Path $portableRoot (Split-Path $Godot -Leaf)
# The small console executable launches the matching main executable beside it.
# Keep both files together, and refresh changed binaries in this isolated toolchain.
foreach ($engineFile in @($Godot, ($Godot -replace '_console\.exe$', '.exe'))) {
    $portableFile = Join-Path $portableRoot (Split-Path $engineFile -Leaf)
    if (-not (Test-Path -LiteralPath $portableFile) -or (Get-FileHash -LiteralPath $engineFile).Hash -ne (Get-FileHash -LiteralPath $portableFile).Hash) {
        Copy-Item -LiteralPath $engineFile -Destination $portableFile -Force
    }
}
Set-Content -LiteralPath (Join-Path $portableRoot '_sc_') -Value '' -Encoding utf8
$templateLink = Join-Path $editorData 'export_templates'
if (-not (Test-Path -LiteralPath $templateLink)) {
    New-Item -ItemType Junction -Path $templateLink -Target $TemplateRoot | Out-Null
}
$debugKeystore = Join-Path $ToolchainRoot 'debug.keystore'
if (-not (Test-Path -LiteralPath $debugKeystore)) {
    & (Join-Path $JavaSdk 'bin/keytool.exe') -genkeypair -keystore $debugKeystore -alias androiddebugkey -storepass android -keypass android -dname 'CN=Android Debug,O=Velvet Table,C=GB' -keyalg RSA -keysize 2048 -validity 10000 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create local Android debug keystore.' }
}
$settingsText = @'
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "JAVA_SDK"
export/android/android_sdk_path = "ANDROID_SDK"
export/android/debug_keystore = "DEBUG_KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
'@
$settingsText = $settingsText.Replace('JAVA_SDK', $JavaSdk.Replace('\','/')).Replace('ANDROID_SDK', $AndroidSdk.Replace('\','/')).Replace('DEBUG_KEYSTORE', $debugKeystore.Replace('\','/'))
Set-Content -LiteralPath (Join-Path $editorData 'editor_settings-4.6.tres') -Value $settingsText -Encoding utf8
$outputDir = Join-Path $projectPath 'builds/android'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$apk = Join-Path $outputDir 'NeonPot-v2.0.0-English.apk'
$exportLog = Join-Path $outputDir 'export.log'
$errorLog = Join-Path $outputDir 'export-error.log'
New-Item -ItemType Directory -Force -Path $GradleTemp | Out-Null
$previousExportEnvironment = @{ TEMP = $env:TEMP; TMP = $env:TMP; GRADLE_OPTS = $env:GRADLE_OPTS }
try {
    $env:TEMP = (Resolve-Path -LiteralPath $GradleTemp).Path
    $env:TMP = $env:TEMP
    $env:GRADLE_OPTS = '-Dorg.gradle.daemon=false -Djava.net.preferIPv4Stack=true -Djava.net.preferIPv6Addresses=false'
    $exportProcess = Start-Process -FilePath $portableExe -ArgumentList @('--headless', '--path', ('"' + $projectPath + '"'), '--export-debug', '"Android Debug"', ('"' + $apk + '"')) -WindowStyle Hidden -RedirectStandardOutput $exportLog -RedirectStandardError $errorLog -PassThru
    if (-not $exportProcess.WaitForExit(300000)) {
        Stop-Process -Id $exportProcess.Id
        throw "Android export timed out. Inspect $errorLog"
    }
} finally {
    foreach ($name in $previousExportEnvironment.Keys) {
        if ($null -eq $previousExportEnvironment[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$name" $previousExportEnvironment[$name] }
    }
}
$errors = Get-Content -LiteralPath $errorLog -Raw
if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $apk) -or $errors -match 'SCRIPT ERROR|ERROR:') {
    if ($errors) { Write-Output $errors }
    throw "Android export failed. Inspect $exportLog"
}
$aapt = Join-Path $AndroidSdk 'build-tools/35.0.1/aapt.exe'
$aapt2 = Join-Path $AndroidSdk 'build-tools/35.0.1/aapt2.exe'
# AAPT1's badging parser rejects the string-encoded Vulkan feature attributes
# written by Godot's native APK exporter. AAPT2 understands that manifest.
$manifestDump = & $aapt2 dump badging $apk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'aapt2 could not inspect APK.' }
$manifestDump | Set-Content -LiteralPath (Join-Path $outputDir 'manifest-badging.txt') -Encoding utf8
$manifestText = $manifestDump -join "`n"
foreach ($requiredPattern in @("package: name='com.neonpot.holdem'", "application-label:'Neon Pot'", "native-code: 'arm64-v8a'", 'android.permission.INTERNET', 'android.permission.VIBRATE')) {
    if ($manifestText -notmatch [regex]::Escape($requiredPattern)) { throw "APK manifest verification failed: $requiredPattern" }
}
foreach ($permissionLine in ($manifestDump | Where-Object { $_ -match '^uses-permission:' })) {
    if ($permissionLine -notmatch "name='android.permission.(INTERNET|VIBRATE)'$") { throw "Unexpected permission: $permissionLine" }
}
$manifestXml = & $aapt dump xmltree $apk AndroidManifest.xml 2>&1
if ($LASTEXITCODE -ne 0) { throw 'aapt could not inspect APK manifest XML.' }
$manifestXml | Set-Content -LiteralPath (Join-Path $outputDir 'manifest-tree.txt') -Encoding utf8
if (($manifestXml -join "`n") -notmatch 'screenOrientation.*0x0') { throw 'Expected landscape orientation in Android manifest.' }
$manifestTreeText = $manifestXml -join "`n"
$hyperOsValues = [ordered]@{
    'android.supports_size_changes' = '0xffffffff'
    'miui.supportAppContinuity' = '0xffffffff'
    'miui.supportFlipWatchOverlayGroupView' = '0x0'
    'miui.supportFlipFullScreen' = '0x0'
}
foreach ($hyperOsDeclaration in $hyperOsValues.Keys) {
    $nameThenValue = [regex]::Escape($hyperOsDeclaration) + "(?s:.{0,240}?)android:value.*" + [regex]::Escape($hyperOsValues[$hyperOsDeclaration])
    if ($manifestTreeText -notmatch $nameThenValue) { throw "Missing or invalid HyperOS outer-screen declaration: $hyperOsDeclaration" }
}
$alignment = & (Join-Path $AndroidSdk 'build-tools/35.0.1/zipalign.exe') -c -P 16 -v 4 $apk 2>&1
$alignment | Set-Content -LiteralPath (Join-Path $outputDir 'alignment.txt') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'APK 16KB page alignment verification failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    if ($null -eq $archive.GetEntry('res/mipmap-anydpi-v26/icon.xml')) { throw 'APK launcher icon resource missing.' }
    if ($null -eq $archive.GetEntry('assets/assets/startup/intro.ogv')) { throw 'Startup movie missing from APK.' }
    $unexpectedEntries = $archive.Entries | Where-Object { $_.FullName -match '^assets/(tests|tools|docs|addons)/|\.keystore$' }
    if ($unexpectedEntries) { throw 'APK contains excluded development files.' }
} finally { $archive.Dispose() }
$previousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $JavaSdk
    $signature = & (Join-Path $AndroidSdk 'build-tools/35.0.1/apksigner.bat') verify --verbose --print-certs $apk 2>&1
    $signature | Set-Content -LiteralPath (Join-Path $outputDir 'signature.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
$apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($apk + '.sha256') -Value "$apkHash  NeonPot-v2.0.0-English.apk" -Encoding ascii
Write-Output "ANDROID_BUILD_PASS: $apk"
Write-Output "APK bytes: $((Get-Item -LiteralPath $apk).Length)"
Write-Output "SHA256: $apkHash"
Write-Output ($manifestDump | Where-Object { $_ -match 'package:|sdkVersion|targetSdkVersion|native-code|uses-permission' })
Write-Output 'Debug-signed APK for direct sharing; no device installation or store upload was performed.'

