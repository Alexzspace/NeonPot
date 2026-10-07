extends SceneTree
const Gallery = preload("res://scripts/deck_gallery.gd")
const Themes = preload("res://scripts/card_themes.gd")
var checks := 0
var failures := 0
var gallery: Control
var applied: Array = []
var closes := 0
var contacts := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DECK_GALLERY: " + label)

func _touch(point: Vector2, pressed: bool, pointer: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func _drag(point: Vector2, relative: Vector2, pointer: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = pointer
	event.position = point
	event.relative = relative
	root.push_input(event, true)

func _tap(point: Vector2) -> void:
	_touch(point, true)
	_touch(point, false)
	await process_frame

func _run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var old_bytes := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	var active_before: int = Themes.active_id
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1440, 660)
	root.size = Vector2i(1152, 528)
	gallery = Gallery.new()
	gallery.selected_theme = 2
	var palette := Theme.new()
	palette.default_font = load("res://assets/fonts/fusion-pixel.ttf")
	palette.default_font_size = 24
	gallery.theme = palette
	gallery.theme_selected.connect(func(id): applied.append(id))
	gallery.closed.connect(func(): closes += 1)
	gallery.contact.connect(func(): contacts += 1)
	root.add_child(gallery)
	await process_frame
	check(gallery.cards.size() == 52, "all 52 cards exist together, not a first-page subset")
	check(gallery.theme_buttons.size() == 4 and gallery.browsed_theme == 2, "four visual theme selectors begin at applied theme")
	check(gallery.preview_face.card_id == 51 and gallery.preview_face.face_up and not gallery.preview_back.face_up, "default fixed preview is spade ace plus back")
	for index in 52:
		check(gallery.cards[index].card_id == index and gallery.cards[index].face_up and not gallery.cards[index].interactive, "static complete-deck card %d contains no private interaction" % index)
	check(gallery._entrance != null and gallery.cards[51].modulate.a < 1, "cards begin staggered entrance")
	await create_timer(1.0).timeout
	check(gallery.cards[51].modulate.a == 1 and gallery.cards[51].position.is_equal_approx(gallery._rests[51]), "last staggered card settles exactly")
	await _tap(gallery.theme_buttons[1].get_rect().get_center())
	check(gallery.browsed_theme == 1 and applied.is_empty(), "browsing theme never applies it")
	gallery.selected_theme = 3
	check(gallery.selected_theme == 3 and gallery.browsed_theme == 1 and gallery.theme_marks[3].visible, "host update changes used marker without overriding current browse")
	await create_timer(0.9).timeout
	var first_point: Vector2 = gallery.grid_view.position + gallery.cards[0].position + gallery.cards[0].size * 0.5
	var before_contacts := contacts
	_touch(first_point, true, 0)
	_touch(gallery.theme_buttons[0].get_rect().get_center(), true, 1)
	_touch(gallery.theme_buttons[0].get_rect().get_center(), false, 1)
	check(gallery._pointer == 0 and gallery.browsed_theme == 1, "second finger cannot steal first pointer or change theme")
	_touch(first_point, false, 0)
	await process_frame
	check(gallery.inspected_card == 0 and contacts == before_contacts + 1 and applied.is_empty(), "single touch selects exactly one enlarged card without applying")
	var scroll_start: Vector2 = gallery.grid_view.position + Vector2(180, 130)
	var old_card: int = gallery.inspected_card
	_touch(scroll_start, true)
	_drag(scroll_start + Vector2(0, -110), Vector2(0, -110))
	_touch(scroll_start + Vector2(0, -110), false)
	await process_frame
	check(gallery._scroll > 0 and gallery.inspected_card == old_card, "drag scrolls rather than clicking a crossed card")
	gallery._scroll_velocity = 0
	gallery._set_scroll(gallery._scroll_limit)
	var last_point: Vector2 = gallery.grid_view.position + gallery.grid_content.position + gallery.cards[51].position + gallery.cards[51].size * 0.5
	check(gallery.grid_view.get_rect().has_point(last_point), "52nd card is reachable at bottom of real scroll range")
	await _tap(last_point)
	check(gallery.inspected_card == 51 and gallery.preview_face.card_id == 51, "last card enlarges in the fixed lower preview")
	gallery.can_apply = false
	await _tap(gallery._preview_panel.position + gallery.apply_button.get_rect().get_center())
	check(applied.is_empty() and gallery.apply_button.disabled and gallery.host_label.text.contains("房主"), "client cannot apply and gets host authority explanation")
	await _tap(gallery.theme_buttons[0].get_rect().get_center())
	check(gallery.browsed_theme == 0 and applied.is_empty(), "client still browses all decks")
	gallery.can_apply = true
	await _tap(gallery._preview_panel.position + gallery.apply_button.get_rect().get_center())
	check(applied == [0], "only explicit use button emits chosen theme")
	for height in [660.0, 900.0, 1018.0]:
		root.content_scale_size = Vector2i(1440, int(height))
		root.size = Vector2i(1008, int(height * 0.7))
		gallery.set_available_height(height)
		await process_frame
		for language in ["zh", "en"]:
			gallery.language = language
			_layout_checks(height, language)
			if DisplayServer.get_name() != "headless" and height in [660.0, 900.0]:
				gallery._set_scroll(0)
				await RenderingServer.frame_post_draw
				var path := "user://deck_gallery_%d_%s.png" % [int(height), language]
				check(root.get_texture().get_image().save_png(path) == OK, "save gallery render")
				print("GALLERY_CAPTURE " + ProjectSettings.globalize_path(path))
	for id in 4:
		gallery._browse(id)
		check(gallery.preview_face.theme_id == id and gallery.preview_back.theme_id == id, "large preview uses fixed browsed theme %d" % id)
		for card in gallery.cards: check(card.theme_id == id, "all gallery faces consistently follow browsed theme %d" % id)
	gallery._press(0, gallery.grid_view.position + Vector2(15, 15))
	gallery._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(gallery._pointer == -2 and gallery._entrance == null, "focus loss cancels pointer and entrance")
	gallery._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	gallery._browse(1)
	gallery.set_available_height(660)
	check(gallery._entrance == null and gallery.cards[51].modulate.a == 1, "resize cancels running card entrances to exact rest")
	var apply_count := applied.size()
	await _tap(gallery.close_button.get_rect().get_center())
	check(closes == 1 and applied.size() == apply_count and not gallery._input_enabled, "back closes once without applying or accepting later input")
	gallery.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	check(Themes.active_id == active_before, "gallery never modifies global card theme itself")
	check(FileAccess.file_exists("user://settings.cfg") == had_settings and (not had_settings or FileAccess.get_file_as_bytes("user://settings.cfg") == old_bytes), "gallery preserves settings file bytes")
	print("DECK_GALLERY_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _layout_checks(height: float, language: String) -> void:
	var area := Rect2(Vector2.ZERO, Vector2(1440, height))
	for control in [gallery.title_label, gallery.close_button, gallery.grid_view, gallery._preview_panel]:
		check(area.encloses(control.get_rect()), "%s %d main areas contained" % [language, int(height)])
	check(gallery.grid_view.get_rect().end.y < gallery._preview_panel.position.y, "scroll grid stays above fixed preview")
	for card in [gallery.preview_face, gallery.preview_back]:
		check(card.size.x >= 146 and is_equal_approx(card.size.x / card.size.y, 132.0 / 184.0), "preview keeps substantial uncompressed playing-card aspect")
		check(Rect2(Vector2.ZERO, gallery._preview_panel.size).encloses(card.get_rect()), "enlarged card is contained in lower preview")
	for label in [gallery.hint_label, gallery.host_label, gallery.preview_label]:
		var width: float = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		check(width <= label.size.x, "%s label fits without horizontal clipping" % language)
