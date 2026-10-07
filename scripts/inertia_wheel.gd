extends Range
## A bounded touch reel; values stay discrete while the print glides between stops.
signal user_changed(new_value: float)
const FONT = preload("res://assets/fonts/fusion-pixel.ttf")
const PITCH := 40.0
var slot_pitch := PITCH
var numeral_size := 30
var strong_snap := false
var _position := 0.0
var _velocity := 0.0
var _pointer := -2
var _last_y := 0.0
var _last_time := 0
var _last_motion := 0
var _internal := false

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_ALL
	clip_contents = true
	_position = _index()
	value_changed.connect(_external_change)
	resized.connect(queue_redraw)
	queue_redraw()

func _index() -> float:
	return (value - min_value) / maxf(step, 0.001)

func _count() -> float:
	return floorf((max_value - min_value) / maxf(step, 0.001))

func _external_change(_new_value: float) -> void:
	if not _internal:
		_position = _index()
		_velocity = 0.0
	queue_redraw()

func _commit_position() -> void:
	var previous := value
	_internal = true
	value = min_value + roundf(_position) * step
	_internal = false
	if not is_equal_approx(previous, value): user_changed.emit(value)
	queue_redraw()

func _point(event: InputEvent) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * event.position

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _pointer == -2: return
	if event is InputEventScreenTouch and not event.pressed and event.index == _pointer:
		_release(event.canceled)
	elif event is InputEventScreenDrag and event.index == _pointer:
		_move(_point(event).y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _pointer == -1:
		_release(false)
	elif event is InputEventMouseMotion and _pointer == -1:
		_move(_point(event).y)

func _gui_input(event: InputEvent) -> void:
	# Let Godot hit-test the initial press, so settings/modal panels shield the reel.
	if event is InputEventScreenTouch and event.pressed:
		_press(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.device != -1 and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not Input.emulate_touch_from_mouse:
			_press(-1, event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_nudge(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			accept_event()
	elif event is InputEventKey and event.pressed and has_focus():
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_HOME, KEY_END]:
			if event.keycode == KEY_HOME: _nudge(-_count())
			elif event.keycode == KEY_END: _nudge(_count())
			else: _nudge(1 if event.keycode == KEY_UP else -1)
			accept_event()

func _press(pointer: int, point: Vector2) -> void:
	if _pointer != -2 or not Rect2(Vector2.ZERO, size).has_point(point): return
	_pointer = pointer
	_velocity = 0.0
	_last_y = point.y
	_last_time = Time.get_ticks_usec()
	_last_motion = _last_time
	grab_focus()
	get_viewport().set_input_as_handled()

func _move(y: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := maxf(0.008, (now - _last_time) / 1000000.0)
	var travel := (_last_y - y) / slot_pitch
	_position = clampf(_position + travel, 0, _count())
	_velocity = lerpf(_velocity, clampf(travel / elapsed, -24, 24), 0.65)
	_last_y = y
	_last_time = now
	if absf(travel) > 0.001: _last_motion = now
	_commit_position()
	get_viewport().set_input_as_handled()

func _release(canceled: bool) -> void:
	_pointer = -2
	if canceled or Time.get_ticks_usec() - _last_motion > 110000: _velocity = 0.0
	get_viewport().set_input_as_handled()

func _nudge(amount: float) -> void:
	_velocity = 0.0
	_position = clampf(roundf(_position) + amount, 0, _count())
	_commit_position()

func _process(delta: float) -> void:
	if _pointer != -2: return
	if absf(_velocity) > 0.12:
		_position = clampf(_position + _velocity * delta, 0, _count())
		_velocity *= exp(-(17.0 if strong_snap else 6.0) * delta)
		if _position <= 0 or _position >= _count(): _velocity = 0.0
	else:
		_velocity = 0.0
		_position = lerpf(_position, roundf(_position), 1.0 - exp(-(24.0 if strong_snap else 13.0) * delta))
		if absf(_position - roundf(_position)) < 0.001: _position = roundf(_position)
	if not is_equal_approx(_position, _index()): _commit_position()

func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("1c1a30")
	background.border_color = Color("8b6594") if has_focus() else Color("55405f")
	background.set_border_width_all(2)
	background.set_corner_radius_all(9)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var center := size.y * 0.5
	draw_rect(Rect2(9, center - slot_pitch * 0.5, maxf(0, size.x - 18), slot_pitch), Color("30243f"))
	for offset in range(-2, 3):
		var index := roundi(_position) + offset
		if index < 0 or index > _count(): continue
		var y := center + (index - _position) * slot_pitch
		var distance := absf(y - center) / slot_pitch
		var color := Color("edc8ef")
		color.a = clampf(1.0 - distance * 0.66, 0.12, 1.0)
		var text := str(roundi(min_value + index * step))
		draw_string(FONT, Vector2(14, y + numeral_size * 0.3667), text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 28, numeral_size, color)
	for side in [-1, 1]:
		var y: float = center + side * slot_pitch * 0.5
		draw_line(Vector2(12, y), Vector2(size.x - 12, y), Color("805680"), 1)

func _cancel() -> void:
	_pointer = -2
	_velocity = 0.0
	_position = _index()
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]: _cancel()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree(): _cancel()
	elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT: queue_redraw()

func _exit_tree() -> void:
	_pointer = -2
	_velocity = 0.0
