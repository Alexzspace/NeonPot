extends Control
## A pixel cassette deck; transport targets stay finger-sized in both layouts.
signal operated
const Marquee = preload("res://scripts/marquee_label.gd")
var music: Node
var compact := false
var title_label: Control
var pause_button: Button
var previous_button: Button
var next_button: Button
var _time := 0.0

class Transport extends Button:
	var glyph := "play"
	func _draw() -> void:
		var center := size * 0.5
		var color := Color("ecd9cf") if not disabled else Color("716778")
		if glyph == "pause":
			for x in [-12, 5]: draw_rect(Rect2(center + Vector2(x, -14), Vector2(7, 28)), color)
		else:
			var direction := -1.0 if glyph == "previous" else 1.0
			var shift := -3.0 if glyph == "play" else 0.0
			for row in range(7):
				var width := 4.0 * (4 - absi(row - 3))
				var x := center.x + shift - (width if direction < 0 else 9.0)
				draw_rect(Rect2(x, center.y - 14 + row * 4, width, 4), color)
			if glyph != "play":
				draw_rect(Rect2(center + Vector2(direction * 17 - 3, -14), Vector2(5, 28)), color)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at := Vector2(18, 27) if compact else Vector2(24, 30)
	title_label = Marquee.new()
	title_label.position = at
	title_label.size = Vector2(342, 46) if compact else Vector2(size.x - 48, 44)
	add_child(title_label)
	var button_y := 0.0 if compact else 88.0
	var button_x := 376.0 if compact else 254.0
	var width := 88.0 if compact else 100.0
	previous_button = _transport("previous", Vector2(button_x, button_y), Vector2(width, 88), func(): music.previous_track())
	pause_button = _transport("play", Vector2(button_x + width + 8, button_y), Vector2(width, 88), func(): music.toggle_pause())
	next_button = _transport("next", Vector2(button_x + (width + 8) * 2, button_y), Vector2(width, 88), func(): music.next_track())
	if is_instance_valid(music): music.changed.connect(_sync)
	_sync()

func _transport(glyph: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Transport.new()
	button.glyph = glyph
	button.position = at
	button.size = dimensions
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = {"previous": "Previous / 上一首", "play": "Play / pause · 播放 / 暂停", "next": "Next / 下一首"}[glyph]
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("49364e") if glyph == "play" else Color("2c2c42")
		if state == "hover": style.bg_color = style.bg_color.lightened(0.1)
		if state == "pressed": style.bg_color = style.bg_color.darkened(0.2)
		style.border_color = Color("ac738f") if glyph == "play" else Color("656077")
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.shadow_color = Color("070a19")
		style.shadow_size = 2
		style.shadow_offset = Vector2(0, 4)
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("73c7d2")
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var last_press := [-1000]
	button.pressed.connect(func():
		var now := Time.get_ticks_msec()
		if now - last_press[0] < 120: return
		last_press[0] = now
		callback.call()
		operated.emit())
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed and not button.disabled:
			button.pressed.emit()
			button.accept_event())
	add_child(button)
	return button

func _sync() -> void:
	if not is_instance_valid(music) or not is_instance_valid(title_label): return
	title_label.text = music.title() if not music.tracks.is_empty() else "NO TAPE / 暂无音乐"
	pause_button.glyph = "play" if music.paused else "pause"
	for button in [previous_button, pause_button, next_button]:
		button.disabled = music.tracks.is_empty()
		button.queue_redraw()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if is_instance_valid(music) and not music.paused and music._player.playing and not music._player.stream_paused:
		_time += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("141727"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("65516d"), false, 2)
	draw_rect(Rect2(0, 0, size.x * 0.42, 3), Color("df77a9"))
	draw_rect(Rect2(size.x * 0.42, 0, size.x * 0.58, 3), Color("64bccc"))
	var font := get_theme_default_font()
	draw_string(font, Vector2(18, 21), "MIDNIGHT / TOKYO • STEREO", HORIZONTAL_ALIGNMENT_LEFT, 342 if compact else size.x - 32, 18, Color("b28aa6"))
	if compact: return
	# Two turning tape reels and a low-resolution transport indicator.
	draw_rect(Rect2(18, 86, 216, 88), Color("24273b"))
	draw_rect(Rect2(18, 86, 216, 88), Color("4f536a"), false, 2)
	for x in [66.0, 184.0]:
		var center := Vector2(x, 127)
		draw_circle(center, 26, Color("121522"))
		draw_arc(center, 22, 0, TAU, 16, Color("aca0a9"), 3)
		for spoke in 3:
			var angle := _time * 2.4 + spoke * TAU / 3
			draw_line(center + Vector2.from_angle(angle) * 8, center + Vector2.from_angle(angle) * 18, Color("df8dac"), 5)
		draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color("d5c5bd"))
	draw_line(Vector2(88, 130), Vector2(162, 130), Color("71677e"), 3)
	for index in 8:
		draw_rect(Rect2(35 + index * 24, 158, 15, 3), Color("63a8b9") if index % 3 != 0 else Color("e18cae"))
