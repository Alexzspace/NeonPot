extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	root.size = Vector2i(1311, 603)
	app._set_preview_profile("iphone", false)
	await process_frame
	app.language = "zh"
	app._build_ui()
	app.feedback.volume = 0.0
	app.feedback.haptic_strength = 0.0
	await create_timer(1.0).timeout
	await _save("home")
	app.player_count.value = 6
	app.session.start_local(["Player", "Two", "Three", "Four", "Five", "Six"], int(app.stack_input.value))
	await app._begin_hand()
	await _idle(app)
	var turns := 0
	while app.shown_state.phase != "river" and turns < 32:
		app.session.set_local_seat(app.shown_state.actor)
		app.session.submit_action("check" if app.shown_state.legal.check else "call")
		await _idle(app)
		turns += 1
	app.session.set_local_seat(app.shown_state.actor)
	await create_timer(1.0).timeout
	for card in app.own_cards:
		var touch := InputEventScreenTouch.new()
		touch.pressed = true
		touch.index = 0
		touch.position = Vector2(60, 80)
		card._gui_input(touch)
	await create_timer(0.3).timeout
	await _save("table")
	while app.shown_state.phase != "showdown" and turns < 64:
		app.session.set_local_seat(app.shown_state.actor)
		app.session.submit_action("check" if app.shown_state.legal.check else "call")
		await _idle(app)
		turns += 1
	await create_timer(0.8).timeout
	await _save("showdown")
	app._close_modal()
	app._show_settings()
	await process_frame
	await _save("settings")
	await _idle(app)
	app.queue_free()
	await create_timer(0.2).timeout
	print("SHOWCASE_CAPTURE_PASS")
	quit()

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := root.get_texture().get_image().save_png("res://artifacts/%s.png" % label)
	if error != OK:
		push_error("Screenshot failed: " + label)
		quit(1)

func _idle(app: Control) -> void:
	while app.presentation_busy or app.input_locked:
		await process_frame
