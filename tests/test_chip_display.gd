extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CHIPS: " + label)

func _separated(display: Control) -> bool:
	for first in display._chip_nodes.size():
		for second in range(first + 1, display._chip_nodes.size()):
			var a: Vector3 = display._chip_nodes[first].position
			var b: Vector3 = display._chip_nodes[second].position
			# Solid chip diameter1.14, face markings span0.196 vertically.
			if Vector2(a.x - b.x, a.z - b.z).length() < 1.14 and absf(a.y - b.y) < 0.196:
				return false
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
	display.size = Vector2(500, 260)
	display.set_amount(0)
	root.add_child(display)
	await process_frame
	check(display._chip_nodes.is_empty(), "zero amount never creates money")
	check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "empty viewport does not render continuously")
	display.set_amount(1200, false)
	check(not display._chip_nodes.is_empty(), "positive amount creates geometry")
	check(display._chip_nodes.size() <= Display.MAX_CHIPS, "bounded geometry count")
	for chip in display._chip_nodes:
		check(chip is MeshInstance3D and chip.mesh is ArrayMesh, "each chip is a combined 3D mesh")
		check(chip.mesh.get_surface_count() == 3, "chip has three material surfaces")
		check(chip.get_aabb().size.x > 1.0 and chip.get_aabb().size.y > 0.1, "mesh contains solid body")
		var top: Label3D = chip.get_node("DenominationTop")
		var bottom: Label3D = chip.get_node("DenominationBottom")
		var denomination: int = display.VALUES[display._denominations[display._chip_nodes.find(chip)]]
		check(top.text == str(denomination) and bottom.text == str(denomination), "every physical chip has its actual value on both faces")
		check(top.position.y > 0.09 and bottom.position.y < -0.09 and top.basis.z.dot(Vector3.UP) > 0.99 and bottom.basis.z.dot(Vector3.DOWN) > 0.99,
			"face labels face outward on opposite surfaces")
		check(not top.double_sided and not bottom.double_sided, "labels cannot show mirrored through the back face")
	check(display._chip_nodes.size() > 5, "useful denomination change visible")
	var first_mesh = display._chip_nodes[0].mesh
	var current_amount: int = display._amount
	display.set_amount(1200, false)
	check(display._chip_nodes[0].mesh == first_mesh, "unchanged amount reuses geometry")
	display.toss(0.2)
	check(display.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "motion wakes viewport")
	# Sample the real tween at a deterministic midpoint, even on a loaded build host.
	display._animation.pause()
	display._animation.custom_step(0.07)
	check(absf(display._chip_nodes[0].rotation.x) > 0.2, "toss performs real 3D axial turn")
	display._animation.play()
	check(display._amount == current_amount, "toss never changes balance")
	await create_timer(0.2).timeout
	check(display._animation == null, "toss finishes")
	check(display._chip_nodes[0].position.is_equal_approx(display._rest_positions[0]), "toss lands at rest")
	check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "settled viewport sleeps")
	display.size = Vector2(520, 280)
	await process_frame
	check(display.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "resize redraw does not become continuous")
	display.set_amount(9223372036854775807, false)
	check(display._chip_nodes.size() <= Display.MAX_CHIPS, "int64 balance cannot explode geometry")
	check(display._meshes.size() <= Display.VALUES.size(), "mesh cache bounded by denominations")
	display.set_amount(-1, false)
	check(display._chip_nodes.is_empty() and display._amount == 0, "negative presentation amount clears")
	for amount in [0, 1, 4, 5, 24, 25, 49, 50, 99, 100, 499, 500, 999, 1000, 1200, 2500, 4000]:
		display.set_amount(amount, false)
		var represented := 0
		for denomination in display._denominations:
			represented += int(Display.VALUES[denomination])
		check(represented == amount, "ordinary balance %d has exact physical denomination sum" % amount)
		check(display._amount == amount and (amount > 0 or display._chip_nodes.is_empty()), "amount/zero rebuild reflects authoritative value")
	var pot = Display.new()
	pot.display_mode = "pot"
	pot.size = Vector2(500, 260)
	pot.position = Vector2(520, 0)
	pot.set_amount(845)
	root.add_child(pot)
	await process_frame
	check(pot._amount == 845 and not pot._chip_nodes.is_empty(), "ready preserves caller's pending amount")
	var scattered := false
	for chip in pot._chip_nodes:
		scattered = scattered or absf(chip.position.z) > 0.3
	check(scattered, "pot has spatial scattered layers")
	var pot_rest: Array = pot._rest_positions.duplicate()
	pot.collect(0.12)
	await create_timer(0.2).timeout
	var ordered := true
	for index in pot._chip_nodes.size():
		ordered = ordered and pot._chip_nodes[index].position.is_equal_approx(pot_rest[index])
	check(ordered and pot._animation == null and is_equal_approx(pot.modulate.a, 1.0), "collect restores separated original piles and opacity")
	pot.set_amount(846, false)
	pot.organize(0.12)
	await create_timer(0.2).timeout
	ordered = true
	for index in pot._chip_nodes.size():
		ordered = ordered and pot._chip_nodes[index].position.is_equal_approx(pot._rest_positions[index])
	check(ordered, "organize settles separated chips without reordering intersecting paths")
	var flight = Display.new()
	flight.display_mode = "flight"
	flight.set_amount(999999)
	root.add_child(flight)
	await process_frame
	check(flight._chip_nodes.size() <= 8, "flight has small fixed geometry budget")
	for pile in [display, pot, flight]:
		for amount in [1, 500, 1000, 10000, 60000, 1000000]:
			pile.set_amount(amount, false)
			check(_separated(pile), "%s amount%d solid faces and footprints do not overlap" % [pile.display_mode, amount])
	pot.set_amount(10000, false)
	pot.nudge()
	pot._animation.pause()
	for frame in 21:
		pot._pose_nudge(float(frame) / 20.0)
		check(_separated(pot), "dense pot nudge remains separated throughout")
	pot.cancel_nudge()
	for tap in 100:
		var previous: Tween = pot._animation
		pot.nudge()
		check(previous == null or not previous.is_valid(), "rapid tap replaces earlier tween instead of queuing")
	pot.cancel_nudge()
	for pile in [display, pot, flight]:
		for kind in ["collect", "organize", "toss", "amount"]:
			pile.set_amount(9999, false)
			pile.set_amount(10000, kind == "amount")
			if kind != "amount": pile.call(kind, 1.0)
			pile._animation.pause()
			for frame in 21:
				var t := float(frame) / 20.0
				if kind == "collect": pile._pose_collect(t)
				elif kind == "toss": pile._pose_toss(t)
				else: pile._pose_layout(t)
				check(not _solid_overlap(pile), "%s %s frame%d has no sampled solid-body penetration" % [pile.display_mode, kind, frame])
				var scale_ok := true
				for chip in pile._chip_nodes: scale_ok = scale_ok and chip.scale.is_equal_approx(Vector3.ONE)
				check(scale_ok, "routine choreography never rescales individual chip models")
			pile._finish_animation(kind)
			check(is_equal_approx(pile.modulate.a, 1.0), "routine animation restores opacity")
	pot.collect(1.0)
	pot._pose_collect(0.5)
	pot.set_amount(500, false)
	check(is_equal_approx(pot.modulate.a, 1.0), "interrupted collection cannot leave next amount faded")
	if "--capture-chips" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		display.set_amount(1200, false)
		pot.set_amount(845, false)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "user://chip_display_review.png"
		check(root.get_texture().get_image().save_png(path) == OK, "save graphical chip evidence")
		print("CHIP_CAPTURE " + ProjectSettings.globalize_path(path))
	flight.toss()
	flight.queue_free()
	pot.nudge()
	pot.queue_free()
	display.set_amount(50)
	display.set_amount(0)
	check(display._animation == null and display._chip_nodes.is_empty(), "zero amount cancels active animation")
	display.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("CHIP_DISPLAY_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
