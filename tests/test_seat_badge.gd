extends SceneTree
const Badge = preload("res://scripts/seat_badge.gd")
const Card = preload("res://scripts/card_view.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("BADGE: " + label)

func _run() -> void:
	root.size = Vector2i(960, 640)
	root.content_scale_size = Vector2i(960, 640)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var background := ColorRect.new()
	background.color = Color("0f1529")
	background.size = Vector2(960, 640)
	root.add_child(background)
	var badge := Badge.new()
	badge.roles = ["SB", "D", "D", "invalid"]
	badge.position = Vector2(650, 410)
	root.add_child(badge)
	await process_frame
	check(badge.roles == ["D", "SB"], "dealer plus small blind is canonical and deduplicated")
	check(badge.size == Vector2(96, 38), "combined roles fit reserved 96 by 38")
	check(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "decorative role chips do not steal touch")
	check(badge.language == "zh", "badge defaults to Chinese")
	for role in ["D", "SB", "BB"]:
		var translated: String = {"D": "庄", "SB": "小盲", "BB": "大盲"}[role]
		check(badge.role_text(role) == translated, "Chinese role caption " + role)
		var font_size := 20
		var text_size: Vector2 = Badge.PIXEL_FONT.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		check(text_size.x <= 40 and Badge.PIXEL_FONT.get_height(font_size) <= 28, "enlarged glyph %s width=%s line_height=%s" % [role, text_size.x, Badge.PIXEL_FONT.get_height(font_size)])
		for character in translated:
			check(Badge.PIXEL_FONT.has_char(character.unicode_at(0)), "bundled pixel font contains role glyph")
	badge.language = "en"
	check(badge.role_text("D") == "D" and badge.role_text("SB") == "SB" and badge.role_text("BB") == "BB", "English preserves original D/SB/BB")
	badge.language = "zh"
	badge.roles = ["D", "SB", "BB"]
	check(badge.roles == ["D", "BB"], "invalid simultaneous blinds cannot overlap or overflow")
	badge.roles = []
	check(badge.roles.is_empty(), "seat losing a role clears old badge")
	badge.roles = ["D", "SB"]
	badge.roles = badge.roles
	check(badge.roles == ["D", "SB"], "same array assignment retains roles")
	for role in ["D", "SB", "BB"]:
		var single := Badge.new()
		single.roles.assign([role])
		single.position = Vector2(650 + ["D", "SB", "BB"].find(role) * 78, 470)
		root.add_child(single)
	var english := Badge.new()
	english.roles = ["D", "SB"]
	english.language = "en"
	english.position = Vector2(650, 535)
	root.add_child(english)
	var icon := Image.new()
	var error := icon.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"))
	check(error == OK and icon.get_size() == Vector2i(512, 512), "original icon renders as a scalable 512px vector")
	check(icon.get_pixel(256, 200).a > 0.9 and icon.get_pixel(0, 0).a < 0.1, "icon has solid emblem and transparent rounded corner")
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(icon)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.size = Vector2(230, 230)
	picture.position = Vector2(650, 70)
	root.add_child(picture)
	for suit in range(4):
		for index in range(3):
			var card := Card.new()
			card.set_card(suit * 13 + [12, 8, 11][index])
			card.size = Card.BASE
			card.position = Vector2(18 + suit * 150, 14 + index * 202)
			root.add_child(card)
	check(Card.PIPS[0][0].count("1") >= 3 and Card.PIPS[3][0].count("1") == 1, "club rounded lobe and spade pointed apex have distinct silhouettes")
	check(Card.PIPS[0] != Card.PIPS[3], "black suit masks differ independently of color")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var destination := "user://neon_pot_components.png"
		check(root.get_texture().get_image().save_png(destination) == OK, "actual card/badge/icon graphical evidence saved")
		print("NEON_COMPONENT_CAPTURE " + ProjectSettings.globalize_path(destination))
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("SEAT_BADGE_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
