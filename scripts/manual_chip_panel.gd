extends Control
## Private reversible selection. Only confirmed emits an authoritative action.
signal confirmed(action: String, raise_to: int, counts: Dictionary)
signal cancelled
signal exchange_requested(pending_counts: Dictionary)
const Chips = preload("res://scripts/chip_display.gd")
const VALUES := [1, 5, 10, 50, 100, 500]
var inventory: Dictionary = {}
var pending: Dictionary = {}
var _taken_counts: Dictionary = {}
var config: Dictionary = {}
var _row: HBoxContainer
var _stage: Control
var _amount: Label
var _confirm: Button
var _actions: VBoxContainer
var _body: Control
var _backdrop: ColorRect
var _views: Dictionary = {}
var _stage_views: Dictionary = {}
var _tween: Tween
var _locked := false
var _closing := false
var _flights := 0
var _staged_counts: Dictionary = {}
var _flight_queues: Dictionary = {}
var _active_columns: Dictionary = {}
var _cancel_after_flights := false
var _exchange_tween: Tween
var _exchanging := false
var _last_touch_ms := -1000
var _touch_buttons: Array = []
var _touch_target: Button
var _touch_index := -1
var _stage_label: Label
var _origin := Vector2.ZERO
var _own_scroll: ScrollContainer
var _pending_scroll: Control
var _flight_tweens: Array[Tween] = []
var _flight_nodes: Array[Control] = []
var _generation := 0
var _motion_rect := Rect2()
var _body_top := 0.0
var _controls_top := 0.0
var _backdrop_left := 0.0
const BACKDROP_FEATHER := 48.0
var _touch_dragged := false
var _pending_touch_value := 0
var _touch_scroll: ScrollContainer
var _stage_chips: Control
const CHIP_PIXELS := Chips.CHIP_PIXELS

func configure(settings: Dictionary) -> void:
	config = settings.duplicate()
	inventory = settings.get("inventory", {}).duplicate(true)
	pending.clear()
	_staged_counts.clear()
	if is_node_ready(): _refresh()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = ColorRect.new()
	_backdrop.color = Color.WHITE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 surface_size = vec2(1.0);
uniform vec2 feather_width = vec2(48.0);
void fragment() {
	float surface_opacity = COLOR.a;
	vec2 local_pixel = UV * surface_size;
	float left_edge = feather_width.x > 0.0 ? smoothstep(0.0, feather_width.x, local_pixel.x) : 1.0;
	float top_edge = feather_width.y > 0.0 ? smoothstep(0.0, feather_width.y, local_pixel.y) : 1.0;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, 4.5).rgb;
	vec3 lavender_glass = mix(blurred, vec3(0.180, 0.155, 0.235), 0.58);
	COLOR = vec4(lavender_glass, left_edge * top_edge * surface_opacity);
}"""

	var material := ShaderMaterial.new()
	material.shader = shader
	_backdrop.material = material
	_body = Control.new()
	add_child(_body)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	_own_scroll = ScrollContainer.new()
	_own_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_own_scroll)
	_own_scroll.add_child(_row)
	_stage = Control.new()
	_pending_scroll = Control.new()
	_body.add_child(_pending_scroll)
	_pending_scroll.add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_chips = Chips.new()
	_stage_chips.display_mode = "pending"
	_stage_chips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_stage_chips)
	_stage.gui_input.connect(_pending_mouse_input)
	_stage_label = Label.new()
	_stage_label.visible = false
	_body.add_child(_stage_label)
	_amount = Label.new()
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount.add_theme_font_size_override("font_size", 23)
	_body.add_child(_amount)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_body.add_child(_actions)
	_confirm = _button("", _submit)
	_actions.add_child(_confirm)
	_actions.add_child(_button(_tr("取消", "Cancel"), cancel))
	var exchange := _button(_tr("换筹", "Exchange"), func() -> void:
		if not _locked and not _closing and _flights == 0: exchange_requested.emit(pending.duplicate(true)))
	exchange.custom_minimum_size.y = 38
	_actions.add_child(exchange)
	for value in VALUES:
		_make_column(value, _row, _views, false)
		var target := Button.new()
		target.flat = true
		target.size = Vector2(CHIP_PIXELS, CHIP_PIXELS * 1.4)
		_stage.add_child(target)
		target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var unused_label := Label.new()
		unused_label.visible = false
		target.add_child(unused_label)
		_stage_views[value] = {"box": target, "button": target, "chips": _stage_chips, "label": unused_label}
	_refresh()
	visible = false

func _tr(zh: String, en: String) -> String:
	return en if str(config.get("language", "zh")) == "en" else zh

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 60)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("e9d6ae"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("33283f") if state != "pressed" else Color("65506e")
		if state == "disabled": style.bg_color = Color("25212e")
		style.border_color = Color("9c7e9d") if state != "disabled" else Color("4e4358")
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		button.add_theme_stylebox_override(state, style)
	_bind_activation(button, callback)
	return button

func _bind_activation(button: Button, callback: Callable) -> void:
	_touch_buttons.append({"button": button, "callback": callback})
	var gesture := {"index": -1}
	button.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - _last_touch_ms > 400: callback.call())
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			_last_touch_ms = Time.get_ticks_msec()
			if event.pressed and not button.disabled:
				gesture.index = event.index
			elif not event.pressed and gesture.index == event.index:
				gesture.index = -1
				if not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(event.position): callback.call()
			button.accept_event())

func _input(event: InputEvent) -> void:
	if not visible or _closing: return
	if event is InputEventScreenDrag and event.index == _touch_index:
		if event.relative.length() > 2: _touch_dragged = true
		if is_instance_valid(_touch_scroll):
			_touch_scroll.scroll_horizontal -= int(event.relative.x)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventScreenTouch: return
	_last_touch_ms = Time.get_ticks_msec()
	var stage_local: Vector2 = _stage.get_global_transform_with_canvas().affine_inverse() * event.position
	if event.pressed and _touch_index < 0 and Rect2(Vector2.ZERO, _stage.size).has_point(stage_local):
		_pending_touch_value = _stage_chips.denomination_at(stage_local)
		if _pending_touch_value > 0:
			_touch_index = event.index
			_touch_target = null
			_touch_scroll = null
			_touch_dragged = false
			get_viewport().set_input_as_handled()
			return
	elif not event.pressed and event.index == _touch_index and _pending_touch_value > 0:
		if not _touch_dragged and _stage_chips.denomination_at(stage_local) == _pending_touch_value: deselect_chip(_pending_touch_value)
		_pending_touch_value = 0
		_touch_index = -1
		get_viewport().set_input_as_handled()
		return
	if event.pressed:
		if _touch_index >= 0: return
		for entry in _touch_buttons:
			var button: Button = entry.button
			var local: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
			if button.is_visible_in_tree() and not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(local) and _touch_visible(button, event.position):
				_touch_target = button
				_touch_index = event.index
				_touch_dragged = false
				_touch_scroll = null
				var ancestor := button.get_parent()
				while ancestor != self and ancestor != null:
					if ancestor is ScrollContainer: _touch_scroll = ancestor
					ancestor = ancestor.get_parent()
				get_viewport().set_input_as_handled()
				return
	elif event.index == _touch_index:
		for entry in _touch_buttons:
			var button: Button = entry.button
			if button != _touch_target: continue
			var local: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
			if not _touch_dragged and not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(local) and _touch_visible(button, event.position): entry.callback.call()
			break
		_touch_target = null
		_touch_index = -1
		get_viewport().set_input_as_handled()

func _touch_visible(button: Control, point: Vector2) -> bool:
	var node: Node = button.get_parent()
	while node != self and node != null:
		if node is ScrollContainer:
			var local: Vector2 = node.get_global_transform_with_canvas().affine_inverse() * point
			if not Rect2(Vector2.ZERO, node.size).has_point(local): return false
		node = node.get_parent()
	return true

func _make_column(value: int, parent: HBoxContainer, registry: Dictionary, staged: bool) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(box)
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(CHIP_PIXELS, 166)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(button)
	var chips := Chips.new()
	chips.display_mode = "manual"
	chips.resized.connect(func() -> void: _uniform_framing.call_deferred())
	chips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(chips)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	box.add_child(label)
	_bind_activation(button, func() -> void:
		if staged: deselect_chip(value)
		else: select_chip(value))
	registry[value] = {"box": box, "button": button, "chips": chips, "label": label}

func open(origin: Rect2, _pot: Vector2) -> void:
	_locked = false
	_closing = false
	visible = true
	var screen := size
	if screen.x <= 0 or screen.y <= 0:
		screen = get_parent().size if get_parent() is Control else get_viewport_rect().size
	var controls_top := float(config.get("controls_top", screen.y - 235))
	_controls_top = controls_top
	var top := maxf(controls_top, screen.y - 235)
	_backdrop_left = maxf(0, origin.position.x - 12)
	_body.position = Vector2(maxf(origin.position.x - 12, screen.x * 0.24), top)
	var destination := _body.position
	_body_top = destination.y
	_origin = origin.position
	_body.size = Vector2(screen.x - _body.position.x - 20, 235)
	var available := _body.size.x - 176
	var own_width := available * 0.72
	_own_scroll.position = Vector2(0, 0)
	_own_scroll.size = Vector2(own_width, 231)
	_pending_scroll.position = Vector2(own_width + 6, 0)
	_pending_scroll.size = Vector2(available - own_width - 6, 193)
	_row.size = Vector2(0, 224)
	_amount.position = Vector2(own_width + 6, 191)
	_amount.size = Vector2(available - own_width - 6, 36)
	_actions.position = Vector2(_body.size.x - 166, 12)
	_actions.size = Vector2(156, _body.size.y - 20)
	_motion_rect = Rect2(destination, Vector2(available, 228))
	_body.pivot_offset = Vector2(_body.size.x * 0.3, _body.size.y)
	_body.scale = Vector2(0.78, 0.78)
	modulate.a = 0.0
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.22)
	_tween.tween_property(_body, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_body.position = origin.position
	_tween.tween_property(_body, "position", destination, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var end := _actions.position
	_actions.position.y += 70
	_tween.tween_property(_actions, "position", end, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_refresh()

func selected_amount() -> int:
	var amount := 0
	for key in pending: amount += int(key) * int(pending[key])
	return amount

func select_chip(value: int) -> void:
	if _locked or _closing or _exchanging: return
	var key := str(value)
	if int(inventory.get(key, 0)) <= int(pending.get(key, 0)): return
	if int(config.get("street_bet", 0)) + selected_amount() + value > int(config.get("max_raise_to", 0)): return
	pending[key] = int(pending.get(key, 0)) + 1
	_contact("chip_throw")
	_fly(value, false)
	_refresh()

func deselect_chip(value: int) -> void:
	if _locked or _closing or _exchanging: return
	var key := str(value)
	if int(pending.get(key, 0)) <= 0: return
	pending[key] = int(pending[key]) - 1
	if int(pending[key]) == 0: pending.erase(key)
	_fly(value, true)
	_refresh()

func update_inventory(counts: Dictionary) -> void:
	if _closing: return
	_exchanging = true
	inventory = counts.duplicate(true)
	if _exchange_tween: _exchange_tween.kill()
	_row.pivot_offset = _row.size * 0.5
	_exchange_tween = create_tween()
	_exchange_tween.tween_property(_row, "scale", Vector2(0.9, 0.94), 0.12).set_trans(Tween.TRANS_CUBIC)
	_exchange_tween.tween_callback(func() -> void:
		_refresh()
		_contact("chip_collect"))
	_exchange_tween.tween_property(_row, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_exchange_tween.tween_callback(func() -> void:
		_exchanging = false
		_refresh())

func _refresh() -> void:
	if not is_node_ready(): return
	for value in VALUES:
		var key := str(value)
		var chosen := int(pending.get(key, 0))
		var count := maxi(0, int(inventory.get(key, 0)) - int(_taken_counts.get(value, 0)))
		var entry: Dictionary = _views[value]
		entry.chips.set_inventory({key: count}, false)
		entry.box.visible = count > 0
		entry.button.custom_minimum_size.x = maxf(CHIP_PIXELS, Chips.measure_inventory_size({key: count}, CHIP_PIXELS).x)
		entry.label.text = "%d\n×%d" % [value, count]
		entry.box.custom_minimum_size.x = entry.button.custom_minimum_size.x
		entry.button.disabled = int(inventory.get(key, 0)) <= chosen or _locked
		var staged: Dictionary = _stage_views[value]
		staged.box.visible = chosen > 0 or int(_staged_counts.get(value, 0)) > 0
		staged.button.disabled = chosen <= 0 or _locked
		staged.label.visible = false
	var staged_inventory := {}
	for value in _staged_counts:
		staged_inventory[str(value)] = _staged_counts[value]
	_layout_zones(staged_inventory)
	_stage_chips.set_inventory(staged_inventory, false)
	_layout_pending_targets.call_deferred()
	var selected := selected_amount()
	var total := selected + int(config.get("street_bet", 0))
	var all_in := total == int(config.get("max_raise_to", 0)) and selected > 0
	var legal := selected > 0 and ((total >= int(config.get("min_raise_to", 0)) and bool(config.get("can_raise", true))) or (all_in and bool(config.get("can_all_in", true))))
	_confirm.disabled = not legal or _locked or _closing or _exchanging or _flights > 0
	_confirm.text = _tr("确认 ALL IN", "Confirm ALL IN") if all_in else _tr("加注", "Raise")
	_amount.text = str(selected)
	_uniform_framing.call_deferred()

func _layout_zones(staged_inventory: Dictionary) -> void:
	if _body.size.x <= 176: return
	var available := _body.size.x - 176
	var own_needed := 0.0
	for value in VALUES:
		var count := maxi(0, int(inventory.get(str(value), 0)) - int(_taken_counts.get(value, 0)))
		if count > 0: own_needed += Chips.measure_inventory_size({str(value): count}, CHIP_PIXELS).x
	var future_stage := staged_inventory.duplicate()
	for value in pending:
		future_stage[str(value)] = maxi(int(future_stage.get(str(value), 0)), int(pending[value]))
	var visible_columns := 0
	for value in VALUES:
		visible_columns += ceili(float(clampi(int(future_stage.get(str(value), 0)), 0, 100)) / 10.0)
	# Keep the draft as a compact front/back pile instead of measuring a long row.
	var pitch := CHIP_PIXELS * Chips.COLUMN_SPACING / 1.14
	var preferred_across := maxi(1, ceili(sqrt(float(visible_columns))))
	var own_minimum := minf(own_needed, CHIP_PIXELS + 16.0)
	var stage_width := minf(maxf(CHIP_PIXELS * 1.7, preferred_across * pitch + 48.0), available - own_minimum - 8.0)
	var own_width := minf(own_needed, maxf(own_minimum, available - stage_width - 8))
	_own_scroll.size.x = own_width
	_pending_scroll.position.x = available - stage_width
	_pending_scroll.size.x = maxf(1, stage_width)
	var across := maxi(1, floori((_pending_scroll.size.x - 8.0) / pitch))
	var rows := ceili(float(visible_columns) / across)
	var required_height := maxf(193.0, 176.0 + maxf(0, rows - 1) * 52.0)
	_pending_scroll.position.y = 193.0 - required_height
	_pending_scroll.size.y = required_height
	_motion_rect.position.y = _body_top + _pending_scroll.position.y
	_motion_rect.size.y = 228.0 - _pending_scroll.position.y
	_update_backdrop()
	_amount.position.x = _pending_scroll.position.x
	_amount.size.x = _pending_scroll.size.x

func _update_backdrop() -> void:
	# Feather outside the old controls, so their text stays fully frosted.
	var covered_top := minf(_controls_top, _motion_rect.position.y)
	var covered_origin := Vector2(_backdrop_left, covered_top).max(Vector2.ZERO)
	_backdrop.position = (covered_origin - Vector2.ONE * BACKDROP_FEATHER).max(Vector2.ZERO)
	_backdrop.size = size - _backdrop.position
	var material := _backdrop.material as ShaderMaterial
	material.set_shader_parameter("surface_size", _backdrop.size)
	material.set_shader_parameter("feather_width", covered_origin - _backdrop.position)


func _pending_mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and Time.get_ticks_msec() - _last_touch_ms > 400:
		var value: int = _stage_chips.denomination_at(event.position)
		if value > 0: deselect_chip(value)
		_stage.accept_event()


func _layout_pending_targets() -> void:
	if not is_inside_tree(): return
	for value in VALUES:
		var target: Button = _stage_views[value].button
		var at: Vector2 = _stage_chips.denomination_position(value)
		if at.x >= 0:
			target.position = at - Vector2(CHIP_PIXELS * 0.5, CHIP_PIXELS * 0.32)
		else:
			target.position = (_pending_scroll.size - target.size) * 0.5


func _uniform_framing() -> void:
	if not is_inside_tree() or _views.is_empty(): return
	# Fixed diameter is shared by table, manual inventory, pending tray and flights.
	for registry in [_views, _stage_views]:
		for entry in registry.values():
			var display = entry.chips
			if display.has_method("set_fixed_chip_pixels"): display.set_fixed_chip_pixels(CHIP_PIXELS)

func _fly(value: int, returning: bool) -> void:
	if not _flight_queues.has(value): _flight_queues[value] = []
	_flight_queues[value].append(returning)
	_flights += 1
	_run_column(value)

func _run_column(value: int) -> void:
	if bool(_active_columns.get(value, false)) or _flight_queues[value].is_empty(): return
	_active_columns[value] = true
	var returning: bool = _flight_queues[value].pop_front()
	if returning: _staged_counts[value] = maxi(0, int(_staged_counts.get(value, 0)) - 1)
	var from: Control = _stage_views[value].button if returning else _views[value].button
	var target: Control = _views[value].button if returning else _stage_views[value].button
	var flight := Chips.new()
	flight.display_mode = "flight"
	flight.size = Vector2(CHIP_PIXELS + 12, CHIP_PIXELS + 12)
	add_child(flight)
	flight.set_inventory({str(value): 1}, false)
	flight.set_fixed_chip_pixels(CHIP_PIXELS)
	flight.toss(0.28)
	flight.position = get_global_transform().affine_inverse() * from.get_global_transform() * (from.size * 0.5) - flight.size * 0.5
	var end := get_global_transform().affine_inverse() * target.get_global_transform() * (target.size * 0.5) - flight.size * 0.5
	var source_view: Control = _stage_views[value].chips if returning else _views[value].chips
	var target_view: Control = _views[value].chips if returning else _stage_views[value].chips
	var source_top: Vector2 = source_view.denomination_position(value)
	var target_top: Vector2 = target_view.denomination_position(value)
	if source_top.x >= 0:
		flight.position = get_global_transform().affine_inverse() * source_view.get_global_transform() * source_top - flight.size * 0.5
	if target_top.x >= 0:
		end = get_global_transform().affine_inverse() * target_view.get_global_transform() * (target_top - Vector2(0, 3)) - flight.size * 0.5
	if not returning: _taken_counts[value] = int(_taken_counts.get(value, 0)) + 1
	var start := flight.position
	start = _clamp_flight(start, flight.size)
	end = _clamp_flight(end, flight.size)
	flight.position = start
	var tween := create_tween()
	_flight_tweens.append(tween)
	_flight_nodes.append(flight)
	var generation := _generation
	tween.tween_method(func(progress: float) -> void:
		if generation != _generation: return
		flight.position = _clamp_flight(start.lerp(end, progress) + Vector2(0, -sin(progress * PI) * 24), flight.size)
		flight.rotation = sin(progress * PI) * 0.2, 0.0, 1.0, 0.28)
	tween.tween_callback(func() -> void:
		if generation != _generation: return
		flight.queue_free()
		_flight_nodes.erase(flight)
		_flight_tweens.erase(tween)
		_flights -= 1
		if not returning: _staged_counts[value] = int(_staged_counts.get(value, 0)) + 1
		else: _taken_counts[value] = maxi(0, int(_taken_counts.get(value, 0)) - 1)
		_active_columns[value] = false
		_contact("chip_stack")
		_refresh()
		_run_column(value)
		if _flights == 0 and _cancel_after_flights: close())
	_refresh()

func _clamp_flight(point: Vector2, extent: Vector2) -> Vector2:
	return Vector2(clampf(point.x, _motion_rect.position.x, maxf(_motion_rect.position.x, _motion_rect.end.x - extent.x)), clampf(point.y, _motion_rect.position.y, maxf(_motion_rect.position.y, _motion_rect.end.y - extent.y)))

func _stop_flights() -> void:
	_generation += 1
	for tween in _flight_tweens:
		if tween and tween.is_valid(): tween.kill()
	_flight_tweens.clear()
	for flight in _flight_nodes:
		if is_instance_valid(flight): flight.queue_free()
	_flight_nodes.clear()
	_flight_queues.clear()
	_active_columns.clear()
	_flights = 0

func _contact(kind: String) -> void:
	var feedback = config.get("feedback")
	if is_instance_valid(feedback) and feedback.has_method("play_chip_contact"):
		feedback.play_chip_contact(kind)

func _submit() -> void:
	_refresh()
	if _confirm.disabled: return
	_locked = true
	var total := int(config.get("street_bet", 0)) + selected_amount()
	confirmed.emit("all_in" if total == int(config.get("max_raise_to", 0)) else "raise", total, pending.duplicate(true))

func cancel() -> void:
	if _locked or _closing: return
	_locked = true
	_cancel_after_flights = true
	_stop_flights()
	if _exchange_tween: _exchange_tween.kill()
	# Return the entire physical bundle together; duration never grows with chip count.
	var returning := pending.duplicate(true)
	_staged_counts.clear()
	pending.clear()
	_taken_counts.clear()
	_refresh()
	var batch := Chips.new()
	batch.display_mode = "pending"
	batch.size = _pending_scroll.size
	batch.size.x = minf(batch.size.x, _motion_rect.size.x)
	add_child(batch)
	batch.set_inventory(returning, false)
	batch.set_fixed_chip_pixels(CHIP_PIXELS)
	batch.position = _clamp_flight(get_staging_position() - batch.size * 0.5, batch.size)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(batch, "position", _clamp_flight(_body.position + Vector2(8, 24), batch.size), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(batch, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(func() -> void:
		batch.queue_free()
		_contact("chip_collect"))
	close()
	cancelled.emit()

func unlock_submission() -> void:
	if _closing or _cancel_after_flights: return
	_locked = false
	_refresh()

func get_staging_position() -> Vector2:
	return get_global_transform().affine_inverse() * _pending_scroll.get_global_transform() * (_pending_scroll.size * 0.5)

func close() -> void:
	if _closing: return
	_closing = true
	_stop_flights()
	if _locked and not _cancel_after_flights:
		_staged_counts.clear()
		_stage.visible = false
		_stage_label.visible = false
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.28)
	_tween.tween_property(_body, "scale", Vector2(0.85, 0.85), 0.28)
	_tween.tween_property(_body, "position", _origin, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and visible and is_node_ready():
		cancel()
