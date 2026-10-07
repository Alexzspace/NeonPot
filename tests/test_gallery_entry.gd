extends SceneTree
const Gallery = preload("res://scripts/deck_gallery.gd")
const Themes = preload("res://scripts/card_themes.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("GALLERY_ENTRY: " + label)

func _run() -> void:
	var gallery := Gallery.new()
	var palette := Theme.new()
	palette.default_font = load("res://assets/fonts/fusion-pixel.ttf")
	gallery.theme = palette
	root.add_child(gallery)
	# Match main's add-child, then safe-area reflow on the first opening.
	gallery.set_available_height(820)
	check(gallery.cards[0].modulate.a == 0, "initial layout never flashes fully visible cards")
	await process_frame
	await create_timer(0.1).timeout
	check(gallery._entrance != null and gallery.cards[51].modulate.a < 1, "post-add layout preserves first entrance")
	check(gallery.cards[0].modulate.a > gallery.cards[51].modulate.a, "first opening deals cards sequentially")
	await create_timer(0.95).timeout
	check(gallery.cards[51].modulate.a == 1 and gallery.cards[51].position.is_equal_approx(gallery._rests[51]), "all initial cards settle")
	for language in ["zh", "en"]:
		gallery.language = language
		var names: Array[String] = []
		for index in 4:
			var label: Label = gallery.theme_names[index]
			check(label.text == Themes.collection_name(index, language) and label.text not in names, "unique bilingual collection name")
			names.append(label.text)
			check(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x <= label.size.x, "collection name fits thumbnail")
	gallery._browse(2)
	gallery._apply()
	check(gallery.selected_theme == 0 and not gallery.theme_marks[2].visible, "unconfirmed selection never marks deck as applied")
	gallery.theme_selected.connect(func(id): gallery.selected_theme = id)
	gallery._apply()
	check(gallery.selected_theme == 2 and gallery.theme_marks[2].visible and gallery.apply_button.text.contains("SELECTED"), "confirmed selection updates marker and button")
	check(gallery.theme_buttons[2].scale.x < 1 and gallery.apply_button.scale.x < 1, "confirmed selection animates top thumbnail and use button")
	await create_timer(0.65).timeout
	check(gallery.theme_buttons[2].scale == Vector2.ONE and gallery.apply_button.modulate == Color.WHITE, "selection feedback settles exactly")
	gallery._apply()
	gallery.set_available_height(660)
	check(gallery._selection_tween == null and gallery.apply_button.scale == Vector2.ONE, "resize cancels confirmation feedback")
	gallery._browse(3)
	gallery._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(gallery._entrance == null and gallery._panel_entrance == null and gallery.cards[51].modulate.a == 1, "focus loss clears all entry choreography")
	gallery.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("GALLERY_ENTRY_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
