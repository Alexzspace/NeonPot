extends Control
signal strokes_changed(strokes: Array)
signal capacity_reached()
const Art = preload("res://scripts/kaleidoscope_art.gd")
var recipe: Dictionary = {}:
	set(value):
		recipe = value.duplicate(true)
		queue_redraw()
var ink_index := 0
var _finger := -1
var _active_points: Array = []
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_ALL
	clip_contents = true
	resized.connect(_finish)
func _half_size() -> Vector2: return Vector2(maxf(size.x * 0.5, 1), maxf(size.y * 0.5, 1))
func _draw() -> void:
	if recipe.is_empty(): return
	var center := size * 0.5
	var half_size := _half_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color.html(recipe.paper))
	var draft := recipe.duplicate(true)
	if not _active_points.is_empty(): draft.strokes.append({"points": _active_points.duplicate(true), "color": ink_index})
	for group in Art.geometry(draft):
		var points := PackedVector2Array()
		for point in group.points: points.append(center + point * half_size)
		var ink := Color.html(recipe.primary if int(group.color) == 0 else recipe.accent)
		ink.a = group.alpha
		if points.size() >= 2: draw_multiline(points, ink, float(recipe.get("line_width", 2)) * minf(half_size.x, half_size.y) / 60.0, true)
func _begin(at: Vector2, pointer: int) -> void:
	if _finger != -1: return
	if recipe.get("strokes", []).size() >= 16:
		capacity_reached.emit()
		return
	var count := 0
	for stroke in recipe.get("strokes", []): count += stroke.points.size()
	if count >= 512:
		capacity_reached.emit()
		return
	_finger = pointer
	grab_focus()
	_active_points = []
	_append(at)
func _append(at: Vector2) -> void:
	# Leaving the canvas ends this stroke; re-entry must start a new stroke.
	# This avoids clamping outside pointer motion into artificial border lines.
	if not Rect2(Vector2.ZERO, size).has_point(at):
		_finish()
		return
	var point := (at - size * 0.5) / _half_size()
	var count := _active_points.size()
	for stroke in recipe.get("strokes", []): count += stroke.points.size()
	if _active_points.size() >= 64 or count >= 512:
		capacity_reached.emit()
		return
	if not _active_points.is_empty() and Vector2(_active_points[-1][0], _active_points[-1][1]).distance_to(point) < 0.018: return
	var quantized := Vector2(snappedf(point.x, 0.001), snappedf(point.y, 0.001))
	_active_points.append([quantized.x, quantized.y])
	queue_redraw()
func _finish() -> void:
	if _finger == -1: return
	_finger = -1
	if _active_points.size() >= 1:
		var strokes: Array = recipe.get("strokes", []).duplicate(true)
		strokes.append({"points": _active_points.duplicate(true), "color": ink_index})
		_active_points.clear()
		recipe.strokes = strokes
		strokes_changed.emit(strokes)
	_active_points.clear()
	queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed: _begin(event.position, event.index)
		elif event.index == _finger: _finish()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _finger:
		_append(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed: _begin(event.position, -2)
		elif _finger == -2: _finish()
		accept_event()
	elif event is InputEventMouseMotion and _finger == -2:
		_append(event.position)
		accept_event()
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _finger: _finish()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _finger == -2: _finish()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED]: _finish()
