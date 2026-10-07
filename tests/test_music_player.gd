extends SceneTree

const Music = preload("res://scripts/music_player.gd")
var checks := 0
var failures := 0
var changes := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _check_decoder(track: Dictionary) -> void:
	var stream := ResourceLoader.load(str(track.path), "AudioStreamOggVorbis", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamOggVorbis
	check(stream != null and stream.get_length() > 1.0, "Godot loads complete song: " + str(track.title))
	if stream == null:
		return
	var source_duration := float(track.source_duration_seconds)
	check(absf(stream.get_length() - source_duration) <= 0.10, "Compressed song retains full source duration: " + str(track.title))
	var compressed_file := FileAccess.open(str(track.path), FileAccess.READ)
	check(compressed_file != null and compressed_file.get_length() >= 3000000 and compressed_file.get_length() <= 5000000, "Complete compressed song is within 3-5 MB: " + str(track.title))
	var playback := stream.instantiate_playback()
	playback.start(minf(10.0, stream.get_length() * 0.5))
	var frames := playback.mix_audio(1.0, 4096)
	var energy := 0.0
	var finite := true
	for frame in frames:
		energy += frame.length_squared()
		finite = finite and is_finite(frame.x) and is_finite(frame.y)
	check(frames.size() > 0 and finite and energy > 0.0001, "Vorbis decodes finite audible stereo samples: " + str(track.title))
	playback.stop()

func _run() -> void:
	var music := Music.new()
	music.level = 0
	music.index = 9
	music.paused = true
	music.changed.connect(func() -> void: changes += 1)
	root.add_child(music)
	await process_frame
	check(music.tracks.size() == 10, "Manifest contains all ten user songs")
	check(music.index == 9 and music.paused, "Persisted index and paused state apply before ready")
	check(not music._player.playing, "Preready user pause prevents playback from starting")
	check("White Dew" in music.title(), "Title uses manifest track metadata")
	check(music._player.volume_db <= -79.0, "Level zero mutes independently of pause")
	for track in music.tracks:
		check(track.path is String and not track.has("stream"), "Playlist metadata never retains decoded AudioStream")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(music.manifest_path))
	for track in manifest.tracks:
		_check_decoder(track)
	var previous_db := -81.0
	for volume in range(11):
		music.set_level(volume)
		check(music.level == volume and music._player.volume_db > previous_db, "Each volume step increases gain: %d" % volume)
		previous_db = music._player.volume_db
	music.set_level(-100)
	check(music.level == 0, "Negative music level clamps to mute")
	music.set_level(100)
	check(music.level == 10, "Oversized music level clamps to ten")
	music.set_level(0)
	music.next_track()
	check(music.index == 0 and music.paused, "Next wraps playlist and preserves pause")
	check(not music._player.playing, "Next while paused never starts the new song")
	music.previous_track()
	check(music.index == 9 and music.paused, "Previous wraps playlist and preserves pause")
	check(not music._player.playing, "Previous while paused never starts the new song")
	music.toggle_pause()
	check(not music.paused and not music._player.stream_paused, "Pause toggle resumes playback")
	check(music._player.playing, "Resuming starts a selected song that has never played")
	var progress_deadline := Time.get_ticks_msec() + 1500
	while music._player.get_playback_position() <= 0.05 and Time.get_ticks_msec() < progress_deadline:
		await process_frame
	check(music._player.playing and music._player.get_playback_position() > 0.05, "AudioStreamPlayer advances music: playing=%s position=%.4f paused=%s" % [music._player.playing, music._player.get_playback_position(), music._player.stream_paused])
	music.set_paused(true)
	var paused_position := music._player.get_playback_position()
	check(music._player.stream_paused, "Pausing existing playback suspends the stream")
	music.set_paused(false)
	check(music._player.playing and music._player.get_playback_position() >= paused_position, "Resuming existing playback preserves position")
	if "--audible" in OS.get_cmdline_user_args():
		music.set_level(3)
		music._player.seek(10.0)
		var peak := -100.0
		var audible_until := Time.get_ticks_msec() + 600
		while Time.get_ticks_msec() < audible_until:
			await process_frame
			peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(0, 0))
		check(peak > -75.0, "Audible music reaches the output bus (peak %.2f dB)" % peak)
		music.set_level(0)
	var old_stream: WeakRef = weakref(music._player.stream)
	music.next_track()
	await create_timer(0.2).timeout
	check(old_stream.get_ref() == null, "Changing songs releases the previous AudioStream")
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(music._player.stream_paused and not music.paused, "Losing focus suspends music without changing user pause")
	music.next_track()
	check(not music._player.playing, "Changing songs without focus never starts playback")
	music._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(music._application_paused and not music.paused, "Focus return preserves background suspension independently of user pause")
	check(not music._player.playing, "Focus return cannot start the background-selected song")
	music._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not music._player.stream_paused, "Foreground resumes music when user did not pause")
	check(music._player.playing, "Foreground starts the selected song when user did not pause")
	music.set_paused(true)
	music._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	music.next_track()
	music._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(music.paused, "Next in background and foreground return preserve user pause")
	check(not music._player.playing, "User pause prevents background-selected song starting on foreground return")
	music.set_paused(false)
	# Exercise the real finished signal by seeking to the end of the last song.
	music.select_track(9)
	music._player.seek(maxf(0.0, music._player.stream.get_length() - 0.04))
	var deadline := Time.get_ticks_msec() + 3000
	while music.index == 9 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(music.index == 0 and music._player.playing, "Natural song finish advances and loops the playlist")
	check(changes >= 18, "Controls and track transitions notify the UI")
	var weak_current: WeakRef = weakref(music._player.stream)
	music.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	check(weak_current.get_ref() == null, "Node shutdown releases current music resource")
	var empty := Music.new()
	empty.manifest_path = ""
	root.add_child(empty)
	empty.next_track()
	empty.previous_track()
	empty.toggle_pause()
	empty.set_level(0)
	check(empty.tracks.is_empty() and empty.title().is_empty() and empty._player.stream == null, "Empty playlist controls are safe")
	empty.queue_free()
	await process_frame
	print("MUSIC_TEST_SUMMARY checks=%d failures=%d driver=%s" % [checks, failures, AudioServer.get_driver_name()])
	quit(1 if failures else 0)
