extends Button
## Short release plays; a deliberate one-second hold opens chip selection.
signal short_tapped
signal hold_completed
signal hold_progress(progress: float)
var hold_enabled := false
var _pointer := -1
var _elapsed := 0.0
var _completed := false
var _start := Vector2.ZERO

func _ready() -> void:
	pressed.connect(func():
		if _pointer == -1 and not _completed: short_tapped.emit())

func cancel_hold() -> void:
	_pointer = -1
	_elapsed = 0.0
	_completed = false
	hold_progress.emit(0.0)

func _process(delta: float) -> void:
	if _pointer == -1 or _completed: return
	if disabled or not is_visible_in_tree():
		cancel_hold()
		return
	if not hold_enabled: return
	_elapsed += delta
	hold_progress.emit(minf(_elapsed, 1.0))
	if _elapsed >= 1.0:
		_completed = true
		hold_completed.emit()

func _gui_input(event: InputEvent) -> void:
	if disabled: return
	var down := false
	var up := false
	var id := -1
	var at := Vector2.ZERO
	if event is InputEventScreenTouch:
		id = event.index
		down = event.pressed
		up = not event.pressed
		at = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		id = -2
		down = event.pressed
		up = not event.pressed
		at = event.position
	elif event is InputEventScreenDrag and event.index == _pointer:
		if event.position.distance_to(_start) > 28.0: cancel_hold()
		accept_event()
		return
	elif event is InputEventMouseMotion and _pointer == -2:
		if event.position.distance_to(_start) > 28.0: cancel_hold()
		accept_event()
		return
	else: return
	if down and _pointer == -1:
		_pointer = id
		_start = at
		_elapsed = 0.0
		_completed = false
	elif up and id == _pointer:
		var tap := not _completed and Rect2(Vector2.ZERO, size).has_point(at)
		cancel_hold()
		if tap: short_tapped.emit()
	accept_event()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_EXIT_TREE]:
		cancel_hold()
