extends SceneTree
const Themes = preload("res://scripts/card_themes.gd")
const Workshop = preload("res://scripts/deck_workshop.gd")
const Art = preload("res://scripts/kaleidoscope_art.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WORKSHOP: " + message)
func touch(at: Vector2, pressed: bool = true) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 3
	event.pressed = pressed
	event.position = at
	return event
func stroke(panel: Control) -> void:
	panel.drawing_canvas._gui_input(touch(Vector2(280, 200)))
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(310, 245)
	panel.drawing_canvas._gui_input(drag)
	panel.drawing_canvas._input(touch(Vector2(1600, 900), false))
func _run() -> void:
	var original := Themes.custom_recipe.duplicate(true)
	var panel := Workshop.new()
	root.add_child(panel)
	check(panel.sliders.size() == 4 and panel.palette_buttons.size() == 16 and panel.preview_cards.size() == 2, "workshop controls")
	var base := Art.geometry(panel.recipe)
	stroke(panel)
	check(panel.recipe.strokes.size() == 1 and panel.recipe.strokes[0].points.size() == 2, "touch drawing commits normalized stroke")
	check(panel.drawing_canvas._finger == -1, "release outside ends pointer")
	check(Art.geometry(panel.recipe) != base, "hand drawing changes repeated geometry")
	var saved_strokes: Array = panel.recipe.strokes.duplicate(true)
	panel.randomize_recipe()
	check(panel.recipe.strokes == saved_strokes and Themes.custom_recipe == original, "randomization retains drawing and isolates draft")
	check(Themes.PALETTE.has(panel.recipe.paper) and Themes.PALETTE.has(panel.recipe.primary) and Themes.PALETTE.has(panel.recipe.accent), "random colors use fixed palette")
	panel.sector_buttons[2].pressed.emit()
	check(panel.recipe.segments == 6, "six fold shortcut")
	panel.sector_buttons[3].pressed.emit()
	check(panel.recipe.segments == 8, "eight fold shortcut")
	panel.sliders[2].user_changed.emit(77)
	check(panel.recipe.depth == 0.77, "layer depth slider")
	panel.mirror_button.button_pressed = false
	check(not panel.recipe.mirror, "rotation without reflection")
	panel.color_buttons[0].pressed.emit()
	panel.palette_buttons[7].pressed.emit()
	check(panel.recipe.paper == Themes.PALETTE[7], "role based fixed palette")
	panel.undo_button.pressed.emit()
	check(panel.recipe.strokes.is_empty(), "undo handstroke")
	panel.drawing_canvas._gui_input(touch(Vector2(290, 180)))
	panel.drawing_canvas._gui_input(touch(Vector2(290, 180), false))
	check(panel.recipe.strokes.size() == 1, "single tap persists")
	panel.drawing_canvas._gui_input(touch(Vector2(250, 200)))
	var second := touch(Vector2(200, 100))
	second.index = 7
	panel.drawing_canvas._gui_input(second)
	check(panel.drawing_canvas._finger == 3, "second finger cannot steal drawing")
	panel.drawing_canvas.hide()
	check(panel.drawing_canvas._finger == -1, "hidden canvas releases pointer")
	panel.drawing_canvas.show()
	panel.drawing_canvas._gui_input(touch(Vector2(280, 200)))
	panel.drawing_canvas._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(panel.drawing_canvas._finger == -1, "focus loss clears pointer")
	panel.drawing_canvas._gui_input(touch(Vector2(280, 200)))
	panel.set_available_height(980)
	check(panel._canvas.position.y == 160 and panel.drawing_canvas._finger == -1, "safe area resize clears pointer")
	panel.clear_button.pressed.emit()
	check(panel.recipe.strokes.is_empty() and not panel.recipe.motif_enabled and Art.geometry(panel.recipe).is_empty(), "clear removes motif and drawing")
	var applied: Array[Dictionary] = []
	panel.recipe_applied.connect(func(value: Dictionary): applied.append(value))
	panel.apply_button.pressed.emit()
	check(applied.size() == 1 and applied[0] == Themes.sanitize_recipe(panel.recipe), "apply sanitized recipe")
	panel.preset_button.pressed.emit()
	check(applied[1].is_empty(), "preset disables DIY")
	panel.language = "en"
	check(panel.apply_button.text == "APPLY & SAVE DECK" and panel.color_buttons[0].text == "PAPER", "English labels")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 660)
		panel.set_available_height(660)
		panel.recipe = Themes.default_recipe()
		panel._scroll.scroll_vertical = 0
		await process_frame
		await process_frame
		var before := root.get_texture().get_image()
		Input.parse_input_event(touch(Vector2(312, 340)))
		await process_frame
		var drag := InputEventScreenDrag.new()
		drag.index = 3
		drag.position = Vector2(342, 370)
		Input.parse_input_event(drag)
		await process_frame
		Input.parse_input_event(touch(Vector2(700, 600), false))
		await process_frame
		check(panel.recipe.strokes.size() == 1, "viewport real touch routes draw and outside release")
		await RenderingServer.frame_post_draw
		var after := root.get_texture().get_image()
		check(before.get_region(Rect2i(32,145,400,400)).get_data() != after.get_region(Rect2i(32,145,400,400)).get_data(), "mapped canvas pixels change")
		after.save_png("res://test-results/v140-kaleido-en.png")
		panel.language = "zh"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v140-kaleido-zh.png")
		panel.reveal_palette()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v140-kaleido-palette.png")
	panel.queue_free()
	await process_frame
	print("DECK_WORKSHOP checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
