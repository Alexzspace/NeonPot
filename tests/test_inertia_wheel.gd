extends SceneTree
const Wheel = preload("res://scripts/inertia_wheel.gd")
var checks := 0
var failures := 0
var changes: Array[float] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WHEEL: " + message)
func touch(point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)
func drag(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = index
	root.push_input(event, true)
func _run() -> void:
	root.size = Vector2i(800, 600)
	var wheel := Wheel.new()
	wheel.position = Vector2(100, 100)
	wheel.size = Vector2(240, 88)
	wheel.min_value = 500
	wheel.max_value = 10000
	wheel.step = 500
	wheel.value = 1000
	wheel.user_changed.connect(func(v): changes.append(v))
	root.add_child(wheel)
	await process_frame
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 105))
	check(wheel.value == 1500, "native drag advances one500-chip stop")
	touch(Vector2(210, 145), true, 1)
	drag(Vector2(210, 20), 1)
	touch(Vector2(210, 20), false, 1)
	check(wheel.value == 1500 and wheel._pointer == 0, "second finger cannot hijack held reel")
	touch(Vector2(200, 105), false)
	await create_timer(0.15).timeout
	check(wheel.value > 1500, "released fast drag coasts through further stops")
	await create_timer(1.4).timeout
	check(absf(wheel._position - roundf(wheel._position)) < 0.01 and wheel._velocity == 0, "inertia settles into a magnetic stop")
	check(changes.size() > 1, "user feedback emitted at discrete stop crossings")
	for v in changes: check(fmod(v, 500) == 0 and v >= 500 and v <= 10000, "all emitted values are valid500-chip steps")
	wheel.value = 9500
	touch(Vector2(200, 145), true)
	drag(Vector2(200, -900))
	touch(Vector2(200, -900), false)
	await create_timer(0.2).timeout
	check(wheel.value == 10000, "upper bound holds under high-velocity swipe outside control")
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 2000))
	touch(Vector2(200, 2000), false, 0, true)
	check(wheel.value == 500 and wheel._velocity == 0, "canceled gesture stops safely at lower bound")
	var old_changes := changes.size()
	wheel.value = 5000
	check(wheel._position == 9 and changes.size() == old_changes, "programmatic setting synchronizes without user feedback")
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 120))
	wheel.hide()
	check(wheel._pointer == -2 and wheel._velocity == 0 and wheel._position == wheel._index(), "hide cancels held pointer and settles value")
	wheel.show()
	wheel.min_value = 2
	wheel.max_value = 6
	wheel.step = 1
	wheel.value = 3
	wheel.strong_snap = true
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 105))
	touch(Vector2(200, 105), false)
	await create_timer(0.7).timeout
	check(wheel.value >= 4 and wheel.value <= 6 and absf(wheel._position - roundf(wheel._position)) < 0.01, "player reel has stronger short-travel settlement")
	wheel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(wheel._pointer == -2 and wheel._velocity == 0, "application focus loss cleans gesture state")
	var modal := Panel.new()
	modal.position = Vector2(50, 50)
	modal.size = Vector2(400, 300)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(modal)
	await process_frame
	var covered_value: float = wheel.value
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 105))
	touch(Vector2(200, 105), false)
	check(wheel._pointer == -2 and wheel.value == covered_value, "visible modal shields underlying reel from native touches")
	var mouse := InputEventMouseButton.new()
	mouse.position = Vector2(200, 145)
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	mouse.pressed = true
	root.push_input(mouse, true)
	check(wheel.value == covered_value, "visible modal shields underlying reel from mouse wheel")
	modal.queue_free()
	await process_frame
	wheel.value = 3
	touch(Vector2(200, 145), true)
	drag(Vector2(200, 105))
	touch(Vector2(200, 105), false, 0, true)
	check(wheel.value == 4, "native reel interaction resumes after modal closes")
	wheel.queue_free()
	await process_frame
	print("INERTIA_WHEEL_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
