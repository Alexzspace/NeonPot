extends SceneTree

const Music = preload("res://scripts/music_player.gd")
const Library = preload("res://scripts/music_library_view.gd")
var checks := 0
var failures := 0
var directory := "user://test_flac_import_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var source := directory.path_join("手绘 音乐's test.flac")
	check(DirAccess.copy_absolute("res://tests/fixtures/import-tone.flac", source) == OK, "Chinese spaced apostrophe fixture copied")
	var original_hash := FileAccess.get_sha256(source)
	var music := Music.new()
	music.library_dir = directory.path_join("library")
	music.manifest_path = ""
	music.paused = true
	root.add_child(music)
	await process_frame
	check(music.flac_available(), "Local Windows FFmpeg discovered")
	music.converter.executable_override = directory.path_join("missing-ffmpeg.exe")
	check(not await music.import_flac(source) and music.last_error == "flac_unavailable", "Missing converter fails clearly")
	music.converter.executable_override = ""
	var invalid_source := directory.path_join("invalid.flac")
	var invalid := FileAccess.open(invalid_source, FileAccess.WRITE)
	invalid.store_string("This is not a FLAC audio source...................................")
	invalid.close()
	check(not await music.import_flac(invalid_source) and music.last_error == "decode", "Invalid FLAC header rejected")
	var too_long := FileAccess.get_file_as_bytes(source)
	# STREAMINFO total samples = 48000 * 1801, just past the duration ceiling.
	var sample_count := 48000 * 1801
	too_long[21] = (too_long[21] & 240) | ((sample_count >> 32) & 15)
	for byte_index in 4:
		too_long[22 + byte_index] = (sample_count >> (24 - byte_index * 8)) & 255
	invalid = FileAccess.open(invalid_source, FileAccess.WRITE)
	invalid.store_buffer(too_long)
	invalid.close()
	check(not await music.import_flac(invalid_source) and music.last_error == "decode" and music.converter.pid == -1, "Overlong FLAC rejected before process launch without truncation")
	var heartbeat := [0]
	var tick := func(): heartbeat[0] += 1
	process_frame.connect(tick)
	check(await music.import_flac(source), "FLAC converts and imports asynchronously")
	process_frame.disconnect(tick)
	check(heartbeat[0] > 0, "Frames continue during conversion")
	check(not music.import_busy and music.converter.pid == -1, "Converter releases busy flag and process")
	check(music.tracks.size() == 1 and music.tracks[0].title == "手绘 音乐's test", "Original source title preserved")
	check(music.tracks[0].path.get_file() == original_hash + ".ogg", "Library identity uses original FLAC digest")
	check(FileAccess.get_sha256(source) == original_hash, "Original FLAC unchanged")
	check(not await music.import_flac(source) and music.last_error == "duplicate", "FLAC duplicate rejected without encoding")
	music.select_track(0)
	check(music._player.stream is AudioStreamOggVorbis and absf(music._player.stream.get_length() - 2.0) < 0.15, "Result decodes at complete source duration")
	music.set_paused(false)
	check(music._player.playing, "Converted FLAC enters actual player playback")
	check(music.remove_imported_track(0), "Remove converted copy")
	var view := Library.new()
	view.music = music
	root.add_child(view)
	await process_frame
	check("*.flac" in view._dialog.filters[0], "Available FLAC appears in picker")
	var result := [-1]
	music.import_finished.connect(func(count: int, _errors: Array[String]): result[0] = count)
	view._import_files(PackedStringArray([source]))
	check(view._import_button.disabled and music.import_busy, "Import disabled during async conversion")
	view.queue_free()
	while music.import_busy or music._batch_busy: await process_frame
	check(result[0] == 1 and music.tracks.size() == 1, "Import survives closing library")
	music.remove_imported_track(0)
	music.import_files(PackedStringArray([source]))
	var child_pid: int = music.converter.pid
	var temporary: String = music.converter.output_path
	check(child_pid > 0, "Cancellation test launches real helper")
	music.shutdown()
	await process_frame
	check(not OS.is_process_running(child_pid), "Shutdown terminates child")
	check(not FileAccess.file_exists(temporary) and not music.import_busy, "Shutdown removes temporary and completes coroutine")
	check(music.tracks.is_empty() and FileAccess.get_sha256(source) == original_hash, "Cancellation leaves original and library intact")
	music.queue_free()
	await process_frame
	var timeout_music := Music.new()
	timeout_music.library_dir = directory.path_join("library")
	timeout_music.manifest_path = ""
	root.add_child(timeout_music)
	timeout_music.converter.timeout_ms = -1
	check(not await timeout_music.import_flac(source) and timeout_music.last_error == "flac_timeout", "Bounded conversion timeout rejects partial output")
	check(DirAccess.get_files_at(timeout_music.library_dir) == PackedStringArray(["library.json"]), "No temporary remains after timeout")
	timeout_music.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for filename in DirAccess.get_files_at(directory.path_join("library")):
		DirAccess.remove_absolute(directory.path_join("library").path_join(filename))
	DirAccess.remove_absolute(directory.path_join("library"))
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(invalid_source)
	DirAccess.remove_absolute(directory)
	print("FLAC_IMPORT_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
