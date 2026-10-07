# Verified state — release 7 October 2026; build validation 5 October 2026

This file records validation of **Neon Pot 2.0.0 English community edition** on 5 October. On 7 October the source was uploaded to the public [Alexzspace/NeonPot repository](https://github.com/Alexzspace/NeonPot), and [v2.0.0](https://github.com/Alexzspace/NeonPot/releases/tag/v2.0.0) was published as the latest release. All 493 source blobs matched the uploaded Git tree; GitHub's APK, EXE, ZIP and checksum-file sizes and SHA256 digests matched local files. See [latest release](https://github.com/Alexzspace/NeonPot/releases/latest) for downloads. These checks do not imply a new build, store publication or Android device installation.

| Check | Result |
| --- | --- |
| Final source regression | 78 suites; 40,415 checks/assertions; zero failures; `ALL_SELFTESTS_PASS`, exit 0 |
| Real-process local networking | Passed: complete hands, mixed humans/AI, discovery, privacy, malformed/stale actions, cosmetic events and disconnect pause |
| English default, saved languages and all home copy | 957 headless / 960 actual D3D12 graphical checks, zero failures |
| About licenses and rapid close/detach | 29 headless / 31 graphical checks, zero failures |
| Windows EXE | 900 frames with normal audio, exit 0, no script errors or leaks |
| Compiled Windows package resources | Fresh isolated profile: English home, ten music tracks and readable notices; 9 checks, zero failures |
| Android APK | See `BUILD_ARTIFACTS.json` for the final inspected package; build checks cover signature, manifest, permissions, ARM64 and 16KB alignment |

Android identity is `com.neonpot.holdem`, version `2.0.0`, version code `14`, ARM64, minimum API 24. Permissions are Internet and Vibration. The shared APK uses a local debug signing key; the key is not included. Windows x64 is not Authenticode-signed.

The source suite's network-authority tests deliberately produce rejected-RPC errors; these are expected when the corresponding suite reports success. An initial run exposed an old test that assumed Chinese and was corrected before the final full pass. An early Dummy-audio diagnostic EXE run warned about exit objects; the final normal-audio run did not reproduce it.

These are source, desktop and package checks. No new phone install, haptic/listening review, physical fold/unfold check or iOS build was performed. Previously saved language choices are preserved, so an existing Chinese profile will remain Chinese until changed in Settings.

For reproduced builds, rerun the scripts in [BUILDING.md](BUILDING.md); old logs do not establish the state of a modified fork. Original local logs remain outside this public source tree in the maintainer's validation directory.
