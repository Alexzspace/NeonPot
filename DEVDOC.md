# Neon Pot development record

Current version: **2.0.0**. English community/source-review edition prepared on **5 October 2026**. The game is complete within its documented Windows/Android and local-multiplayer scope.

## 2.0.0 — GitHub public release, 7 October 2026

- Uploaded the 493-file English source snapshot to Alexzspace/NeonPot; the repository is public.
- Added a latest-release download link to the README and prepared v2.0.0 with the existing Windows EXE/ZIP and Android APK built on 5 October. No gameplay, runtime assets, protocol or package versions changed; no rebuild was performed.
- Rechecked all three binary SHA256 hashes against the saved build manifest; all matched. Confirmed the initial remote main commit matches the local source commit. Historical test results below remain dated 5 October; no new regression or physical-device test is claimed.
- Published [v2.0.0](https://github.com/Alexzspace/NeonPot/releases/tag/v2.0.0) as the latest release, with Android APK, standalone Windows EXE, Windows ZIP and SHA256SUMS.txt. GitHub reported all four assets uploaded with matching sizes and SHA256 digests. All 493 remote source blobs matched the local Git tree after the download-link update. The tagged runtime source matches the existing binaries; subsequent publication-record edits are documentation-only.
- Original code remains MIT; supplied music/startup media and third-party assets retain their separate notices. Startup-media provenance remains a maintainer documentation item.

## 2.0.0 — English community edition, 5 October 2026

- A fresh installation, missing language field or invalid saved locale now uses English. Saved English and Chinese choices remain intact; the user-data directory is unchanged.
- Corrected long home-title layout: configure wrapping before assigning text, retain the original 44px font and fit two lines in the existing panel. This fixes cached width expansion and overlap in the English home screen.
- Added an isolated language/persistence/native-touch regression covering all 24 home lines, 10 company lines, both languages and three window sizes. A pre-existing Chinese-specific solo tutorial fixture now explicitly selects Chinese.
- Prepared an independent public source tree with English player/build/architecture documentation, configurable Windows tooling, MIT for original work and separate notices for supplied media and third-party assets.
- Added a lazy-loaded, independently scrollable license reader to the public About screen. Rapid close/detach cases are covered.
- Kept the ten bundled songs based on the maintainer's distribution-permission confirmation. Original FLAC files, Git history, user preferences, credentials, caches and private promotion files are absent from this source tree.
- No poker rules, network protocol, package identity or version number changed. The public export presets cover Windows and Android APK; a Play upload is not part of this edition.
- Final source gate: 78 suites, 40,415 checks/assertions in their logs, zero failures, plus passing real-process network suites. `ALL_SELFTESTS_PASS`, exit 0. Only deliberately forged RPC authority rejections appeared in the expected network tests.
- Actual D3D12 language/layout check: 960 checks, zero failures. About notices/lifecycle: 31 graphical checks, zero failures. Headless focused checks: 957 language/layout and 29 notices/lifecycle.
- Exported Windows game: 900 rendered frames with the normal audio driver, exit 0 and no script errors/leaks; compiled-package fresh-profile probe: 9 checks, zero failures. Android details and delivery hashes are recorded in `docs/STATUS.md` and `docs/BUILD_ARTIFACTS.json`.
- Preparation caught and corrected the old tutorial fixture's implicit Chinese assumption and the long English title layout. An earlier diagnostic Windows run using Dummy audio warned about exit objects; the final normal-audio run passed without reproducing that warning.
- No GitHub/Discord upload, store submission or phone installation was performed. Device-specific haptics/touch/fold behaviour and iOS remain separate acceptance boundaries. Startup-media provenance is separately noted in `THIRD_PARTY_NOTICES.md`.

## 2.0.0 — Original feature baseline, 14 September 2026

The 2.0.0 baseline introduced exact physical chip inventories, individual manual chip selection and withdrawal, explicit change-making, compact staged chips, retained pot composition, animated payouts, magnetic bet amounts and the precise raise editor. Solo AI, local mixed tables, deck customisation, music import and bilingual settings predate this community edition. The previous Windows/APK/AAB artifacts are historical and are not the English packages described above.
