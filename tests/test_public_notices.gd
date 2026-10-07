extends SceneTree
const About = preload("res://scripts/about_view.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PUBLIC_NOTICES: " + message)

func tap(control: Control) -> void:
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func run() -> void:
	root.size = Vector2i(1440, 660)
	check(FileAccess.file_exists("res://licenses/NOTICE.txt"), "packaged notices exist")
	for language in ["en", "zh"]:
		var about := About.new()
		about.language = language
		about.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var palette := Theme.new()
		palette.default_font = load("res://assets/fonts/fusion-pixel.ttf")
		about.theme = palette
		root.add_child(about)
		await process_frame
		await process_frame
		check(about.notices == null, "notices are loaded only on request")
		check(about.notices_button.text == ("许可证与鸣谢" if language == "zh" else "LICENSES AND CREDITS"), "localized notice action")
		about.scroll.ensure_control_visible(about.notices_button)
		await process_frame
		await process_frame
		check(about.scroll.get_global_rect().encloses(about.notices_button.get_global_rect()), "notice button is reachable in About scroll")
		await tap(about.notices_button)
		await process_frame
		await process_frame
		check(is_instance_valid(about.notices) and about.notices.visible, "native touch reveals notices")
		if is_instance_valid(about.notices):
			for required in ["MIT License", "Fusion Pixel Font", "Godot"]:
				check(required in about.notices.text, "notices include " + required)
			check(about.notices.selection_enabled and about.notices.scroll_active, "notices can be selected and independently scrolled")
			check(about.notices.size.y >= 300 and about.notices.size.y <= 400, "notice reader has bounded readable height")
			check(about.scroll.get_global_rect().encloses(about.notices.get_global_rect()), "opened notice reader scrolls into full view")
			if DisplayServer.get_name() != "headless" and "--capture-notices" in OS.get_cmdline_user_args():
				DirAccess.make_dir_recursive_absolute("res://test-results")
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png("res://test-results/public-notices-" + language + ".png") == OK, "capture notice reader")
			about.scroll.ensure_control_visible(about.notices_button)
			await process_frame
			await process_frame
			await tap(about.notices_button)
			check(not about.notices.visible, "second native tap collapses notices")
		about.queue_free()
		await process_frame
		await process_frame
	# Close while the reader's two-frame layout coroutine is still pending.
	# Detaching without freeing also tests that a surviving node has no tree.
	for close_mode in ["immediate", "next-frame", "detached"]:
		var closing_about := About.new()
		closing_about.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(closing_about)
		closing_about._toggle_notices()
		check(is_instance_valid(closing_about.notices), "rapid-close fixture opens reader")
		if close_mode == "next-frame":
			await process_frame
		if close_mode == "detached":
			root.remove_child(closing_about)
			await process_frame
			await process_frame
		closing_about.queue_free()
		await process_frame
		await process_frame
		check(not is_instance_valid(closing_about), "pending reader closes safely: " + close_mode)
	print("PUBLIC_NOTICES checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
