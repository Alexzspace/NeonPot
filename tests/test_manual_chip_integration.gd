extends SceneTree
const Scene = preload("res://scenes/main.tscn")
const Inventory = preload("res://scripts/chip_inventory.gd")
var checks := 0
var failures := 0
var app: Control
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MANUAL_INTEGRATION: " + message)
func idle() -> void:
	var limit := Time.get_ticks_msec() + 16000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < limit: await process_frame
	check(not app.presentation_busy and not app.input_locked, "presentation settles")
func touch(control: Control, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = control.get_global_transform() * (control.size * 0.5)
	root.push_input(event, true)
func hold() -> void:
	touch(app.chip_touch, true)
	await create_timer(0.7).timeout
	check(app.chip_display.scale.x > 1.08, "hold visibly lifts stack before activation")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v150-hold-polish.png")
	await create_timer(0.38).timeout
	touch(app.chip_touch, false)
	await create_timer(0.4).timeout
	check(is_instance_valid(app.manual_panel), "native one-second hold opens panel")
func _run() -> void:
	root.size = Vector2i(1311, 603) if "--compact" in OS.get_cmdline_user_args() else Vector2i(1440, 810)
	app = Scene.instantiate()
	app.settings_path = "user://v150-integration-unused.cfg"
	root.add_child(app)
	await process_frame
	app._change_language("en" if "--english" in OS.get_cmdline_user_args() else "zh")
	await process_frame
	app._close_modal()
	app.music.set_level(0)
	app.feedback.volume = 0
	for quantity in [20, 100]:
		var packet = app.Chips.new()
		var packet_inventory := {"1": quantity, "5": quantity, "10": quantity, "50": quantity, "100": quantity, "500": quantity}
		packet.display_mode = "flight"
		packet.size = app._chip_packet_size(packet_inventory)
		app.add_child(packet)
		packet.set_inventory(packet_inventory)
		var packet_fits := true
		for phase in [0.0, 0.19, 0.38, 0.57, 0.76, 1.0]:
			packet._pose_toss(phase)
			var bounds := Rect2(packet.size * 0.5, Vector2.ZERO)
			for index in packet._chip_nodes.size():
				if index % 10 not in [0, 9]: continue
				var chip = packet._chip_nodes[index]
				for vertex in chip.mesh.get_faces():
					var point: Vector2 = packet._camera.unproject_position(chip.global_transform * vertex) * packet.size / Vector2(packet.viewport_3d.size)
					packet_fits = packet_fits and Rect2(Vector2.ZERO, packet.size).has_point(point)
					bounds = bounds.expand(point)
			if not Rect2(Vector2.ZERO, packet.size).encloses(bounds): print("PACKET_CLIP phase=%s bounds=%s size=%s" % [phase, bounds, packet.size])
		check(packet_fits, "large payout packet retains complete fixed-size chip geometry")
		packet.queue_free()
	app.session.start_local(["You", "Opponent"], 6500)
	app.session.begin_hand()
	await idle()
	app.session.set_local_seat(app.session.state.actor)
	await idle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v150-slider-polish.png")
	var before: Dictionary = app.session.state.duplicate(true)
	check(app.manual_bet_hint.visible and app.manual_bet_hint.text == app.words("长按手动加注", "Hold to bet manually"), "localized manual hold hint visible beside resting inventory")
	check(app.manual_bet_hint.position.y >= app.chip_display.position.y + app.chip_display.size.y and app.manual_bet_hint.position.y + app.manual_bet_hint.size.y <= app.table.size.y + 1, "hint clears chips and stays in logical table bounds")
	await hold()
	if not is_instance_valid(app.manual_panel):
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://test-results/v150-failed-hold.png")
		app.queue_free()
		await process_frame
		quit(1)
		return
	var panel: Control = app.manual_panel
	check(not app.manual_bet_hint.visible, "resting hint hidden while manually selecting")
	check(int(panel.inventory.get("1", 0)) > 0, "unit chips available after opening real table")
	touch(panel._views[1].button, true)
	touch(panel._views[1].button, false)
	await create_timer(0.4).timeout
	check(panel.selected_amount() == 1, "visible unit denomination accepts native touch")
	panel.deselect_chip(1)
	await create_timer(0.4).timeout
	check(panel.selected_amount() == 0, "unit selection withdraws exactly")
	panel.select_chip(50)
	panel.select_chip(50)
	panel.select_chip(50)
	await create_timer(1.0).timeout
	check(panel.selected_amount() == 150, "three real 50 chips selected")
	check(app.session.state == before, "selection remains private uncommitted")
	panel.deselect_chip(50)
	await create_timer(0.4).timeout
	check(panel.selected_amount() == 100, "one chip withdrawal")
	panel.exchange_requested.emit(panel.pending.duplicate(true))
	await create_timer(0.5).timeout
	check(is_instance_valid(app.manual_panel) and panel.selected_amount() == 100, "exchange preserves panel and pending chips")
	check(app.session.state.players[app.session.local_seat].stack == before.players[app.session.local_seat].stack, "exchange preserves balance")
	for denomination in [1, 5, 10, 50, 100, 500]: panel.select_chip(denomination)
	await create_timer(0.65).timeout
	check(panel.selected_amount() == 766 and panel._stage_chips._physical_columns() == 3, "six selected denominations form three-column pending pile")
	check(panel._row.get_combined_minimum_size().x <= panel._own_scroll.size.x + 1, "compact pending pile leaves the 6500-stack selector fully visible")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/v150-manual-en-compact.png" if "--compact" in OS.get_cmdline_user_args() else "res://test-results/v150-manual-zh.png")
	for denomination in [1, 5, 10, 50, 100, 500]: panel.deselect_chip(denomination)
	await create_timer(0.65).timeout
	check(panel.selected_amount() == 100, "front/back pending denominations all withdraw individually")
	panel._submit()
	await idle()
	await create_timer(0.35).timeout
	check(not is_instance_valid(app.manual_panel), "accepted bet closes panel")
	check(app.session.state.players[app.session.local_seat].stack == before.players[app.session.local_seat].stack - 100, "confirmed exact contribution deducted")
	check(Inventory.value(app._displayed_pot_chips) == app._displayed_pot, "pot visual exact value")
	check(app.pot_display.get_inventory() == app.session.state.pot_chips, "pot physical denominations exact")
	app.session.set_local_seat(app.session.state.actor)
	await idle()
	await hold()
	if is_instance_valid(app.manual_panel):
		panel = app.manual_panel
		panel.select_chip(10)
		panel.cancel()
		await create_timer(1.0).timeout
		check(not is_instance_valid(app.manual_panel), "cancel returns and closes")
	app.session.set_local_seat(app.session.state.actor)
	app.session.submit_action("all_in")
	await idle()
	if app.session.state.phase != "showdown":
		app.session.set_local_seat(app.session.state.actor)
		app.session.submit_action("all_in")
		check(app._runout_pending, "all-in runout has dedicated presentation")
		await idle()
	check(app.session.state.phase == "showdown", "real engine settles all-in hand")
	check(app._displayed_pot == 0 and Inventory.value(app.pot_display.get_inventory()) == 0, "payout removes physical pot")
	check(app.chip_display.get_inventory() == app.session.state.players[app.session.local_seat].chips, "payout merges original denominations into own stack")
	app._close_modal()
	app._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not is_instance_valid(app.manual_panel), "background clears selection")
	app._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	await process_frame
	print("MANUAL_CHIP_INTEGRATION_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
