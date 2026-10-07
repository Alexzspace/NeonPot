extends SceneTree
const Exact = preload("res://scripts/exact_raise_panel.gd")
var checks := 0
var failures := 0
var values: Array[int] = []
var cancelled := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var panel = Exact.new()
	panel.configure(100, 20, 3000, "zh")
	panel.size = Vector2(520, 300)
	root.add_child(panel)
	panel.accepted.connect(func(value: int) -> void: values.append(value))
	panel.cancel_requested.connect(func() -> void: cancelled += 1)
	await process_frame
	check(panel._wheel.step == 1 and panel._wheel.value == 100, "reel starts at configured exact integer")
	check(panel._wheel.numeral_size >= 52 and not panel._edit.visible and not panel._edit.has_focus(), "large reel never opens keyboard by default")
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	touch.position = Vector2(260, 130)
	touch.pressed = true
	root.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(260, 62)
	drag.relative = Vector2(0, -68)
	root.push_input(drag, true)
	touch = touch.duplicate()
	touch.position = drag.position
	touch.pressed = false
	touch.canceled = true
	root.push_input(touch, true)
	check(panel._wheel.value == 101 and panel._edit.text == "101", "native vertical drag changes exactly one unit and syncs keyboard draft")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = Vector2(260, 100)
	wheel.pressed = true
	root.push_input(wheel, true)
	check(panel._wheel.value == 102, "mouse wheel advances one integer")
	panel._toggle_keyboard()
	check(panel._edit.visible and panel._edit.text == "102" and panel._edit.has_focus(), "keyboard only opens on explicit toggle with current value")
	for code in [KEY_7, KEY_2, KEY_5]:
		var key := InputEventKey.new()
		key.keycode = code
		key.unicode = code
		key.pressed = true
		root.push_input(key, true)
	await process_frame
	check(panel._wheel.value == 725, "keyboard input synchronizes hidden reel")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	check(values == [725], "keyboard Enter accepts selected draft")
	panel._edit.text = "999999"
	panel._edit.text_changed.emit(panel._edit.text)
	panel._apply()
	check(values[-1] == 3000 and panel._edit.text == "3000", "keyboard value above stack clamps to maximum")
	panel._edit.text = "-2"
	panel._edit.text_changed.emit(panel._edit.text)
	panel._apply()
	check(values[-1] == 20, "keyboard value below minimum clamps to legal minimum")
	var accepted_before := values.size()
	for invalid in ["", "abc", "1.5"]:
		panel._edit.text = invalid
		panel._edit.text_changed.emit(invalid)
		panel._apply()
		check(panel._apply_button.disabled and values.size() == accepted_before, "invalid keyboard text cannot accept: " + invalid)
	panel._edit.text = "431"
	panel._edit.text_changed.emit(panel._edit.text)
	panel._toggle_keyboard()
	check(panel._wheel.visible and panel._wheel.value == 431 and not panel._edit.visible, "returning to reel preserves keyboard selection")
	var cancel_touch := InputEventScreenTouch.new()
	cancel_touch.position = panel._cancel_button.position + panel._cancel_button.size * 0.5
	cancel_touch.index = 2
	cancel_touch.pressed = true
	root.push_input(cancel_touch, true)
	cancel_touch = cancel_touch.duplicate()
	cancel_touch.pressed = false
	root.push_input(cancel_touch, true)
	check(cancelled == 1 and values.size() == accepted_before, "cancel never emits accepted draft")
	panel.configure(9000, 20, 3000, "en")
	check(panel._wheel.value == 3000 and panel._toggle.text == "Keyboard", "reconfiguration clamps initial value and resets mode")
	panel.queue_free()
	await process_frame
	print("EXACT_RAISE_PANEL_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
