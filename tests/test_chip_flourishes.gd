extends SceneTree

const Display = preload("res://scripts/chip_display.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
var checks := 0
var failures := 0
var contacts: Array[String] = []
var completed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FLOURISH: " + label)

func _geometry_in_frame(display: Control, label: String) -> void:
	var viewport_size: Vector2 = display.viewport_3d.size
	var area := Rect2(Vector2.ZERO, viewport_size).grow(0.75)
	var all_inside := true
	for chip in display._chip_nodes:
		for x in [-0.58, 0.58]:
			for y in [-0.08, 0.11]:
				for z in [-0.58, 0.58]:
					var world: Vector3 = chip.global_transform * Vector3(x, y, z)
					var pixel: Vector2 = display._camera.unproject_position(world)
					all_inside = all_inside and area.has_point(pixel) and not display._camera.is_position_behind(world)
	check(all_inside, label + " all solid-chip corners stay in camera frame")

func _solid_overlap(display: Control) -> bool:
	# Sample actual cylindrical body points, transformed into the other chip's
	# local cylinder. This catches axial-spin interpenetration missed by centers.
	for first in display._chip_nodes.size():
		var a: Node3D = display._chip_nodes[first]
		for second in range(first + 1, display._chip_nodes.size()):
			var b: Node3D = display._chip_nodes[second]
			if a.position.distance_to(b.position) > 1.16: continue
			var relative := b.transform.affine_inverse() * a.transform
			for height in [-0.06, 0.0, 0.06]:
				for spoke in 12:
					var angle := spoke * TAU / 12.0
					var point: Vector3 = relative * Vector3(cos(angle) * 0.54, height, sin(angle) * 0.54)
					if Vector2(point.x, point.z).length() < 0.56 and absf(point.y) < 0.063: return true
	return false

func _run() -> void:
	var display = Display.new()
	display.size = Vector2(358, 174)
	display.visual_scale = 1.35
	display.set_amount(1000000)
	root.add_child(display)
	display.contact.connect(func(kind: String): contacts.append(kind))
	display.animation_finished.connect(func(kind: String): completed.append(kind))
	await process_frame
	check(display._amount == 1000000 and display.visual_scale == 1.35, "ready preserves amount and requested enlargement")
	check(display._chip_nodes.size() <= Display.MAX_CHIPS, "large balance remains bounded")
	var has_front := false
	var has_back := false
	for at in display._rest_positions:
		has_front = has_front or at.z > 0.4
		has_back = has_back or at.z < -0.4
	check(has_front and has_back, "narrow component uses compact staggered piles")
	_geometry_in_frame(display, "enlarged rest")
	var standard = Display.new()
	standard.size = display.size
	standard.set_amount(1000000)
	root.add_child(standard)
	await process_frame
	check(display._camera.size <= standard._camera.size, "visual scale never shrinks projected geometry when high-count framing sets the minimum")
	standard.queue_free()
	var middle_poses: Dictionary = {}
	for style in range(6):
		contacts.clear()
		var before_finished := completed.size()
		display.flourish(style)
		check(display._animation_kind == "flourish" and display.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
			"style %d starts bounded active motion" % style)
		await create_timer(Gestures.duration(style) * 0.40).timeout
		var displaced := 0
		var depth_changed := false
		var signature: Array = []
		for index in display._chip_nodes.size():
			var chip: Node3D = display._chip_nodes[index]
			if chip.position.distance_to(display._rest_positions[index]) > 0.08:
				displaced += 1
			depth_changed = depth_changed or absf(chip.position.z - display._rest_positions[index].z) > 0.05
			signature.append(chip.position.snapped(Vector3.ONE * 0.01))
		middle_poses[str(signature)] = true
		check(displaced >= 2 and depth_changed, "style %d performs visible multi-chip 3D motion" % style)
		check(display._amount == 1000000, "style %d cannot change balance" % style)
		_geometry_in_frame(display, "style %d live midpoint" % style)
		await create_timer(Gestures.duration(style) * 0.65 + 0.06).timeout
		check(display._animation == null and completed.size() == before_finished + 1 and completed.back() == "flourish",
			"style %d completes exactly once" % style)
		check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "style %d viewport sleeps after settling" % style)
		check(contacts.size() == display._contact_schedule(style).size(), "style %d has one signal per physical contact cue" % style)
		for index in display._chip_nodes.size():
			check(display._chip_nodes[index].position.is_equal_approx(display._rest_positions[index]) and display._chip_nodes[index].rotation.is_equal_approx(display._rest_rotations[index]),
				"style %d restores original chip transform" % style)
		check(is_equal_approx(display._camera.size, display._rest_camera_size), "style %d restores camera size" % style)
	check(middle_poses.size() == 6, "all six styles have different spatial choreography")
	# Dense deterministic pose sampling complements live midpoint checks, including
	# the tallest rare cascade and the narrower remote view / preview modal.
	for dimensions in [Vector2(358, 174), Vector2(246, 174), Vector2(400, 230)]:
		display.size = dimensions
		await process_frame
		for style in range(6):
			var fixed_camera: Transform3D = display._camera.transform
			var fixed_size: float = display._camera.size
			var unchanged_positions: Array = display._rest_positions.duplicate()
			display.flourish(style)
			check(display._camera.transform.is_equal_approx(fixed_camera) and is_equal_approx(display._camera.size / display.size.y, fixed_size / dimensions.y),
				"expanded motion canvas preserves resting pixel scale")
			display._animation.pause()
			for frame in range(21):
				display._pose_flourish(float(frame) / 20.0)
				check(not _solid_overlap(display), "all six flourishes preserve actual solid-chip separation at every sampled frame")
				_geometry_in_frame(display, "%s style%d frame%d" % [dimensions, style, frame])
				check(display._camera.transform.is_equal_approx(fixed_camera) and is_equal_approx(display._camera.size / display.size.y, fixed_size / dimensions.y),
					"all sampled motion frames preserve world-to-pixel scale")
				var unchanged_scale := true
				for chip in display._chip_nodes:
					unchanged_scale = unchanged_scale and chip.scale.is_equal_approx(Vector3.ONE)
				check(unchanged_scale and display._rest_positions == unchanged_positions,
					"motion preserves model scale and immutable rest positions")
			display._stop_animation()
			display._finish_animation("fixture")
			check(display._camera.transform.is_equal_approx(fixed_camera) and is_equal_approx(display._camera.size / display.size.y, fixed_size / dimensions.y), "gesture end restores original viewport and pixel scale")
	contacts.clear()
	display.flourish(Gestures.RARE)
	await create_timer(0.35).timeout
	display.set_amount(257, false)
	var after_interrupt := contacts.size()
	check(display._amount == 257 and display._animation == null, "new authoritative amount interrupts flourish")
	await create_timer(0.40).timeout
	check(contacts.size() == after_interrupt, "interrupted flourish emits no future contact sounds")
	var rebuilt_value := 0
	for denomination in display._denominations:
		rebuilt_value += int(Display.VALUES[denomination])
	check(rebuilt_value == 257, "live amount replacement rebuilds exact denominations")
	for index in display._chip_nodes.size():
		check(display._chip_nodes[index].position == display._rest_positions[index], "new amount has clean rest layout")
	display.flourish(-1)
	check(display._animation == null, "invalid style does not start a flourish")
	display.flourish(Gestures.RARE)
	await create_timer(0.35).timeout
	display.cancel_flourish()
	var contacts_at_cancel := contacts.size()
	check(display._animation == null and display._animation_kind.is_empty(), "session pause cancels recreational motion")
	for index in display._chip_nodes.size():
		check(display._chip_nodes[index].position == display._rest_positions[index] and display._chip_nodes[index].rotation == display._rest_rotations[index], "cancel restores exact chip pose")
	check(is_equal_approx(display._camera.size, display._rest_camera_size), "cancel restores camera framing")
	await create_timer(0.40).timeout
	check(contacts.size() == contacts_at_cancel, "session cancellation suppresses future contacts")
	contacts.clear()
	display.nudge()
	display.cancel_flourish()
	check(display._animation_kind == "nudge", "cancel flourish preserves unrelated legacy animation")
	await create_timer(0.48).timeout
	check(contacts.is_empty() and completed.back() == "nudge", "legacy nudge retains behavior without new contact signals")
	display.flourish(Gestures.RARE)
	await create_timer(0.08).timeout
	display.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("CHIP_FLOURISH_TEST checks=%d failures=%d hardware_visuals=desktop_only" % [checks, failures])
	quit(1 if failures else 0)
