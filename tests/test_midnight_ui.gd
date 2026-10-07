extends SceneTree
## Rendered background motion and active pixel-player / chip-view lifecycle regression.
const Scene = preload("res://scenes/main.tscn")
const Gestures = preload("res://scripts/chip_gestures.gd")
var checks := 0
var failures := 0
var app: Control
var settings_existed := false
var settings_backup := PackedByteArray()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIDNIGHT_UI: " + message)

func _idle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while (app.presentation_busy or app.input_locked or not app._presentation_queue.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not app.presentation_busy and not app.input_locked, "table presentation reaches idle")

func _wall_wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _save(image: Image, label: String) -> void:
	var path := "user://midnight_" + label + ".png"
	check(image.save_png(path) == OK, "save actual rendered " + label)
	print("MIDNIGHT_CAPTURE " + ProjectSettings.globalize_path(path))

func _run() -> void:
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	var silent := ConfigFile.new()
	silent.load("user://settings.cfg")
	silent.set_value("music", "paused", true)
	silent.set_value("music", "level", 0)
	silent.save("user://settings.cfg")
	root.size = Vector2i(1311, 603)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app._set_preview_profile("iphone", false)
	app.feedback.volume = 0.0
	app.feedback.haptic_strength = 0.0
	check(app._background_material is ShaderMaterial, "live application exposes its actual background material")
	check(not app.music._player.playing, "saved pause is respected before the mini player appears")
	if DisplayServer.get_name() != "headless":
		# Hide the foreground to isolate shader motion from cassette reels and chips.
		app.canvas.hide()
		app._background_material.set_shader_parameter("preview_time", 0.0)
		var first := await _render()
		var repeat := await _render()
		app._background_material.set_shader_parameter("preview_time", 2.0)
		var second := await _render()
		check(first.get_size() == root.size and second.get_size() == root.size, "comparison uses actual viewport pixels")
		var changed := 0
		var samples := 0
		var difference := 0.0
		var repeat_difference := 0.0
		for y in range(8, first.get_height(), 16):
			for x in range(8, first.get_width(), 16):
				var a := first.get_pixel(x, y)
				var b := second.get_pixel(x, y)
				var same := repeat.get_pixel(x, y)
				var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				difference += delta
				repeat_difference += absf(a.r - same.r) + absf(a.g - same.g) + absf(a.b - same.b)
				changed += 1 if delta > 0.01 else 0
				samples += 1
		check(repeat_difference / samples < 0.001, "fixed preview time produces stable pixels")
		check(float(changed) / samples > 0.25 and difference / samples > 0.01, "time 0 to 2 visibly changes the rendered background")
		print("MIDNIGHT_SHADER_PIXELS samples=%d changed=%d mean_rgb_delta=%.5f repeat_delta=%.5f" % [samples, changed, difference / samples, repeat_difference / samples])
		_save(first, "background_t0")
		_save(second, "background_t2")
		app._background_material.set_shader_parameter("preview_time", -1.0)
		app.canvas.show()
	else:
		print("MIDNIGHT_SHADER_PIXELS skipped=headless; run graphically for pixel verification")
	app.session.start_local(["Alice", "Bob", "Charlie"], 1000)
	app.session.begin_hand()
	await _idle()
	var own: int = app.shown_state.you
	var opponent := (own + 1) % 3
	var original: Dictionary = app.session.state.duplicate(true)
	app._on_chip_gesture(own, 101, Gestures.NORMAL.SCATTER)
	check(app.chip_display._flourish_style == Gestures.NORMAL.SCATTER, "own gesture starts exact selected style")
	check(not app.has_method("_show_observer"), "obsolete observer replay removed")
	app._on_chip_gesture(opponent, 102, Gestures.RARE)
	var completed_opponent: WeakRef = weakref(app._fidget_nodes[opponent])
	await _wall_wait(Gestures.duration(Gestures.RARE) + 0.45)
	check(completed_opponent.get_ref() == null, "remote rare gesture expires after its shared duration and fade")
	check(app.session.state == original, "cosmetic presentation leaves poker state unchanged")
	app._show_settings()
	var deck_ref: WeakRef = weakref(app.music_pause_button.get_parent())
	# Destroy all presentation paths while they are still running.
	app._on_chip_gesture(own, 103, Gestures.RARE)
	app._on_chip_gesture(opponent, 104, Gestures.RARE)
	app.music.set_paused(false)
	var app_ref: WeakRef = weakref(app)
	var remote_ref: WeakRef = weakref(app._fidget_nodes[opponent])
	var song_ref: WeakRef = weakref(app.music._player.stream)
	var material_ref: WeakRef = weakref(app._background_material)
	app.queue_free()
	await process_frame
	await _wall_wait(0.25)
	for reference in [app_ref, remote_ref, deck_ref, song_ref, material_ref]:
		check(reference.get_ref() == null, "destroying active UI releases scene, animation, music and shader resources")
	if settings_existed:
		var settings_file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		settings_file.store_buffer(settings_backup)
		settings_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	check(FileAccess.file_exists("user://settings.cfg") == settings_existed, "original settings-file presence is restored")
	if settings_existed:
		check(FileAccess.get_file_as_bytes("user://settings.cfg") == settings_backup, "original settings bytes are restored exactly")
	print("MIDNIGHT_UI_SUMMARY checks=%d failures=%d renderer=%s" % [checks, failures, DisplayServer.get_name()])
	quit(1 if failures else 0)
