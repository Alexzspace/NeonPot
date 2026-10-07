# Building and testing

## Requirements

- Godot **4.6.2 stable**, standard Windows edition, with both the main executable and its adjacent console executable.
- Matching Godot 4.6.2 export templates for exports.
- PowerShell on Windows for the supplied automation. The game itself uses GDScript, not C#.
- FFmpeg on `PATH`, or an absolute `NEON_POT_FFMPEG` path, for the full Windows test suite's FLAC-import checks. FFmpeg is not required for normal play and is not bundled.

Set `GODOT` to the console executable, pass `-Godot` to a script, or put a supported Godot console command on `PATH`. Examples use replaceable paths, not a developer account's folders.

```powershell
$env:GODOT = 'C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe'
& $env:GODOT --headless --editor --path . --import
& .\tools\selftest.ps1
```

Run these commands from the repository root. Success requires `ALL_SELFTESTS_PASS`, zero failures and no unexpected script errors/leaks. Network tests deliberately attempt forged authority calls; the corresponding rejection errors are expected only when those suites explicitly pass. Tests use real local processes and UDP traffic.

For the English-first graphical/native-touch check:

```powershell
& $env:GODOT --path . --script res://tests/test_language_defaults.gd -- --capture-language
& $env:GODOT --path . --script res://tests/test_public_notices.gd
```

## Windows

```powershell
& .\tools\build_windows.ps1
```

Output: `builds/windows/NeonPot-v2.0.0-English/NeonPot.exe` and `builds/windows/NeonPot-v2.0.0-English-Windows.zip`, plus SHA256 files. The ZIP includes English player instructions and license notices. Run the packaged EXE from its own directory; do not pass the source project's `--path` when testing the package. Windows code signing is not configured.

## Android APK

Install JDK 17, Android SDK platform 35, build-tools **35.0.1**, platform-tools and Godot's Android export templates. The current build verification uses the versioned build-tools directory. Supply local paths explicitly or use `JAVA_HOME`, `ANDROID_HOME` / `ANDROID_SDK_ROOT`. Keep signing files outside the repository.

```powershell
& .\tools\build_android.ps1 `
  -JavaSdk 'C:\Tools\jdk-17' `
  -AndroidSdk 'C:\Android\Sdk' `
  -TemplateRoot "$env:APPDATA\Godot\export_templates" `
  -GradleTemp 'C:\NeonPotTemp'
```

The template installer expands the official Android source template into ignored `android/` and applies this repository's manifest overlays. The build script uses an isolated Godot settings directory, signs with a local debug keystore, verifies the manifest/ARM64 ABI/permissions/signature/16KB alignment, and writes `builds/android/NeonPot-v2.0.0-English.apk` with a SHA256 file. It does not install the app or upload anything.

Package identity: `com.neonpot.holdem`, version name `2.0.0`, version code `14`. Rebuilding the same source does not guarantee byte-identical binaries. Debug signing keys are machine-local; builds signed by another key cannot replace an existing install with the same package identity.

There is no Play AAB publishing configuration in this public review package. Create your own signing identity and publishing configuration if you fork the project; never commit private keys or Godot export credentials.

## Resource maintenance

Runtime sound resources are included. To regenerate or verify the procedural effects:

```powershell
& $env:GODOT --headless --path . --script res://tools/bake_feedback.gd -- --verify
```

`prepare_intro.ps1` accepts a source movie path and needs FFmpeg. The original source movie and lossless music are not needed to run, test or export the included game. The Ogg playlist and manifest already contain the playable music.

## Validation boundaries

The automated suite covers source behavior and local-process networking. A successful export proves a package was built and inspected; it does not prove phone touch quality, haptics, thermal performance, foldable transitions, or iOS support. See [STATUS.md](STATUS.md) for evidence from the prepared community build.
