extends SceneTree
const ManualPanel = preload("res://scripts/manual_chip_panel.gd")
var checks := 0
var failures := 0
var submissions: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var panel = ManualPanel.new()
	panel.configure({"inventory": {"50": 3, "10": 2}, "street_bet": 10, "min_raise_to": 100, "max_raise_to": 180})
	root.add_child(panel)
	panel.open(Rect2(300, 450, 200, 160), Vector2(850, 350))
	panel.confirmed.connect(func(action: String, total: int, counts: Dictionary): submissions.append([action, total, counts]))
	await create_timer(0.4).timeout
	var tap := InputEventScreenTouch.new()
	tap.position = panel._views[50].button.get_global_transform_with_canvas() * (panel._views[50].button.size * 0.5)
	tap.index = 0
	tap.pressed = true
	root.push_input(tap, true)
	tap = tap.duplicate()
	tap.pressed = false
	root.push_input(tap, true)
	await process_frame
	check(panel.selected_amount() == 50, "native touchscreen tap selects exactly one chip")
	panel._views[50].button.pressed.emit()
	check(panel.selected_amount() == 50, "emulated mouse after touch cannot double select")
	panel.deselect_chip(50)
	await create_timer(0.7).timeout
	panel.select_chip(50)
	check(panel.selected_amount() == 50 and panel._confirm.disabled, "below minimum cannot submit")
	panel.select_chip(50)
	panel.select_chip(50)
	panel.select_chip(50)
	check(panel.selected_amount() == 150, "cannot select more physical chips than owned")
	check(panel._flights == 3 and panel._active_columns.size() == 1, "rapid taps queue one flight per denomination")
	panel.deselect_chip(50)
	check(panel.selected_amount() == 100 and panel.inventory["50"] == 3, "withdraw one preserves real inventory")
	await create_timer(1.4).timeout
	check(panel._staged_counts.get(50) == 2 and panel._flights == 0, "queued select then withdrawal lands exact remaining count")
	var own_display = panel._views[50].chips
	var other_display = panel._views[10].chips
	check(is_equal_approx(own_display._camera.size / own_display.size.y, other_display._camera.size / other_display.size.y), "denomination columns share physical coin pixel diameter")
	var staged_display = panel._stage_views[50].chips
	check(is_equal_approx(own_display._camera.size / own_display.size.y, staged_display._camera.size / staged_display.size.y), "pending chips use same physical diameter as own columns")
	check(not panel._pending_scroll is ScrollContainer, "pending tray has no scrolling control")
	check(panel._amount.text == "100" and not panel._stage_label.visible, "pending tray only labels total amount")
	check("\n" in panel._views[50].label.text and not panel._stage_views[50].label.visible, "owned quantities are vertical and pending quantities are hidden")
	check(is_equal_approx(own_display._camera.size / own_display.size.y, 1.14 / 64.0), "manual chips preserve global 64 pixel diameter")
	if "--visual" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/manual-panel.png")
	panel._submit()
	panel._submit()
	check(submissions.size() == 1 and submissions[0][1] == 110, "single commit raises to own prior plus selection")
	check(submissions[0][2] == {"50": 2}, "commit preserves exact selected denomination")
	panel.unlock_submission()
	check(not panel._locked, "rejected submission can unlock for correction")
	panel.queue_free()
	await process_frame
	panel = ManualPanel.new()
	panel.configure({"inventory": {"10": 2}, "street_bet": 10, "min_raise_to": 100, "max_raise_to": 30})
	root.add_child(panel)
	panel.open(Rect2(300, 450, 200, 160), Vector2(850, 350))
	panel.select_chip(10)
	panel.select_chip(10)
	await create_timer(1.4).timeout
	check(not panel._confirm.disabled and "ALL IN" in panel._confirm.text, "short all-in is explicit and allowed")
	panel.update_inventory({"10": 2, "5": 2})
	check(panel.selected_amount() == 20, "exchange refresh does not clear pending chips")
	panel.cancel()
	check(panel.pending.is_empty() and panel._cancel_after_flights, "cancel releases all private selections")
	await create_timer(1.0).timeout
	check(not is_instance_valid(panel), "close frees modal after animation")
	panel = ManualPanel.new()
	panel.configure({"inventory": {"10": 2}, "street_bet": 10, "min_raise_to": 100, "max_raise_to": 30, "can_raise": false, "can_all_in": false})
	root.add_child(panel)
	panel.open(Rect2(300, 450, 200, 160), Vector2(850, 350))
	panel.select_chip(10)
	panel.select_chip(10)
	await create_timer(0.7).timeout
	check(panel._confirm.disabled, "action rights reject illegal short all-in even with full selection")
	panel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(panel._flights == 0 and panel.pending.is_empty(), "cancel kills flight queue and returns all selected chips in one batch")
	await create_timer(1.0).timeout
	panel = ManualPanel.new()
	panel.configure({"inventory": {"50": 200}, "street_bet": 0, "min_raise_to": 100, "max_raise_to": 5000})
	root.add_child(panel)
	panel.open(Rect2(350, 500, 200, 160), Vector2(1000, 300))
	await create_timer(0.4).timeout
	var diameter_scale: float = panel._views[50].chips._camera.size / panel._views[50].chips.size.y
	var scroll: ScrollContainer = panel._own_scroll
	var touch_point: Vector2 = scroll.get_global_transform_with_canvas() * Vector2(25, 50)
	var drag_touch := InputEventScreenTouch.new()
	drag_touch.position = touch_point
	drag_touch.pressed = true
	drag_touch.index = 3
	root.push_input(drag_touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = touch_point - Vector2(20, 0)
	drag.relative = Vector2(-20, 0)
	root.push_input(drag, true)
	drag_touch = drag_touch.duplicate()
	drag_touch.pressed = false
	root.push_input(drag_touch, true)
	check(panel.selected_amount() == 0 and scroll.scroll_horizontal > 0, "horizontal drag scrolls without selecting a chip")
	var outside := InputEventScreenTouch.new()
	outside.position = scroll.get_global_transform_with_canvas() * Vector2(scroll.size.x + 20, 50)
	outside.index = 4
	outside.pressed = true
	root.push_input(outside, true)
	outside = outside.duplicate()
	outside.pressed = false
	root.push_input(outside, true)
	check(panel.selected_amount() == 0, "clipped overflowing chip button cannot receive touches outside scroll")
	for i in 11: panel.select_chip(50)
	await process_frame
	check(is_equal_approx(diameter_scale, panel._views[50].chips._camera.size / panel._views[50].chips.size.y), "eleventh selected chip never changes camera diameter")
	check(panel.get_staging_position().y >= panel.size.y - 235, "pending area stays entirely in bottom controls")
	for i in 89: panel.select_chip(50)
	check(panel.selected_amount() == 5000 and panel._flights > 0, "100 chips selected while earlier flights remain active")
	panel.cancel()
	check(panel._flights == 0 and panel.pending.is_empty() and panel._taken_counts.is_empty(), "inflight cancel clears all reservations immediately")
	await create_timer(0.4).timeout
	check(not is_instance_valid(panel), "100 chip cancellation completes under half a second")
	panel = ManualPanel.new()
	var full_inventory := {"1": 10, "5": 11, "10": 13, "50": 10, "100": 7, "500": 3}
	panel.configure({"inventory": full_inventory, "street_bet": 0, "min_raise_to": 20, "max_raise_to": 5000})
	root.add_child(panel)
	panel.open(Rect2(350, 500, 200, 160), Vector2(1000, 300))
	panel.pending = full_inventory.duplicate()
	for key in full_inventory:
		panel._staged_counts[int(key)] = full_inventory[key]
		panel._taken_counts[int(key)] = full_inventory[key]
	panel._refresh()
	await create_timer(0.4).timeout
	var display = panel._stage_chips
	var bounds := Rect2()
	var first := true
	for chip in display._chip_nodes:
		for vertex in chip.mesh.get_faces():
			var point: Vector2 = display._camera.unproject_position(chip.global_transform * vertex) * display.size / Vector2(display.viewport_3d.size)
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else: bounds = bounds.expand(point)
	check(Rect2(Vector2.ZERO, display.size).encloses(bounds), "complete mixed all-in inventory stays inside pending tray without shrinking")
	var depth_rows: Array[float] = []
	for at in display._rest_positions:
		if not depth_rows.has(at.z): depth_rows.append(at.z)
	check(depth_rows.size() >= 2 and display._physical_columns() <= 3, "mixed pending chips pack front and back instead of a single row")
	check(panel._pending_scroll.size.x < 270 and is_equal_approx(display._camera.size / display.size.y, 1.14 / display.CHIP_PIXELS), "compact pending pile keeps full chip size within narrow footprint")
	check(panel._own_scroll.size.x < 1, "pending tray takes released own inventory space")
	var return_point: Vector2 = display.get_global_transform_with_canvas() * display.denomination_position(50)
	var return_touch := InputEventScreenTouch.new()
	return_touch.position = return_point
	return_touch.index = 5
	return_touch.pressed = true
	root.push_input(return_touch, true)
	return_touch = return_touch.duplicate()
	return_touch.pressed = false
	root.push_input(return_touch, true)
	check(panel.pending["50"] == 9, "shared pending tray supports native touch withdrawal")
	await create_timer(0.4).timeout
	var many_stacks := {"1": 60, "5": 60, "10": 60, "50": 50, "100": 50, "500": 50}
	panel.inventory = many_stacks.duplicate()
	panel.pending = many_stacks.duplicate()
	for key in many_stacks:
		panel._staged_counts[int(key)] = many_stacks[key]
		panel._taken_counts[int(key)] = many_stacks[key]
	panel._refresh()
	await process_frame
	await process_frame
	bounds = Rect2()
	first = true
	for chip in display._chip_nodes:
		for vertex in chip.mesh.get_faces():
			var point: Vector2 = display._camera.unproject_position(chip.global_transform * vertex) * display.size / Vector2(display.viewport_3d.size)
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else: bounds = bounds.expand(point)
	check(Rect2(Vector2.ZERO, display.size).encloses(bounds), "33 complete ten-chip stacks fit expanded pending tray")
	check(panel._pending_scroll.position.y < 0 and panel._amount.position.y == 191, "large pending tray expands upwards without moving total")
	check(panel._motion_rect.position.y <= panel._body_top + panel._pending_scroll.position.y and panel._backdrop.position.y <= panel._motion_rect.position.y, "expanded tray remains inside flight and backdrop bounds")
	return_point = display.get_global_transform_with_canvas() * display.denomination_position(500)
	return_touch = InputEventScreenTouch.new()
	return_touch.position = return_point
	return_touch.index = 6
	return_touch.pressed = true
	root.push_input(return_touch, true)
	return_touch = return_touch.duplicate()
	return_touch.pressed = false
	root.push_input(return_touch, true)
	check(panel.pending["500"] == 49, "expanded 33-stack tray supports native touch withdrawal")
	await create_timer(0.4).timeout
	panel.inventory["1"] = 70
	panel.config["max_raise_to"] = 100000
	panel._refresh()
	await process_frame
	await process_frame
	check(panel._own_scroll.size.x >= 80 and panel._views[1].box.visible, "large pending selection preserves space for remaining own chips")
	panel._own_scroll.scroll_horizontal = 0
	var remaining_point: Vector2 = panel._views[1].button.get_global_transform_with_canvas() * (panel._views[1].button.size * 0.5)
	var remaining_touch := InputEventScreenTouch.new()
	remaining_touch.position = remaining_point
	remaining_touch.index = 7
	remaining_touch.pressed = true
	root.push_input(remaining_touch, true)
	remaining_touch = remaining_touch.duplicate()
	remaining_touch.pressed = false
	root.push_input(remaining_touch, true)
	check(panel.pending["1"] == 61, "remaining own denomination stays native-touch selectable beside large pending tray")
	panel.queue_free()
	await process_frame
	print("MANUAL_CHIP_PANEL_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
