extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
var checks := 0
var failures := 0
var contacts: Array[String] = []
var completed: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENTRY_CHIPS: " + message)
func _rest(display: Control) -> bool:
	for index in display._chip_nodes.size():
		if not display._chip_nodes[index].visible: return false
		if not display._chip_nodes[index].position.is_equal_approx(display._rest_positions[index]): return false
	return true
func _run() -> void:
	var display = Display.new()
	display.size = Vector2(280, 170)
	display.visual_scale = 1.5
	display.set_amount(1000, false)
	display.table_entry_stack()
	display.contact.connect(func(kind: String): contacts.append(kind))
	display.animation_finished.connect(func(kind: String): completed.append(kind))
	root.add_child(display)
	check(display._animation_kind == "table_entry", "pre-ready table entry starts")
	await process_frame
	display.cancel_intro()
	for amount in [1000, 1000000]:
		display.set_amount(amount, false)
		display.table_entry_stack()
		display._animation.pause()
		contacts.clear()
		var camera: Transform3D = display._camera.transform
		var camera_size: float = display._camera.size
		var size_before: Vector2 = display.size
		var previous_visible := 0
		for frame in 101:
			var t := float(frame) / 100.0
			display._pose_table_entry(t)
			var visible_chips := 0
			var positions: Array[Vector3] = []
			var rotations: Array[Vector3] = []
			for chip in display._chip_nodes:
				if chip.visible: visible_chips += 1
				positions.append(chip.position)
				rotations.append(chip.rotation)
			check(visible_chips >= previous_visible, "chips enter progressively without disappearing")
			previous_visible = visible_chips
			var bounds: Rect2 = display._project_bounds(positions, rotations)
			var half: Vector2 = Vector2(camera_size * display.size.x / display.size.y, camera_size) * 0.5
			check(display._packet_fits(bounds, half, true), "complete moving geometry stays within fixed camera")
			check(display._camera.transform.is_equal_approx(camera) and display._camera.size == camera_size and display.size == size_before, "entry never zooms or resizes chip canvas")
			var separated := true
			for index in positions.size():
				for other in range(index + 1, positions.size()):
					if Vector2(positions[index].x - positions[other].x, positions[index].z - positions[other].z).length() < 1.14:
						separated = separated and absf(positions[index].y - positions[other].y) >= 0.196
			check(separated, "fall and settle preserve ceramic face separation")
		check(_rest(display), "all chips exactly at rest by completion")
		check(contacts.size() >= 2 and contacts.size() <= 15 and contacts.back() == "chip_land", "landing contacts are bounded with final seat accent")
		display.cancel_intro()
	for reason in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		display.table_entry_stack()
		display._notification(reason)
		check(_rest(display) and display._animation == null, "background restores hidden and moving chips")
	display.table_entry_stack()
	display.hide()
	check(_rest(display) and display._animation == null, "hide restores complete stack")
	display.show()
	display.table_entry_stack()
	display.set_amount(500, false)
	check(_rest(display) and display._animation == null, "amount replacement cancels pending contacts")
	display.table_entry_stack()
	display._build_chips()
	check(_rest(display) and display._animation == null, "direct rebuild cancels animation")
	contacts.clear()
	display.table_entry_stack(0.3)
	await create_timer(0.4).timeout
	check(completed == ["table_entry"] and _rest(display), "real tween completes once with restored stack")
	check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "finished entry stops continuous rendering")
	display.table_entry_stack()
	display.queue_free()
	await process_frame
	await process_frame
	check(completed == ["table_entry"], "exit cannot produce late completion")
	print("ENTRY_CHIPS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
