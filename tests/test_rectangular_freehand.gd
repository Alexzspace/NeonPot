extends SceneTree
const Themes = preload("res://scripts/card_themes.gd")
const Art = preload("res://scripts/kaleidoscope_art.gd")
const Workshop = preload("res://scripts/deck_workshop.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RECTANGULAR_FREEHAND: " + message)
func _run() -> void:
	var panel := Workshop.new()
	root.add_child(panel)
	check(not panel.clear_button.disabled, "default motif can be cleared before drawing")
	panel.clear_button.pressed.emit()
	check(not panel.recipe.motif_enabled and Art.geometry(panel.recipe).is_empty(), "clear removes every motif including rim")
	panel.sliders[1].user_changed.emit(45)
	panel.palette_buttons[9].pressed.emit()
	panel.undo_button.pressed.emit()
	check(Art.geometry(panel.recipe).is_empty(), "sliders colors and undo never resurrect motif")
	panel.freehand_button.pressed.emit()
	var canvas: Control = panel.drawing_canvas
	canvas._begin(canvas.size * Vector2(0.96, 0.96), 1)
	canvas._append(canvas.size * Vector2(0.82, 0.91))
	canvas._finish()
	var p: Array = panel.recipe.strokes[0].points[0]
	check(Vector2(p[0], p[1]).distance_to(Vector2(0.92, 0.92)) < 0.001, "touch corner remains outside old circle")
	var geometry := Art.geometry(panel.recipe)
	check(geometry.size() == 1 and geometry[0].points.size() == 2, "pure freehand contains only original segment")
	check(geometry[0].points[0].distance_to(Vector2(0.92, 0.92)) < 0.001, "unmapped geometry preserves exact hand location")
	panel.undo_button.pressed.emit()
	check(Art.geometry(panel.recipe).is_empty(), "undo last handmade stroke returns blank")
	var saved: Array = []
	panel.recipe_applied.connect(func(value: Dictionary): saved.append(value))
	panel.apply_button.pressed.emit()
	check(not saved[0].is_empty() and not saved[0].motif_enabled, "blank applied as custom recipe not preset disable")
	var reopened := Workshop.new()
	reopened.recipe = JSON.parse_string(JSON.stringify(saved[0]))
	root.add_child(reopened)
	check(Art.geometry(reopened.recipe).is_empty(), "blank survives serialize and reopen")
	reopened.reset_button.pressed.emit()
	check(reopened.recipe.motif_enabled and not Art.geometry(reopened.recipe).is_empty(), "explicit default reload restores motif")
	reopened.clear_button.pressed.emit()
	reopened.motif_buttons[1].pressed.emit()
	check(reopened.recipe.motif_enabled and reopened.recipe.motif == 1, "explicit motif selection restores chosen motif")
	var old := Themes.sanitize_recipe({"version": 2, "strokes": [{"points": [[0.6, 0.7], [-0.3, 0.4]], "color": 1}]})
	check(old.version == 3 and old.motif_enabled and old.strokes[0].points.size() == 2 and Vector2(old.strokes[0].points[0][0], old.strokes[0].points[0][1]).distance_to(Vector2(0.6, 0.7)) < 0.00001, "legacy strokes migrate without data loss")
	var clipped := Art.clip_segment(Vector2(0.8, 0), Vector2(1.8, 0.5))
	check(clipped.size() == 2 and clipped[1].distance_to(Vector2(1, 0.1)) < 0.001, "clipping preserves crossing segment slope")
	check(Art.clip_segment(Vector2(2, 0), Vector2(2, 0.8)).is_empty(), "fully outside segment creates no border ink")
	for turns in [1, 2, 3, 6, 8, 12]:
		var recipe := Themes.default_recipe()
		recipe.motif_enabled = false
		recipe.segments = turns
		recipe.rotation = 37
		recipe.strokes = [{"points": [[-0.95, -0.95], [0.95, 0.95]], "color": 0}]
		var inside := true
		for group in Art.geometry(recipe):
			for point in group.points:
				inside = inside and absf(point.x) <= 1.00001 and absf(point.y) <= 1.00001
		check(inside, "rotated rectangle strokes clip for %d sectors" % turns)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1440, 660)
		reopened.hide()
		panel.clear_strokes()
		await process_frame
		await RenderingServer.frame_post_draw
		var blank := root.get_texture().get_image()
		var region := blank.get_region(Rect2i(35, 148, 394, 394))
		var uniform := true
		var paper := region.get_pixel(0, 0)
		for y in range(0, region.get_height(), 7):
			for x in range(0, region.get_width(), 7): uniform = uniform and region.get_pixel(x, y).is_equal_approx(paper)
		check(uniform, "blank canvas pixels have no phantom guides or motif")
		blank.save_png("res://test-results/rectangular-blank.png")
		panel.use_freehand()
		canvas._begin(canvas.size * Vector2(0.95, 0.95), 1)
		canvas._append(canvas.size * Vector2(0.72, 0.87))
		canvas._append(canvas.size * Vector2(0.92, 0.72))
		canvas._finish()
		panel.recipe.segments = 8
		panel.recipe.mirror = true
		panel._sync()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/rectangular-handmade.png")
	panel.queue_free()
	reopened.queue_free()
	await process_frame
	print("RECTANGULAR_FREEHAND checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
