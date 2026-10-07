extends SceneTree
const Main = preload("res://scripts/main.gd")
const Themes = preload("res://scripts/card_themes.gd")
const Workshop = preload("res://scripts/deck_workshop.gd")
const Art = preload("res://scripts/kaleidoscope_art.gd")
var checks := 0
var failures := 0
class Probe extends Main:
	func _load_settings() -> void:
		Themes.custom_recipe = {}
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func reload_preferences() -> void: super._load_settings()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("KALEIDOSCOPE_INTEGRATION: " + message)
func screen_point(control: Control, local: Vector2) -> Vector2:
	return root.get_final_transform() * (control.get_global_transform_with_canvas() * local)
func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
func draw_stroke(control: Control) -> void:
	var start := screen_point(control, control.size * Vector2(0.94, 0.06))
	await touch(start, true)
	var previous := start
	for i in range(1, 9):
		var point := screen_point(control, control.size * Vector2(0.94 + i * 0.004, 0.06 + i * 0.014))
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = point
		event.relative = point - previous
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		previous = point
		await process_frame
	await touch(previous, false)
func tap(control: Control) -> void:
	var point := screen_point(control, control.size * 0.5)
	await touch(point, true)
	await touch(point, false)
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test-results/kaleidoscope-" + label + ".png") == OK, "capture " + label)
func run() -> void:
	root.size = Vector2i(1440, 660)
	var app := Probe.new()
	app.settings_path = "user://kaleidoscope-integration-" + str(Time.get_ticks_usec()) + ".cfg"
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	await process_frame
	for lang in ["zh", "en"]:
		app.language = lang
		app._show_deck_workshop()
		await process_frame
		var panel: Control = app.modal
		await tap(panel.clear_button)
		check(not panel.recipe.motif_enabled and Art.geometry(panel.recipe).is_empty(), "Clear removes motif and all hand strokes")
		await tap(panel.apply_button)
		Themes.custom_recipe = {}
		app.reload_preferences()
		app._show_deck_workshop()
		await process_frame
		panel = app.modal
		check(not panel.recipe.motif_enabled and Art.geometry(panel.recipe).is_empty(), "blank design survives Apply, reload and reopening")
		await capture("blank-" + lang)
		var before: Dictionary = Themes.custom_recipe.duplicate(true)
		await draw_stroke(panel.drawing_canvas)
		check(panel.recipe.strokes.size() == 1, "native routed stroke reaches draft")
		var corner: Array = panel.recipe.strokes[0].points[0]
		check(corner[0] > 0.85 and corner[1] < -0.85, "rectangle corner is not projected onto a circle")
		check(Themes.custom_recipe == before, "touch art cannot mutate active deck before Apply")
		await tap(panel.undo_button)
		check(panel.recipe.strokes.is_empty(), "native Undo removes last draft stroke")
		check(Art.geometry(panel.recipe).is_empty(), "Undo in pure hand drawing returns to blank")
		await draw_stroke(panel.drawing_canvas)
		var draft: Dictionary = Themes.sanitize_recipe(panel.recipe)
		await capture(lang)
		await tap(panel.palette_button)
		check(panel.palette_buttons.size() == 16, "native shortcut exposes fixed palette")
		await capture("palette-" + lang)
		await tap(panel.apply_button)
		check(not app.modal is Workshop and Themes.custom_recipe == draft, "native Apply saves drawn recipe")
		Themes.custom_recipe = {}
		app.reload_preferences()
		check(Themes.custom_recipe == draft, "drawn points and symmetry survive real ConfigFile roundtrip")
	app._show_deck_workshop()
	await process_frame
	root.size = Vector2i(2160, 1527)
	await process_frame
	check(app.modal.drawing_canvas.size.x > 200, "drawing workspace survives tall resize")
	root.go_back_requested.emit()
	await process_frame
	check(app.modal == null, "Back clears workshop lifecycle")
	app._close_modal()
	DirAccess.remove_absolute(app.settings_path)
	app.queue_free()
	await process_frame
	await process_frame
	Themes.custom_recipe = {}
	print("KALEIDOSCOPE_INTEGRATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
