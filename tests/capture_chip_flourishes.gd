extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(640, 480)
	root.content_scale_size = Vector2i(640, 480)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var background := ColorRect.new()
	background.color = Color("11101d")
	background.size = Vector2(640, 480)
	root.add_child(background)
	var label := Label.new()
	label.position = Vector2(20, 14)
	label.add_theme_font_size_override("font_size", 20)
	root.add_child(label)
	var display = Display.new()
	display.size = Vector2(318, 218)
	display.position = Vector2(160, 220)
	display.visual_scale = 1.5
	root.add_child(display)
	var names := ["STACK PRESS", "CROSS SHUFFLE", "LAYER FAN", "PUSH CUT", "MASTER SHUFFLE", "FINGER RAKE"]
	var progress := [0.0, 0.34, 0.54, 0.72]
	for amount in [1000, 10000]:
		display.set_amount(amount, false)
		var sheet := Image.create(1280, 1440, false, Image.FORMAT_RGBA8)
		for style in 6:
			display.flourish(style)
			display._animation.pause()
			for frame in 4:
				label.text = "%s · %d · %d%%" % [names[style], amount, int(progress[frame] * 100)]
				display._pose_flourish(progress[frame])
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var capture := root.get_texture().get_image()
				capture.convert(Image.FORMAT_RGBA8)
				capture.resize(320, 240)
				sheet.blit_rect(capture, Rect2i(0, 0, 320, 240), Vector2i(frame * 320, style * 240))
			display.cancel_flourish()
		var path := "res://test-results/chip-dynamics-%d.png" % amount
		print("CHIP_DYNAMICS_CAPTURE error=%d path=%s" % [sheet.save_png(path), ProjectSettings.globalize_path(path)])
	display.queue_free()
	background.queue_free()
	label.queue_free()
	await process_frame
	await process_frame
	quit()
