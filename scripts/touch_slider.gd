extends Range
## A single-finger slider with a large grab area and discrete optional notches.
signal value_edit_requested
signal user_changed(value: float)
signal magnet_entered
var magnets: Array = []
var _snapped := -1.0
var _last_drag_x := 0.0
var _last_drag_ms := 0

func set_magnets(points: Array) -> void:
	if _finger != -1: return
	magnets = points.duplicate(true)
	_snapped = -1.0
	queue_redraw()

var editable := true:
	set(next):
		editable = next
		if not next: _finger = -1
		queue_redraw()
var caption := "":
	set(next):
		caption = next
		queue_redraw()
var notches := false
var allow_value_edit := false
var outer_layout := false:
	set(next):
		outer_layout = next
		_finger = -1
		queue_redraw()
var _finger := -1
var _label_press := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	value_changed.connect(func(_next: float): queue_redraw())
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var ink := Color("d9aad5") if editable else Color("666078")
	var track_y := 110.0 if outer_layout and not caption.is_empty() else size.y * (0.70 if not caption.is_empty() else 0.5)
	var left := _track_padding()
	var right := maxf(left, size.x - left)
	var fraction := clampf((value - min_value) / maxf(1, max_value - min_value), 0, 1)
	var x := lerpf(left, right, fraction)
	draw_style_box(_style(Color("161626"), Color("484158"), 14), Rect2(Vector2.ZERO, size))
	draw_line(Vector2(left, track_y), Vector2(right, track_y), Color("45415a"), 18 if outer_layout else 12, true)
	draw_line(Vector2(left, track_y), Vector2(x, track_y), ink, 16 if outer_layout else 12, true)
	if notches:
		for index in range(int(max_value - min_value) + 1):
			var at := lerpf(left, right, float(index) / maxf(1, max_value - min_value))
			draw_circle(Vector2(at, track_y), 4, Color("8d809a"), true, -1, true)
	var header := header_layout()
	var label_rects: Array = header.label_rects
	for index in magnets.size():
		var point: Dictionary = magnets[index]
		var mark := _magnet_track_x(float(point.value))
		var active := absf(value - float(point.value)) < 0.5
		var mark_ink := Color("f4d7bb") if active else Color("bfa0b8")
		draw_line(Vector2(mark, track_y - 10), Vector2(mark, track_y + 10), mark_ink, 2, true)
		if index < label_rects.size():
			var rect: Rect2 = label_rects[index]
			# Fixed header cells identify moving track landmarks without chasing them.
			var start := Vector2(rect.get_center().x, rect.end.y + 1)
			var end := Vector2(mark, track_y - 12)
			draw_line(start, end, Color(mark_ink, 0.70 if active else 0.32), 1.0, true)
			var frame := _style(Color(mark_ink, 0.10 if active else 0.035), Color(mark_ink, 0.42 if active else 0.20), 7)
			frame.set_border_width_all(1)
			draw_style_box(frame, rect)
			var font := get_theme_default_font()
			var font_size: int = header.label_font_size
			var baseline := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
			draw_string(font, Vector2(rect.position.x, baseline), str(point.label), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, mark_ink)
	var thumb := Rect2(x - 38, track_y - 36, 76, 72) if outer_layout else Rect2(x - 26, track_y - 25, 52, 50)
	draw_style_box(_style(Color("78516f") if editable else Color("393348"), ink, 10), thumb)
	for offset in [-6, 0, 6]:
		var grip_height := 13.0 if outer_layout else 8.0
		draw_line(Vector2(x + offset, track_y - grip_height), Vector2(x + offset, track_y + grip_height), ink, 2)
	if not caption.is_empty():
		var font := get_theme_default_font()
		var baseline := 49.0 if outer_layout else 31.0
		var value_area := _value_edit_rect()
		if allow_value_edit:
			var field := Rect2(value_area.position + Vector2(12, 4), value_area.size - Vector2(24, 6))
			var field_style := _style(Color(0.65, 0.48, 0.66, 0.09 if editable else 0.025), Color(ink, 0.52 if editable else 0.22), 8)
			field_style.set_border_width_all(1)
			draw_style_box(field_style, field)
			var key_origin := field.position + Vector2(12, field.size.y * 0.5 - 5)
			draw_rect(Rect2(key_origin - Vector2(3, 3), Vector2(22, 15)), Color(ink, 0.6), false, 1)
			for row in 2:
				for column in 3:
					draw_rect(Rect2(key_origin + Vector2(column * 6, row * 5), Vector2(3, 2)), Color(ink, 0.75))
		draw_string(font, Vector2(header.caption_rect.position.x, baseline), caption, HORIZONTAL_ALIGNMENT_LEFT, header.caption_rect.size.x, int(header.caption_font_size), ink)
		draw_string(font, Vector2(value_area.position.x, baseline), str(int(value)), HORIZONTAL_ALIGNMENT_RIGHT, value_area.size.x - 24, 42 if outer_layout else 28, Color("f4e9e1"))
	if has_focus():
		draw_style_box(_style(Color.TRANSPARENT, ink, 14), Rect2(Vector2.ONE * 2, size - Vector2.ONE * 4))

## Header geometry is public for layout regression checks. Caption, landmark cells
## and numeric value have disjoint horizontal regions, independent of magnet values.
func header_layout() -> Dictionary:
	var font := get_theme_default_font()
	var value_rect := _value_edit_rect()
	var caption_size := 36 if outer_layout else 26
	var left := 24.0 if outer_layout else 22.0
	var gap := 12.0 if outer_layout else 10.0
	var available := maxf(1.0, value_rect.position.x - left - gap)
	var caption_width := available
	var rects: Array[Rect2] = []
	var label_size := 24 if outer_layout else 18
	if not magnets.is_empty():
		caption_width = minf(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x + 2, available * 0.42)
		while caption_size > 12 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x > caption_width:
			caption_size -= 1
		var row_left := left + caption_width + gap
		var row_right := value_rect.position.x - gap
		var cell_width := maxf(1.0, (row_right - row_left) / maxi(4, magnets.size()))
		for index in magnets.size():
			rects.append(Rect2(row_left + index * cell_width + 2, 18 if outer_layout else 6, maxf(1.0, cell_width - 4), 32 if outer_layout else 25))
		for point in magnets:
			while label_size > 10 and font.get_string_size(str(point.label), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x > maxf(1.0, cell_width - 12):
				label_size -= 1
	return {"caption_rect": Rect2(left, 0, caption_width, 70 if outer_layout else 38), "value_rect": value_rect, "label_rects": rects, "caption_font_size": caption_size, "label_font_size": label_size}

func _magnet_track_x(amount: float) -> float:
	var padding := _track_padding()
	return lerpf(padding, maxf(padding, size.x - padding), clampf((amount - min_value) / maxf(1, max_value - min_value), 0, 1))

func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style

func _track_padding() -> float:
	return 44.0 if outer_layout else 30.0

func _value_edit_rect() -> Rect2:
	return Rect2(size.x - 240, 0, 240, 70) if outer_layout else Rect2(size.x - 210, 0, 210, 38)

func _set_from_x(x: float) -> void:
	var old := value
	var padding := _track_padding()
	var target := lerpf(min_value, max_value, clampf((x - padding) / maxf(1, size.x - padding * 2), 0, 1))
	var now := Time.get_ticks_msec()
	var speed := absf(x - _last_drag_x) / maxf(1, now - _last_drag_ms) * 1000.0 if _last_drag_ms > 0 else 0.0
	_last_drag_x = x
	_last_drag_ms = now
	var selected := -1.0
	if speed < 900.0:
		var nearest := 10.0
		for point in magnets:
			var mark := padding + (float(point.value) - min_value) / maxf(1, max_value - min_value) * (size.x - padding * 2)
			var distance := absf(x - mark)
			if distance < nearest:
				nearest = distance
				selected = float(point.value)
	if selected >= 0:
		target = selected
		if _snapped != selected: magnet_entered.emit()
	_snapped = selected
	value = target
	if value != old: user_changed.emit(value)

func _activate_header_label(at: Vector2) -> bool:
	var rects: Array = header_layout().label_rects
	for index in rects.size():
		if not rects[index].has_point(at): continue
		var old := value
		var target := float(magnets[index].value)
		if _snapped != target: magnet_entered.emit()
		_snapped = target
		value = target
		if value != old: user_changed.emit(value)
		return true
	return false

func _gui_input(event: InputEvent) -> void:
	if not editable: return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1:
			grab_focus()
			_label_press = _activate_header_label(event.position)
			if _label_press:
				_finger = event.index
			elif allow_value_edit and _value_edit_rect().has_point(event.position):
				value_edit_requested.emit()
			else:
				_last_drag_ms = 0
				_finger = event.index
				_set_from_x(event.position.x)
		elif not event.pressed and event.index == _finger:
			_finger = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index == _finger:
		if not _label_press: _set_from_x(event.position.x)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.pressed and _finger == -1:
			grab_focus()
			_label_press = _activate_header_label(event.position)
			if _label_press:
				_finger = -2
			elif allow_value_edit and _value_edit_rect().has_point(event.position):
				value_edit_requested.emit()
			else:
				_last_drag_ms = 0
				_finger = -2
				_set_from_x(event.position.x)
		elif not event.pressed and _finger == -2:
			_finger = -1
		accept_event()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _finger == -2:
		if not _label_press: _set_from_x(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var old := value
		if event.keycode == KEY_LEFT: value -= step
		elif event.keycode == KEY_RIGHT: value += step
		elif event.keycode == KEY_HOME: value = min_value
		elif event.keycode == KEY_END: value = max_value
		else: return
		if value != old: user_changed.emit(value)
		accept_event()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]: queue_redraw()
	if what in [NOTIFICATION_FOCUS_EXIT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED]:
		_finger = -1
