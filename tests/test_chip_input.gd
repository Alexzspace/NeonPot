extends SceneTree
const ChipSlider = preload("res://scripts/touch_slider.gd")
const Hold = preload("res://scripts/chip_hold_button.gd")
var checks := 0
var failures := 0
var taps := 0
var holds := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var slider = ChipSlider.new()
	root.add_child(slider)
	slider.size = Vector2(660, 88)
	slider.min_value = 20
	slider.max_value = 1020
	slider.step = 1
	slider.set_magnets([{"value": 520, "label": "1/2"}])
	slider._set_from_x(334)
	check(slider.value == 520, "slow drag gently attracts within ten logical pixels")
	slider._last_drag_ms = 0
	slider._set_from_x(360)
	check(slider.value != 520, "continued drag leaves magnet")
	slider._finger = 0
	slider.set_magnets([{"value": 700, "label": "3/4"}])
	check(slider.magnets[0].value == 520, "magnets frozen while finger held")
	slider._finger = -1
	slider.set_magnets([{"value": 700, "label": "3/4"}])
	check(slider.magnets[0].value == 700, "next drag gets current pot landmarks")
	var button = Hold.new()
	root.add_child(button)
	button.size = Vector2(200, 100)
	button.hold_enabled = true
	button.short_tapped.connect(func(): taps += 1)
	button.hold_completed.connect(func(): holds += 1)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = Vector2(50, 50)
	down.pressed = true
	button._gui_input(down)
	button._process(0.5)
	var up = down.duplicate()
	up.pressed = false
	button._gui_input(up)
	check(taps == 1 and holds == 0, "short release only fidgets")
	button._gui_input(down)
	button._process(1.01)
	button._gui_input(up)
	check(taps == 1 and holds == 1, "long hold does not also short tap")
	button._gui_input(down)
	button._process(0.5)
	button.cancel_hold()
	button._process(1.0)
	check(holds == 1, "cancelled hold cannot open later")
	button.queue_free()
	slider.queue_free()
	await process_frame
	print("CHIP_INPUT_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
