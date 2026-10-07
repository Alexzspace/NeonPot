# Third-party notices

## Original project work

Copyright (c) 2026 Alex Zhao. Original game scripts, project documentation, procedural card/chip/background graphics, icon artwork and generated sound effects are covered by the root MIT `LICENSE`, except for the third-party and supplied media listed below. The Android template overlays retain the underlying Godot Engine notice.

## Godot Engine

Godot Engine 4.6.2 is distributed under MIT. See `licenses/GODOT-LICENSE.txt`, `licenses/GODOT-AUTHORS.txt` and `licenses/GODOT-COPYRIGHT.txt` for the engine and its third-party components. These files come from the upstream `4.6.2-stable` tag. Official license page: https://godotengine.org/license/ .

## Fonts

`assets/fonts/fusion-pixel.ttf` is Fusion Pixel Font by TakWolf, obtained from the upstream v2026.09.01 release. Preserve `assets/fonts/OFL.txt` and every notice in `assets/fonts/LICENSES/`. These cover Fusion Pixel and its upstream Ark Pixel, Cubic 11 and Galmuri components. They are not covered by the game's MIT license. Copies are also in `licenses/fonts/` for packaged distribution.

Upstream: https://github.com/TakWolf/fusion-pixel-font .

## Bundled music

Ten Ogg Vorbis tracks by Miserable Faith / 痛仰乐队 are included: Ethereal, Highland, Jambo, Melody of the Rain, Mirage, Morning Espresso, Nightlife, Rosemary, Wandering and White Dew.

The project maintainer confirmed on 5 October 2026 that they have permission to include these songs in the public source package and community game builds. That confirmation is the basis for inclusion; an independent rights audit is not claimed. Rights in the compositions and recordings remain with their respective holders. The project's MIT license does not grant permission to extract, sell, sublicense, adapt or reuse the recordings separately or in another product. Contact the relevant rights holder before such use. No broader downstream media license is supplied here.

`assets/music/manifest.json` records track identities, source hashes, durations and included Ogg hashes. Original FLAC files are not included. `licenses/MEDIA-NOTICE.txt` repeats the distribution boundary.

## Startup movie

`assets/startup/intro.ogv` is a locally converted copy of the maintainer-supplied `Godot Effect.mp4`. The source movie is not included. No separate open-media license was recorded for this clip; it is excluded from the project's MIT grant. Do not assume permission for independent reuse. The maintainer should retain its provenance and permission evidence before publishing this review copy.

## Test fixtures and optional tools

The short audio fixtures under `tests/fixtures/` are generated sine tones, not commercial music. FFmpeg is an optional external tool and is not bundled. The Android SDK, Java, export templates and signing keys are also external build dependencies.
