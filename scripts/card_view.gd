class_name PokerCard
extends Control
## Original, tactile playing card. Pressing a private card only peeks at it.

signal touched(kind: String)

const Timing = preload("res://scripts/presentation_timing.gd")
const BASE := Vector2(132, 184)
const Themes = preload("res://scripts/card_themes.gd")
const Art = preload("res://scripts/kaleidoscope_art.gd")
const BACK_TEXTURE = preload("res://assets/card_back.svg")
const BACK_TEXTURES := [BACK_TEXTURE, preload("res://assets/cards/back_contemporary.svg"),
	preload("res://assets/cards/back_constructivist.svg"), preload("res://assets/cards/back_competition.svg")]
const INK := Color("243444")
const RED := Color("ae3444")
const GOLD := Color("cba970")
const PAPER := Color("f4ecdb")
const CORNER_PIP_PIXEL := 3.2
const NUMBER_PIP_PIXEL := 3.5
const DENSE_PIP_PIXEL := 3.2
const ACE_PIP_PIXEL := 7.8
const PIPS := [
	["00001110000", "00011111000", "00011111000", "00001110000", "01110101110", "11111111111", "11111111111", "01110101110", "00000100000", "00001110000", "00011111000"],
	["0001000", "0011100", "0111110", "1111111", "0111110", "0011100", "0001000"],
	["0110110", "1111111", "1111111", "0111110", "0011100", "0001000", "0000000"],
	["00000100000", "00001110000", "00011111000", "00111111100", "01111111110", "11111111111", "11111111111", "01111111110", "00110101100", "00000100000", "00001110000"]
]

var custom_recipe: Dictionary = {}:
	set(value):
		custom_recipe = Themes.sanitize_recipe(value)
		queue_redraw()

var _marks_recipe: Dictionary = {}
var _recipe_back: Array[Dictionary] = []
var _recipe_front: Array[Dictionary] = []

var card_id: int = -1
var winning_colors: Array = []:
	set(value):
		winning_colors = value
		queue_redraw()
var theme_id: int = -1:
	set(value):
		theme_id = -1 if value == -1 else Themes.valid_id(value)
		queue_redraw()
var face_up: bool = false:
	set(value):
		face_up = value
		queue_redraw()
var interactive: bool = false:
	set(value):
		interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		if not value:
			_release()
var card_scale: float = 1.0:
	set(value):
		card_scale = maxf(value, 0.1)
		custom_minimum_size = BASE * card_scale
		queue_redraw()

var _peeking := false
var _pointer := -2
var _drag_distance := 0.0
var _tilt := 0.0
var _target_tilt := 0.0
var _velocity := 0.0
var _lift := 0.0
var _flip_width := 1.0
var _deal_offset := Vector2.ZERO
var _deal_alpha := 1.0
var _flip_tween: Tween
var _deal_tween: Tween
var _pending_deal := -1.0
var _swiped := false

func _ready() -> void:
	add_to_group("poker_cards")
	custom_minimum_size = BASE * card_scale
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if _pending_deal >= 0.0:
		deal(_pending_deal)
	set_process(true)

func set_card(value: int, revealed: bool = true) -> void:
	_release()
	if _flip_tween:
		_flip_tween.kill()
	_flip_width = 1.0
	card_id = value if value >= 0 and value < 52 else -1
	face_up = revealed
	queue_redraw()

func deal(delay: float = 0.0) -> void:
	if not is_inside_tree():
		_pending_deal = maxf(delay, 0.0)
		return
	_pending_deal = -1.0
	if _deal_tween:
		_deal_tween.kill()
	_deal_offset = Vector2(45, -95)
	_deal_alpha = 0.0
	_tilt = -0.14
	_deal_tween = create_tween().set_speed_scale(Timing.rate)
	_deal_tween.tween_interval(maxf(delay, 0.0))
	_deal_tween.tween_property(self, "_deal_alpha", 1.0, 0.12)
	_deal_tween.parallel().tween_property(self, "_deal_offset", Vector2.ZERO, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func flip(revealed: bool) -> void:
	_release()
	if not is_inside_tree():
		face_up = revealed
		return
	if _flip_tween:
		_flip_tween.kill()
	_flip_tween = create_tween().set_speed_scale(Timing.rate)
	_flip_tween.tween_property(self, "_flip_width", 0.04, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func() -> void: face_up = revealed)
	_flip_tween.tween_property(self, "_flip_width", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	var target_lift := 9.0 if _peeking else 0.0
	var moving := absf(_velocity) > 0.0001 or absf(_target_tilt - _tilt) > 0.0001 or absf(target_lift - _lift) > 0.01
	var animating := (_flip_tween and _flip_tween.is_running()) or (_deal_tween and _deal_tween.is_running())
	if not moving and not animating:
		return
	var step := minf(delta, 0.033)
	_velocity += ((_target_tilt - _tilt) * 190.0 - _velocity * 22.0) * step
	_tilt += _velocity * step
	_lift = lerpf(_lift, target_lift, 1.0 - exp(-18.0 * delta))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_inside_tree() and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or not is_visible_in_tree()):
			_release()

func _gui_input(event: InputEvent) -> void:
	if not interactive or card_id < 0 or _pointer != -2:
		return
	if event is InputEventScreenTouch and event.pressed:
		_press(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.device != -1 and not Input.emulate_touch_from_mouse:
			_press(-1, event.position)
			accept_event()

func _input(event: InputEvent) -> void:
	if _pointer == -2:
		return
	if event is InputEventScreenTouch and event.index == _pointer and not event.pressed:
		_release()
	elif event is InputEventScreenDrag and event.index == _pointer:
		_drag(event.relative)
	elif event is InputEventMouseButton and _pointer == -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_release()
	elif event is InputEventMouseMotion and _pointer == -1:
		_drag(event.relative)

func _press(pointer: int, position_on_card: Vector2) -> void:
	_pointer = pointer
	_drag_distance = 0.0
	_swiped = false
	_peeking = not face_up
	_target_tilt = clampf((position_on_card.x / maxf(size.x, 1.0) - 0.5) * 0.18, -0.09, 0.09)
	touched.emit("touch")
	queue_redraw()

func _drag(relative: Vector2) -> void:
	_target_tilt = clampf(_target_tilt + relative.x * 0.002, -0.16, 0.16)
	_drag_distance += relative.length()
	if not _swiped and _drag_distance > 8.0:
		_swiped = true
		touched.emit("swipe")

func _release() -> void:
	var was_pressed := _pointer != -2
	_pointer = -2
	_peeking = false
	_target_tilt = 0.0
	if was_pressed:
		touched.emit("release")
	queue_redraw()

func _draw_center() -> Vector2:
	return size * 0.5 + _deal_offset * (size / BASE) - Vector2(0, _lift * size.y / BASE.y)

func _draw_angle() -> float:
	return _tilt

func _theme() -> int:
	return Themes.valid_id(Themes.active_id if theme_id == -1 else theme_id)

func effective_recipe() -> Dictionary:
	if not custom_recipe.is_empty(): return custom_recipe
	return Themes.custom_recipe if theme_id == -1 else {}

func _draw() -> void:
	var ratio := size / BASE
	var center := _draw_center()
	var angle := _draw_angle()
	draw_set_transform(center, angle, ratio * Vector2(_flip_width, 1.0))
	var outline := _outline(Rect2(-BASE * 0.5, BASE), 5.0)
	for i in range(4, 0, -1):
		var shadow := PackedVector2Array()
		for p in outline:
			shadow.append(p + Vector2(0, 2 + i * 2 + _lift * 0.4))
		draw_colored_polygon(shadow, Color(0.015, 0.025, 0.035, 0.055 * _deal_alpha))
	var recipe := effective_recipe()
	draw_colored_polygon(outline, _c(Themes.paper(_theme()) if recipe.is_empty() else Color.html(recipe.paper)))
	draw_set_transform(center, angle, ratio * Vector2(_flip_width, 1.0))
	if (face_up or _peeking) and card_id >= 0:
		_draw_face()
	else:
		_draw_back()
	draw_polyline(outline + PackedVector2Array([outline[0]]), _c(Themes.edge(_theme())), 1.0)
	if face_up and card_id >= 0:
		if not winning_colors.is_empty():
			# Dark keyline separates luminous frames from both white and black decks.
			# Shared board cards use perimeter segments, preserving the entire face.
			var frame := _outline(Rect2(-BASE * 0.5, BASE).grow(1.0 / maxf(ratio.x, 0.1)), 5.0)
			frame.append(frame[0])
			draw_polyline(frame, _c(Color("080a14")), 9.0 / maxf(ratio.x, 0.1), true)
			for edge in range(frame.size() - 1):
				var color_index := mini(edge * winning_colors.size() / (frame.size() - 1), winning_colors.size() - 1)
				draw_line(frame[edge], frame[edge + 1], _c(winning_colors[color_index]), 4.5 / maxf(ratio.x, 0.1), true)

	draw_set_transform(Vector2.ZERO)

func _outline(rect: Rect2, corner: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([a + Vector2(corner, 0), Vector2(b.x - corner, a.y), Vector2(b.x, a.y + corner), b - Vector2(0, corner), b - Vector2(corner, 0), Vector2(a.x + corner, b.y), Vector2(a.x, b.y - corner), a + Vector2(0, corner)])

func _c(color: Color) -> Color:
	return Color(color, color.a * _deal_alpha)

func _draw_back() -> void:
	var recipe := effective_recipe()
	if not recipe.is_empty():
		_draw_recipe(recipe, false)
		return
	draw_texture_rect(BACK_TEXTURES[_theme()], Rect2(-BASE * 0.5, BASE), false, _c(Color.WHITE))

func _draw_face() -> void:
	var recipe := effective_recipe()
	if not recipe.is_empty():
		_draw_recipe(recipe, true)
		return
	var rank := card_id % 13 + 2
	var suit := card_id / 13
	var theme := _theme()
	var color := Themes.ink(theme, suit)
	if theme == 0:
		# Foil is printed geometry, never a moving light/reflection shader.
		draw_rect(Rect2(-61, -87, 122, 174), _c(Color("443721")), false, 1)
		for sign_y in [-1, 1]:
			draw_line(Vector2(-29, 80 * sign_y), Vector2(29, 80 * sign_y), _c(Color("8a6c3d")), 1)
			draw_colored_polygon(PackedVector2Array([Vector2(-3, 80 * sign_y), Vector2(0, 77 * sign_y), Vector2(3, 80 * sign_y), Vector2(0, 83 * sign_y)]), _c(GOLD))
	elif theme == 1:
		_draw_contemporary(rank, suit, color)
	elif theme == 2:
		_draw_constructivist(rank, suit, color)
	_corner(rank, suit, color, false)
	_corner(rank, suit, color, true)
	if theme in [1, 2]: return
	if rank >= 11 and rank <= 13:
		if theme == 0: _foil_court(rank, suit, color)
		else: _portrait(rank, suit, color)
	elif rank == 14:
		_pip(Vector2(0, -4), suit, ACE_PIP_PIXEL, color)
	else:
		var pixel := DENSE_PIP_PIXEL if rank >= 9 else NUMBER_PIP_PIXEL
		for p in _number_pip_positions(rank):
			_pip(p, suit, pixel, color, p.y > 0)

func _rank_text(rank: int) -> String:
	return {11: "J", 12: "Q", 13: "K", 14: "A"}.get(rank, str(rank))

func _art_polygon(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), _c(color))

func _foil_court(rank: int, suit: int, color: Color) -> void:
	# Engraved, two-way Art Deco court: angular foil, obsidian negative space.
	var dark_gold := Color("7c6033")
	for inverted in [false, true]:
		draw_set_transform(_draw_center(), _draw_angle() + (PI if inverted else 0.0), size / BASE * Vector2(_flip_width, 1.0))
		_art_polygon([Vector2(-29, -12), Vector2(-19, -35), Vector2(19, -35), Vector2(29, -12), Vector2(29, -2), Vector2(-29, -2)], dark_gold)
		for x in range(-24, 25, 6):
			draw_line(Vector2(x, -3), Vector2(x * 0.45, -29), _c(color), 1)
		_art_polygon([Vector2(-12, -57), Vector2(10, -57), Vector2(16, -43), Vector2(5, -34), Vector2(-11, -40)], color)
		_art_polygon([Vector2(1, -54), Vector2(11, -49), Vector2(5, -39), Vector2(1, -39)], dark_gold)
		draw_line(Vector2(-8, -48), Vector2(-2, -48), _c(Color("08090b")), 2)
		if rank == 11:
			_art_polygon([Vector2(-17, -57), Vector2(-10, -68), Vector2(14, -64), Vector2(16, -57)], dark_gold)
			draw_line(Vector2(10, -64), Vector2(25, -73), _c(color), 2)
		elif rank == 12:
			draw_arc(Vector2(0, -55), 19, PI, TAU, 20, _c(dark_gold), 2)
			_art_polygon([Vector2(-13, -57), Vector2(-11, -67), Vector2(0, -61), Vector2(11, -67), Vector2(13, -57)], color)
		else:
			_art_polygon([Vector2(-15, -57), Vector2(-17, -69), Vector2(-6, -64), Vector2(0, -74), Vector2(6, -64), Vector2(17, -69), Vector2(15, -57)], color)
			draw_line(Vector2(-5, -38), Vector2(0, -31), _c(color), 3)
		draw_line(Vector2(26, -63), Vector2(26, -15), _c(color), 1)
		_pip(Vector2(26, -65), suit, 1.8, color)
		draw_line(Vector2(-30, 0), Vector2(30, 0), _c(dark_gold), 1)
	draw_set_transform(_draw_center(), _draw_angle(), size / BASE * Vector2(_flip_width, 1.0))

func _draw_contemporary(rank: int, suit: int, color: Color) -> void:
	var lilac := Color("b5a2ca")
	var coral := Color("d9765d")
	var teal := Color("2f716d")
	var dark := Color("262948")
	# Offset collage and generous index margins form a different printed composition.
	draw_rect(Rect2(-30, -74, 58, 142), _c(lilac))
	draw_circle(Vector2(11, 33), 28, _c(coral))
	_art_polygon([Vector2(-30, -18), Vector2(31, -55), Vector2(31, 4)], teal)
	for x in range(-24, 29, 7):
		draw_line(Vector2(x, 54), Vector2(x, 66), _c(dark), 1)
	if rank in [11, 12, 13]:
		# Cut-paper profile: hat, asymmetric face, eye, earring and overlapping garment.
		draw_circle(Vector2(0, -18), 22, _c(Color("ead4ae")))
		_art_polygon([Vector2(5, -38), Vector2(20, -23), Vector2(28, -15), Vector2(17, -10), Vector2(9, 5), Vector2(5, 5)], coral)
		draw_circle(Vector2(5, -21), 2, _c(dark))
		draw_line(Vector2(11, -7), Vector2(18, -7), _c(color), 2)
		_art_polygon([Vector2(-12, 4), Vector2(6, 7), Vector2(31, 43), Vector2(-30, 43)], teal)
		if rank == 11:
			_art_polygon([Vector2(-27, -34), Vector2(-15, -55), Vector2(17, -47), Vector2(25, -34)], dark)
			draw_line(Vector2(-13, -48), Vector2(1, -63), _c(coral), 4)
		elif rank == 12:
			draw_arc(Vector2(-2, -24), 27, PI * 0.8, PI * 1.9, 28, _c(dark), 9)
			draw_circle(Vector2(-19, -5), 4, _c(Color("ddc676")))
			_art_polygon([Vector2(-22, -47), Vector2(-12, -60), Vector2(-3, -47), Vector2(7, -59), Vector2(17, -42)], color)
		else:
			_art_polygon([Vector2(-25, -39), Vector2(-25, -60), Vector2(-12, -49), Vector2(-3, -65), Vector2(8, -49), Vector2(21, -58), Vector2(21, -39)], dark)
			_art_polygon([Vector2(-9, -6), Vector2(9, 3), Vector2(-1, 16), Vector2(-13, 5)], dark)
		_pip(Vector2(1, 29), suit, 3.0, Color("ece4dc"))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(-27, -28), _rank_text(rank), HORIZONTAL_ALIGNMENT_CENTER, 54, 43 if rank != 10 else 36, _c(dark))
		_pip(Vector2(1, 20), suit, 5.7 if rank == 14 else 4.8, color)
		draw_circle(Vector2(-19, 44), 5, _c(Color("ddc676")))

func _draw_constructivist(rank: int, suit: int, color: Color) -> void:
	var red := Color("bc3029")
	var black := Color("171d27")
	var paper := Color("e7dfc9")
	# Diagonal tension, strict circles and cut planes; no collage or traditional frame.
	_art_polygon([Vector2(-29, -73), Vector2(30, -73), Vector2(30, 35), Vector2(-29, 68)], red)
	_art_polygon([Vector2(-29, -18), Vector2(30, -47), Vector2(30, -24), Vector2(-29, 6)], black)
	for y in range(47, 69, 5):
		draw_line(Vector2(-29, y), Vector2(30, y - 29), _c(black), 1)
	if rank in [11, 12, 13]:
		_art_polygon([Vector2(-17, -39), Vector2(9, -39), Vector2(20, -25), Vector2(11, -21), Vector2(11, -7), Vector2(-7, 3), Vector2(-17, -6)], paper)
		_art_polygon([Vector2(-5, -37), Vector2(9, -37), Vector2(18, -26), Vector2(9, -25), Vector2(9, -9), Vector2(-5, -2)], Color("b5a681"))
		draw_rect(Rect2(-8, -28, 7, 3), _c(black))
		_art_polygon([Vector2(-9, 2), Vector2(9, -3), Vector2(29, 27), Vector2(-27, 48)], black)
		if rank == 11:
			_art_polygon([Vector2(-22, -41), Vector2(0, -64), Vector2(22, -41)], black)
		elif rank == 12:
			draw_circle(Vector2(-3, -45), 19, _c(black))
			draw_circle(Vector2(-3, -45), 10, _c(paper))
			draw_rect(Rect2(-20, -44, 35, 6), _c(black))
		else:
			_art_polygon([Vector2(-22, -41), Vector2(-22, -62), Vector2(-9, -53), Vector2(0, -67), Vector2(9, -53), Vector2(22, -62), Vector2(22, -41)], black)
		_pip(Vector2(0, 19), suit, 2.8, paper)
	else:
		draw_circle(Vector2(0, -35), 23, _c(paper))
		draw_string(ThemeDB.fallback_font, Vector2(-24, -22), _rank_text(rank), HORIZONTAL_ALIGNMENT_CENTER, 48, 37 if rank != 10 else 30, _c(black))
		_pip(Vector2(0, 15), suit, 5.8 if rank == 14 else 5.0, paper)
	# Suit-colored register accents retain the red/black convention at the corners.
	draw_rect(Rect2(-61, 35, 4, 26), _c(color))
	draw_rect(Rect2(57, -61, 4, 26), _c(color))

func _number_pip_positions(rank: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if rank == 2 or rank == 3:
		positions = [Vector2(0, -48), Vector2(0, 48)]
		if rank == 3:
			positions.append(Vector2.ZERO)
	else:
		positions = [Vector2(-25, -48), Vector2(25, -48), Vector2(-25, 48), Vector2(25, 48)]
		if rank == 5:
			positions.append(Vector2.ZERO)
		if rank >= 6 and rank <= 8:
			positions.append_array([Vector2(-25, 0), Vector2(25, 0)])
		if rank == 7:
			positions.append(Vector2(0, -25))
		if rank == 8:
			positions.append_array([Vector2(0, -25), Vector2(0, 25)])
		if rank >= 9:
			positions.append_array([Vector2(-25, -16), Vector2(25, -16), Vector2(-25, 16), Vector2(25, 16)])
			if rank == 9:
				positions.append(Vector2.ZERO)
			else:
				positions.append_array([Vector2(0, -33), Vector2(0, 33)])
	return positions

func _corner(rank: int, suit: int, color: Color, inverted: bool) -> void:
	var text_rank: String = {11: "J", 12: "Q", 13: "K", 14: "A"}.get(rank, str(rank))
	var font := ThemeDB.fallback_font
	var font_size := 25 if rank != 10 else 20
	# Rotate both type and pip in the lower corner, as on physical playing cards.
	if inverted:
		draw_set_transform(_draw_center(), _draw_angle() + PI, size / BASE * Vector2(_flip_width, 1.0))
	draw_string(font, Vector2(-61, -61), text_rank, HORIZONTAL_ALIGNMENT_CENTER, 28, font_size, _c(color))
	_pip(Vector2(-49, -43), suit, CORNER_PIP_PIXEL, color)
	if inverted:
		draw_set_transform(_draw_center(), _draw_angle(), size / BASE * Vector2(_flip_width, 1.0))

func _pip(center: Vector2, suit: int, pixel: float, color: Color, inverted: bool = false) -> void:
	var grid: Array = PIPS[clampi(suit, 0, 3)]
	var dimension := grid.size()
	pixel *= 7.0 / dimension
	for row in range(dimension):
		for col in range(dimension):
			if grid[row][col] == "1":
				var p := Vector2(col - dimension * 0.5, row - dimension * 0.5)
				if inverted:
					p = Vector2(dimension * 0.5 - 1.0 - col, dimension * 0.5 - 1.0 - row)
				var printed := color
				if _theme() == 0:
					# Fixed foil bands baked into the ink, independent of time or pointer.
					var band := float(col) / maxf(dimension - 1, 1)
					printed = color.lerp(Color("92703b"), 0.3) if band < 0.25 else color.lerp(Color("ffe2a0"), 0.5) if band < 0.55 else color
				draw_rect(Rect2(center + p * pixel, Vector2.ONE * pixel), _c(printed))

func _portrait(rank: int, suit: int, color: Color) -> void:
	draw_rect(Rect2(-34, -63, 68, 126), _c(GOLD))
	draw_rect(Rect2(-32, -61, 64, 122), _c(Color("e5ddc8")))
	# Two-way court illustration: a crown, face, collar, brocade robe and staff.
	var rows: Array[String] = [
		"...g.g.g...", "...ggggg...", "...gygyg...", "....hhh....",
		"...hsssh...", "...ssiss...", "...sssss...", "....ssr....",
		"....sss....", "...wsssw...", "..wwwwwcc..", ".ccccgcccc.",
		"ccgcccggccc", "cccgcgcccgc", "cgcccgccgcc", "ccgccgccccc",
		"cccccggcgcc", "cgcgccccgcc", "cccccggcccc", "cccccgccccc"
	]
	if rank == 11:
		rows[0] = "..........."
		rows[1] = "...rrrrr..."
		rows[2] = "..rrrrrrg.."
	elif rank == 12:
		rows[7] = "...hssrh..."
		rows[8] = "...hsssh..."
		rows[10] = "..hwwwwwh.."
	else:
		rows[7] = "...hssrh..."
		rows[8] = "....hhh...."
	var palette := {"g": GOLD, "y": Color("f4d998"), "h": INK, "s": Color("d3ab84"), "i": Color("342c32"), "r": RED, "w": PAPER, "c": color}
	for inverted in [false, true]:
		var factor := -1.0 if inverted else 1.0
		for row in range(rows.size()):
			for col in range(11):
				var key := rows[row][col]
				if palette.has(key):
					var p := Vector2((col - 5.5) * 3, -58 + row * 3)
					if inverted:
						p = -p - Vector2(3, 3)
					draw_rect(Rect2(p, Vector2(3, 3)), _c(palette[key]))
		# Staff for kings, slim sword for jacks, flower for queens.
		draw_rect(Rect2(Vector2(23, -51) * factor - (Vector2(2, 0) if inverted else Vector2.ZERO), Vector2(2, 48) * Vector2(1, factor)).abs(), _c(GOLD))
		_pip(Vector2(24, -49) * factor, suit if rank == 12 else 1, 1.5, color)
	draw_line(Vector2(-30, 0), Vector2(30, 0), _c(GOLD), 2)

func _draw_recipe(recipe: Dictionary, front: bool) -> void:
	var primary := Color.html(recipe.primary)
	var accent := Color.html(recipe.accent)
	draw_rect(Rect2(-60, -86, 120, 172), _c(primary), false, 1.0)
	if _marks_recipe != recipe:
		_marks_recipe = recipe.duplicate(true)
		_recipe_back.clear()
		_recipe_front.clear()
		for group in Art.geometry(recipe):
			var back_points := PackedVector2Array()
			var front_points := PackedVector2Array()
			for p in group.points:
				back_points.append(p * Vector2(53, 78))
				front_points.append(p * Vector2(29, 68))
			_recipe_back.append({"points": back_points, "color": group.color, "alpha": group.alpha})
			_recipe_front.append({"points": front_points, "color": group.color, "alpha": group.alpha})
	for group in (_recipe_front if front else _recipe_back):
		var color := accent if group.color == 1 else primary
		color.a = group.alpha * (0.14 if front else 0.9)
		draw_multiline(group.points, _c(color), recipe.line_width * (0.55 if front else 0.85), true)
	if not front: return
	var rank := card_id % 13 + 2
	var suit := card_id / 13
	var ink := Themes.recipe_ink(recipe, suit)
	_corner(rank, suit, ink, false)
	_corner(rank, suit, ink, true)
	if rank in [11, 12, 13]:
		draw_string(ThemeDB.fallback_font, Vector2(-27, -17), _rank_text(rank), HORIZONTAL_ALIGNMENT_CENTER, 54, 42, _c(ink))
		_pip(Vector2(0, 24), suit, 4.7, ink)
	elif rank == 14:
		_pip(Vector2(0, -4), suit, ACE_PIP_PIXEL, ink)
	else:
		for p in _number_pip_positions(rank):
			_pip(p, suit, DENSE_PIP_PIXEL if rank >= 9 else NUMBER_PIP_PIXEL, ink, p.y > 0)
