extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
const Feedback = preload("res://scripts/feedback.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1311, 603)
	root.content_scale_size = Vector2i(1311, 603)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var backdrop := ColorRect.new()
	backdrop.color = Color("11101d")
	backdrop.size = Vector2(1311, 603)
	root.add_child(backdrop)
	var label := Label.new()
	label.position = Vector2(36, 26)
	label.add_theme_font_size_override("font_size", 28)
	label.z_index = 100
	root.add_child(label)
	var feedback := Feedback.new()
	root.add_child(feedback)
	feedback.volume = 0.7
	feedback.haptic_strength = 0
	var displays: Array = []
	for index in 2:
		var amount_label := Label.new()
		amount_label.text = "1000" if index == 0 else "10000"
		amount_label.position = Vector2(260 + index * 600, 560)
		amount_label.add_theme_font_size_override("font_size", 26)
		backdrop.add_child(amount_label)
		var display := Display.new()
		display.size = Vector2(318, 218)
		display.position = Vector2(160 + index * 600, 315)
		display.visual_scale = 1.5
		root.add_child(display)
		display.set_amount(1000 if index == 0 else 10000, false)
		if index == 0: display.contact.connect(func(kind: String): feedback.play_chip_contact(kind, true))
		displays.append(display)
	for style in [0, 1, 2, 3, 5, 4]:
		label.text = "NEON POT 1.1.1  /  %s" % ("HIDDEN / 2s" if style == Gestures.RARE else "STYLE %d / 1s" % style)
		await create_timer(0.3).timeout
		for display in displays: display.flourish(style)
		await create_timer(Gestures.duration(style) + 0.25).timeout
	for display in displays: display.queue_free()
	feedback.queue_free()
	label.queue_free()
	backdrop.queue_free()
	await process_frame
	await process_frame
	quit()
