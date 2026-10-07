extends SceneTree
const Main = preload("res://scripts/main.gd")
const PROFILES := {"iphone": Vector2i(2622, 1206), "android": Vector2i(2400, 1080), "kpad": Vector2i(2560, 1600), "sqrt2": Vector2i(2160, 1527)}
var checks := 0
var failures := 0
var app: Control
var only := ""

class Probe extends Main:
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.level = 0
		music.paused = true
	func _save_settings() -> void:
		pass

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TABLE_TYPE: " + label)

func _idle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	await process_frame
	while (app.presentation_busy or app.input_locked or not app._presentation_queue.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	check(not app.presentation_busy and not app.input_locked, "presentation settles before typography checks")

func _text_rect(label: Label) -> Rect2:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var ink := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var local := Rect2(Vector2(0, (label.size.y - ink.y) * 0.5), Vector2(minf(ink.x, label.size.x), ink.y))
	return label.get_global_transform() * local

func _check_layout(stage: String) -> void:
	var safe: Rect2 = app.safe_rect
	var title := _text_rect(app.title_label)
	var hand := _text_rect(app.hand_label)
	var room := _text_rect(app.room_info)
	check(safe.grow(1).encloses(app.canvas.get_global_rect()), stage + " canvas stays inside safe area")
	check(title.end.x < hand.position.x and hand.end.x < room.position.x, stage + " title, hand and room form a separated inline sequence")
	check(app.title_label.get_theme_font_size("font_size") > app.hand_label.get_theme_font_size("font_size") and app.hand_label.get_theme_font_size("font_size") >= app.room_info.get_theme_font_size("font_size"), stage + " metadata is visually subordinate to title")
	for child in app.canvas.get_children():
		if child is Button and child.visible and child.position.x >= 1002:
			check(not title.intersects(child.get_global_rect()) and not hand.intersects(child.get_global_rect()) and not room.intersects(child.get_global_rect()), stage + " header text leaves both header buttons clear")
	check(app.room_info.position.x + app.room_info.size.x <= 976.1, stage + " room field reserves gap before x1002 header controls")
	check(app.pot_label.get_parent() == app.pot_panel, stage + " pot caption belongs to receiving panel")
	check(app.pot_label.position.x >= 12 and app.pot_label.position.x <= 24 and app.pot_label.position.y <= 12, stage + " pot caption is inset at panel top-left")
	check(app.pot_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, stage + " pot caption is left aligned")
	check(app.pot_label.get_theme_color("font_color") == app.balance_label.get_theme_color("font_color") and app.pot_label.get_theme_color("font_color") == Main.GOLD, stage + " pot and own stack share gold accent")
	check(app.pot_panel.get_global_rect().grow(1).encloses(app.pot_display.get_global_rect()), stage + " pot viewport stays inside receiving panel")
	check(app.pot_label.z_index + app.pot_panel.z_index > app.pot_display.z_index, stage + " pot caption draws above chips without an empty masking band")
	var fits := true
	for chip in app.pot_display._chip_nodes:
		for vertex in chip.mesh.get_faces():
			var pixel: Vector2 = app.pot_display._camera.unproject_position(chip.global_transform * vertex)
			var local: Vector2 = pixel / Vector2(app.pot_display.viewport_3d.size) * app.pot_display.size
			var global: Vector2 = app.pot_display.get_global_transform() * local
			fits = fits and app.pot_panel.get_global_rect().has_point(global)
	check(fits, stage + " actual pot chip geometry stays inside panel frame")
	check(app.phase_label.position.x < app.board_cards[0].position.x, stage + " phase caption is at table left")
	for card in app.deck_cards:
		check(not app.phase_label.get_global_rect().intersects(card.get_global_rect()), stage + " phase does not overlap deck")
	for slot in app.seats:
		check(slot.panel.visible, stage + " six player seats visible")
		if slot.badge.visible:
			check(not slot.name.get_global_rect().intersects(slot.badge.get_global_rect()), stage + " six-seat badge does not cover name")
	for label in [app.pot_label, app.hand_label, app.room_info, app.phase_label]:
		check(safe.grow(1).encloses(label.get_global_rect()), stage + " table metadata fits safe area")

func _run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var settings_bytes := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = PROFILES.iphone
	root.size = Vector2i(1311, 603)
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	if not is_instance_valid(app.title_label) or not is_instance_valid(app.pot_panel):
		check(false, "main scene initializes all typography controls")
		app.queue_free()
		await process_frame
		print("TABLE_TYPOGRAPHY_SUMMARY checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	app.session.start_local(["长姓名玩家甲", "MIX Flip", "K Pad", "Delta", "朋友戊", "Neon Player"], 1000)
	app.session.begin_hand()
	await _idle()
	for action_index in 6:
		if app.session.state.phase != "preflop": break
		app.session.set_local_seat(app.session.state.actor)
		app.session.submit_action("call" if app.session.state.legal.get("call", false) else "check")
		await _idle()
	app.session.set_local_seat(0)
	await _idle()
	check(app.session.state.phase == "flop" and app.session.state.board.size() == 3, "six-player fixture reaches real flop for visible board typography")
	for profile in PROFILES:
		if not only.is_empty() and profile != only: continue
		root.content_scale_size = PROFILES[profile]
		root.size = Vector2i(Vector2(PROFILES[profile]) * (0.38 if profile in ["kpad", "sqrt2"] else 0.5))
		app._set_preview_profile(profile, false)
		await process_frame
		await process_frame
		for language in ["zh", "en"]:
			app.language = language
			app._build_ui()
			await _idle()
			_check_layout(profile + " " + language)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var path := "user://table_typography_%s_%s.png" % [profile, language]
				check(root.get_texture().get_image().save_png(path) == OK, "save actual typography evidence")
				print("TABLE_TYPE_CAPTURE " + ProjectSettings.globalize_path(path))
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	check(FileAccess.file_exists("user://settings.cfg") == had_settings and (not had_settings or FileAccess.get_file_as_bytes("user://settings.cfg") == settings_bytes), "read-only test leaves user settings byte-identical")
	print("TABLE_TYPOGRAPHY_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
