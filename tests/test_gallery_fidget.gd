extends SceneTree
const Gallery = preload("res://scripts/deck_gallery.gd")
const Themes = preload("res://scripts/card_themes.gd")
var gallery: Control
var checks := 0
var failures := 0
var applied: Array = []

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("GALLERY_FIDGET: " + description)

func touch(point: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func drag(point: Vector2, relative: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = relative
	root.push_input(event, true)

func center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)

func tap(point: Vector2) -> void:
	touch(point, true)
	touch(point, false)
	await process_frame

func _run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var original_settings := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	var original_theme: int = Themes.active_id
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1440, 660)
	root.size = Vector2i(1152, 528)
	gallery = Gallery.new()
	var palette := Theme.new()
	palette.default_font = load("res://assets/fonts/fusion-pixel.ttf")
	gallery.theme = palette
	gallery.theme_selected.connect(func(id): applied.append(id))
	root.add_child(gallery)
	await create_timer(0.95).timeout
	if not "_small_angles" in gallery or not "_gesture_axis" in gallery:
		check(false, "production fidget API is present before testing")
		gallery.queue_free()
		await process_frame
		_finish()
		return
	check(gallery._small_angles.size() == 52, "every small card has independent retained angle")
	var a: Control = gallery.cards[3]
	var b: Control = gallery.cards[7]
	check(a.pivot_offset.is_equal_approx(a.size * 0.5), "small card tilts around its center")
	var point := center(a)
	var initial_scroll: float = gallery._scroll
	var initial_inspected: int = gallery.inspected_card
	touch(point, true)
	drag(point + Vector2(65, 3), Vector2(65, 3))
	check(absf(a.rotation) > 0.04 and is_equal_approx(gallery._scroll, initial_scroll), "native horizontal touch tilts without vertical scrolling")
	var axis: Variant = gallery._gesture_axis
	drag(point + Vector2(72, 100), Vector2(7, 97))
	check(gallery._gesture_axis == axis and is_equal_approx(gallery._scroll, initial_scroll), "later vertical drift cannot steal established horizontal axis")
	touch(point + Vector2(72, 100), false)
	var angle_a := a.rotation
	await create_timer(0.65).timeout
	check(is_equal_approx(a.rotation, angle_a) and is_equal_approx(gallery._small_angles[3], angle_a), "small card retains its tilt after release and idle")
	check(gallery.inspected_card == initial_inspected, "horizontal fidget does not also activate tap inspection")
	point = center(b)
	touch(point, true)
	drag(point + Vector2(-60, 1), Vector2(-60, 1))
	touch(point + Vector2(-60, 1), false)
	var angle_b := b.rotation
	check(angle_a * angle_b < 0 and is_equal_approx(a.rotation, angle_a), "two cards retain independent opposite tilts")
	point = center(gallery.cards[9])
	var old_rotation: float = gallery.cards[9].rotation
	touch(point, true)
	drag(point + Vector2(3, -65), Vector2(3, -65))
	check(gallery._scroll > initial_scroll and is_equal_approx(gallery.cards[9].rotation, old_rotation), "native vertical gesture scrolls without rotating its card")
	axis = gallery._gesture_axis
	drag(point + Vector2(90, -75), Vector2(87, -10))
	check(gallery._gesture_axis == axis and is_equal_approx(gallery.cards[9].rotation, old_rotation), "later horizontal drift cannot steal established vertical axis")
	touch(point + Vector2(90, -75), false)
	gallery._scroll_velocity = 0
	gallery._set_scroll(0)
	point = center(a)
	touch(point, true, 0)
	touch(center(b), true, 1)
	drag(center(b) + Vector2(110, 0), Vector2(110, 0), 1)
	touch(center(b) + Vector2(110, 0), false, 1)
	check(gallery._pointer == 0 and is_equal_approx(b.rotation, angle_b), "second finger neither hijacks pointer nor changes another retained card")
	touch(point, false, 0, true)
	check(gallery._pointer == -2 and is_equal_approx(a.rotation, angle_a), "canceled touch ends capture while retaining established small-card angle")
	await tap(center(gallery.theme_buttons[2]))
	await create_timer(0.95).timeout
	check(gallery.browsed_theme == 2 and is_equal_approx(a.rotation, angle_a) and is_equal_approx(b.rotation, angle_b), "theme switch and new entrance preserve per-card physical arrangement")
	gallery.set_available_height(900)
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1008, 630)
	await process_frame
	check(is_equal_approx(a.rotation, angle_a) and is_equal_approx(b.rotation, angle_b), "resize retains all previously set small-card tilts")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "user://gallery_fidget_small_retained.png"
		check(root.get_texture().get_image().save_png(path) == OK, "capture multiple retained small-card tilts")
		print("GALLERY_FIDGET_CAPTURE " + ProjectSettings.globalize_path(path))
	for preview in [gallery.preview_face, gallery.preview_back]:
		point = center(preview)
		touch(point, true)
		drag(point + Vector2(64, 8), Vector2(64, 8))
		check(absf(preview.rotation) > 0.04, "fixed large preview responds to actual touch drag")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := "user://gallery_fidget_preview_%s.png" % ("face" if preview == gallery.preview_face else "back")
			check(root.get_texture().get_image().save_png(path) == OK, "capture dragged large preview")
			print("GALLERY_FIDGET_CAPTURE " + ProjectSettings.globalize_path(path))
		touch(point + Vector2(64, 8), false)
		await create_timer(0.75).timeout
		check(absf(preview.rotation) < 0.001, "large preview springs back after release")
	check(is_equal_approx(a.rotation, angle_a) and is_equal_approx(b.rotation, angle_b), "large preview release never resets small cards")
	point = center(gallery.preview_face)
	touch(point, true)
	drag(point + Vector2(-55, 0), Vector2(-55, 0))
	touch(point + Vector2(-55, 0), false, 0, true)
	await create_timer(0.75).timeout
	check(absf(gallery.preview_face.rotation) < 0.001 and gallery._pointer == -2, "system-canceled preview touch returns to rest")
	point = center(gallery.preview_back)
	touch(point, true)
	drag(point + Vector2(50, 0), Vector2(50, 0))
	gallery._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.75).timeout
	check(gallery._pointer == -2 and absf(gallery.preview_back.rotation) < 0.001, "focus loss cleans up a held preview")
	check(is_equal_approx(a.rotation, angle_a) and is_equal_approx(b.rotation, angle_b), "lifecycle cancellation preserves retained small-card arrangement")
	gallery._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	point = center(gallery.preview_face)
	touch(point, true)
	drag(point + Vector2(50, 0), Vector2(50, 0))
	touch(point + Vector2(50, 0), false)
	check(not gallery._preview_tweens.is_empty(), "preview spring owns tracked finite tweens")
	gallery.hide()
	check(gallery._pointer == -2 and gallery._preview_tweens.is_empty(), "hide cancels pending springs without leaking timers")
	gallery.queue_free()
	await process_frame
	await create_timer(0.8).timeout
	check(applied.is_empty() and Themes.active_id == original_theme, "all fidgets stay local and never apply a deck")
	check(FileAccess.file_exists("user://settings.cfg") == had_settings and (not had_settings or FileAccess.get_file_as_bytes("user://settings.cfg") == original_settings), "no fidget touches persisted user settings")
	_finish()

func _finish() -> void:
	print("GALLERY_FIDGET_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
