extends SceneTree
const Card = preload("res://scripts/card_view.gd")
const Themes = preload("res://scripts/card_themes.gd")
const GALLERY_SIZE := Vector2i(1992, 1112)
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARD_THEMES: " + message)

func _run() -> void:
	var original_active := Themes.active_id
	check(Themes.COUNT == 4, "four complete print families")
	for invalid in [-9223372036854775807, -2, -1, 4, 99, 9223372036854775807]:
		check(Themes.valid_id(invalid) == 0, "invalid theme safely falls back to black gold")
	var inherited := Card.new()
	root.add_child(inherited)
	check(inherited.is_in_group("poker_cards"), "live cards join redraw group")
	for theme in Themes.COUNT:
		Themes.active_id = theme
		check(inherited._theme() == theme, "default card follows global theme")
		inherited.theme_id = (theme + 1) % Themes.COUNT
		check(inherited._theme() == (theme + 1) % Themes.COUNT, "explicit gallery theme stays fixed")
		inherited.theme_id = -1
		for id in 52:
			inherited.set_card(id, false)
			call_group("poker_cards", "queue_redraw")
			check(inherited.card_id == id and not inherited.face_up and not inherited._peeking, "theme redraw never exposes hidden identity")
		check(Card.BACK_TEXTURES[theme].get_size() == Vector2(528, 736), "static back texture resolution")
	inherited.theme_id = 900
	check(inherited.theme_id == 0, "fixed invalid theme normalized")
	inherited.queue_free()
	await process_frame
	var graphical := DisplayServer.get_name() != "headless"
	if graphical:
		for theme in Themes.COUNT: await render_theme(theme)
	Themes.active_id = original_active
	print("CARD_THEMES checks=%d failures=%d graphical=%s" % [checks, failures, graphical])
	quit(1 if failures else 0)

func render_theme(theme: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = GALLERY_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = GALLERY_SIZE
	background.color = Color("24212c")
	viewport.add_child(background)
	var heading := Label.new()
	heading.text = ["01 / OBSIDIAN FOIL", "02 / AFTER HOURS COLLAGE", "03 / RED CONSTRUCTION", "04 / TOURNAMENT STANDARD"][theme]
	heading.position = Vector2(20, 10)
	heading.add_theme_font_size_override("font_size", 26)
	viewport.add_child(heading)
	for suit in 4:
		for rank in 13:
			var card := Card.new()
			card.theme_id = theme
			card.size = Card.BASE
			card.position = Vector2(20 + rank * 152, 56 + suit * 212)
			card.set_card(suit * 13 + rank, true)
			viewport.add_child(card)
	var back := Card.new()
	back.theme_id = theme
	back.size = Card.BASE
	back.position = Vector2(20, 906)
	back.set_card(-1, false)
	viewport.add_child(back)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and image.get_size() == GALLERY_SIZE, "full 52-card sheet renders")
	if image != null:
		var signatures: Dictionary = {}
		for suit in 4:
			for rank in 13:
				var origin := Vector2i(20 + rank * 152, 56 + suit * 212)
				var face := image.get_region(Rect2i(origin, Vector2i(Card.BASE)))
				signatures[hash(face.get_data())] = true
				var index_region := image.get_region(Rect2i(origin + Vector2i(6, 10), Vector2i(24, 45)))
				var paper: Color = Themes.paper(theme)
				var index_marks := 0
				for y in index_region.get_height():
					for x in index_region.get_width():
						var contrast := absf(index_region.get_pixel(x, y).get_luminance() - paper.get_luminance())
						if contrast > 0.1: index_marks += 1
				check(index_marks > 75, "rank and suit are printed clearly at readable corner")
				if theme == 0:
					var white := 0
					for y in face.get_height():
						for x in face.get_width():
							var color := face.get_pixel(x, y)
							if color.r > 0.8 and color.g > 0.8 and color.b > 0.8: white += 1
					check(white == 0, "obsidian face and border contain no white paper")
		check(signatures.size() == 52, "all 52 rendered identities remain distinct")
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		var path := "res://artifacts/card-theme-%d-all52.png" % theme
		check(image.save_png(path) == OK, "complete theme sheet saved")
		var hidden := image.get_region(Rect2i(Vector2i(back.position), Vector2i(Card.BASE))).get_data()
		back.set_card(51, false)
		await process_frame
		await RenderingServer.frame_post_draw
		var second := viewport.get_texture().get_image()
		check(second.get_region(Rect2i(Vector2i(back.position), Vector2i(Card.BASE))).get_data() == hidden, "unknown and known hidden cards render identical back")
	viewport.queue_free()
	await process_frame
