extends Control
## Draft-only kaleidoscope editor. Main owns persistence and local activation.
signal closed()
signal recipe_applied(recipe: Dictionary)
const Themes = preload("res://scripts/card_themes.gd")
const Card = preload("res://scripts/card_view.gd")
const TouchSlider = preload("res://scripts/touch_slider.gd")
const DrawingCanvas = preload("res://scripts/kaleidoscope_canvas.gd")
const EDIT_KEYS := ["segments", "rotation", "depth", "line_width"]
var language := "zh":
	set(value):
		language = "en" if value == "en" else "zh"
		if is_instance_valid(apply_button): _labels()
var recipe: Dictionary = {}:
	set(value):
		recipe = Themes.sanitize_recipe(value)
		if is_instance_valid(apply_button): _sync()
var preview_cards: Array[Control] = []
var sliders: Array[Range] = []
var _slider_labels: Array[Label] = []
var color_buttons: Array[Button] = []
var palette_buttons: Array[Button] = []
var selected_color_role := 0
var _scroll: ScrollContainer
var controls_scroll: ScrollContainer
var apply_button: Button
var close_button: Button
var random_button: Button
var reset_button: Button
var palette_button: Button
var preset_button: Button
var undo_button: Button
var clear_button: Button
var freehand_button: Button
var mirror_button: CheckButton
var sector_buttons: Array[Button] = []
var motif_buttons: Array[Button] = []
var ink_buttons: Array[Button] = []
var drawing_canvas: Control
var _title: Label
var _hint: Label
var _draw_title: Label
var _preview_title: Label
var _seed_label: Label
var _depth_note: Label
var _color_labels: Array[Label] = []
var _canvas: Control
var _rng := RandomNumberGenerator.new()
var _available_height := 660.0
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_rng.randomize()
	if recipe.is_empty(): recipe = Themes.default_recipe()
	_canvas = Control.new()
	add_child(_canvas)
	_canvas.size = Vector2(1440, 660)
	_title = _label(Vector2(30, 17), Vector2(1100, 46), 32)
	_hint = _label(Vector2(32, 66), Vector2(1250, 32), 18)
	close_button = _button(Vector2(1268, 20), Vector2(142, 52), func(): drawing_canvas._finish(); closed.emit())
	_draw_title = _label(Vector2(32, 106), Vector2(400, 30), 20)
	drawing_canvas = DrawingCanvas.new()
	drawing_canvas.position = Vector2(32, 145)
	drawing_canvas.size = Vector2(400, 400)
	drawing_canvas.recipe = recipe
	_canvas.add_child(drawing_canvas)
	drawing_canvas.capacity_reached.connect(func(): _hint.text = "本笔或画布已满：抬手继续，或撤销 / 清空笔画" if language == "zh" else "Stroke or canvas limit reached: lift to continue, or Undo / Clear")
	drawing_canvas.strokes_changed.connect(func(strokes: Array): recipe.strokes = strokes; _preview())
	undo_button = _button(Vector2(32, 558), Vector2(93, 45), undo_stroke)
	clear_button = _button(Vector2(134, 558), Vector2(93, 45), clear_strokes)
	clear_button.add_theme_font_size_override("font_size", 16)
	for i in 2:
		ink_buttons.append(_button(Vector2(237 + i * 101, 558), Vector2(94, 45), func(): drawing_canvas._finish(); drawing_canvas.ink_index = i; _preview()))
	_preview_title = _label(Vector2(465, 106), Vector2(365, 30), 20)
	for i in 2:
		var card := Card.new()
		card.theme_id = 0
		card.custom_recipe = recipe
		card.set_card(51, i == 0)
		card.card_scale = 1.27
		card.position = Vector2(465 + i * 183, 167)
		card.size = Card.BASE * 1.27
		_canvas.add_child(card)
		preview_cards.append(card)
	_seed_label = _label(Vector2(465, 610), Vector2(360, 46), 14)
	random_button = _button(Vector2(465, 483), Vector2(176, 52), randomize_recipe)
	palette_button = _button(Vector2(651, 483), Vector2(165, 52), reveal_palette)
	reset_button = _button(Vector2(465, 550), Vector2(351, 52), func(): drawing_canvas._finish(); recipe = Themes.default_recipe())
	freehand_button = _button(Vector2(465, 421), Vector2(351, 48), use_freehand)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	controls_scroll = scroll
	scroll.position = Vector2(853, 108)
	scroll.size = Vector2(557, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_canvas.add_child(scroll)
	var controls := Control.new()
	controls.custom_minimum_size = Vector2(534, 990)
	scroll.add_child(controls)
	for i in 3:
		var button := _button(Vector2(i * 177, 0), Vector2(168, 44), func(): drawing_canvas._finish(); recipe.motif = i; recipe.motif_enabled = true; _preview())
		button.reparent(controls, false)
		motif_buttons.append(button)
	for i in 4:
		var label := _label(Vector2(0, 66 + i * 95), Vector2(520, 28), 20)
		label.reparent(controls, false)
		_slider_labels.append(label)
		var slider := TouchSlider.new()
		slider.position = Vector2(0, 100 + i * 95)
		slider.size = Vector2(526, 49)
		slider.min_value = [1, 0, 0, 1][i]
		slider.max_value = [12, 360, 100, 5][i]
		slider.step = 0.1 if i == 3 else 1
		controls.add_child(slider)
		sliders.append(slider)
		slider.user_changed.connect(_slider_changed.bind(i))
	for i in 4:
		var button := _button(Vector2(i * 88, 451), Vector2(80, 44), func(): drawing_canvas._finish(); recipe.segments = [2, 3, 6, 8][i]; _sync())
		button.reparent(controls, false)
		sector_buttons.append(button)
	mirror_button = CheckButton.new()
	mirror_button.position = Vector2(355, 451)
	mirror_button.size = Vector2(173, 44)
	mirror_button.add_theme_font_size_override("font_size", 18)
	controls.add_child(mirror_button)
	mirror_button.toggled.connect(func(on: bool): drawing_canvas._finish(); recipe.mirror = on; _preview())
	for i in 3:
		var button := _button(Vector2(i * 177, 520), Vector2(166, 48), func(): selected_color_role = i; reveal_palette(); _preview())
		button.reparent(controls, false)
		color_buttons.append(button)
	for i in Themes.PALETTE.size():
		var button := _button(Vector2((i % 4) * 132, 584 + (i / 4) * 84), Vector2(124, 72), func(): _color_changed(Color.html(Themes.PALETTE[i]), selected_color_role))
		button.reparent(controls, false)
		var style := StyleBoxFlat.new()
		style.bg_color = Color.html(Themes.PALETTE[i])
		style.border_color = Color("82788e")
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		palette_buttons.append(button)
	_depth_note = _label(Vector2(0, 934), Vector2(528, 42), 16)
	_depth_note.reparent(controls, false)
	preset_button = _button(Vector2(32, 607), Vector2(400, 48), func(): drawing_canvas._finish(); recipe_applied.emit({}))
	apply_button = _button(Vector2(853, 607), Vector2(557, 48), func(): drawing_canvas._finish(); recipe_applied.emit(Themes.sanitize_recipe(recipe)))
	_sync()
	_labels()
	set_available_height(_available_height)
func set_available_height(height: float) -> void:
	_available_height = maxf(660, height)
	size = Vector2(1440, _available_height)
	queue_redraw()
	if is_instance_valid(drawing_canvas): drawing_canvas._finish()
	if is_instance_valid(_canvas): _canvas.position.y = (_available_height - 660.0) * 0.5
func randomize_recipe() -> void:
	drawing_canvas._finish()
	var next := recipe.duplicate(true)
	next.version = Themes.RECIPE_VERSION
	next.motif_enabled = true
	next.seed = _rng.randi_range(0, 2147483647)
	next.motif = _rng.randi_range(0, 2)
	next.segments = [4, 6, 8, 10, 12][_rng.randi_range(0, 4)]
	next.rotation = _rng.randi_range(0, 359)
	next.paper = Themes.PALETTE[_rng.randi_range(0, 3)]
	next.primary = Themes.PALETTE[_rng.randi_range(6, 15)]
	next.accent = Themes.PALETTE[_rng.randi_range(10, 15)]
	recipe = next
func use_freehand() -> void:
	drawing_canvas._finish()
	recipe.segments = 1
	recipe.mirror = false
	recipe.rotation = 0.0
	recipe.depth = 0.0
	_sync()
func undo_stroke() -> void:
	drawing_canvas._finish()
	if not recipe.strokes.is_empty(): recipe.strokes.pop_back()
	_preview()
func clear_strokes() -> void:
	drawing_canvas._finish()
	recipe.strokes = []
	recipe.motif_enabled = false
	_preview()
func _slider_changed(value: float, index: int) -> void:
	drawing_canvas._finish()
	recipe[EDIT_KEYS[index]] = value / 100.0 if index == 2 else value
	_preview()
func _color_changed(color: Color, index: int) -> void:
	drawing_canvas._finish()
	recipe[["paper", "primary", "accent"][index]] = color.to_html(false)
	_preview()
func _sync() -> void:
	if recipe.is_empty(): recipe = Themes.default_recipe()
	for i in sliders.size(): sliders[i].set_value_no_signal(float(recipe[EDIT_KEYS[i]]) * (100 if i == 2 else 1))
	mirror_button.set_pressed_no_signal(recipe.mirror)
	_preview()
func _preview() -> void:
	for card in preview_cards: card.custom_recipe = recipe.duplicate(true)
	drawing_canvas.recipe = recipe
	_slider_text()
	_seed_label.text = ("统一牌背 · 角标保持清晰\n种子 " if language == "zh" else "Shared back · Protected corners\nSeed ") + str(recipe.seed)
	undo_button.disabled = recipe.strokes.is_empty()
	clear_button.disabled = recipe.strokes.is_empty() and not recipe.motif_enabled
	for i in motif_buttons.size(): motif_buttons[i].modulate = Color("f8d7a5") if recipe.motif_enabled and recipe.motif == i else Color("afa4bd")
	for i in ink_buttons.size():
		ink_buttons[i].modulate = Color.html(recipe.primary if i == 0 else recipe.accent)
		ink_buttons[i].text = ("• " if drawing_canvas.ink_index == i else "") + ((["主色", "辅色"] if language == "zh" else ["INK 1", "INK 2"])[i])
	for i in color_buttons.size(): color_buttons[i].modulate = Color("f8d7a5") if selected_color_role == i else Color("afa4bd")
	for i in palette_buttons.size():
		palette_buttons[i].text = "✓" if recipe[["paper", "primary", "accent"][selected_color_role]] == Themes.PALETTE[i] else ""
		palette_buttons[i].add_theme_color_override("font_color", Color.BLACK if Color.html(Themes.PALETTE[i]).get_luminance() > 0.4 else Color.WHITE)
	_draw_title.text = ("手绘 → 万花筒  ·  %d / 16 笔" if language == "zh" else "DRAW → KALEIDOSCOPE  ·  %d / 16") % recipe.strokes.size()
func reveal_palette() -> void:
	_scroll.scroll_vertical = 500
func _labels() -> void:
	var zh := language == "zh"
	_title.text = "牌面工坊 / 万花筒" if zh else "DECK WORKSHOP / KALEIDOSCOPE"
	_hint.text = "整块画布均可手绘 · 清空全部可从零开始 · 应用后保存" if zh else "Draw across the whole canvas · Clear All starts blank · Apply to save"
	close_button.text = "返回" if zh else "BACK"
	random_button.text = "换个构图" if zh else "NEW PATTERN"
	palette_button.text = "16 色配色" if zh else "16 COLORS"
	freehand_button.text = "直接手绘 · 不映射" if zh else "FREEHAND · NO MAPPING"
	reset_button.text = "载入默认图案" if zh else "LOAD DEFAULT PATTERN"
	preset_button.text = "使用预设牌面" if zh else "USE PRESET DECK"
	apply_button.text = "应用并保存整副牌" if zh else "APPLY & SAVE DECK"
	undo_button.text = "撤销" if zh else "UNDO"
	clear_button.text = "清空全部" if zh else "CLEAR ALL"
	clear_button.tooltip_text = "移除默认图案和所有笔迹，从纯底色开始" if zh else "Remove motif and all strokes; start with blank paper"
	ink_buttons[0].text = "主色笔" if zh else "INK 1"
	ink_buttons[1].text = "强调笔" if zh else "INK 2"
	_preview_title.text = "整副牌预览 / 正面与牌背" if zh else "DECK PREVIEW / FACE & BACK"
	mirror_button.text = "镜像" if zh else "MIRROR"
	for i in 4: sector_buttons[i].text = str([2, 3, 6, 8][i]) + ("向" if zh else "X")
	for i in 3:
		motif_buttons[i].text = (["花瓣", "晶格", "星轨"] if zh else ["PETALS", "LATTICE", "ORBITS"])[i]
		color_buttons[i].text = (["底色", "主线", "辅线"] if zh else ["PAPER", "MAIN INK", "ACCENT"])[i]
	_depth_note.text = "纵深是多层缩放的立体错觉；滑动右栏查看更多" if zh else "Layered depth is a 3D illusion. Scroll for colors."
	_preview()
func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("e3d4e5"))
	label.mouse_filter = MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label
func _button(at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	_canvas.add_child(button)
	return button
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("100e1c"))
func _slider_text() -> void:
	var names := ["旋转扇区", "映射角度", "层叠纵深 · 平面 → 立体", "画笔线宽"] if language == "zh" else ["ROTATIONAL SECTORS", "MAPPING ANGLE", "LAYER DEPTH · FLAT → 3D", "BRUSH WIDTH"]
	for i in _slider_labels.size():
		var value := float(recipe[EDIT_KEYS[i]]) * (100 if i == 2 else 1)
		_slider_labels[i].text = "%s  ·  %s%s" % [names[i], ("%.1f" % value) if i == 3 else str(int(value)), "°" if i == 1 else ""]
