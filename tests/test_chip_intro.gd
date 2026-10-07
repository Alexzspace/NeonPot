extends SceneTree

const Display = preload("res://scripts/chip_display.gd")
var checks := 0
var failures := 0
var completed: Array[String] = []
var contacts: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHIP_INTRO: " + message)

func _at_rest(display: Control) -> bool:
	for index in display._chip_nodes.size():
		if not display._chip_nodes[index].position.is_equal_approx(display._rest_positions[index]): return false
		if not display._chip_nodes[index].rotation.is_equal_approx(display._rest_rotations[index]): return false
	return true

func _in_frame(display: Control) -> bool:
	var area := Rect2(Vector2.ZERO, Vector2(display.viewport_3d.size)).grow(0.8)
	for chip in display._chip_nodes:
		for x in [-0.58, 0.58]:
			for y in [-0.08, 0.11]:
				for z in [-0.58, 0.58]:
					var world: Vector3 = chip.global_transform * Vector3(x, y, z)
					if not area.has_point(display._camera.unproject_position(world)): return false
	return true

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
	display.size = Vector2(318, 218)
	display.visual_scale = 1.5
	display.set_amount(1000, false)
	display.intro_stack(0.8)
	display.animation_finished.connect(func(kind: String): completed.append(kind))
	display.contact.connect(func(kind: String): contacts.append(kind))
	root.add_child(display)
	check(display._animation_kind == "intro", "pre-ready request starts after chip geometry exists")
	await process_frame
	display.cancel_intro()
	check(_at_rest(display), "cancel restores every actual chip node")
	for amount in [1000, 1000000]:
		display.set_amount(amount, false)
		var camera: Transform3D = display._camera.transform
		var camera_size: float = display._camera.size
		var rests: Array = display._rest_positions.duplicate()
		display.intro_stack()
		display._animation.pause()
		check(display._animation_kind == "intro" and not _at_rest(display), "intro raises existing chips without changing amount")
		check(display._amount == amount and display._intro_order.size() == display._chip_nodes.size(), "all actual chips enter without rebuilding denominations")
		for frame in range(21):
			display._pose_intro(float(frame) / 20.0)
			check(not _solid_overlap(display), "intro never clamps upper chips through their neighbours")
			check(display._camera.transform.is_equal_approx(camera) and display._camera.size == camera_size, "intro camera stays fixed at every sampled frame")
			check(display._rest_positions == rests, "intro preserves immutable rest positions")
			var scale_ok := true
			for chip in display._chip_nodes: scale_ok = scale_ok and chip.scale.is_equal_approx(Vector3.ONE)
			check(scale_ok and _in_frame(display), "chip scale fixed and geometry remains in viewport")
		display._pose_intro(0.5)
		var first: int = display._intro_order[0]
		var last: int = display._intro_order.back()
		check(display._chip_nodes[first].position.is_equal_approx(rests[first]) and display._chip_nodes[last].position.distance_to(rests[last]) > 0.05, "lower chips land before later chips")
		display.cancel_intro()
		check(_at_rest(display) and display._animation == null, "explicit cancel restores rest and stops tween")
	display.set_amount(1000, false)
	display.intro_stack(0.4)
	await create_timer(0.5).timeout
	check(completed == ["intro"] and _at_rest(display), "real tween finishes once at exact resting pose")
	check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "completed intro lets viewport sleep")
	check(contacts.is_empty(), "intro has no unsolicited opening sound or haptic burst")
	for reason in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		display.intro_stack()
		display._notification(reason)
		check(display._animation == null and _at_rest(display), "background cancels intro at rest")
	display.intro_stack()
	display.hide()
	check(display._animation == null and _at_rest(display), "hidden intro cannot keep moving")
	display.show()
	display.intro_stack()
	display.size += Vector2(2, 0)
	check(display._animation == null and _at_rest(display), "resize cancels intro before reframing")
	display.intro_stack()
	display.nudge()
	check(display._animation_kind == "nudge" and _at_rest(display), "new motion replaces intro from original resting geometry")
	display._pose_nudge(0.2)
	check(not _at_rest(display), "nudge fixture has an actual displaced pose")
	display.cancel_nudge()
	check(display._animation == null and _at_rest(display), "cancel_nudge restores all actual transforms")
	display.toss()
	display.cancel_nudge()
	display.cancel_intro()
	check(display._animation_kind == "toss", "targeted cancellation preserves payout/throw animation")
	display._stop_animation()
	display.set_amount(0, false)
	display.intro_stack()
	check(display._animation == null and display._chip_nodes.is_empty(), "empty intro is safe")
	display.set_amount(1000, false)
	display.intro_stack(NAN)
	check(display._animation_kind == "intro", "nonfinite duration uses safe default")
	display.set_amount(500, false)
	check(display._amount == 500 and display._animation == null and _at_rest(display), "amount replacement cancels old intro")
	display.intro_stack()
	display.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(display) and completed == ["intro"], "mid-intro scene exit leaves no late completion")
	print("CHIP_INTRO checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
