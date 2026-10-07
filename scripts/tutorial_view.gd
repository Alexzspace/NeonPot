class_name PokerTutorial
extends Control
## Static beginner reference. The owner handles closed; this view never touches a table or music.
signal closed

const PAGE_COUNT := 5
const PAPER := Color("f4e9e1")
const MUTED := Color("a3a5bd")
const ACCENT := Color("d9aad5")
const PAGES := [
	{
		"zh": ["先认识这手牌", "用两张底牌与五张公共牌，选出最好的五张。", [
			["2 张底牌", "每人各有两张，只有自己能看。游戏中按住看牌，松手盖住。"],
			["5 张公共牌", "牌桌中央的牌由所有仍在这手牌中的玩家共同使用。"],
			["只比最好的 5 张", "可用零张、一张或两张底牌；也可以直接使用五张公共牌。"],
			["先看牌型表", "返回牌型表可查从高牌到皇家同花顺的大小顺序。"]]],
		"en": ["MEET YOUR HAND", "Choose your best five cards from two hole cards and five community cards.", [
			["2 HOLE CARDS", "Two private cards for each player. Hold to peek; release to hide."],
			["5 COMMUNITY CARDS", "Cards in the middle are shared by everyone still in the hand."],
			["BEST FIVE ONLY", "Use zero, one or two hole cards. Playing all five board cards is allowed."],
			["HAND RANKINGS", "Return to the hand chart for the order from high card to royal flush."]]]
	},
	{
		"zh": ["一手牌怎样进行", "发牌后最多进行四轮下注；公共牌按 3 + 1 + 1 张翻开。", [
			["翻牌前 PREFLOP", "先下大小盲注，再发两张底牌，进行第一轮下注。"],
			["翻牌 FLOP", "翻开三张公共牌，再进行一轮下注。"],
			["转牌 TURN", "再翻一张公共牌，然后下注。此时共有四张公共牌。"],
			["河牌 RIVER", "翻开最后一张公共牌，完成最后一轮下注后比牌。"]]],
		"en": ["HOW A HAND UNFOLDS", "Up to four betting rounds. Community cards appear as 3 + 1 + 1.", [
			["PREFLOP", "Post the blinds, receive two hole cards, then begin the first betting round."],
			["FLOP", "Reveal three community cards, then have another betting round."],
			["TURN", "Reveal one more community card and bet. There are now four on the board."],
			["RIVER", "Reveal the fifth community card. The last betting round leads to showdown."]]]
	},
	{
		"zh": ["庄位、盲注与行动顺序", "D 是庄位标记；SB 是小盲，BB 是大盲。", [
			["每手轮换", "庄位每手移到下一位仍有筹码的玩家。盲注先投入底池。"],
			["三人及以上", "庄位左侧依次是小盲、大盲。翻牌前从大盲左侧开始行动。"],
			["翻牌之后", "从庄位左侧第一位仍能下注的玩家开始，依座位顺序行动。"],
			["只剩两人时", "庄位同时是小盲，另一位是大盲。庄位翻牌前先行动，翻牌后后行动。"]]],
		"en": ["BUTTON, BLINDS & TURNS", "D marks the dealer button. SB is the small blind; BB is the big blind.", [
			["EACH NEW HAND", "Move D to the next player with chips. Blinds go into the pot before the deal."],
			["THREE OR MORE", "Left of D sit SB, then BB. Preflop action starts to the left of BB."],
			["AFTER THE FLOP", "Start left of D with the first player who can still bet; continue in seat order."],
			["HEADS-UP: TWO", "D is also SB: first to act preflop, last after the flop. The other player is BB."]]]
	},
	{
		"zh": ["轮到你时可以做什么", "界面只开放当前合法的操作；选好加注金额后，再点加注。", [
			["过牌 CHECK", "没有需要跟的下注时，不加筹码，把行动交给下一位。"],
			["跟注 CALL", "补上差额，跟到当前下注金额。"],
			["加注至 RAISE TO", "填写本轮累计下注总额，包含本轮已经投入的筹码。"],
			["弃牌 FOLD", "退出这一手；已投入底池的筹码不会退回。"],
			["全下 ALL-IN", "投入全部剩余筹码。之后不再下注，但仍可参与比牌。"]]],
		"en": ["YOUR ACTIONS", "Only legal actions are enabled. Choose an amount, then press Raise.", [
			["CHECK", "When you owe no chips, pass the action without adding a bet."],
			["CALL", "Match the current bet by adding only the chips you still owe."],
			["RAISE TO", "Set your TOTAL bet for this round, including chips already in."],
			["FOLD", "Leave this hand. Chips you already put in the pot stay there."],
			["ALL-IN", "Bet all your remaining chips. You stop betting but stay in the hand."]]]
	},
	{
		"zh": ["谁赢得底池", "底池就是这一手大家已经投入的筹码。", [
			["其他人全弃牌", "最后一位没弃牌的玩家直接获胜，不必等公共牌全部翻完。"],
			["多人留下比牌", "最后一轮下注结束，比较每人最好的五张牌，较大者获胜。"],
			["一样大就平分", "五张牌的牌力完全相同就平分对应底池；花色不分大小。"],
			["全下与边池", "全下者只能赢有自己出资的底池。其他人多投的部分另成边池，分别结算。"]]],
		"en": ["WHO WINS THE POT?", "The pot holds all chips contributed during this hand.", [
			["EVERYONE ELSE FOLDS", "The last player still in wins, even before all community cards are revealed."],
			["SHOWDOWN", "After the last betting round, compare each remaining player's best five cards."],
			["TIED HANDS", "Equal five-card hands split the relevant pot. Suits never break a tie."],
			["ALL-IN & SIDE POTS", "An all-in player can win only pots they paid into. Extra bets form side pots."]]]
	}
]

var language := "zh":
	set(value):
		language = "en" if value == "en" else "zh"
		if is_node_ready(): _render_page()
var page_index := 0
var title_label: Label
var intro_label: Label
var page_label: Label
var previous_button: Button
var next_button: Button
var close_button: Button
var content: Control
var detail_labels: Array[Label] = []
var row_titles: Array[Label] = []

func _ready() -> void:
	size = Vector2(1440, 660)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("181829")
	backdrop.size = size
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var background := Panel.new()
	background.position = Vector2(16, 12)
	background.size = Vector2(1408, 636)
	background.add_theme_stylebox_override("panel", _style(Color("181829"), Color("725474")))
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	title_label = _label(Rect2(44, 38, 1172, 64), 40, PAPER)
	intro_label = _label(Rect2(44, 114, 1352, 56), 27, ACCENT)
	close_button = _button(Rect2(1256, 28, 132, 88), func(): closed.emit())
	content = Control.new()
	content.position = Vector2(44, 184)
	content.size = Vector2(1352, 332)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	previous_button = _button(Rect2(44, 548, 388, 88), previous_page)
	next_button = _button(Rect2(1008, 548, 388, 88), next_page)
	page_label = _label(Rect2(456, 548, 528, 88), 27, MUTED)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_render_page()

func set_available_height(height: float) -> void:
	var extra := maxf(0.0, height - 660.0)
	size = Vector2(1440, maxf(660, height))
	for child in get_children():
		if not child is Control: continue
		if not child.has_meta("tutorial_base"):
			child.set_meta("tutorial_base", Rect2(child.position, child.size))
		var base: Rect2 = child.get_meta("tutorial_base")
		child.position = base.position
		child.size = base.size
		if child is Panel or child is ColorRect: child.size.y += extra
		elif child == content: child.size.y += extra
		elif base.position.y >= 548: child.position.y += extra
	_render_page()

func show_page(value: int) -> void:
	page_index = clampi(value, 0, PAGE_COUNT - 1)
	if is_node_ready(): _render_page()

func previous_page() -> void:
	show_page(page_index - 1)

func next_page() -> void:
	if page_index == PAGE_COUNT - 1:
		closed.emit()
	else:
		show_page(page_index + 1)

func _render_page() -> void:
	var page: Array = PAGES[page_index][language]
	title_label.text = page[0]
	intro_label.text = page[1]
	close_button.text = "返回" if language == "zh" else "BACK"
	previous_button.text = "上一页" if language == "zh" else "PREVIOUS"
	previous_button.disabled = page_index == 0
	next_button.text = ("返回牌型表" if language == "zh" else "BACK TO HANDS") if page_index == PAGE_COUNT - 1 else ("下一页" if language == "zh" else "NEXT")
	page_label.text = ("新手入门  %d / %d" if language == "zh" else "GETTING STARTED  %d / %d") % [page_index + 1, PAGE_COUNT]
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	detail_labels.clear()
	row_titles.clear()
	var rows: Array = page[2]
	var row_height := content.size.y / rows.size()
	for index in rows.size():
		var at := float(index) * row_height
		var stripe := ColorRect.new()
		stripe.color = Color("262238") if index % 2 == 0 else Color("1e1e31")
		stripe.position = Vector2(0, at)
		stripe.size = Vector2(content.size.x, row_height - 6)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(stripe)
		var heading := _label(Rect2(18, at + 4, 304, row_height - 14), 26, ACCENT, content)
		heading.text = rows[index][0]
		row_titles.append(heading)
		var detail := _label(Rect2(338, at + 4, 994, row_height - 14), 26, PAPER, content)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = rows[index][1]
		detail_labels.append(detail)

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(2)
	result.set_corner_radius_all(8)
	return result

func _button(rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := Color("49364e") if state != "disabled" else Color("232235")
		if state == "hover": fill = fill.lightened(0.12)
		if state == "pressed": fill = fill.darkened(0.16)
		button.add_theme_stylebox_override(state, _style(fill, Color("725474")))
	button.add_theme_color_override("font_color", PAPER)
	button.pressed.connect(action)
	add_child(button)
	return button

func _label(rect: Rect2, font_size: int, color: Color, parent: Control = self) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
