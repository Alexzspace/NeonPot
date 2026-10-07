extends Control
## A tactile showroom. Only applying a deck changes preferences or a room.
signal theme_selected(id: int)
signal closed()
signal contact()

const Card = preload("res://scripts/card_view.gd")
const Themes = preload("res://scripts/card_themes.gd")
const ACCENT := Color("d9aad5")
const INK := Color("f4e9e1")
const MUTED := Color("a3a5bd")
const GAP := 10.0

var language := "zh":
	set(value):
		language = "en" if value == "en" else "zh"
		if is_node_ready(): _refresh_labels()
var selected_theme := 0:
	set(value):
		var previous := selected_theme
		selected_theme = Themes.valid_id(value)
		if is_node_ready():
			_refresh_selection()
			if previous != selected_theme: _animate_selection()
var can_apply := true:
	set(value):
		can_apply = value
		if is_node_ready(): _refresh_labels()
var browsed_theme := 0
var inspected_card := 51
var cards: Array[Control] = []
var theme_buttons: Array[Button] = []
var theme_marks: Array[ColorRect] = []
var theme_names: Array[Label] = []
var grid_view: Control
var grid_content: Control
var preview_face: Control
var preview_back: Control
var apply_button: Button
var close_button: Button
var title_label: Label
var hint_label: Label
var host_label: Label
var preview_label: Label
var _preview_panel: Panel
var _entrance: Tween
var _rests: Array[Vector2] = []
var _scroll := 0.0
var _scroll_limit := 0.0
var _scroll_velocity := 0.0
var _pointer := -2
var _press_position := Vector2.ZERO
var _last_position := Vector2.ZERO
var _press_target := ""
var _press_index := -1
var _dragging := false
var _last_move_usec := 0
var _input_enabled := true
var _gesture_axis := ""
var _small_angles: Array[float] = []
var _preview_tweens: Array[Tween] = []
var _start_angle := 0.0
var _panel_entrance: Tween
var _selection_tween: Tween
var _initial_entry_pending := true

func _ready() -> void:
	size = Vector2(1440, maxf(660, size.y))
	mouse_filter = Control.MOUSE_FILTER_STOP
	browsed_theme = selected_theme
	title_label = _label(34, ACCENT)
	close_button = _button(_close)
	for theme_index in Themes.COUNT:
		var button := _button(_browse.bind(theme_index))
		theme_buttons.append(button)
		var face := _card(button, 51, true, theme_index, 49)
		face.position = Vector2(103, 7)
		var back := _card(button, 51, false, theme_index, 49)
		back.position = Vector2(173, 7)
		var name_label := _label(20, INK, button)
		name_label.position = Vector2(12, 77)
		name_label.size = Vector2(307, 26)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		theme_names.append(name_label)
		var mark := ColorRect.new()
		mark.color = ACCENT
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.position = Vector2(18, 46)
		mark.size = Vector2(8, 22)
		button.add_child(mark)
		theme_marks.append(mark)
	grid_view = Control.new()
	grid_view.clip_contents = true
	grid_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid_view)
	grid_content = Control.new()
	grid_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_view.add_child(grid_content)
	for card_id in 52:
		cards.append(_card(grid_content, card_id, true, browsed_theme, 92))
		_small_angles.append(0.0)
	_preview_panel = Panel.new()
	_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_panel.add_theme_stylebox_override("panel", _style(Color("202036"), Color("54435e")))
	add_child(_preview_panel)
	preview_face = _card(_preview_panel, inspected_card, true, browsed_theme, 146)
	preview_back = _card(_preview_panel, inspected_card, false, browsed_theme, 146)
	preview_label = _label(30, INK, _preview_panel)
	hint_label = _label(22, MUTED, _preview_panel)
	host_label = _label(22, MUTED, _preview_panel)
	apply_button = _button(_apply, _preview_panel)
	resized.connect(_layout)
	_layout()
	_refresh_labels()
	_refresh_selection()
	# Main applies safe-area layout immediately after add_child; let that finish
	# before starting, so the initial cards are not snapped to rest by reflow.
	for card in cards: card.modulate.a = 0.0
	_begin_initial_entry.call_deferred()

func _begin_initial_entry() -> void:
	if not _initial_entry_pending or not _input_enabled or not is_visible_in_tree(): return
	_initial_entry_pending = false
	_panel_entrance = create_tween().set_parallel(true)
	for control in [title_label, close_button, _preview_panel] + theme_buttons:
		control.modulate.a = 0.0
		_panel_entrance.tween_property(control, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_animate_cards()

func set_available_height(height: float) -> void:
	size = Vector2(1440, maxf(660, height))
	if is_node_ready(): _layout()

func _label(font_size: int, color: Color, parent: Node = self) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style

func _button(action: Callable, parent: Node = self) -> Button:
	var button := Button.new()
	# One gesture router handles native touch and emulated mouse exactly once.
	# Keyboard/accessibility activation still uses the normal pressed signal.
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color("242237"), Color("665570")))
	button.add_theme_stylebox_override("focus", _style(Color("393047"), ACCENT))
	button.add_theme_stylebox_override("disabled", _style(Color("1b1929"), Color("383343")))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _card(parent: Node, id: int, face: bool, deck: int, width: float) -> Control:
	var card := Card.new()
	card.card_scale = width / Card.BASE.x
	card.size = Card.BASE * card.card_scale
	card.theme_id = deck
	parent.add_child(card)
	card.set_card(id, face)
	card.pivot_offset = card.size * 0.5
	return card

func _layout() -> void:
	if not is_instance_valid(grid_view): return
	_cancel_input()
	_stop_entrance()
	_stop_selection()
	title_label.position = Vector2(28, 8)
	title_label.size = Vector2(900, 52)
	close_button.position = Vector2(1210, 8)
	close_button.size = Vector2(202, 52)
	for index in theme_buttons.size():
		theme_buttons[index].position = Vector2(28 + index * 351, 74)
		theme_buttons[index].size = Vector2(331, 106)
	grid_view.position = Vector2(28, 196)
	grid_view.size = Vector2(1384, size.y - 466)
	grid_content.size = Vector2(1384, 4 * 143 + 12)
	_rests.clear()
	for index in cards.size():
		var rest := Vector2(7 + (index % 13) * 106, 8 + (index / 13) * 143)
		cards[index].position = rest
		_rests.append(rest)
	_scroll_limit = maxf(0, grid_content.size.y - grid_view.size.y)
	_set_scroll(_scroll)
	_preview_panel.position = Vector2(28, size.y - 252)
	_preview_panel.size = Vector2(1384, 232)
	preview_face.position = Vector2(20, 14)
	preview_back.position = Vector2(186, 14)
	preview_label.position = Vector2(364, 22)
	preview_label.size = Vector2(980, 46)
	hint_label.position = Vector2(364, 76)
	hint_label.size = Vector2(960, 40)
	host_label.position = Vector2(364, 142)
	host_label.size = Vector2(580, 40)
	apply_button.position = Vector2(954, 140)
	apply_button.size = Vector2(408, 68)
	apply_button.pivot_offset = apply_button.size * 0.5
	for button in theme_buttons: button.pivot_offset = button.size * 0.5
	if _initial_entry_pending:
		for card in cards: card.modulate.a = 0.0
	queue_redraw()

func _refresh_labels() -> void:
	title_label.text = "牌面展廊" if language == "zh" else "DECK GALLERY"
	close_button.text = "返回" if language == "zh" else "BACK"
	for index in theme_names.size(): theme_names[index].text = Themes.collection_name(index, language)
	_refresh_description()
	hint_label.text = "上下浏览 · 左右拨弄 · 轻点放大，这是你的展廊" if language == "zh" else "SCROLL · TILT · TAP TO INSPECT. MAKE IT YOURS."
	host_label.text = ("房主决定牌桌主题" if language == "zh" else "THE HOST CHOOSES THE TABLE DECK") if not can_apply else ("选好后再使用这副牌" if language == "zh" else "BROWSE FIRST. APPLY WHEN READY.")
	_refresh_apply_label()
	apply_button.disabled = not can_apply

func _refresh_apply_label() -> void:
	var applied := browsed_theme == selected_theme
	apply_button.text = ("已选用  ✓" if language == "zh" else "SELECTED  ✓") if applied else ("使用这副牌" if language == "zh" else "USE THIS DECK")
	apply_button.add_theme_stylebox_override("normal", _style(Color("393047") if applied else Color("242237"), ACCENT if applied else Color("665570")))

func _refresh_selection() -> void:
	_refresh_description()
	_refresh_apply_label()
	for index in theme_buttons.size():
		theme_marks[index].visible = index == selected_theme
		theme_buttons[index].add_theme_stylebox_override("normal", _style(Color("393047") if index == browsed_theme else Color("211e31"), ACCENT if index == browsed_theme else Color("51465e")))
	for card in cards: card.theme_id = browsed_theme
	preview_face.theme_id = browsed_theme
	preview_back.theme_id = browsed_theme

func _refresh_description() -> void:
	if not is_instance_valid(preview_label): return
	var chinese := ["黑夜为纸，鎏金落笔。", "色块游离，让秩序留一处即兴。", "以几何为序，以锋芒破局。", "褪去繁饰，让每一手清晰有度。"]
	var english := ["MIDNIGHT STOCK. A SIGNATURE IN GOLD.", "COLOUR WANDERS. ORDER LEAVES ROOM FOR ART.", "GEOMETRY IN ORDER. SPIRIT AT THE EDGE.", "PURE FORM. EVERY HAND IN FOCUS."]
	preview_label.text = chinese[browsed_theme] if language == "zh" else english[browsed_theme]
	preview_label.add_theme_font_size_override("font_size", 28 if language == "zh" else 26)

func _browse(id: int) -> void:
	if not _input_enabled: return
	_cancel_input()
	browsed_theme = Themes.valid_id(id)
	_set_scroll(0.0)
	_refresh_selection()
	_animate_cards()
	contact.emit()

func _inspect(id: int) -> void:
	inspected_card = clampi(id, 0, 51)
	preview_face.set_card(inspected_card, true)
	preview_back.set_card(inspected_card, false)
	contact.emit()

func _apply() -> void:
	if not can_apply or not _input_enabled: return
	_cancel_input()
	contact.emit()
	theme_selected.emit(browsed_theme)
	# Authority confirms by updating selected_theme synchronously or in a later
	# snapshot. Do not mark a rejected request as applied.
	if selected_theme == browsed_theme: _animate_selection()

func _animate_selection() -> void:
	_stop_panel_entrance()
	_stop_selection()
	_selection_tween = create_tween().set_parallel(true)
	var controls: Array[Control] = [theme_buttons[selected_theme]]
	if selected_theme == browsed_theme: controls.append(apply_button)
	for control in controls:
		control.scale = Vector2(0.97, 0.97)
		control.modulate = Color(1.16, 1.10, 1.15)
		_selection_tween.tween_property(control, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_selection_tween.tween_property(control, "modulate", Color.WHITE, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _stop_selection() -> void:
	if _selection_tween and _selection_tween.is_valid(): _selection_tween.kill()
	_selection_tween = null
	for control in theme_buttons:
		control.scale = Vector2.ONE
		control.modulate = Color.WHITE
	if is_instance_valid(apply_button):
		apply_button.scale = Vector2.ONE
		apply_button.modulate = Color.WHITE

func _stop_panel_entrance() -> void:
	if _panel_entrance and _panel_entrance.is_valid(): _panel_entrance.kill()
	_panel_entrance = null
	for control in [title_label, close_button, _preview_panel] + theme_buttons:
		if is_instance_valid(control): control.modulate.a = 1.0

func _close() -> void:
	if not _input_enabled: return
	_input_enabled = false
	_initial_entry_pending = false
	_cancel_input()
	_stop_entrance()
	_stop_panel_entrance()
	contact.emit()
	closed.emit()

func _animate_cards() -> void:
	_stop_entrance()
	_entrance = create_tween().set_parallel(true)
	for index in cards.size():
		cards[index].position = _rests[index] + Vector2(22, 12)
		cards[index].modulate.a = 0.0
		var delay := index * 0.009
		_entrance.tween_property(cards[index], "position", _rests[index], 0.38).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_entrance.tween_property(cards[index], "modulate:a", 1.0, 0.24).set_delay(delay)

func _stop_entrance() -> void:
	if _entrance and _entrance.is_valid(): _entrance.kill()
	_entrance = null
	for index in mini(cards.size(), _rests.size()):
		cards[index].position = _rests[index]
		cards[index].modulate.a = 1.0

func _point(event: InputEvent) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * event.position

func _input(event: InputEvent) -> void:
	if not _input_enabled or not is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		if event.pressed: _press(event.index, _point(event))
		elif event.index == _pointer: _release(_point(event), event.canceled)
	elif event is InputEventScreenDrag and event.index == _pointer:
		_move(_point(event))
	elif event is InputEventMouseButton and event.device != -1:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and grid_view.get_global_rect().has_point(event.position):
			_stop_entrance()
			_set_scroll(_scroll + (-90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 90))
			get_viewport().set_input_as_handled()
		elif not Input.emulate_touch_from_mouse and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _press(-1, _point(event))
			elif _pointer == -1: _release(_point(event), false)
	elif event is InputEventMouseMotion and _pointer == -1:
		_move(_point(event))

func _press(pointer: int, point: Vector2) -> void:
	if _pointer != -2 or not Rect2(Vector2.ZERO, size).has_point(point): return
	_pointer = pointer
	_press_position = point
	_last_position = point
	_last_move_usec = Time.get_ticks_usec()
	_scroll_velocity = 0.0
	_dragging = false
	_gesture_axis = ""
	_start_angle = 0.0
	_press_target = ""
	_press_index = -1
	if close_button.get_rect().has_point(point): _press_target = "close"
	elif Rect2(_preview_panel.position + apply_button.position, apply_button.size).has_point(point): _press_target = "apply"
	elif Rect2(_preview_panel.position + preview_face.position, preview_face.size).has_point(point):
		_press_target = "preview_face"
		_stop_preview_motion(false)
		_start_angle = preview_face.rotation
	elif Rect2(_preview_panel.position + preview_back.position, preview_back.size).has_point(point):
		_press_target = "preview_back"
		_stop_preview_motion(false)
		_start_angle = preview_back.rotation
	elif grid_view.get_rect().has_point(point):
		_press_target = "grid"
		_stop_entrance()
		_press_index = _card_at(point)
		if _press_index >= 0: _start_angle = _small_angles[_press_index]
	else:
		for index in theme_buttons.size():
			if theme_buttons[index].get_rect().has_point(point):
				_press_target = "theme"
				_press_index = index
	get_viewport().set_input_as_handled()

func _card_at(point: Vector2) -> int:
	var local := point - grid_view.position - grid_content.position
	for index in cards.size():
		if cards[index].get_rect().has_point(local): return index
	return -1

func _move(point: Vector2) -> void:
	if _pointer == -2: return
	var travel := point - _press_position
	if not _dragging and travel.length() > 12:
		_dragging = true
		_gesture_axis = "horizontal" if absf(travel.x) > absf(travel.y) else "vertical"
		if _gesture_axis == "horizontal" and ((_press_target == "grid" and _press_index >= 0) or _press_target.begins_with("preview_")):
			contact.emit()
	if _press_target == "grid" and _dragging and _gesture_axis == "vertical":
		var now := Time.get_ticks_usec()
		var elapsed := maxf(0.008, (now - _last_move_usec) / 1000000.0)
		_set_scroll(_scroll - (point.y - _last_position.y))
		_scroll_velocity = clampf(-(point.y - _last_position.y) / elapsed, -1600, 1600)
		_last_move_usec = now
	elif _dragging and _gesture_axis == "horizontal":
		var angle := clampf(_start_angle + travel.x * 0.004, -0.22, 0.22)
		if _press_target == "grid" and _press_index >= 0:
			_small_angles[_press_index] = angle
			cards[_press_index].rotation = angle
		elif _press_target == "preview_face": preview_face.rotation = angle
		elif _press_target == "preview_back": preview_back.rotation = angle
	_last_position = point
	get_viewport().set_input_as_handled()

func _release(point: Vector2, canceled: bool) -> void:
	var target := _press_target
	var index := _press_index
	var tapped := not _dragging and point.distance_to(_press_position) <= 12 and not canceled
	_pointer = -2
	_press_target = ""
	_gesture_axis = ""
	if target.begins_with("preview_"): _return_previews()
	if canceled: _scroll_velocity = 0.0
	get_viewport().set_input_as_handled()
	if tapped:
		match target:
			"close": _close()
			"apply": _apply()
			"theme": _browse(index)
			"grid":
				if index >= 0 and _card_at(point) == index: _inspect(index)

func _set_scroll(value: float) -> void:
	_scroll = clampf(value, 0, _scroll_limit)
	grid_content.position.y = -_scroll
	queue_redraw()

func _process(delta: float) -> void:
	if _pointer != -2 or absf(_scroll_velocity) < 2: return
	_set_scroll(_scroll + _scroll_velocity * delta)
	_scroll_velocity *= exp(-9 * delta)
	if _scroll <= 0 or _scroll >= _scroll_limit: _scroll_velocity = 0.0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("11101e"))
	if not is_instance_valid(grid_view) or _scroll_limit <= 0: return
	var at := grid_view.position + Vector2(grid_view.size.x - 4, 0)
	draw_rect(Rect2(at, Vector2(3, grid_view.size.y)), Color("393246"))
	var thumb := maxf(24, grid_view.size.y * grid_view.size.y / grid_content.size.y)
	at.y += (grid_view.size.y - thumb) * _scroll / _scroll_limit
	draw_rect(Rect2(at, Vector2(3, thumb)), ACCENT)

func _cancel_input() -> void:
	_pointer = -2
	_dragging = false
	_press_target = ""
	_scroll_velocity = 0.0
	_gesture_axis = ""
	_stop_preview_motion(true)
	_stop_selection()

func _stop_preview_motion(reset: bool) -> void:
	for tween in _preview_tweens:
		if tween and tween.is_valid(): tween.kill()
	_preview_tweens.clear()
	if reset:
		if is_instance_valid(preview_face): preview_face.rotation = 0.0
		if is_instance_valid(preview_back): preview_back.rotation = 0.0

func _return_previews() -> void:
	_stop_preview_motion(false)
	for card in [preview_face, preview_back]:
		if not is_instance_valid(card) or is_zero_approx(card.rotation): continue
		var tween := create_tween()
		tween.tween_property(card, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_preview_tweens.append(tween)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_initial_entry_pending = false
		_cancel_input()
		_stop_entrance()
		_stop_panel_entrance()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		_initial_entry_pending = false
		_cancel_input()
		_stop_entrance()
		_stop_panel_entrance()

func _exit_tree() -> void:
	_initial_entry_pending = false
	_cancel_input()
	_stop_entrance()
	_stop_panel_entrance()
