# Local music playlist

The ten original FLAC files are retained privately by the maintainer and are not included in this repository. `manifest.json` records their filenames, byte sizes and SHA-256 hashes, plus the hashes of the local Ogg derivatives. No audio was uploaded during conversion.

Godot 4.6 imports WAV, Ogg Vorbis and MP3; FLAC is not a native import format. These tracks use **Ogg Vorbis, stereo, 48000 Hz**, with libvorbis nominal bitrate selected from each complete song's duration to target approximately **4 MB**. Embedded artwork and source metadata remain in the original FLAC files. [Godot audio import documentation](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_audio_samples.html), [FFmpeg libvorbis options](https://ffmpeg.org/ffmpeg-codecs.html#libvorbis).

Originals total **649,505,781 bytes**. Version 2 reduces the ten playable Ogg files from **82,520,639 to 38,382,813 bytes** (53.49% smaller). Each is within **3,000,000–5,000,000 bytes**; MB here uses decimal bytes. All songs retain their full source duration and stereo channels. There is no trimming, silence padding, or second-generation recompression: each is encoded directly from its original FLAC.

| Song | Previous bytes | Current bytes | Full duration (s) | Nominal kbps |
| --- | ---: | ---: | ---: | ---: |
| Ethereal | 8,781,377 | 3,782,760 | 381.56 | 83 |
| Highland | 10,157,646 | 3,921,845 | 450.28 | 71 |
| Jambo | 6,457,962 | 3,507,789 | 328.32 | 97 |
| Melody of the Rain | 8,388,566 | 3,835,481 | 339.71 | 93 |
| Mirage | 10,485,256 | 3,954,926 | 456.67 | 70 |
| Morning Espresso | 6,471,174 | 4,066,498 | 240.87 | 132 |
| Nightlife | 9,732,601 | 3,958,218 | 426.16 | 75 |
| Rosemary | 9,606,273 | 3,903,594 | 421.40 | 75 |
| Wandering | 6,341,607 | 3,536,456 | 289.63 | 110 |
| White Dew | 6,098,177 | 3,915,246 | 243.84 | 130 |

The playable Ogg files are already included. Recreating them from private lossless originals is a maintainer task and is not required for running, testing or exporting this repository.

`MusicPlayer` loads only the selected song using `ResourceLoader.CACHE_MODE_IGNORE`; playlist entries contain strings, not preloaded audio. The current compressed song and its playback buffers are resident; switching or destroying the player releases the previous stream. The playlist advances in manifest order, including wrapping at either end. End-of-song looping is handled by the player, with individual Ogg looping disabled.

For export, include `assets/music/manifest.json` as a non-resource file and export the Ogg resources. Keep the large source `BGM/` folder out of source-control staging and release bundles.

Playback checks:

```powershell
& $godot --headless --path . --script res://tests/test_music_player.gd
& $godot --path . --script res://tests/test_music_player.gd -- --audible
```

Historical validation before the English community build: after importing the compressed resources in Godot 4.6.2: **90/0 headless** and **91/0 actual Windows WASAPI audio**, both exiting cleanly without errors or leaked resources. These include the original 70 headless / 71 audible checks plus full-source duration and 3–5 MB assertions for every song. Tests decode PCM from all ten songs, observe playback advancing, exercise natural end-of-song playlist wrapping, verify pause/mute/background behavior and verify old/current stream release. A second preparation run reused all ten validated outputs and reverified unchanged source hashes. The lower bitrates are lossy; listening quality and device-specific audio remain user playtest items.

Paused startup and selecting a song while paused/backgrounded do not start playback; restoring focus or unpausing starts a pending song and resumes an already-playing paused song in place.


## Distribution notice

The maintainer confirmed permission to include these ten songs in this public source package and its game builds on 5 October 2026. The music is not covered by the game code's MIT license, and no separate downstream reuse or sublicensing permission is granted here. See ../../THIRD_PARTY_NOTICES.md and ../../licenses/MEDIA-NOTICE.txt.
