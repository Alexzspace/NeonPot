extends Control
## Each physical press requests one prop contact; emulated mouse is never a second tap.
signal pressed()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		pressed.emit()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION and not Input.emulate_touch_from_mouse:
			pressed.emit()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
		pressed.emit()
		accept_event()
