extends SceneTree
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
var test_prefix := "user://language-defaults-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]

# Use Main's real settings loader and full UI initialization, but keep all
# persistent paths away from the player's preferences and imported music.
class IsolatedMain extends Main:
	func _load_settings() -> void:
		music.library_dir = settings_path + "-music"
		super._load_settings()
		feedback.volume = 0.0
		feedback.haptic_strength = 0.0
		music.set_level(0)
		music.set_paused(true)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LANGUAGE_DEFAULTS: " + message)

func start_app(path: String) -> Control:
	var app := IsolatedMain.new()
	check(app.language == "en", "Main initializes in English before settings load")
	app.settings_path = path
	app._night_lines._bags = {"home": [7], "company": [9]}
	app.animate_on_start = true
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	await process_frame
	app._cancel_home_entrance()
	check(app.music.library_dir == path + "-music", "imported music stays isolated")
	return app

func stop_app(app: Control) -> void:
	app._close_modal()
	app._cancel_home_entrance()
	app._cancel_presentation()
	app.music.shutdown()
	app.feedback.haptics.stop()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
	await process_frame

func check_home(app: Control, expected: String, label: String) -> void:
	check(app.language == expected, label + ": stored locale is valid")
	check(app.home.visible, label + ": actual home is visible")
	check(app.home_host_button.text == ("创建牌桌" if expected == "zh" else "HOST TABLE"), label + ": home action is localized")
	check(app.music.language == expected, label + ": music receives selected locale")

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func tap(control: Control) -> void:
	check(control != null, "native touch target exists")
	if control == null:
		return
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func check_saved(path: String, expected: String) -> void:
	var config := ConfigFile.new()
	check(config.load(path) == OK, "language change writes isolated settings")
	check(config.get_value("preferences", "language", "") == expected, "language choice persists as " + expected)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture-language" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test-results/language-en-" + label + ".png") == OK, "English " + label + " captured")

func check_copy_bounds(label: Label, width: float, height: float, lines: int, context: String) -> void:
	check(label.size.x <= width + 0.1 and label.size.y <= height + 0.1, context + ": label stays inside its allotted rectangle")
	check(label.get_line_count() <= lines and label.get_visible_line_count() == label.get_line_count(), context + ": all text fits in the intended lines")
	var glyphs_inside := true
	for index in label.text.length():
		var bounds := label.get_character_bounds(index)
		if bounds.has_area() and (bounds.position.x < -0.1 or bounds.end.x > width + 0.1 or bounds.end.y > height + 0.1):
			glyphs_inside = false
	check(glyphs_inside, context + ": rendered glyphs stay inside the allotted area")

func check_home_copy(app: Control) -> void:
	print("HOME_COPY_INITIAL rect=%s lines=%d base=%s" % [app._home_title_label.get_rect(), app._home_title_label.get_line_count(), app._home_title_label.get_meta("layout_base")])
	check_copy_bounds(app._home_title_label, 620, 104, 2, "fresh English startup")
	await capture("long-home")
	for viewport in [Vector2i(1440, 660), Vector2i(1311, 603), Vector2i(1200, 900)]:
		root.size = viewport
		await process_frame
		await process_frame
		for locale in ["en", "zh"]:
			app.language = locale
			for index in Main.NightLines.HOME.size():
				app._night_lines._bags = {"home": [index], "company": [index % Main.NightLines.COMPANY.size()]}
				app._return_home_if_uncovered()
				app._cancel_home_entrance()
				await process_frame
				check_copy_bounds(app._home_title_label, 620, 104, 2, "%s home %d at %s" % [locale, index, viewport])
				check_copy_bounds(app._home_company_label, 608, 48, 1, "%s company %d at %s" % [locale, index % Main.NightLines.COMPANY.size(), viewport])
	root.size = Vector2i(1440, 660)
	app.language = "en"
	app._night_lines._bags = {"home": [7], "company": [9]}
	app._return_home_if_uncovered()
	app._cancel_home_entrance()
	await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1440, 660)
	var cases := [
		{"name": "missing", "expected": "en"},
		{"name": "blank", "expected": "en"},
		{"name": "legacy", "expected": "en"},
		{"name": "saved-zh", "locale": "zh", "expected": "zh"},
		{"name": "saved-en", "locale": "en", "expected": "en"},
		{"name": "invalid", "locale": "unsupported-locale", "expected": "en"}
	]
	for entry in cases:
		var path := test_prefix + "-" + str(entry.name) + ".cfg"
		check(not FileAccess.file_exists(path), "new test settings path")
		if entry.name != "missing":
			var config := ConfigFile.new()
			if entry.name == "legacy":
				config.set_value("preferences", "frame_limit", 30)
			if entry.has("locale"):
				config.set_value("preferences", "language", entry.locale)
			check(config.save(path) == OK, "fixture settings saved")
		var app := await start_app(path)
		check_home(app, str(entry.expected), str(entry.name))
		if entry.name == "legacy":
			check(app.frame_limit == 30, "legacy unrelated preferences are respected")
		if entry.name == "missing":
			check(not FileAccess.file_exists(path), "first start does not require a saved preference")
			await check_home_copy(app)
			await capture("home")
			await tap(app.settings_button)
			check(app.modal != null, "native touch opens settings")
			await create_timer(0.25).timeout
			await capture("settings")
			await tap(find_button(app.modal, "简体中文"))
			check_home(app, "zh", "switch to Chinese")
			check_saved(path, "zh")
			await stop_app(app)
			app = await start_app(path)
			check_home(app, "zh", "restart keeps Chinese choice")
			await tap(app.settings_button)
			await create_timer(0.25).timeout
			await tap(find_button(app.modal, "ENGLISH"))
			check_home(app, "en", "switch back to English")
			check_saved(path, "en")
			await stop_app(app)
			app = await start_app(path)
			check_home(app, "en", "restart keeps English choice")
		await stop_app(app)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(path) == OK, "isolated settings cleaned up")
		check(not DirAccess.dir_exists_absolute(path + "-music"), "test does not create imported music")
	print("LANGUAGE_DEFAULTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
