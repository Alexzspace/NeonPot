class_name MusicPlayer
extends Node
## Sequential local playlist. Metadata stays resident; only the selected song is loaded.

signal changed()
signal import_busy_changed()
signal import_finished(imported: int, errors: Array[String])

const AudioConverter = preload("res://scripts/local_audio_converter.gd")
var converter: Node
var import_busy := false
var _batch_busy := false
var _shutting_down := false

var manifest_path := "res://assets/music/manifest.json"
var library_dir := "user://music"
const MAX_IMPORT_BYTES := 64 * 1024 * 1024
const MAX_LIBRARY_BYTES := 512 * 1024 * 1024
const MAX_IMPORTED_TRACKS := 100
var tracks: Array = []
const DEFAULT_TRACK := 6 # Nightlife, stable manifest order.
var index: int = DEFAULT_TRACK
var language := "zh"
var level: int = 3:
	set(value):
		level = clampi(value, 0, 10)
		_apply_volume()
var paused: bool = false:
	set(value):
		paused = value
		_apply_pause()
var last_error := ""
var _player: AudioStreamPlayer
var _application_paused := false
var _focused := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	converter = AudioConverter.new()
	add_child(converter)
	_player = AudioStreamPlayer.new()
	_player.name = "CurrentSong"
	_player.max_polyphony = 1
	add_child(_player)
	_player.finished.connect(_on_finished)
	_read_manifest()
	_read_library()
	_select_track(index)

func title() -> String:
	if tracks.is_empty() or index < 0 or index >= tracks.size():
		return ""
	var track: Dictionary = tracks[index]
	var artist := str(track.get("artist_en", track.get("artist", ""))) if language == "en" else str(track.get("artist", ""))
	var track_title := str(track.get("title", ""))
	return track_title if artist.is_empty() else artist + " — " + track_title

func set_level(value: int) -> void:
	level = value
	changed.emit()

func set_paused(value: bool) -> void:
	paused = value
	changed.emit()

func toggle_pause() -> void:
	set_paused(not paused)

func next_track() -> void:
	_select_track(index + 1)

func previous_track() -> void:
	_select_track(index - 1)

func select_track(value: int) -> void:
	_select_track(value)

func _read_manifest() -> void:
	tracks.clear()
	if manifest_path.is_empty():
		return
	if not FileAccess.file_exists(manifest_path):
		last_error = "Music manifest is unavailable."
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not data is Dictionary or not data.get("tracks", null) is Array:
		last_error = "Music manifest is invalid."
		return
	for entry in data.tracks:
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if path.begins_with("res://assets/music/") and path.get_extension().to_lower() == "ogg" and ResourceLoader.exists(path):
			# Keep strings only. Never preload AudioStreams into playlist metadata.
			tracks.append({"path": path, "title": str(entry.get("title", path.get_file().get_basename())), "artist": str(entry.get("artist", "")), "artist_en": str(entry.get("artist_en", entry.get("artist", "")))})

func _select_track(requested: int) -> void:
	if not is_instance_valid(_player):
		index = requested
		return
	_player.stop()
	_player.stream = null
	if tracks.is_empty():
		index = 0
		changed.emit()
		return
	index = posmod(requested, tracks.size())
	var path := str(tracks[index].path)
	var stream: AudioStream = _load_audio(path) if tracks[index].get("imported", false) else ResourceLoader.load(path, "AudioStreamOggVorbis", ResourceLoader.CACHE_MODE_IGNORE)
	if stream == null:
		last_error = "This music track could not be decoded."
		changed.emit()
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	else:
		stream.set("loop", false)
	_player.stream = stream
	_apply_volume()
	_apply_pause()
	last_error = ""
	changed.emit()

func _apply_volume() -> void:
	if is_instance_valid(_player):
		# Low background listening levels leave headroom for physical table sounds.
		_player.volume_db = -80.0 if level == 0 else lerpf(-34.0, -6.0, float(level - 1) / 9.0)

func _apply_pause() -> void:
	if not is_instance_valid(_player):
		return
	var should_pause := paused or _application_paused or not _focused
	_player.stream_paused = should_pause
	# A newly selected paused song must never enter the audio mixer, even briefly.
	# Existing paused playback resumes in place; a stopped selected song starts here.
	if not should_pause and _player.stream != null and not _player.playing:
		_apply_volume()
		_player.play()

func _on_finished() -> void:
	next_track()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_application_paused = true
		NOTIFICATION_APPLICATION_RESUMED:
			_application_paused = false
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
		_:
			return
	_apply_pause()

func shutdown() -> void:
	_shutting_down = true
	if is_instance_valid(converter): converter.cancel()
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null

func _exit_tree() -> void:
	shutdown()

func import_track(source: String) -> bool:
	var extension := source.get_extension().to_lower()
	if extension not in ["mp3", "ogg", "wav"]:
		return _fail("format")
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _fail("read")
	var length := file.get_length()
	if length < 12 or length > MAX_IMPORT_BYTES:
		return _fail("size")
	var total := 0
	var count := 0
	for track in tracks:
		if track.get("imported", false):
			count += 1
			total += int(track.get("bytes", 0))
	if count >= MAX_IMPORTED_TRACKS or total + length > MAX_LIBRARY_BYTES:
		return _fail("capacity")
	var bytes := file.get_buffer(length)
	file.close()
	if not _has_audio_header(bytes, extension):
		return _fail("decode")
	var stream := _decode_audio(bytes, extension)
	if stream == null or stream.get_length() <= 0.0 or stream.get_length() > 1800.0:
		return _fail("decode")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var filename := digest.finish().hex_encode() + "." + extension
	var destination := library_dir.path_join(filename)
	for track in tracks:
		if track.path == destination:
			return _fail("duplicate")
	if DirAccess.make_dir_recursive_absolute(library_dir) != OK:
		return _fail("write")
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return _fail("write")
	output.store_buffer(bytes)
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		DirAccess.remove_absolute(destination)
		return _fail("write")
	tracks.append({"path": destination, "title": source.get_file().get_basename().left(100), "artist": "", "artist_en": "", "imported": true, "bytes": length})
	if not _save_library():
		tracks.pop_back()
		DirAccess.remove_absolute(destination)
		return _fail("write")
	last_error = ""
	changed.emit()
	return true

func flac_available() -> bool:
	return is_instance_valid(converter) and not converter.executable().is_empty()

func import_files(paths: PackedStringArray) -> void:
	# Keep the coroutine on the persistent player, so closing the library is safe.
	if _batch_busy or import_busy or _shutting_down: return
	_batch_busy = true
	import_busy_changed.emit()
	var imported := 0
	var errors: Array[String] = []
	for source in paths:
		if _shutting_down: break
		var success: bool = await import_flac(source) if source.get_extension().to_lower() == "flac" else import_track(source)
		if success: imported += 1
		else: errors.append(source.get_file() + ": " + error_text())
	_batch_busy = false
	import_busy_changed.emit()
	import_finished.emit(imported, errors)

func import_flac(source: String) -> bool:
	if import_busy or _shutting_down: return _fail("flac_busy")
	if not flac_available(): return _fail("flac_unavailable")
	if source.get_extension().to_lower() != "flac": return _fail("format")
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return _fail("read")
	var length := file.get_length()
	if length < 42 or length > MAX_IMPORT_BYTES: return _fail("size")
	var bytes := file.get_buffer(length)
	file.close()
	# FLAC must begin with its mandatory 34-byte STREAMINFO block. Duration is
	# checked before conversion and against the result; never trim long sources.
	if bytes.slice(0, 4).get_string_from_ascii() != "fLaC" or (bytes[4] & 127) != 0 or bytes[5] != 0 or bytes[6] != 0 or bytes[7] != 34:
		return _fail("decode")
	var rate := (int(bytes[18]) << 12) | (int(bytes[19]) << 4) | (int(bytes[20]) >> 4)
	var samples := ((int(bytes[21]) & 15) << 32) | (int(bytes[22]) << 24) | (int(bytes[23]) << 16) | (int(bytes[24]) << 8) | int(bytes[25])
	var duration := float(samples) / float(maxi(1, rate))
	if rate <= 0 or duration <= 0.0 or duration > 1800.0: return _fail("decode")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var filename := digest.finish().hex_encode() + ".ogg"
	var destination := library_dir.path_join(filename)
	var imported_count := 0
	for track in tracks:
		if track.path == destination: return _fail("duplicate")
		if track.get("imported", false): imported_count += 1
	if imported_count >= MAX_IMPORTED_TRACKS: return _fail("capacity")
	if DirAccess.make_dir_recursive_absolute(library_dir) != OK: return _fail("write")
	var temporary := library_dir.path_join(".flac-import-" + str(Time.get_ticks_usec()) + ".ogg")
	import_busy = true
	last_error = ""
	import_busy_changed.emit()
	var success: bool = converter.start(source, temporary)
	if success: success = await converter.completed
	var error: String = converter.last_error
	if success and FileAccess.get_sha256(source) != filename.get_basename():
		success = false
		error = "read"
	if success:
		var stream := _load_audio(temporary)
		if stream == null or absf(stream.get_length() - duration) > 0.15:
			success = false
			error = "decode"
	if success:
		var result_file := FileAccess.open(temporary, FileAccess.READ)
		var result_length := result_file.get_length() if result_file != null else 0
		if result_file != null: result_file.close()
		var total := 0
		var count := 0
		for track in tracks:
			if track.get("imported", false):
				count += 1
				total += int(track.get("bytes", 0))
		if result_length < 12 or result_length > MAX_IMPORT_BYTES:
			success = false
			error = "size"
		elif count >= MAX_IMPORTED_TRACKS or total + result_length > MAX_LIBRARY_BYTES:
			success = false
			error = "capacity"
		elif DirAccess.rename_absolute(temporary, destination) != OK:
			success = false
			error = "write"
		else:
			tracks.append({"path": destination, "title": source.get_file().get_basename().left(100), "artist": "", "artist_en": "", "imported": true, "bytes": result_length})
			if not _save_library():
				tracks.pop_back()
				DirAccess.remove_absolute(destination)
				success = false
				error = "write"
	converter.cleanup()
	import_busy = false
	last_error = "" if success else error
	import_busy_changed.emit()
	changed.emit()
	return success

func remove_imported_track(track_index: int) -> bool:
	if track_index < 0 or track_index >= tracks.size() or not tracks[track_index].get("imported", false):
		return _fail("remove")
	var removed: Dictionary = tracks[track_index]
	if not _safe_library_name(str(removed.path).get_file()) or str(removed.path).get_base_dir() != library_dir:
		return _fail("remove")
	tracks.remove_at(track_index)
	if not _save_library():
		tracks.insert(track_index, removed)
		return _fail("write")
	if track_index == index:
		_select_track(index)
	elif track_index < index:
		index -= 1
	var error := DirAccess.remove_absolute(str(removed.path))
	if error != OK and error != ERR_DOES_NOT_EXIST:
		return _fail("remove")
	last_error = ""
	changed.emit()
	return true

func error_text() -> String:
	var messages := {
		"flac_unavailable": ["这台设备未配置 FLAC 转换器；可导入 MP3、Ogg 或 WAV。", "FLAC conversion is unavailable on this device. Import MP3, Ogg or WAV."],
		"flac_convert": ["FLAC 转换失败，原文件未修改。", "FLAC conversion failed. Your original is unchanged."],
		"flac_timeout": ["FLAC 转换超时，已停止。原文件未修改。", "FLAC conversion timed out and stopped. Your original is unchanged."],
		"flac_cancelled": ["FLAC 导入已取消。", "FLAC import cancelled."],
		"flac_busy": ["请等待当前音乐导入完成。", "Wait for the current music import to finish."],
		"format": ["支持 MP3、Ogg Vorbis 和 WAV。", "Choose MP3, Ogg Vorbis or WAV."],
		"read": ["无法读取文件，请重新选择。", "Cannot read the file. Please select it again."],
		"size": ["文件需小于 64 MB，且不是空文件。", "Choose a non-empty file up to 64 MB."],
		"capacity": ["音乐库已达上限：100 首或 512 MB。", "Library limit: 100 tracks or 512 MB."],
		"decode": ["无法解码，或曲目超过 30 分钟。", "Cannot decode this track, or it exceeds 30 minutes."],
		"duplicate": ["这首音乐已在库中。", "This track is already in your library."],
		"write": ["无法保存音乐库，请检查可用空间。", "Cannot save the library. Check free storage."],
		"remove": ["无法移除这首曲目。", "Cannot remove this track."]}
	return str(messages[last_error][1 if language == "en" else 0]) if messages.has(last_error) else last_error

func _fail(code: String) -> bool:
	last_error = code
	changed.emit()
	return false

func _safe_library_name(filename: String) -> bool:
	if filename != filename.get_file() or filename.get_extension() not in ["mp3", "ogg", "wav"]:
		return false
	var hash_part := filename.get_basename()
	return hash_part.length() == 64 and hash_part.is_valid_hex_number(false)

func _read_library() -> void:
	var path := library_dir.path_join("library.json")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 128 * 1024:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Array:
		return
	var seen: Dictionary = {}
	for entry in data.slice(0, MAX_IMPORTED_TRACKS):
		if not entry is Dictionary:
			continue
		var filename := str(entry.get("file", ""))
		var audio_path := library_dir.path_join(filename)
		if not _safe_library_name(filename) or seen.has(filename) or not FileAccess.file_exists(audio_path):
			continue
		var audio_file := FileAccess.open(audio_path, FileAccess.READ)
		if audio_file == null or audio_file.get_length() > MAX_IMPORT_BYTES:
			continue
		seen[filename] = true
		tracks.append({"path": audio_path, "title": str(entry.get("title", "Local music")).left(100), "artist": "", "artist_en": "", "imported": true, "bytes": audio_file.get_length()})

func _save_library() -> bool:
	var entries: Array = []
	for track in tracks:
		if track.get("imported", false):
			entries.append({"file": str(track.path).get_file(), "title": track.title})
	var temporary := library_dir.path_join("library.json.tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(entries))
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(temporary, library_dir.path_join("library.json")) == OK

func _has_audio_header(bytes: PackedByteArray, extension: String) -> bool:
	if bytes.size() < 12:
		return false
	match extension:
		"wav": return bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE"
		"ogg": return bytes.slice(0, 4).get_string_from_ascii() == "OggS"
		"mp3": return bytes.slice(0, 3).get_string_from_ascii() == "ID3" or (bytes[0] == 255 and bytes[1] & 224 == 224)
	return false

func _decode_audio(bytes: PackedByteArray, extension: String) -> AudioStream:
	match extension:
		"mp3": return AudioStreamMP3.load_from_buffer(bytes)
		"ogg": return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav": return AudioStreamWAV.load_from_buffer(bytes)
	return null

func _load_audio(path: String) -> AudioStream:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_IMPORT_BYTES:
		return null
	var bytes := file.get_buffer(file.get_length())
	if not _has_audio_header(bytes, path.get_extension()):
		return null
	return _decode_audio(bytes, path.get_extension())
