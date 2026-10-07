extends SceneTree
const SliderScript = preload("res://scripts/touch_slider.gd")
var checks := 0
var failures := 0
var label_changes: Array = []
var magnet_contacts := 0
var edit_requests := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SLIDER_LABELS: " + label)
func _initialize() -> void: _run.call_deferred()
func pointer(slider: Control, kind: String, pressed: bool, point: Vector2) -> void:
	var event: InputEvent
	if kind == "touch":
		event = InputEventScreenTouch.new()
		event.index = 6
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = slider.get_global_transform() * point
	root.push_input(event, true)
func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1100, 500)
	var slider = SliderScript.new()
	root.add_child(slider)
	for outer in [false, true]:
		slider.outer_layout = outer
		slider.size = Vector2(900, 160) if outer else Vector2(648, 88)
		slider.min_value = 20
		slider.max_value = 1000
		for caption in ["加注至", "RAISE TO"]:
			slider.caption = caption
			for labels in [["1/3", "1/2", "3/4", "1/1"], ["2 BB", "2.5 BB", "3 BB"], ["MIN", "1/2", "3/4", "1/1"]]:
				var points: Array = []
				for index in labels.size(): points.append({"value": 40 + index * 40, "label": labels[index]})
				slider.set_magnets(points)
				var layout: Dictionary = slider.header_layout()
				check(layout.label_rects.size() == points.size(), "all magnet labels always have cells")
				var previous: Rect2 = layout.caption_rect
				var font: Font = slider.get_theme_default_font()
				check(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, layout.caption_font_size).x <= layout.caption_rect.size.x + 1, "caption fits and remains visible")
				for index in labels.size():
					var rect: Rect2 = layout.label_rects[index]
					check(rect.position.x >= previous.end.x, "label does not overlap preceding label or caption")
					check(rect.end.x <= layout.value_rect.position.x, "label does not overlap numeric entry")
					check(font.get_string_size(labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, layout.label_font_size).x <= rect.size.x + 1, "label text fits assigned cell")
					previous = rect
				var marker: float = slider._magnet_track_x(points[0].value)
				for point in points: point.value += 100
				slider.set_magnets(points)
				check(slider.header_layout().label_rects == layout.label_rects, "pot changes never move header text")
				check(slider._magnet_track_x(points[0].value) != marker, "pot change moves actual leader endpoint")
				slider.value = 740
				slider.max_value = 2000
				check(slider.header_layout().label_rects == layout.label_rects, "value and range do not move header text")
				check(slider.header_layout().caption_rect == layout.caption_rect, "caption remains fixed")
				slider.max_value = 1000
				await process_frame
	# Reserve four cells so adding/removing a legal fourth landmark cannot shift text.
	for caption in ["加注至", "RAISE TO"]:
		slider.caption = caption
		for outer in [false, true]:
			slider.outer_layout = outer
			slider.size = Vector2(900, 160) if outer else Vector2(648, 88)
			slider.set_magnets([{"value": 50, "label": "1/3"}, {"value": 100, "label": "1/2"}, {"value": 150, "label": "3/4"}])
			var three: Array = slider.header_layout().label_rects
			slider.set_magnets([{"value": 50, "label": "1/3"}, {"value": 100, "label": "1/2"}, {"value": 150, "label": "3/4"}, {"value": 200, "label": "1/1"}])
			var four: Array = slider.header_layout().label_rects
			for index in three.size(): check(three[index] == four[index], "fourth legal landmark does not redistribute existing header cells")
	# Exercise real input routing, not an activation helper in isolation.
	slider.user_changed.connect(func(amount: float): label_changes.append(amount))
	slider.magnet_entered.connect(func(): magnet_contacts += 1)
	slider.value_edit_requested.connect(func(): edit_requests += 1)
	slider.allow_value_edit = true
	slider.caption = "RAISE TO"
	for outer in [false, true]:
		slider.outer_layout = outer
		slider.size = Vector2(900, 160) if outer else Vector2(648, 88)
		slider.set_magnets([{"value": 50, "label": "MIN"}, {"value": 125, "label": "1/2"}, {"value": 250, "label": "3/4"}, {"value": 400, "label": "1/1"}])
		await process_frame
		var rects: Array = slider.header_layout().label_rects
		for kind in ["touch", "mouse"]:
			for index in rects.size():
				slider.value = 900
				slider._snapped = -1
				var changed_before := label_changes.size()
				var contact_before := magnet_contacts
				var center: Vector2 = rects[index].get_center()
				pointer(slider, kind, true, center)
				check(slider.value == slider.magnets[index].value, "fixed label selects exact amount via " + kind)
				check(label_changes.size() == changed_before + 1 and label_changes.back() == slider.magnets[index].value, "label emits one user change")
				check(magnet_contacts == contact_before + 1, "label emits magnet contact")
				check(edit_requests == 0, "label never requests numeric editor")
				var motion: InputEvent
				if kind == "touch":
					motion = InputEventScreenDrag.new()
					motion.index = 6
				else:
					motion = InputEventMouseMotion.new()
					motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				motion.position = slider.get_global_transform() * Vector2(slider.size.x - 35, slider.size.y * 0.7)
				root.push_input(motion, true)
				pointer(slider, kind, false, center)
				check(slider.value == slider.magnets[index].value and slider._finger == -1, "label gesture never becomes an x-mapped drag")
		var unchanged: float = slider.value
		var contacts_before := magnet_contacts
		var changes_before := label_changes.size()
		var emulated := InputEventMouseButton.new()
		emulated.button_index = MOUSE_BUTTON_LEFT
		emulated.pressed = true
		emulated.device = InputEvent.DEVICE_ID_EMULATION
		emulated.position = rects[0].get_center()
		slider._gui_input(emulated)
		check(slider.value == unchanged and magnet_contacts == contacts_before and label_changes.size() == changes_before, "emulated mouse cannot repeat header activation")
		slider.editable = false
		for kind in ["touch", "mouse"]:
			pointer(slider, kind, true, rects[0].get_center())
			pointer(slider, kind, false, rects[0].get_center())
		check(slider.value == unchanged and magnet_contacts == contacts_before and label_changes.size() == changes_before, "disabled labels ignore both pointer types")
		slider.editable = true
		var amount_point: Vector2 = slider._value_edit_rect().get_center()
		pointer(slider, "touch", true, amount_point)
		pointer(slider, "touch", false, amount_point)
		check(edit_requests == 1 and slider.value == unchanged, "numeric amount retains separate exact editor")
		edit_requests = 0
		var track_y: float = 110.0 if outer else slider.size.y * 0.7
		pointer(slider, "touch", true, Vector2(slider._track_padding(), track_y))
		check(slider.value == slider.min_value and slider._finger == 6, "ordinary track keeps capture and x mapping")
		pointer(slider, "touch", false, Vector2(slider._track_padding(), track_y))
	slider.queue_free()
	await process_frame
	print("SLIDER_LABELS_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

