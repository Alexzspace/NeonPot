extends Control
## An editable amount draft. Acceptance selects the slider amount; it never bets.
signal accepted(value: int)
signal cancel_requested
const Wheel = preload("res://scripts/inertia_wheel.gd")
const FONT = preload("res://assets/fonts/fusion-pixel.ttf")
var _initial := 0
var _minimum := 0
var _maximum := 0
var _language := "zh"
var _keyboard_mode := false
var _last_touch_ms := -1000
var _wheel: Range
var _edit: LineEdit
var _toggle: Button
var _apply_button: Button
var _cancel_button: Button
var _hint: Label

func configure(initial: int, minimum: int, maximum: int, language: String = "zh") -> void:
	_minimum = minimum
	_maximum = maxi(minimum, maximum)
	_initial = clampi(initial, _minimum, _maximum)
	_language = language
	if is_node_ready(): _reset()

func _ready() -> void:
	custom_minimum_size = Vector2(520, 300)
	_wheel = Wheel.new()
	_wheel.slot_pitch = 68.0
	_wheel.numeral_size = 56
	_wheel.strong_snap = true
	_wheel.position = Vector2.ZERO
	_wheel.size = Vector2(520, 204)
	add_child(_wheel)
	_wheel.user_changed.connect(func(value: float) -> void:
		_edit.text = str(roundi(value))
		_validate())
	_edit = LineEdit.new()
	_edit.position = Vector2(0, 62)
	_edit.size = Vector2(520, 80)
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.add_theme_font_override("font", FONT)
	_edit.add_theme_font_size_override("font_size", 56)
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_edit.max_length = 12
	for state in ["normal", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1c1a30")
		style.border_color = Color("8b6594") if state == "focus" else Color("55405f")
		style.set_border_width_all(2)
		style.set_corner_radius_all(9)
		_edit.add_theme_stylebox_override(state, style)
	add_child(_edit)
	_edit.text_changed.connect(func(_text: String) -> void:
		if _is_integer(_edit.text): _wheel.value = clampi(_edit.text.to_int(), _minimum, _maximum)
		_validate())
	_edit.text_submitted.connect(func(_text: String) -> void: _apply())
	_hint = Label.new()
	_hint.position = Vector2(0, 210)
	_hint.size = Vector2(300, 30)
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color("a99bb4"))
	add_child(_hint)
	_toggle = _button("", Rect2(318, 208, 202, 34), _toggle_keyboard)
	_toggle.flat = true
	_cancel_button = _button(_tr("取消", "Cancel"), Rect2(0, 252, 248, 48), cancel_requested.emit)
	_apply_button = _button(_tr("确定", "Apply"), Rect2(272, 252, 248, 48), _apply)
	_reset()

func _tr(zh: String, en: String) -> String:
	return en if _language == "en" else zh

func _button(text: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("edc8ef"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("30243f") if state == "pressed" else Color("1c1a30")
		style.border_color = Color("805680") if state != "disabled" else Color("453b50")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	add_child(button)
	button.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - _last_touch_ms > 400: action.call())
	var touch := {"index": -1}
	button.gui_input.connect(func(event: InputEvent) -> void:
		if not event is InputEventScreenTouch: return
		_last_touch_ms = Time.get_ticks_msec()
		if event.pressed and not button.disabled: touch.index = event.index
		elif not event.pressed and touch.index == event.index:
			touch.index = -1
			if not event.canceled and not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(event.position): action.call()
		button.accept_event())
	return button

func _reset() -> void:
	_keyboard_mode = false
	_wheel.min_value = _minimum
	_wheel.max_value = _maximum
	_wheel.step = 1
	_wheel.value = _initial
	_edit.text = str(_initial)
	_edit.visible = false
	_wheel.visible = true
	_toggle.text = _tr("键盘输入", "Keyboard")
	_cancel_button.text = _tr("取消", "Cancel")
	_apply_button.text = _tr("确定", "Apply")
	_validate()

func _toggle_keyboard() -> void:
	if _keyboard_mode:
		if not _is_integer(_edit.text):
			_validate()
			return
		_wheel.value = clampi(_edit.text.to_int(), _minimum, _maximum)
		_edit.text = str(roundi(_wheel.value))
	else:
		_wheel._cancel()
		_edit.text = str(roundi(_wheel.value))
	_keyboard_mode = not _keyboard_mode
	_wheel.visible = not _keyboard_mode
	_edit.visible = _keyboard_mode
	_toggle.text = _tr("滚轮选择", "Reel") if _keyboard_mode else _tr("键盘输入", "Keyboard")
	if _keyboard_mode:
		_edit.grab_focus()
		_edit.select_all()
	else:
		_wheel.grab_focus()
	_validate()

func _is_integer(text: String) -> bool:
	return not text.is_empty() and text.is_valid_int()

func _validate() -> void:
	var valid := not _keyboard_mode or _is_integer(_edit.text)
	_apply_button.disabled = not valid
	_hint.text = "%d – %d" % [_minimum, _maximum] if valid else _tr("请输入整数", "Enter a whole number")

func _apply() -> void:
	if _keyboard_mode and not _is_integer(_edit.text):
		_validate()
		return
	var value := clampi(_edit.text.to_int(), _minimum, _maximum) if _keyboard_mode else roundi(_wheel.value)
	_wheel.value = value
	_edit.text = str(value)
	accepted.emit(value)
