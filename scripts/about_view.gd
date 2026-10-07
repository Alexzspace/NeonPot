extends Control
## A quiet, scrollable colophon. No settings or gameplay state is changed here.
signal closed()
var language := "zh"
var scroll: ScrollContainer
var body: VBoxContainer
var notices_button: Button
var notices: RichTextLabel

func words(zh: String, en: String) -> String:
	return zh if language == "zh" else en

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("11101e")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var back := Button.new()
	back.text = words("‹ 返回设置", "‹ SETTINGS")
	back.position = Vector2(28, 8)
	back.size = Vector2(260, 72)
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(func(): closed.emit())
	add_child(back)
	scroll = ScrollContainer.new()
	scroll.position = Vector2(156, 94)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	scroll.add_child(body)
	text(words("霓虹夜河", "NEON POT"), 56, Color("d4a0c9"), true)
	text(words("N E O N   P O T", "霓虹夜河"), 26, Color("9e91b5"), true)
	text("—  ♦  —", 28, Color("bd9e68"), true)
	text(words("午夜之后，霓虹倒映在湿润的街道上。\n城市仍未入眠，下一局已经开始。", "After midnight, neon lights spill across rain-soaked streets.\nThe city is still awake. Another hand is about to begin."), 28, Color("c7b4d7"), true)
	text(words("《霓虹夜河》是一款由 Alex Zhao 独立设计、开发与制作的像素风德州扑克游戏。本作融合经典牌桌体验、复古像素美术与霓虹都市夜景，专注于面对面牌局中的判断、博弈与交流。", "Neon Pot is a pixel-art Texas Hold’em game independently designed, developed and produced by Alex Zhao. It combines the tension of the poker table with retro pixel art and neon city nights, focusing on judgment, strategy and the social experience of playing face to face."), 28, Color("ddd6e0"))
	text(words("纯粹的德州扑克体验", "A pure Texas Hold’em experience"), 32, Color("d4a0c9"), true)
	text(words("没有行动倒计时，也没有实时胜率或手牌强弱提示。留给你的，是读懂牌局的判断、下注时的取舍，以及与同桌朋友彼此试探的乐趣。", "No action timers, live odds or hand-strength hints. Take your time to read the table, weigh each bet and enjoy the mind games with friends across the table."), 28, Color("ddd6e0"))
	text(words("这是一个由单人开发者长期维护的独立项目，\n源于对游戏设计、扑克文化与数字艺术的热爱。\n目前，本作以非商业形式开发与发布，不以营利为目的。", "A long-term solo independent project, created out of a passion for game design, poker culture and digital art. The game is currently developed and released on a non-commercial basis and is not intended for profit."), 28, Color("b6adbf"))
	text(words("愿你享受每一次下注后的沉默，\n以及河牌落下前，城市短暂屏息的瞬间。", "Enjoy the silence after every bet,\nand the moment when the city holds its breath before the river falls."), 28, Color("c7b4d7"), true)
	var line := HSeparator.new()
	body.add_child(line)
	text(words("独立设计与开发", "INDEPENDENT DESIGN & DEVELOPMENT"), 22, Color("9e91b5"), true)
	text("Alex Zhao", 38, Color("e5c4df"), true)
	text(words("单人独立开发 · 非商业项目", "SOLO INDIE DEVELOPMENT · NON-COMMERCIAL"), 24, Color("b6adbf"), true)
	text("VERSION  " + str(ProjectSettings.get_setting("application/config/version", "0.5.0")), 22, Color("9e91b5"), true)
	notices_button = Button.new()
	notices_button.text = words("许可证与鸣谢", "LICENSES AND CREDITS")
	notices_button.custom_minimum_size.y = 64
	notices_button.add_theme_font_size_override("font_size", 24)
	notices_button.pressed.connect(_toggle_notices)
	body.add_child(notices_button)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 42
	body.add_child(spacer)
	resized.connect(_layout)
	_layout()

func _toggle_notices() -> void:
	if not is_instance_valid(notices):
		notices = RichTextLabel.new()
		notices.custom_minimum_size.y = 340
		notices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		notices.selection_enabled = true
		notices.scroll_active = true
		notices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notices.add_theme_font_size_override("normal_font_size", 22)
		notices.text = FileAccess.get_file_as_string("res://licenses/NOTICE.txt")
		body.add_child(notices)
		body.move_child(notices, notices_button.get_index() + 1)
	else:
		notices.visible = not notices.visible
	notices_button.text = words("收起许可证与鸣谢", "HIDE LICENSES AND CREDITS") if notices.visible else words("许可证与鸣谢", "LICENSES AND CREDITS")
	if notices.visible:
		_reveal_notices()

func _reveal_notices() -> void:
	# Containers need a layout pass before the new reader has its final bounds.
	var tree := get_tree()
	await tree.process_frame
	if not is_inside_tree() or is_queued_for_deletion():
		return
	await tree.process_frame
	if is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(notices) and notices.visible:
		scroll.ensure_control_visible(notices)

func text(value: String, font_size: int, color: Color, center := false) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if center: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(label)

func set_available_height(height: float) -> void:
	size = Vector2(1440, maxf(660, height))
	_layout()

func _layout() -> void:
	if is_instance_valid(scroll): scroll.size = Vector2(maxf(1, size.x - 312), maxf(1, size.y - 110))
