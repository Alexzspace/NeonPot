# Neon Pot: optional Core Haptics plugin source

**Status: source and runtime hook only. This Windows workspace has no macOS/Xcode build or iPhone hardware validation. No plugin binary is included or enabled.** The existing Godot iOS fallback remains available without installing this plugin. Nothing here changes the shared music player or audio session category.

`NeonPotHaptics` exposes `is_supported()`, `play_transients(times: PackedFloat32Array, intensities: PackedFloat32Array, sharpness: float) -> bool`, and `stop()`. Times are relative seconds; intensities and sharpness are clamped to 0–1. Each call accepts at most eight short transients. Unsupported hardware returns false without issuing a vibration request. The runtime driver discovers the singleton only when installed and supported; otherwise it uses the Godot fallback. A failed native playback also falls back for the driver lifetime.

The six chip profiles have distinct duration, intensity and sharpness. `Feedback.play_chip_contact()` takes the same selected sound variant's contact offsets and actual playback pitch, then schedules corresponding haptic impulses. Shared audio can be muted independently. The driver merges contacts within 12 ms using the stronger profile, keeps at most 32 pending events, avoids dispatching over an active Android primitive, and discards events more than 45 ms late. Android API 31+ hardware primitive durations refine that active interval. This bounds overlapping events without repeated cancel/restart storms. Timing is controlled by the game loop and native driver; absolute physical audio/haptic latency has **not** been measured on devices.

The main presentation calls `play_chip_contact(kind, shared=false, intensity=1.0)` at its visual/audio activity boundary and `cancel_chip_haptics()` when canceling a presentation. Focus loss, application pause, and scene exit clear queued contacts and stop the available native motor. `Feedback` processes the bounded queue each frame; callers must not call raw `pulse("chip")` on top of every contact. Normal audio-only previews keep using `play_audio_only()`.

Windows headless verification: **116/0 haptic tests** and **1493/0 feedback tests**, both with clean shutdown. These validate profile distinctions, mocked contact timing and pitch, bounded overlap/coalescing, cancellation, native argument values, audio/haptic mute separation, and independent focus/background state. They do not validate Objective-C++ compilation or native motor behavior.

Godot 4.6 already implements its iOS `Input.vibrate_handheld` fallback with continuous Core Haptics on supported hardware. The optional plugin adds transient events and material sharpness. The driver uses the available `AppleEmbedded` capability and start/stop hooks; it does not simulate cancellation by creating a new zero-duration vibration. If the engine reports no haptic hardware, the driver silently does nothing. Without an available stop hook, the fallback has only brief finite pulses; clearing its queue prevents later contacts.

## Build later on a Mac

1. Use the Godot **4.6.2** engine source and the exact compile configuration matching the iOS export templates. Generate the engine headers with its iOS SCons configuration.
2. Create an Objective-C++ static-library Xcode target, add `neon_pot_haptics.mm`, enable ARC, set minimum iOS 13, and use the matching Godot header search paths, defines, and C++ settings. Link Foundation and CoreHaptics. The code and API compatibility must be compiled and reviewed on that Mac before release.
3. Build arm64 device Debug/Release archives (and a simulator archive only if needed). Follow Godot's documented `.a` or `.xcframework` packaging. No build command is claimed as tested here.
4. Copy the finished archive(s) and this example configuration, renamed `NeonPotHaptics.gdip`, into `res://ios/plugins/NeonPotHaptics/`. Match the `binary` field to the output name. Enable the plugin in the iOS export preset only after those binaries exist.
5. On iPhone, verify `backend == "ios_core_haptics"`, low/high intensity and zero, all six activities, rapid overlapping collisions, app background/focus return, and scene cancellation. Confirm music continues uninterrupted. Also test the no-plugin fallback and an unsupported device. Record actual feel and timing separately from desktop mock results.

## Primary references

- [Godot iOS plugin packaging and matching engine headers](https://docs.godotengine.org/en/4.6/tutorials/platform/ios/ios_plugin.html) (the documentation carries a version-update notice; verify against the matching source when building).
- [Godot 4.6 AppleEmbedded haptic implementation](https://github.com/godotengine/godot/blob/4.6/drivers/apple_embedded/apple_embedded.mm).
- [Apple: preparing an app for Core Haptics and hardware capability checks](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics).
- [Apple: transient intensity and sharpness](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time).
- [Android: primitive support and duration queries](https://developer.android.com/reference/android/os/Vibrator#getPrimitiveDurations(int...)).
