extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHIP_PRESENCE: " + label)
func screen_point(display: Control, index: int) -> Vector2:
	return display.position + display._camera.unproject_position(display._chip_nodes[index].global_position) * (display.size / Vector2(display.viewport_3d.size))
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

func run() -> void:
	root.size = Vector2i(1440, 1000)
	var backdrop := ColorRect.new()
	backdrop.color = Color("11101d")
	backdrop.size = Vector2(1440, 1000)
	root.add_child(backdrop)
	var display = Display.new()
	display.size = Vector2(318, 218)
	display.position = Vector2(560, 430)
	display.visual_scale = 1.5
	root.add_child(display)
	var previous_count := 0
	for amount in [1000, 4500, 5000, 7500, 10000, 60000]:
		display.set_amount(amount, false)
		var represented := 0
		for denomination in display._denominations: represented += int(Display.VALUES[denomination])
		check(represented == amount, "actual denomination sum remains exact through60000")
		check(display._chip_nodes.size() > previous_count, "larger balance adds real visible chips instead of plateauing")
		check(display._chip_nodes.size() <= Display.MAX_CHIPS, "high-value geometry remains bounded")
		previous_count = display._chip_nodes.size()
		print("CHIP_AMOUNT amount=%d count=%d" % [amount, previous_count])
	for style in Gestures.DURATIONS.size():
		check(Gestures.duration(style) == (2.0 if style == Gestures.RARE else 1.0), "five normal methods last1second and the master combination lasts2seconds")
	var graphical := DisplayServer.get_name() != "headless"
	for dimensions in [Vector2(318, 218), Vector2(318, 174)]:
		display.size = dimensions
		for amount in [500, 1000, 4500, 10000, 60000]:
			display.set_amount(amount, false)
			await process_frame
			var rests: Array[Vector2] = []
			for index in display._chip_nodes.size(): rests.append(screen_point(display, index))
			var baseline: Image
			if graphical:
				await RenderingServer.frame_post_draw
				baseline = root.get_texture().get_image()
				baseline.resize(288, 200)
			for style in range(Gestures.DURATIONS.size()):
				display.flourish(style)
				display._animation.pause()
				display._pose_flourish(0.0)
				await process_frame
				var pixel_stable := true
				for index in display._chip_nodes.size(): pixel_stable = pixel_stable and screen_point(display, index).distance_to(rests[index]) < 1.0
				check(pixel_stable, "expanded canvas preserves exact resting screen position and scale")
				# All discs now articulate independently around their own axis,
				# including lower layers, and remain active through the final rebound.
				var articulated: Dictionary = {}
				var returning: Dictionary = {}
				for sample in [0.25, 0.45, 0.73, 0.82, 0.91]:
					display._pose_flourish(sample)
					for index in display._chip_nodes.size():
						var turn: float = absf(display._chip_nodes[index].rotation.y - display._rest_rotations[index].y)
						if turn > 0.03: articulated[index] = true
						if sample >= 0.73 and turn > 0.01: returning[index] = true
				check(articulated.size() >= ceili(display._chip_nodes.size() * 0.5), "majority independently twist with staggered layer phases")
				check(returning.size() >= ceili(display._chip_nodes.size() * 0.5), "majority remain articulated during settling instead of rigid return")
				display._pose_flourish(0.82)
				var cross_column_twist := false
				for a in display._chip_nodes.size():
					for b in range(a + 1, display._chip_nodes.size()):
						if display._flourish_levels[a] != display._flourish_levels[b] or display._flourish_columns[a] == display._flourish_columns[b]: continue
						var ya: float = display._chip_nodes[a].rotation.y - display._rest_rotations[a].y
						var yb: float = display._chip_nodes[b].rotation.y - display._rest_rotations[b].y
						cross_column_twist = cross_column_twist or absf(ya - yb) > 0.01
				check(cross_column_twist, "same-level chips in different columns retain individual yaw phases during return")
				var peak := 0.0
				var visibly_moving: Dictionary = {}
				var locally_moving: Dictionary = {}
				var most_visible := 0.5
				for frame in range(1, 20):
					var t := frame / 20.0
					display._pose_flourish(t)
					if frame in [1, 5, 10, 15, 19]: check(not _solid_overlap(display), "mass choreography has no sampled body penetration at every supported balance")
					for index in display._moving_indices:
						var movement := screen_point(display, index).distance_to(rests[index])
						if movement > peak:
							peak = movement
							most_visible = t
						if movement >= 12.0: visibly_moving[index] = true
						var relative: Vector3 = (display._chip_nodes[index].position - display._rest_positions[index]) - (display._chip_nodes[0].position - display._rest_positions[0])
						if relative.length() > 0.08: locally_moving[index] = true
					var grounded := false
					var low_hands := true
					for index in display._chip_nodes.size():
						var rest: Vector3 = display._rest_positions[index]
						var at: Vector3 = display._chip_nodes[index].position
						grounded = grounded or absf(at.y) < 0.005
						low_hands = low_hands and at.y - rest.y <= maxf(1.05, rest.y + Display.CHIP_PITCH) + 0.001
					check(grounded and low_hands, "whole-pile handwork stays grounded without global-rank airborne lanes")
				check(peak >= 24.0 and visibly_moving.size() >= ceili(display._chip_nodes.size() * 0.5), "every variant visibly moves at least half of all chips12px with a24px peak")
				check(locally_moving.size() >= ceili(display._chip_nodes.size() * 0.5), "at least half the chips have distinct local motion beyond a common rigid displacement")
				print("CHIP_MOTION amount=%d height=%d style=%d peak=%.1f moving=%d/%d local=%d canvas=%.2f" % [amount, int(dimensions.y), style, peak, visibly_moving.size(), display._chip_nodes.size(), locally_moving.size(), display._motion_canvas_factor])
				if graphical:
					display._pose_flourish(most_visible)
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var snapshot := root.get_texture().get_image()
					if dimensions.y == 218:
						snapshot.save_png("res://test-results/chip-presence-%d-%d.png" % [amount, style])
					snapshot.resize(288, 200)
					var changed := 0
					for y in range(20, 180):
						for x in range(20, 268):
							var delta := snapshot.get_pixel(x, y) - baseline.get_pixel(x, y)
							if absf(delta.r) + absf(delta.g) + absf(delta.b) > 0.18: changed += 1
					check(changed >= 110, "actual rendered image has a clearly visible moving footprint")
				display.cancel_flourish()
				await process_frame
				check(display.size == dimensions and display.position == Vector2(560, 430), "end restores original layout footprint")
				for index in display._chip_nodes.size(): check(screen_point(display, index).distance_to(rests[index]) < 1.0, "end restores resting screen pose")
	display.flourish(Gestures.RARE)
	display._pose_flourish(0.5)
	display.hide()
	check(not display._motion_canvas_expanded and display._animation == null and display.size == Vector2(318, 174), "hidden display immediately restores footprint and stops rendering motion")
	display.show()
	for notification in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		display.flourish(Gestures.RARE)
		display._notification(notification)
		check(not display._motion_canvas_expanded and display._animation == null, "background cancels expanded animation and future contacts")
	display.flourish(0)
	display.position = Vector2(540, 410)
	display.size = Vector2(330, 190)
	check(display.size == Vector2(330, 190) and display.position == Vector2(540, 410) and display._animation == null, "external reflow retains requested footprint instead of restoring stale size")
	display.flourish(0)
	display.size = Vector2(350, 195)
	check(display.size == Vector2(350, 195) and display.position == Vector2(540, 410), "size-only reflow cannot retain expanded-canvas positional offset")
	display.queue_free()
	backdrop.queue_free()
	await process_frame
	await process_frame
	print("CHIP_PRESENCE_SUMMARY checks=%d failures=%d graphical=%s" % [checks, failures, graphical])
	quit(0 if failures == 0 else 1)
