extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0
var app: Control

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EXACT_INTEGRATION: " + message)

func tap(control: Control, local: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = control.get_global_transform() * local
		root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1311, 603) if "--compact" in OS.get_cmdline_user_args() else Vector2i(1440, 810)
	app = Scene.instantiate()
	app.settings_path = "user://exact-raise-test.cfg"
	root.add_child(app)
	await process_frame
	app._change_language("en" if "--english" in OS.get_cmdline_user_args() else "zh")
	await process_frame
	app._close_modal()
	app.music.set_level(0)
	app.feedback.volume = 0
	app.session.start_local(["You", "Opponent"], 5000)
	app.session.begin_hand()
	var timeout := Time.get_ticks_msec() + 16000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < timeout: await process_frame
	app.session.set_local_seat(app.session.state.actor)
	await process_frame
	check(app.balance_label.z_index > app.chip_display.z_index and app.pot_label.z_index > app.pot_display.z_index, "totals overlay chip geometry without a masking band")
	var state_before: Dictionary = app.session.state.duplicate(true)
	var value_before: float = app.amount_input.value
	tap(app.amount_input, app.amount_input._value_edit_rect().get_center())
	await create_timer(0.3).timeout
	check(is_instance_valid(app.modal), "native amount click opens precise editor")
	var editor: Control = app.modal.find_child("ExactRaiseEditor", true, false)
	check(is_instance_valid(editor), "compact reel editor mounted")
	check(editor.get_parent().size.x == 584 and editor.get_parent().size.y == 408, "precise editor uses compact shell")
	check(app.modal.z_index > app.balance_label.z_index, "focused editor covers raised table totals")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v150-exact-compact.png" if "--compact" in OS.get_cmdline_user_args() else "res://test-results/v150-exact-zh.png")
	editor.cancel_requested.emit()
	await process_frame
	check(not is_instance_valid(app.modal) and app.amount_input.value == value_before, "cancel preserves slider selection")
	app._show_exact_raise()
	editor = app.modal.find_child("ExactRaiseEditor", true, false)
	var chosen := mini(int(app.amount_input.max_value), int(app.amount_input.min_value) + 7)
	editor.accepted.emit(chosen)
	await process_frame
	check(app.amount_input.value == chosen and not is_instance_valid(app.modal), "accept adopts precise amount only")
	check(app.session.state == state_before, "editor never submits poker action")
	app.pot_display.set_inventory({"100": 1, "50": 3, "10": 19, "5": 11, "1": 2})
	app.pot_label.text = app.words("底池 497", "POT 497")
	app.pot_display.set_inventory({"500": 18, "100": 10, "50": 10, "10": 28, "5": 20, "1": 2})
	app.pot_label.text = app.words("底池 10882", "POT 10882")
	await process_frame
	check(app.pot_display._chip_nodes.size() == 88 and app.pot_display._overflow_counts.is_empty(), "10882 pot retains every physical chip without reserve substitution")
	var pot_fits := true
	var inside := Rect2(Vector2.ZERO, app.pot_display.size)
	for chip in app.pot_display._chip_nodes:
		for vertex in chip.mesh.get_faces():
			var point: Vector2 = app.pot_display._camera.unproject_position(chip.global_transform * vertex) * app.pot_display.size / Vector2(app.pot_display.viewport_3d.size)
			pot_fits = pot_fits and inside.has_point(point)
	check(pot_fits and app.pot_panel.get_rect().encloses(app.pot_display.get_rect()), "10882 pot chips remain complete inside enclosing UI frame")
	app.chip_display.set_inventory({"500": 6, "100": 12, "50": 8, "10": 14, "5": 3, "1": 4})
	app.balance_label.text = app.words("筹码 4759", "STACK 4759")
	check(app.pot_label.get_theme_constant("outline_size") == 3 and app.balance_label.get_theme_constant("outline_size") == 3 and app.pot_label.get_theme_color("font_outline_color") == app.balance_label.get_theme_color("font_outline_color"), "pot and own total share a subtle dark outline")
	check(app.pot_label.get_theme_font_size("font_size") <= 34, "pot caption is smaller in normal and compact table layouts")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v150-overflow-compact.png" if "--compact" in OS.get_cmdline_user_args() else "res://test-results/v150-overflow-zh.png")
	var prop_events: Array = []
	app.session.table_prop_gesture.connect(func(seat, sequence, kind): prop_events.append(kind))
	for index in [0, 44, 87]:
		var chip: MeshInstance3D = app.pot_display._chip_nodes[index]
		var point: Vector2 = app.pot_display._camera.unproject_position(chip.global_position) * app.pot_display.size / Vector2(app.pot_display.viewport_3d.size)
		var previous_count := prop_events.size()
		tap(app.pot_display, point)
		check(prop_events.size() == previous_count + 1 and prop_events.back() == "pot" and app.pot_display._animation_kind == "nudge", "dense pot chip touch reaches one authoritative contact")
		var moved := false
		var observe_until := Time.get_ticks_msec() + 300
		while Time.get_ticks_msec() < observe_until:
			await process_frame
			for chip_index in app.pot_display._chip_nodes.size():
				moved = moved or app.pot_display._chip_nodes[chip_index].position.distance_to(app.pot_display._rest_positions[chip_index]) > 0.015 or app.pot_display._chip_nodes[chip_index].rotation.distance_to(app.pot_display._rest_rotations[chip_index]) > 0.03
		check(moved, "dense pot responds with visible 3D motion index=%d kind=%s" % [index, app.pot_display._animation_kind])
		await create_timer(0.15).timeout
	check(app.session.state == state_before, "dense pot interaction preserves authoritative gameplay and inventories")
	app.music.shutdown()
	app.queue_free()
	await create_timer(0.15).timeout
	await process_frame
	print("EXACT_RAISE_INTEGRATION_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
