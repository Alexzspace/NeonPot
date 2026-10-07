`import-tone.mp3` is a generated 440 Hz sine tone, 0.25 seconds at 22050 Hz,
encoded locally with FFmpeg libmp3lame at 32 kbit/s for runtime import tests.
It contains no third-party music and is excluded from product exports with tests/.

`import-tone.flac` is a generated 440 Hz sine tone, 2 seconds at 48000 Hz,
encoded locally with FFmpeg FLAC for the optional Windows import conversion tests.
It contains no third-party music. Tests copy it to a Chinese/spaced/apostrophe filename.
