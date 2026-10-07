extends SceneTree
const Card = preload("res://scripts/card_view.gd")
const Main = preload("res://scripts/main.gd")
class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
var checks := 0
var failures := 0
var public_events: Array = []
const GALLERY_SIZE := Vector2i(1992, 1160)
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CARD_ART: " + message)
func wait_ms(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline: await process_frame
func symmetry(texture: Texture2D) -> void:
	var bitmap := texture.get_image()
	check(bitmap != null and bitmap.get_size() == Vector2i(528, 736), "back uses one static 528 by 736 rasterized SVG texture")
	if bitmap == null: return
	bitmap.convert(Image.FORMAT_RGBA8)
	var bytes := bitmap.get_data()
	var width := bitmap.get_width()
	var height := bitmap.get_height()
	for axis in ["horizontal", "vertical"]:
		var differences := 0
		var maximum := 0
		var total := 0
		for y in height:
			for x in width:
				var mirrored_x := width - x - 1 if axis == "horizontal" else x
				var mirrored_y := height - y - 1 if axis == "vertical" else y
				var source := (y * width + x) * 4
				var target := (mirrored_y * width + mirrored_x) * 4
				for channel in 4:
					var difference := absi(int(bytes[source + channel]) - int(bytes[target + channel]))
					total += difference
					maximum = maxi(maximum, difference)
					if difference > 4: differences += 1
		var fraction := float(differences) / float(width * height * 4)
		var mean := float(total) / float(width * height * 4 * 255)
		print("CARD_BACK_SYMMETRY axis=%s mean=%.8f mismatch_fraction=%.8f max_byte_error=%d" % [axis, mean, fraction, maximum])
		# Permit only tiny renderer edge rounding, not a displaced repeating motif.
		check(mean < 0.0008 and fraction < 0.001, "back is pixel-symmetric about the %s center axis" % axis)
func _run() -> void:
	check(Card.BACK_TEXTURE is Texture2D, "card back is backed by the shared static texture")
	symmetry(Card.BACK_TEXTURE)
	root.size = Vector2i(1440, 660)
	var app := Probe.new()
	root.add_child(app)
	await process_frame
	app.session.chip_gesture.connect(func(seat, sequence, style): public_events.append([seat, sequence, style]))
	app.session.board_gesture.connect(func(seat, sequence, index, kind, offset): public_events.append([seat, sequence, index, kind, offset]))
	app.session.table_prop_gesture.connect(func(seat, sequence, kind): public_events.append([seat, sequence, kind]))
	var ace: Control = app.home_cards[1]
	ace.theme_id = 3
	var touches: Array = []
	ace.touched.connect(func(kind): touches.append(kind))
	check(ace.card_id % 13 == 12 and ace.face_up and ace.interactive, "homepage ace is visible and interactive")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = ace.get_global_transform() * (ace.size * 0.5)
	press.pressed = true
	root.push_input(press, true)
	check(ace._pointer == 0 and ace.face_up and not ace._peeking, "native touch captures visible ace without turning it over")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = press.position + Vector2(35, -12)
	drag.relative = Vector2(35, -12)
	root.push_input(drag, true)
	await wait_ms(100)
	check(absf(ace._tilt) > 0.01 and ace.face_up, "native drag moves the face-up ace visually")
	press.position = Vector2(1430, 650)
	press.pressed = false
	root.push_input(press, true)
	await wait_ms(600)
	check(ace._pointer == -2 and ace.face_up and not ace._peeking and absf(ace._tilt) < 0.002, "outside release restores ace without covering its face")
	check(touches == ["touch", "swipe", "release"], "home ace emits each local touch stage once")
	check(public_events.is_empty() and app.session.state.is_empty(), "homepage fidget creates no public event or game state")
	app.queue_free()
	await process_frame
	var graphical := DisplayServer.get_name() != "headless"
	if graphical: await gallery()
	print("CARD_ART checks=%d failures=%d graphical=%s" % [checks, failures, graphical])
	quit(0 if failures == 0 else 1)
func label(parent: Node, words: String, at: Vector2, font_size: int = 22) -> void:
	var node := Label.new()
	node.text = words
	node.position = at
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("dbc494"))
	parent.add_child(node)
func gallery() -> void:
	var viewport := SubViewport.new()
	viewport.size = GALLERY_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("11121b")
	background.size = GALLERY_SIZE
	viewport.add_child(background)
	label(viewport, "NEON POT  /  52-CARD ART REVIEW", Vector2(20, 12), 28)
	for rank in 13:
		label(viewport, str(rank + 2) if rank < 9 else ["J", "Q", "K", "A"][rank - 9], Vector2(24 + rank * 152, 48), 20)
	for suit in 4:
		for rank in 13:
			var card := Card.new()
			card.theme_id = 3
			card.size = Card.BASE
			card.position = Vector2(20 + rank * 152, 80 + suit * 212)
			card.set_card(suit * 13 + rank, true)
			viewport.add_child(card)
	label(viewport, "SHARED BACK  /  MIRROR-SYMMETRIC BLACK AND GOLD", Vector2(190, 958), 26)
	label(viewport, "Rows: clubs / diamonds / hearts / spades.  Columns: 2 through ace.", Vector2(190, 1008), 22)
	var back := Card.new()
	back.theme_id = 0
	back.position = Vector2(20, 948)
	back.size = Card.BASE
	back.set_card(-1, false)
	viewport.add_child(back)
	await process_frame
	await RenderingServer.frame_post_draw
	var bitmap := viewport.get_texture().get_image()
	check(bitmap != null and bitmap.get_size() == GALLERY_SIZE, "all 52 front faces and shared back render in the graphical viewport")
	if bitmap != null:
		for suit in 4:
			var origin := Vector2i(20 + 12 * 152, 80 + suit * 212)
			var marked := 0
			# Former line occupied center-local y=36, or face pixel y=128.
			# This clean region is below every ace pip and away from the corners.
			for y in range(126, 131):
				for x in range(46, 87):
					var pixel := bitmap.get_pixel(origin.x + x, origin.y + y)
					var paper: Color = Card.Themes.paper(3)
					var difference := maxf(absf(pixel.r - paper.r), maxf(absf(pixel.g - paper.g), absf(pixel.b - paper.b)))
					if difference > 0.025: marked += 1
			check(marked == 0, "ace suit %d has clean paper below its central pip, with no decorative line" % suit)
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		var path := "res://artifacts/cards-52-gallery.png"
		check(bitmap.save_png(path) == OK, "52-card visual gallery saved")
		print("CARD_ART_GALLERY " + ProjectSettings.globalize_path(path))
	viewport.queue_free()
	await process_frame
