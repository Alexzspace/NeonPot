extends Control
## Non-interactive camera art: left lens becomes the deck, right lens the pot.
signal calibration_changed

var camera_zone := Rect2()
var camera_bounds := Rect2()
var deck_center := Vector2.ZERO
var pot_center := Vector2.ZERO
var show_notches := false
var left_offset := Vector2(-2, 0)
var right_offset := Vector2(-27, 0)
var left_radius := 175.0
var right_radius := 175.0
var _calibration_elapsed := 0.0
var _calibration_text := ""

func _process(delta: float) -> void:
	if not visible: return
	_calibration_elapsed += delta
	if _calibration_elapsed < 0.5: return
	_calibration_elapsed = 0.0
	var path := "user://mixflip-camera-calibration.json"
	if not FileAccess.file_exists(path): return
	var raw := FileAccess.get_file_as_string(path)
	if raw == _calibration_text: return
	var data = JSON.parse_string(raw)
	if not data is Dictionary: return
	_calibration_text = raw
	left_offset = Vector2(clampf(float(data.get("left_x", -2)), -80, 80), clampf(float(data.get("left_y", 0)), -80, 80))
	right_offset = Vector2(clampf(float(data.get("right_x", -27)), -80, 80), clampf(float(data.get("right_y", 0)), -80, 80))
	left_radius = clampf(float(data.get("left_radius", 175)), 140, 190)
	right_radius = clampf(float(data.get("right_radius", 175)), 140, 190)
	queue_redraw()
	calibration_changed.emit()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(zone: Rect2, bounds: Rect2, deck_at: Vector2, pot_at: Vector2) -> void:
	camera_zone = zone
	camera_bounds = bounds
	deck_center = deck_at
	pot_center = pot_at
	visible = camera_zone.has_area()
	queue_redraw()

func _draw() -> void:
	if not camera_zone.has_area(): return
	draw_rect(camera_zone, Color("100f1d", 0.74), true)
	var step := camera_zone.size.x / 9.0
	for i in range(1, 9):
		var x := camera_zone.position.x + step * i
		draw_line(Vector2(x, 0), Vector2(x - 48, camera_zone.end.y), Color(0.70, 0.38, 0.72, 0.04), 3.0)
	# The left ring was photographically aligned; use its radius for both lenses.
	draw_arc(deck_center + left_offset, left_radius, 0.0, TAU, 128, Color("65d6d4"), 3.0, true)
	draw_arc(pot_center + right_offset, right_radius, 0.0, TAU, 128, Color("e59acb"), 3.0, true)
	if show_notches:
		_draw_notch(false)
		_draw_notch(true)

func notch_rect(bottom: bool) -> Rect2:
	var midpoint := (deck_center + left_offset + pot_center + right_offset) * 0.5
	return Rect2(midpoint.x - 84, camera_zone.end.y - 106 if bottom else 18.0, 168, 88)

func _draw_notch(bottom: bool) -> void:
	var left_center := deck_center + left_offset
	var right_center := pot_center + right_offset
	var midpoint := (left_center + right_center) * 0.5
	var points := PackedVector2Array()
	# Follow the circular lens edges, widening toward the top/bottom bezel.
	for i in range(17):
		var y := lerpf(18.0, 106.0, float(i) / 16.0)
		var actual_y := camera_zone.end.y - y if bottom else y
		var dy := actual_y - left_center.y
		var inset := sqrt(maxf(0.0, pow(left_radius + 8.0, 2) - dy * dy))
		var left := maxf(midpoint.x - 84.0, left_center.x + inset + 5.0)
		points.append(Vector2(left, camera_zone.end.y - y if bottom else y))
	for i in range(16, -1, -1):
		var y := lerpf(18.0, 106.0, float(i) / 16.0)
		var actual_y := camera_zone.end.y - y if bottom else y
		var dy := actual_y - right_center.y
		var inset := sqrt(maxf(0.0, pow(right_radius + 8.0, 2) - dy * dy))
		var right := minf(midpoint.x + 84.0, right_center.x - inset - 5.0)
		points.append(Vector2(right, camera_zone.end.y - y if bottom else y))
	var rounded := PackedVector2Array()
	for i in range(points.size()):
		var p := points[i]
		var before := points[(i - 1 + points.size()) % points.size()]
		var after := points[(i + 1) % points.size()]
		var a := p.move_toward(before, minf(5.0, p.distance_to(before) * 0.4))
		var b := p.move_toward(after, minf(5.0, p.distance_to(after) * 0.4))
		for j in range(5):
			var t := float(j) / 4.0
			rounded.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	draw_colored_polygon(rounded, Color("201b32", 0.72))
	rounded.append(rounded[0])
	draw_polyline(rounded, Color("b98ebc", 0.48), 1.5, true)
