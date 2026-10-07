extends SceneTree
## Native viewport dispatch through a scaled Control, plus isolated lifecycle probes.

const SliderScript = preload("res://scripts/touch_slider.gd")
var checks := 0
var failures := 0
var slider: Range
var edits := 0
var changed: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TOUCH_SLIDER FAILED: " + label)


func _touch(index: int, pressed: bool, local_position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = slider.get_global_transform() * local_position
	root.push_input(event, true)


func _drag(index: int, local_position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = slider.get_global_transform() * local_position
	root.push_input(event, true)


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(900, 500)
	var surface := Control.new()
	surface.position = Vector2(30, 40)
	surface.size = Vector2(850, 430)
	surface.scale = Vector2(0.9, 0.9)
	root.add_child(surface)
	slider = SliderScript.new()
	slider.position = Vector2(40, 50)
	slider.size = Vector2(596, 112)
	slider.min_value = 0
	slider.max_value = 10
	slider.step = 1
	slider.value = 0
	slider.caption = "SOUND EFFECTS"
	slider.notches = true
	slider.user_changed.connect(func(value: float): changed.append(value))
	slider.value_edit_requested.connect(func(): edits += 1)
	surface.add_child(slider)
	var other := Button.new()
	other.position = Vector2(40, 250)
	other.size = Vector2(200, 80)
	other.text = "Other control"
	surface.add_child(other)
	await process_frame
	_touch(3, true, Vector2(30, 78))
	_check(slider._finger == 3 and slider.has_focus(), "actual scaled viewport touch captures one finger")
	_drag(3, Vector2(298, 78))
	_check(slider.value == 5, "actual touch drag reaches midpoint integer")
	var prior: float = slider.value
	_touch(4, true, Vector2(520, 78))
	_drag(4, Vector2(560, 78))
	_touch(4, false, Vector2(560, 78))
	_check(slider._finger == 3 and slider.value == prior, "second finger cannot hijack or release first finger")
	_drag(3, Vector2(750, 78))
	_check(slider.value == 10, "outside drag clamps maximum")
	_drag(3, Vector2(-100, 78))
	_check(slider.value == 0, "outside drag clamps minimum")
	_touch(3, false, Vector2(-100, 78))
	_check(slider._finger == -1, "release outside slider clears capture")
	prior = slider.value
	_drag(3, Vector2(500, 78))
	_check(slider.value == prior, "orphan drag after release does nothing")
	for level in range(11):
		var x := lerpf(30.0, 566.0, float(level) / 10.0)
		_touch(3, true, Vector2(x, 78))
		_touch(3, false, Vector2(x, 78))
		_check(slider.value == level, "level %d is reachable by viewport touch" % level)
	for value in changed:
		_check(value == roundf(value) and value >= 0 and value <= 10, "user signals expose only integer 0–10 values")
	slider.editable = false
	prior = slider.value
	_touch(3, true, Vector2(30, 78))
	_drag(3, Vector2(300, 78))
	_touch(3, false, Vector2(300, 78))
	_check(slider.value == prior and slider._finger == -1, "disabled slider ignores touch")
	slider.editable = true
	_touch(3, true, Vector2(200, 78))
	slider.editable = false
	_check(slider._finger == -1, "disabling during a drag cancels capture")
	_touch(3, false, Vector2(200, 78))
	slider.editable = true
	slider.allow_value_edit = true
	prior = slider.value
	_touch(3, true, Vector2(500, 20))
	_touch(3, false, Vector2(500, 20))
	_check(edits == 1 and slider.value == prior and slider._finger == -1, "value title tap requests exact editor without dragging")
	_touch(3, true, Vector2(200, 78))
	slider.notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(slider._finger == -1, "application focus loss cancels capture")
	_touch(3, false, Vector2(200, 78))
	_touch(3, true, Vector2(200, 78))
	other.grab_focus()
	_check(slider._finger == -1, "control focus moving elsewhere cancels capture")
	_touch(3, false, Vector2(200, 78))
	_touch(3, true, Vector2(200, 78))
	slider.hide()
	_check(slider._finger == -1, "hiding slider cancels capture")
	slider.show()
	_touch(3, false, Vector2(200, 78))
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(30, 78)
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	prior = slider.value
	slider._gui_input(mouse)
	_check(slider.value == prior and slider._finger == -1, "emulated mouse does not duplicate touch input")
	slider.outer_layout = true
	slider.size.y = 164
	await process_frame
	for level in range(11):
		var x := lerpf(44.0, 552.0, float(level) / 10.0)
		_touch(3, true, Vector2(x, 110))
		_touch(3, false, Vector2(x, 110))
		_check(slider.value == level, "outer track touch reaches level %d at drawn geometry" % level)
	prior = slider.value
	_touch(3, true, Vector2(370, 60))
	_touch(3, false, Vector2(370, 60))
	_check(edits == 2 and slider.value == prior and slider._finger == -1, "outer enlarged amount region opens exact editor without changing value")
	_touch(3, true, Vector2(44, 110))
	_check(slider._finger == 3 and slider.value == 0, "outer track remains draggable below amount header")
	slider.outer_layout = false
	_check(slider._finger == -1, "layout switch cancels active touch")
	_touch(3, false, Vector2(44, 110))
	slider.size.y = 112
	prior = slider.value
	_touch(3, true, Vector2(370, 60))
	_touch(3, false, Vector2(370, 60))
	_check(edits == 2 and slider.value != prior, "normal layout restores original smaller amount hit region")
	surface.queue_free()
	await process_frame
	print("TOUCH_SLIDER_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
