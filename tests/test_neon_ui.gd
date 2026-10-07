extends SceneTree
const Main = preload("res://scripts/main.gd")
const Lines = preload("res://scripts/night_lines.gd")
const TouchRange = preload("res://scripts/touch_slider.gd")
var checks := 0
var failures := 0
var app: Control
var existed := false
var backup := PackedByteArray()

class Probe extends Main:
	var saves := 0
	func _save_settings() -> void:
		saves += 1
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.level = 0
		music.paused = true
	func exercise_real_save() -> void:
		super._save_settings()
	func exercise_real_load() -> void:
		super._load_settings()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NEON_UI: " + label)

func _nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_nodes(child))
	return result

func _audit(label: String) -> void:
	var safe: Rect2 = app.safe_rect
	var canvas: Rect2 = app.canvas.get_global_rect()
	check(safe.grow(1).encloses(canvas), label + " canvas stays in safe area")
	check(canvas.get_area() / safe.get_area() > 0.97, label + " uses full available tall canvas")
	for node in _nodes(app):
		if node is Control and node.is_visible_in_tree() and (node is BaseButton or node is TouchRange or node is SpinBox):
			check(canvas.grow(1).encloses(node.get_global_rect()), label + " target inside canvas: " + str(node.name))
	for slot in app.seats:
		if slot.panel.is_visible_in_tree() and slot.badge.visible:
			check(not slot.name.get_rect().intersects(slot.badge.get_rect()), label + " role badge does not overlap player name")
			check(Rect2(Vector2.ZERO, slot.panel.size).encloses(slot.badge.get_rect()), label + " role badge fits seat")

func _idle(label: String) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 15000
	while (app.presentation_busy or app.input_locked or not app._presentation_queue.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	check(not app.presentation_busy and not app.input_locked and app._presentation_queue.is_empty(), label + " presentation settles")

func _resize(dimensions: Vector2i, profile: String) -> void:
	root.content_scale_size = dimensions
	root.size = Vector2i(Vector2(dimensions) * 0.60)
	app._set_preview_profile(profile, false)
	await process_frame
	await process_frame
	app._layout()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "user://neon_ui_%s.png" % label
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + label)
	print("NEON_CAPTURE " + ProjectSettings.globalize_path(path))

func _tap(control: Control) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = root.get_final_transform() * control.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	var release := event.duplicate() as InputEventScreenTouch
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func _run() -> void:
	existed = FileAccess.file_exists("user://settings.cfg")
	if existed: backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1280, 800)
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	check(app.player_count.value == 5, "home defaults to five total seats")
	check(app.music.tracks[app.music.index].title == "Nightlife", "fresh runtime defaults to Nightlife")
	app.music.language = "en"
	check(app.music.title() == "Miserable Faith — Nightlife", "English artist and default title are correct")
	var lines := Lines.new()
	for kind in ["home", "turn", "company"]:
		var count: int = Lines.COMPANY.size() if kind == "company" else (Lines.HOME.size() if kind == "home" else Lines.TURN.size())
		check(count == 10 if kind == "company" else count >= 20, kind + " has the requested number of original lines")
		var prior := -1
		for cycle in range(3):
			var seen: Dictionary = {}
			for draw in count:
				var selected := lines.next_index(kind)
				check(not seen.has(selected) and selected != prior, kind + " does not repeat within bag or across boundary")
				check(not lines.line(kind, selected, "zh").is_empty() and not lines.line(kind, selected, "en").is_empty(), kind + " has both languages")
				seen[selected] = true
				prior = selected
	for entry in [["kpad", Vector2i(1280, 800)], ["sqrt2", Vector2i(1080, 764)], ["free_tall", Vector2i(960, 850)], ["free_wide", Vector2i(1440, 720)]]:
		var key: String = entry[0]
		await _resize(entry[1], key if key in ["kpad", "sqrt2"] else "")
		_audit(key + " home")
		await _capture(key + "_home")
		for language in ["zh", "en"]:
			app._change_language(language)
			app._close_modal()
			app._show_play_settings()
			await process_frame
			_audit(key + " " + language + " AI settings")
			check(app.ai_slider.min_value == 0 and app.ai_slider.max_value == 10 and app.ai_slider.step == 1, "AI slider has eleven integer levels")
			app.ai_slider.value = 8
			app.ai_slider.user_changed.emit(8.0)
			check(app.session.ai_aggression == 8 and app.saves > 0, "AI setting reaches session and requests persistence")
			await _capture(key + "_" + language + "_settings")
			app._close_modal()
			app._show_tutorial()
			await process_frame
			_audit(key + " tutorial")
			await _capture(key + "_" + language + "_tutorial")
			app._close_modal()
	# Exercise the actual storage functions once, restoring the exact original
	# bytes below. Normal UI callbacks are intercepted by Probe.
	app.exercise_real_save()
	var saved := ConfigFile.new()
	check(saved.load("user://settings.cfg") == OK and saved.get_value("solo", "aggression", -1) == 8, "real config persists AI aggression")
	app.session.set_ai_aggression(1)
	app.exercise_real_load()
	check(app.session.ai_aggression == 8, "real settings reload restores AI aggression")
	app.feedback.volume = 0
	app.feedback.haptic_strength = 0
	app.music.level = 0
	app.music.paused = true
	app.session.start_local(["Long Player Name Alpha", "朋友乙", "Charlie", "Delta", "Echo"], 1000)
	app.session.begin_hand()
	await _idle("five seats dealt")
	for entry in [["kpad", Vector2i(1280, 800)], ["sqrt2", Vector2i(1080, 764)], ["free_tall", Vector2i(960, 850)]]:
		await _resize(entry[1], entry[0] if entry[0] != "free_tall" else "")
		_audit(entry[0] + " five seats")
		await _capture(entry[0] + "_table")
	app.session.set_local_seat(app.session.state.actor)
	await _idle("actor selected")
	var hand: int = app.session.state.hand_id
	var before_pot: int = app.session.state.pot
	app._call_or_check()
	await process_frame
	check(app.presentation_busy, "accepted call starts real chip transfer")
	var still_layout: Vector2 = app.chip_display.position
	await _resize(Vector2i(1280, 800), "kpad")
	check(app._layout_pending and app.chip_display.position == still_layout, "live resize preserves animation coordinates until landing")
	await _capture("resize_during_bet")
	await _idle("resize during betting")
	check(not app._layout_pending and app.session.state.hand_id == hand and app.session.state.pot > before_pot, "resize reflows after landing without replaying or losing bet")
	_audit("resized live table")
	# A real short heads-up hand reaches the direct settlement action.
	app._cancel_presentation()
	app.session.start_local(["Dealer Long Name", "Big Blind"], 1000)
	app.session.begin_hand()
	await _idle("heads-up dealt")
	_audit("heads-up names and badges")
	var dealer: int = app.session.state.dealer
	check(app.seats[dealer].badge.roles == ["D", "SB"], "heads-up dealer also shows small blind")
	await _capture("heads_up")
	app.session.set_local_seat(app.session.state.actor)
	await _idle("HU actor selected")
	app._act("fold")
	await _idle("settlement")
	check(app.session.state.phase == "showdown" and is_instance_valid(app.modal), "fold settles into direct result modal")
	var next: BaseButton
	for node in _nodes(app.modal):
		if node is BaseButton and ("NEXT HAND" in node.text or "下一手" in node.text): next = node
	check(is_instance_valid(next), "settlement contains direct next-hand action")
	_audit("settlement")
	await _capture("settlement_next_hand")
	var old_hand: int = app.session.state.hand_id
	if is_instance_valid(next):
		_tap(next)
		await _idle("next hand tap")
		check(app.session.state.hand_id == old_hand + 1 and not is_instance_valid(app.modal), "touching next hand deals directly and closes result modal")
	# Preserve production stretch configuration and change only the native window.
	# Changing content_scale_size above isolates layout; this catches outer black
	# bars or a fixed logical viewport masking real desktop resize events.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1440, 660)
	app._set_preview_profile("", false)
	for dimensions in [Vector2i(960, 600), Vector2i(900, 636)]:
		root.size = dimensions
		await process_frame
		await process_frame
		app._layout()
		var rendered: Rect2 = root.get_final_transform() * app.get_global_rect()
		var window_area := float(root.size.x * root.size.y)
		print("NEON_NATIVE_RESIZE window=%s logical=%s rendered=%s aspect=%s" % [root.size, app.size, rendered, root.content_scale_aspect])
		check(rendered.get_area() / window_area > 0.97, "production native window resize uses full surface without letterboxing")
		await _capture("production_window_%dx%d" % [dimensions.x, dimensions.y])
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	if existed:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		DirAccess.remove_absolute("user://settings.cfg")
	check(FileAccess.file_exists("user://settings.cfg") == existed and (not existed or FileAccess.get_file_as_bytes("user://settings.cfg") == backup), "original user settings restored byte-for-byte")
	print("NEON_UI_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
