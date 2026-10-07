extends Control
## Waiting room shared by LAN host and guests; table authority stays in TableSession.
var app: Control
var heading: Label
var detail: Label
var rows: Array = []
var start_button: Button
var add_button: Button
var leave_button: Button
var _signature := ""
var _state: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	app._panel(self, Rect2(28, 98, 1384, 442), Color("191a2b", 0.9), Color("715175"), 20)
	heading = app._label(self, "", Rect2(48, 106, 1310, 44), 36)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail = app._label(self, "", Rect2(48, 150, 1310, 30), 24, Color("b8acc5"))
	add_button = app._button(self, app.words("添加 AI", "ADD AI"), Rect2(28, 552, 340, 88), func(): app.session.add_bot(app.session.ai_aggression))
	leave_button = app._button(self, app.words("离开牌桌", "LEAVE TABLE"), Rect2(384, 552, 340, 88), app._confirm_leave)
	start_button = app._button(self, app.words("开始发牌", "DEAL HAND"), Rect2(748, 552, 664, 88), app._begin_hand, Color("684664"))

func update_state(state: Dictionary) -> void:
	_state = state
	var players: Array = state.get("players", [])
	var signature: String = app.language + str(app.session.is_host)
	for player in players: signature += str(player.get("name", "")) + str(player.get("is_bot", false))
	if signature != _signature:
		_signature = signature
		for row in rows:
			row.panel.hide()
			row.panel.queue_free()
		rows.clear()
		for seat in players.size(): _add_row(seat, players[seat])
	var host_name: String = str(state.get("room_name", players[0].get("name", "") if not players.is_empty() else ""))
	heading.text = app.words("%s的牌桌", "%s's table") % host_name
	var bots := 0
	for seat in players.size():
		var player: Dictionary = players[seat]
		if player.get("is_bot", false):
			bots += 1
			var slider: Range = rows[seat].slider
			if slider._finger == -1: slider.value = int(player.get("ai_aggression", 6))
			rows[seat].level.text = app.words("激进度 %d", "AGGRESSION %d") % int(player.get("ai_aggression", 6))
	var humans := players.size() - bots
	detail.text = app.words("%d 位朋友 · %d 位 AI · 每人 %d 筹码 · 同一 Wi-Fi 即可入座", "%d FRIENDS · %d AI · %d CHIPS EACH · JOIN ON THE SAME WI-FI") % [humans, bots, int(players[0].get("stack", 0)) if not players.is_empty() else 0]
	add_button.visible = app.session.is_host
	add_button.disabled = players.size() >= 6 or state.get("paused", false)
	start_button.disabled = not app.session.is_host or not state.get("can_start", false)
	start_button.text = app.words("开始发牌", "DEAL HAND") if app.session.is_host else app.words("等待房主发牌", "WAITING FOR THE HOST")
	layout_height(app.canvas.size.y)

func _add_row(seat: int, player: Dictionary) -> void:
	var panel: Control = app._panel(self, Rect2(48 + (seat % 2) * 684, 182 + (seat / 2) * 120, 656, 116), Color("242137"), Color("53445f"), 12)
	var title: Label = app._label(panel, str(player.get("name", "")) + ("" if player.get("is_bot", false) else app.words(" · 已入座", " · SEATED")), Rect2(14, 0, 300 if player.get("is_bot", false) else 620, 32), 26)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row := {"panel": panel}
	if player.get("is_bot", false):
		var slider = app.TouchSlider.new()
		slider.position = Vector2(14, 34)
		slider.size = Vector2(430, 80)
		slider.min_value = 0
		slider.max_value = 10
		slider.step = 1
		slider.notches = true
		slider.value = int(player.get("ai_aggression", 6))
		slider.editable = app.session.is_host
		panel.add_child(slider)
		slider.user_changed.connect(func(value: float):
			app.feedback.play("touch")
			app.session.set_bot_aggression(seat, int(value)))
		row.slider = slider
		row.level = app._label(panel, "", Rect2(302, 0, 142, 32), 21, Color("d9aad5"), true)
		var remove: Button = app._button(panel, app.words("移除", "REMOVE"), Rect2(464, 26, 180, 88), func(): app.session.remove_bot(seat))
		remove.visible = app.session.is_host
	else:
		app._label(panel, app.words("房主", "HOST") if seat == 0 else app.words("朋友已连接", "CONNECTED"), Rect2(16, 46, 615, 42), 26, Color("82d7d0"))
	rows.append(row)

func layout_height(height: float) -> void:
	size = Vector2(1440, height)
	var extra := maxf(0, height - 660)
	get_child(0).size.y = 442 + extra
	for seat in rows.size(): rows[seat].panel.position.y = 182 + (seat / 2) * 120 + extra * 0.5
	for button in [add_button, leave_button, start_button]:
		if is_instance_valid(button): button.position.y = height - 116
