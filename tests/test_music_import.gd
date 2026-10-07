extends SceneTree

const Music = preload("res://scripts/music_player.gd")
const Library = preload("res://scripts/music_library_view.gd")
var checks := 0
var failures := 0
var directory := "user://test_music_import_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var source := directory.path_join("fixture.wav")
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(44100)
	for i in 22050:
		data.encode_s16(i * 2, int(sin(float(i) * TAU * 440.0 / 22050.0) * 1000))
	sample.data = data
	check(sample.save_to_wav(source) == OK, "Creates real PCM audio fixture")
	var music := Music.new()
	music.library_dir = directory.path_join("library")
	music.manifest_path = ""
	music.paused = true
	root.add_child(music)
	await process_frame
	check(not music.import_track(directory.path_join("missing.wav")), "Missing file rejected")
	check(not music.import_track(source + ".exe"), "Unsupported format rejected")
	var invalid := FileAccess.open(directory.path_join("invalid.wav"), FileAccess.WRITE)
	invalid.store_string("This is not audio at all")
	invalid.close()
	check(not music.import_track(directory.path_join("invalid.wav")), "Invalid header rejected")
	check(music.import_track(source), "Valid WAV imports")
	check(music.tracks.size() == 1 and music.tracks[0].imported, "Metadata appended")
	var imported_path: String = music.tracks[0].path
	check(FileAccess.file_exists(imported_path) and imported_path != source, "Source copied into private library")
	check(not music.import_track(source) and music.tracks.size() == 1, "Duplicate import rejected")
	music.select_track(0)
	check(music._player.stream is AudioStreamWAV and not music._player.playing, "Imported WAV decodes and honors pause")
	music.set_paused(false)
	check(music._player.playing, "Imported audio enters real playback")
	var restored := Music.new()
	restored.library_dir = music.library_dir
	restored.manifest_path = ""
	restored.paused = true
	root.add_child(restored)
	await process_frame
	check(restored.tracks.size() == 1 and restored.tracks[0].title == "fixture", "Restart restores metadata and title")
	check(restored._player.stream is AudioStreamWAV, "Restored track decodes without resource import")
	var view := Library.new()
	view.music = music
	view.language = "en"
	root.add_child(view)
	await process_frame
	check(view._list.get_child_count() == 1, "Imported track rendered in library")
	view._play(0)
	check(not music.paused, "Library play action resumes selected track")
	view._remove(0)
	check(music.tracks.is_empty() and music._player.stream == null and not music._player.playing, "Removing current track stops and releases empty playlist")
	check(not FileAccess.file_exists(imported_path) and FileAccess.file_exists(source), "Removal deletes only owned copy")
	check(JSON.parse_string(FileAccess.get_file_as_string(music.library_dir.path_join("library.json"))) == [], "Removal persists")
	check(not music.remove_imported_track(0), "Invalid deletion rejected")
	music.tracks.append({"path": "res://assets/music/10-white-dew.ogg", "title": "builtin"})
	check(not music.remove_imported_track(0), "Built-in tracks cannot be removed")
	check(not music._safe_library_name("../outside.wav") and not music._safe_library_name("fixture.wav"), "Library filenames reject traversal and foreign paths")
	check(music.import_track("res://assets/music/10-white-dew.ogg"), "Real Ogg Vorbis imports without ResourceLoader")
	music.select_track(1)
	check(music._player.stream is AudioStreamOggVorbis and music._player.playing, "Imported Ogg enters playback")
	check(music.remove_imported_track(1) and music.index == 0, "Removing active imported track selects remaining builtin index")
	check(music.import_track("res://tests/fixtures/import-tone.mp3"), "Real generated MP3 imports")
	music.select_track(1)
	check(music._player.stream is AudioStreamMP3 and music._player.playing, "Imported MP3 decodes and plays")
	check(music.remove_imported_track(1), "MP3 private copy removed safely")
	view.queue_free()
	music.queue_free()
	restored.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	for filename in DirAccess.get_files_at(directory.path_join("library")):
		DirAccess.remove_absolute(directory.path_join("library").path_join(filename))
	DirAccess.remove_absolute(directory.path_join("library"))
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(directory.path_join("invalid.wav"))
	DirAccess.remove_absolute(directory)
	print("MUSIC_IMPORT_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
