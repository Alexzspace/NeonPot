class_name PublicPokerCard
extends "res://scripts/card_view.gd"
## Public-card motion is cosmetic and server-confirmed. Never uses private-card peeking.

signal gesture_requested(kind: String, offset: Vector2)

const DRAG_INTERVAL_USEC := 50000
const HEARTBEAT_USEC := 250000
const DRAG_DISTANCE := 16.0

var public_interactive := false:
	set(value):
		if public_interactive == value: return
		public_interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if not value: cancel_public_gesture()

var _public_pointer := -2
var _press_origin := Vector2.ZERO
var _request_offset := Vector2.ZERO
var _request_dirty := false
var _last_request_usec := 0
var _public_down := false
var _public_offset := Vector2.ZERO
var _public_target := Vector2.ZERO
var _public_velocity := Vector2.ZERO
var _public_angle := 0.0
var _public_angle_target := 0.0
var _public_angle_velocity := 0.0

func _ready() -> void:
	super._ready()
	interactive = false
	mouse_filter = Control.MOUSE_FILTER_STOP if public_interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(reset_public_gesture)
	set_notify_transform(true)

func set_card(value: int, revealed: bool = true) -> void:
	var clean := value if value >= 0 and value < 52 else -1
	if clean == card_id and revealed == face_up: return
	reset_public_gesture()
	super.set_card(clean, revealed)

func flip(revealed: bool) -> void:
	if revealed == face_up: return
	reset_public_gesture()
	super.flip(revealed)

func apply_public_gesture(kind: String, offset: Vector2) -> void:
	if not offset.is_finite() or kind not in ["press", "drag", "release"]: return
	if kind == "release":
		_public_down = false
		_public_target = Vector2.ZERO
		_public_angle_target = 0.0
		# An authoritative release (including expiry) ends local ownership too.
		_public_pointer = -2
		_request_dirty = false
	else:
		if is_inside_tree() and not is_visible_in_tree(): return
		if kind == "drag" and not _public_down: return
		_public_down = true
		var clean := offset.clamp(Vector2(-1, -1), Vector2.ONE)
		_public_target = clean.limit_length(1.0) * 12.0 + Vector2(0, -4)
		_public_angle_target = clean.x * 0.08
	queue_redraw()

func cancel_public_gesture(reset_visual: bool = false) -> void:
	var was_local := _public_pointer != -2
	_public_pointer = -2
	_request_dirty = false
	_request_offset = Vector2.ZERO
	if reset_visual: _reset_public_visual()
	if was_local: gesture_requested.emit("release", Vector2.ZERO)

func reset_public_gesture() -> void:
	# Lifecycle reset differs from a rejected user's local cancellation.
	cancel_public_gesture(true)

func _reset_public_visual() -> void:
	_public_down = false
	_public_target = Vector2.ZERO
	_public_offset = Vector2.ZERO
	_public_velocity = Vector2.ZERO
	_public_angle = 0.0
	_public_angle_target = 0.0
	_public_angle_velocity = 0.0
	_peeking = false
	queue_redraw()

func _process(delta: float) -> void:
	super._process(delta)
	if _public_pointer != -2:
		var elapsed := Time.get_ticks_usec() - _last_request_usec
		if (_request_dirty and elapsed >= DRAG_INTERVAL_USEC) or elapsed >= HEARTBEAT_USEC:
			_emit_drag()
	var moving := _public_offset.distance_squared_to(_public_target) > 0.00001 or _public_velocity.length_squared() > 0.00001 or absf(_public_angle - _public_angle_target) > 0.00001 or absf(_public_angle_velocity) > 0.00001
	if not moving: return
	var step := minf(maxf(delta, 0), 0.033)
	_public_velocity += ((_public_target - _public_offset) * 190.0 - _public_velocity * 22.0) * step
	_public_offset = (_public_offset + _public_velocity * step).limit_length(16.0)
	_public_angle_velocity += ((_public_angle_target - _public_angle) * 190.0 - _public_angle_velocity * 22.0) * step
	_public_angle = clampf(_public_angle + _public_angle_velocity * step, -0.10, 0.10)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not public_interactive or _public_pointer != -2: return
	if event is InputEventScreenTouch and event.pressed:
		_begin_public_press(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.device != InputEvent.DEVICE_ID_EMULATION and not Input.emulate_touch_from_mouse:
			_begin_public_press(-1, event.position)
			accept_event()

func _begin_public_press(pointer: int, at: Vector2) -> void:
	_public_pointer = pointer
	_press_origin = at
	_request_offset = Vector2.ZERO
	_request_dirty = false
	_last_request_usec = Time.get_ticks_usec()
	gesture_requested.emit("press", Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if _public_pointer == -2: return
	if event is InputEventScreenTouch and event.index == _public_pointer and not event.pressed:
		_finish_public_press()
	elif event is InputEventScreenDrag and event.index == _public_pointer:
		_request_drag(event.position)
	elif event is InputEventMouseButton and _public_pointer == -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if event.device != InputEvent.DEVICE_ID_EMULATION: _finish_public_press()
	elif event is InputEventMouseMotion and _public_pointer == -1 and event.device != InputEvent.DEVICE_ID_EMULATION:
		_request_drag(event.position)

func _request_drag(viewport_position: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse() * viewport_position
	_request_offset = ((local - _press_origin) / DRAG_DISTANCE).clamp(Vector2(-1, -1), Vector2.ONE)
	_request_dirty = true
	if Time.get_ticks_usec() - _last_request_usec >= DRAG_INTERVAL_USEC: _emit_drag()

func _emit_drag() -> void:
	_request_dirty = false
	_last_request_usec = Time.get_ticks_usec()
	gesture_requested.emit("drag", _request_offset)

func _finish_public_press() -> void:
	_public_pointer = -2
	_request_dirty = false
	gesture_requested.emit("release", Vector2.ZERO)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_TRANSFORM_CHANGED]:
		reset_public_gesture()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset_public_gesture()

func _exit_tree() -> void:
	reset_public_gesture()

func _draw_center() -> Vector2:
	return super._draw_center() + _public_offset

func _draw_angle() -> float:
	return super._draw_angle() + _public_angle

func _draw() -> void:
	# A drawing-only transform leaves the original hit rectangle and deal tween intact.
	var ratio := size / BASE
	var center := _draw_center()
	var angle := _draw_angle()
	draw_set_transform(center, angle, ratio * Vector2(_flip_width, 1.0))
	var outline := _outline(Rect2(-BASE * 0.5, BASE), 5.0)
	for i in range(4, 0, -1):
		var shadow := PackedVector2Array()
		for point in outline:
			shadow.append(point + Vector2(0, 2 + i * 2 + (2 if _public_down else 0)))
		draw_colored_polygon(shadow, Color(0.015, 0.025, 0.035, 0.055 * _deal_alpha))
	draw_colored_polygon(outline, _c(Themes.paper(_theme())))
	if face_up and card_id >= 0: _draw_face()
	else: _draw_back()
	draw_polyline(outline + PackedVector2Array([outline[0]]), _c(Themes.edge(_theme())), 1.0)
	draw_set_transform(Vector2.ZERO)
