extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHIP_INVENTORY_DISPLAY: " + label)
func mesh_fits(display: Control) -> bool:
	var output: Rect2 = display.get_render_rect()
	for chip in display._chip_nodes:
		for vertex in chip.mesh.get_faces():
			if not output.has_point(display._project_to_local(chip.global_transform * vertex)): return false
	return true
func run() -> void:
	var display = Display.new()
	display.size = Vector2(620, 260)
	display.display_mode = "pot"
	root.add_child(display)
	display.set_inventory({"50": 13, "10": 7, "5": 3})
	check(display._amount == 735, "exact inventory value")
	check(display._chip_nodes.size() == 23, "no exchanged or omitted ordinary chips")
	var rests: Dictionary = {}
	var seen: Dictionary = {}
	for index in display._chip_nodes.size():
		var denom: int = Display.VALUES[display._denominations[index]]
		seen[denom] = int(seen.get(denom, 0)) + 1
		rests[str(denom) + ":" + str(seen[denom])] = display._rest_positions[index]
		check(display._rest_positions[index].y <= 9 * Display.CHIP_PITCH + 0.001, "ten chips per column maximum")
	display.set_inventory({"50": 15, "10": 7, "5": 3}, true)
	display._animation.pause()
	seen.clear()
	for index in display._chip_nodes.size():
		var denom: int = Display.VALUES[display._denominations[index]]
		seen[denom] = int(seen.get(denom, 0)) + 1
		var key := str(denom) + ":" + str(seen[denom])
		if rests.has(key): check(rests[key] == display._rest_positions[index], "existing discs keep their slots")
	for t in [0.0, 0.3, 0.6, 1.0]:
		display._pose_inventory(t)
		for a in display._chip_nodes.size():
			for b in range(a + 1, display._chip_nodes.size()):
				var delta: Vector3 = display._chip_nodes[a].position - display._chip_nodes[b].position
				check(Vector2(delta.x, delta.z).length() >= 1.14 or absf(delta.y) >= 0.196, "arrival never intersects solid discs")
	display.display_mode = "expanded"
	display.set_inventory({"1": 1, "5": 2, "10": 3, "50": 4, "100": 5, "500": 6})
	var last_x := -INF
	for value in [1, 5, 10, 50, 100, 500]:
		var at: Vector2 = display.denomination_position(value)
		check(at.x > last_x, "expanded denominations ascend left to right")
		check(display.denomination_at(at) == value, "top chip hit selects correct denomination")
		last_x = at.x
	display.set_inventory({"1": 1000000})
	check(display.get_inventory() == {"1": 1000000}, "extreme inventory retained exactly")
	check(display._overflow_counts.get("1", 0) + display._chip_nodes.size() == 1000000, "all deferred chips explicitly accounted for")
	check(display.chips.has_node("Reserve1"), "reserve visible label exists")
	check(display._chip_nodes.size() <= 600, "large inventory geometry bounded")
	display.set_inventory({})
	display.display_mode = "stack"
	display.size = Vector2(358, 174)
	display.set_fixed_chip_pixels(Display.CHIP_PIXELS)
	display.set_inventory({"50": 10})
	var camera_size: float = display._camera.size
	var first_center: Vector2 = display._camera.unproject_position(display._chip_nodes[0].global_position)
	var edge: Vector2 = display._camera.unproject_position(display._chip_nodes[0].global_position + display._camera.basis.x * 1.14)
	var first_diameter: float = first_center.distance_to(edge) * display.size.y / display.viewport_3d.size.y
	display.set_inventory({"50": 11})
	check(is_equal_approx(display._camera.size, camera_size), "eleventh chip never zooms the camera")
	check(display._rest_positions[10].x > display._rest_positions[0].x and display._rest_positions[10].z == display._rest_positions[0].z, "eleventh chip starts adjacent horizontal column")
	check(absf(first_diameter - Display.CHIP_PIXELS) < 0.1, "physical diameter is fixed requested pixel size")
	display.display_mode = "manual"
	display.set_inventory({"50": 11})
	check(is_equal_approx(display._camera.size, camera_size), "manual mode keeps same physical pixel scale")
	for top_index in [9, 10]:
		var top: Vector2 = display._camera.unproject_position(display._chip_nodes[top_index].global_position) * display.size / Vector2(display.viewport_3d.size)
		check(display.denomination_at(top) == 50, "either same-denomination stack can be withdrawn")
	check(display.denomination_at(Vector2(-1, 50)) == 0, "outside display never selects inventory")
	var measured: Vector2 = Display.measure_inventory_size({"50": 11}, Display.CHIP_PIXELS)
	check(measured.x >= 100, "manual two-column measurement reserves horizontal width")
	display.display_mode = "flight"
	display.size = Vector2(68, 68)
	display.set_inventory({"50": 1})
	display.set_fixed_chip_pixels(Display.CHIP_PIXELS)
	check(is_equal_approx(display._camera.size / display.size.y, 1.14 / Display.CHIP_PIXELS), "explicit flight scale matches resting chip diameter")
	# A normal mixed3000-stack must be compact and retain visible unit chips.
	display.display_mode = "stack"
	display.size = Vector2(358, 174)
	display.set_inventory({"500": 3, "100": 8, "50": 11, "10": 10, "5": 8, "1": 10})
	var footprints: Array[Vector2] = []
	for at in display._rest_positions:
		var footprint := Vector2(at.x, at.z)
		if not footprints.has(footprint): footprints.append(footprint)
	var actual_bounds := Rect2()
	var first_vertex := true
	for index in display._chip_nodes.size():
		for vertex in display._chip_nodes[index].mesh.get_faces():
			var point: Vector2 = display._camera.unproject_position(display._chip_nodes[index].global_transform * vertex) * display.size / Vector2(display.viewport_3d.size)
			if first_vertex:
				actual_bounds = Rect2(point, Vector2.ZERO)
				first_vertex = false
			else: actual_bounds = actual_bounds.expand(point)
	print("MIXED_PROJECTED_BOUNDS %s control=%s" % [actual_bounds, display.size])
	check(Rect2(Vector2.ZERO, display.size).encloses(actual_bounds), "actual mixed physical geometry fits normal own panel")
	check(footprints.size() == 7, "physical columns contain no reserved empty gaps")
	for index in range(1, 5):
		check(is_equal_approx(footprints[index].x - footprints[index - 1].x, Display.COLUMN_SPACING), "neighbouring stacks nearly touch")
	for value in [1, 5, 10, 50, 100, 500]:
		var point: Vector2 = display.denomination_position(value)
		check(Rect2(Vector2.ZERO, display.size).has_point(point), "all mixed-inventory denominations visible: %d" % value)
	check(is_equal_approx(display._camera.size / display.size.y, 1.14 / Display.CHIP_PIXELS), "mixed normal inventory stays globally sized")
	var flight = Display.new()
	flight.display_mode = "flight"
	flight.size = Vector2(84, 84)
	root.add_child(flight)
	flight.set_inventory({"1": 1})
	check(is_equal_approx(flight._camera.size / flight.size.y, 1.14 / Display.CHIP_PIXELS), "flight defaults to global size without explicit override")
	flight.queue_free()
	# The pot's old140px viewport cropped the white chips even at rest. Output
	# overflow must expose those pixels without changing layout anchors or size.
	var pot = Display.new()
	pot.display_mode = "pot"
	pot.position = Vector2(80, 120)
	pot.size = Vector2(310, 140)
	root.add_child(pot)
	pot.set_inventory({"1": 17, "5": 16, "10": 10, "50": 6})
	check(pot._amount == 497 and not mesh_fits(pot), "497 pot fixture reproduces old viewport clipping")
	var unit_anchor: Vector2 = pot.denomination_position(1)
	pot.set_render_overflow_enabled(true)
	check(pot.position == Vector2(80, 120) and pot.size == Vector2(310, 140), "overflow leaves public layout bounds untouched")
	check(pot.get_render_rect().size.y > 140 and mesh_fits(pot), "expanded transparent canvas contains every physical vertex")
	check(pot.denomination_position(1).distance_to(unit_anchor) < 0.1, "overflow preserves original chip projection anchor")
	check(pot.denomination_at(pot.denomination_position(1)) == 1, "overflow projection retains denomination hit mapping")
	var center: Vector3 = pot._chip_nodes[0].global_position
	var diameter: float = pot._project_to_local(center).distance_to(pot._project_to_local(center + pot._camera.basis.x * 1.14))
	check(absf(diameter - Display.CHIP_PIXELS) < 0.1, "expanded output keeps64px discs without camera shrink")
	var resting_output: Rect2 = pot.get_render_rect()
	pot.flourish(4)
	pot._animation.pause()
	pot._pose_flourish(0.45)
	check(pot.position == Vector2(80, 120) and pot.size == Vector2(310, 140), "overflow flourish expands only child output")
	check(mesh_fits(pot), "expanded flourish canvas contains moving geometry")
	pot.cancel_flourish()
	check(pot.get_render_rect() == resting_output and mesh_fits(pot), "flourish cancellation restores unclipped resting output")
	pot.flourish(1)
	pot.size = Vector2(280, 120)
	check(pot.size == Vector2(280, 120) and pot.position == Vector2(80, 120), "resize during flourish retains requested layout")
	check(not pot._motion_canvas_expanded and mesh_fits(pot), "resize rebuilds output rather than restoring stale bounds")
	pot.hide()
	pot.show()
	check(mesh_fits(pot), "hide and restore preserve unclipped resting geometry")
	pot.set_render_overflow_enabled(false)
	check(pot.viewport_3d.get_parent() == pot and pot.get_render_rect() == Rect2(Vector2.ZERO, pot.size), "overflow opt-out restores ordinary viewport ownership")
	pot.queue_free()
	var bounded = Display.new()
	bounded.display_mode = "pot"
	bounded.set_bounded_pot_enabled(true)
	root.add_child(bounded)
	var full_pot := {"500": 18, "100": 10, "50": 10, "10": 28, "5": 20, "1": 2}
	bounded.size = Vector2(304, 180)
	bounded.set_inventory(full_pot)
	check(not bounded._overflow_counts.is_empty(), "old adaptive pot viewport reproduces eight-stack reserve substitution")
	bounded.size = Vector2(292, 236)
	check(bounded._chip_nodes.size() == 88 and bounded._overflow_counts.is_empty(), "full adaptive panel resize immediately restores every original chip")
	for area in [Vector2(334, 174), Vector2(292, 236)]:
		bounded.size = area
		bounded.set_inventory({})
		bounded.set_inventory(full_pot, true)
		bounded._animation.pause()
		check(bounded._amount == 10882 and bounded._chip_nodes.size() == 88, "10882 pot keeps all ten physical stacks")
		check(bounded._overflow_counts.is_empty(), "normal ten-stack pot never enters reserve display")
		check(bounded.get_render_rect() == Rect2(Vector2.ZERO, area), "pot output stays inside enclosing UI interior")
		for progress in [0.0, 0.3, 0.7, 1.0]:
			bounded._pose_inventory(progress)
			check(mesh_fits(bounded), "pot arrival geometry never crosses frame")
		bounded._stop_animation()
		bounded.table_entry_stack()
		bounded._animation.pause()
		for progress in [0.0, 0.3, 0.7, 1.0]:
			bounded._pose_table_entry(progress)
			check(mesh_fits(bounded), "pot entry geometry never crosses frame")
		bounded.cancel_intro()
		for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
			bounded._pose_nudge(progress)
			check(mesh_fits(bounded), "pot nudge geometry never crosses frame")
			if progress == 0.25:
				var largest_twist := 0.0
				for index in bounded._chip_nodes.size():
					largest_twist = maxf(largest_twist, absf(bounded._chip_nodes[index].rotation.y - bounded._rest_rotations[index].y))
				check(largest_twist > 0.1, "dense pot retains visible interaction when translation is constrained")
			bounded._pose_collect(progress)
			check(mesh_fits(bounded), "pot collect geometry never crosses frame")
		bounded._restore_rest_pose()
		check(absf(bounded._camera.size / area.y - 1.14 / Display.CHIP_PIXELS) < 0.001, "bounded pot keeps global64px diameter")
	bounded.set_inventory({"500": 100, "100": 100, "50": 100, "10": 100, "5": 100, "1": 100})
	check(mesh_fits(bounded), "extreme inventory shows only whole fitting stacks")
	var retained: int = bounded._chip_nodes.size()
	for count in bounded._overflow_counts.values(): retained += int(count)
	check(retained == 600 and bounded.get_inventory()["1"] == 100, "extreme reserves retain exact denominations without exchanging")
	bounded.nudge()
	bounded._animation.pause()
	for progress in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0]:
		bounded._pose_nudge(progress)
		check(mesh_fits(bounded), "capacity-full pot interaction stays inside frame")
	bounded._pose_nudge(0.25)
	check(absf(bounded._chip_nodes[0].rotation.y - bounded._rest_rotations[0].y) > 0.1, "capacity-full pot click remains visibly animated")
	bounded._stop_animation()
	bounded._restore_rest_pose()
	bounded.queue_free()
	display.queue_free()
	await process_frame
	print("CHIP_INVENTORY_DISPLAY_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
