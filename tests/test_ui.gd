extends SceneTree
## Instantiate the actual product scene and exercise privacy and table controls.

const Scene = preload("res://scenes/main.tscn")
const Card = preload("res://scripts/card_view.gd")
var checks := 0
var failures := 0
var app: Control

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _wait_presentation(reason: String) -> void:
	# State signals may start an async presentation in the same frame.
	await process_frame
	var deadline := Time.get_ticks_msec() + 15000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not app.presentation_busy and not app.input_locked, "Presentation completed: " + reason)
	await process_frame

func _all_nodes(node: Node) -> Array[Node]:
	var nodes: Array[Node] = [node]
	for child in node.get_children():
		nodes.append_array(_all_nodes(child))
	return nodes

func _visible_card_ids() -> Array[int]:
	var ids: Array[int] = []
	for node in _all_nodes(app):
		if node is Card and node.is_visible_in_tree() and node.face_up and node.card_id >= 0:
			ids.append(node.card_id)
	return ids

func _text_in(node: Node) -> String:
	var result := ""
	for child in _all_nodes(node):
		if child is Label or child is Button:
			result += child.text + "\n"
	return result

func _capture(name: String) -> void:
	if "--capture-ui" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "user://ui_%s.png" % name
	check(root.get_texture().get_image().save_png(path) == OK, "Save %s visual evidence" % name)
	print("UI_CAPTURE %s" % ProjectSettings.globalize_path(path))

func _run() -> void:
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app.feedback.volume = 0.0
	app.feedback.haptic_strength = 0.0
	app.language = "zh"
	app._build_ui()
	check(app.home.visible and not app.table.visible, "Product scene starts at home")
	app.player_count.value = 3
	app.stack_input.value = 1500
	app.session.start_local(["Player", "Two", "Three"], int(app.stack_input.value))
	check(app.session.state.phase == "lobby" and app.table.visible, "Internal fixture reaches table lobby")
	var equal_stacks := true
	for player in app.session.state.players:
		equal_stacks = equal_stacks and player.stack == 1500
	check(equal_stacks, "Configured starting chips are equal across seats")
	check(app.deal_button.visible and not app.deal_button.disabled, "Host can begin with three seated players")
	app._begin_hand()
	await _wait_presentation("deal")
	check(app.session.state.phase == "preflop", "Deal enters preflop")
	check(not app.own_cards[0].face_up and not app.own_cards[1].face_up, "Private cards start concealed")
	check(app.own_cards[0].interactive and not app.board_cards[0].interactive and app.board_cards[0].public_interactive, "Private peek stays separate from cosmetic public-card touch")
	var legal: Dictionary = app.shown_state.legal
	check(app.raise_button.disabled == not legal.get("raise", false), "Raise control follows legal action snapshot")
	var pot_before: int = app.shown_state.pot
	app._confirm_allin()
	check(is_instance_valid(app.modal) and app.shown_state.pot == pot_before, "Opening all-in confirmation commits no chips")
	app._close_modal()
	check(app.shown_state.pot == pot_before, "Cancelling all-in preserves stack and pot")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(55, 85)
	app.own_cards[0]._gui_input(press)
	check(app.own_cards[0]._peeking, "Own private card can be peeked")
	app._show_reference()
	check(not app.own_cards[0]._peeking, "Opening reference immediately closes an active peek")
	var reference_text := _text_in(app.modal)
	check("皇家同花顺" in reference_text and "高牌" in reference_text and "A2345" in reference_text, "Chinese reference contains full ranking range and wheel rule")
	await _capture("reference_zh")
	app._close_modal()
	app.amount_input.value = 137
	app.raise_button.pressed.emit()
	await _wait_presentation("first raise")
	check(app.shown_state.current_bet == 137 and app.shown_state.players[0].bet == 137, "Exact amount input submits the selected raise-to value")
	check(app.session.local_seat == 0 and app.raise_button.disabled, "Opponent turn preserves own viewpoint and disables betting")
	var next_actor: int = app.shown_state.actor
	app.session.set_local_seat(next_actor)
	check(app.session.local_seat == next_actor and not app.own_cards[0].face_up, "Handoff selects actor while leaving cards concealed")
	app.amount_input.value = 274
	app.raise_button.pressed.emit()
	await _wait_presentation("second raise")
	check(app.shown_state.players[next_actor].bet == 274, "Raise-to total includes already posted small blind")
	var paused: Dictionary = app.shown_state.duplicate(true)
	paused.paused = true
	app._on_state(paused)
	await _wait_presentation("pause")
	check(app.fold_button.disabled and app.call_button.disabled and app.raise_button.disabled and app.allin_button.disabled, "Disconnected table disables all betting controls")
	check(not app.own_cards[0].interactive, "Disconnected table disables private card interaction")
	app.language = "en"
	app._build_ui()
	app._show_reference()
	reference_text = _text_in(app.modal)
	check("ROYAL FLUSH" in reference_text and "HIGH CARD" in reference_text and "SUITS ARE EQUAL" in reference_text, "English reference contains ranking and tie rules")
	await _capture("reference_en")
	app._close_modal()
	app.language = "zh"
	app._status("Connection failed. Check LAN IP, Wi-Fi, and host firewall.")
	check(app.toast_label.text != "Connection failed. Check LAN IP, Wi-Fi, and host firewall.", "Critical connection failure is localized in Chinese")
	# Presentation fixture: all three players reach a legitimate public showdown.
	var showdown: Dictionary = app.shown_state.duplicate(true)
	showdown.phase = "showdown"
	showdown.paused = false
	showdown.actor = -1
	showdown.you = 0
	showdown.board = [0, 14, 28, 42, 4]
	showdown.legal = {}
	showdown.result = [{"seat": 1, "amount": 30}]
	showdown.players[0].cards = [12, 25]
	showdown.players[1].cards = [38, 51]
	showdown.players[2].cards = [9, 22]
	for player in showdown.players:
		player.folded = false
	app._on_state(showdown)
	await _wait_presentation("showdown awards")
	var displayed := _visible_card_ids()
	check(38 in displayed and 51 in displayed and 9 in displayed and 22 in displayed, "Showdown displays all non-folded opponents' public hole cards")
	await _capture("showdown")
	app._show_settings()
	await create_timer(0.4).timeout
	app._close_modal()
	await create_timer(0.4).timeout
	check(app.own_cards[0].face_up and app.own_cards[1].face_up, "Closing settings preserves public showdown cards")
	app._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.4).timeout
	app._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.4).timeout
	check(app.own_cards[0].face_up and app.own_cards[1].face_up, "Focus return preserves public showdown cards")
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout # Let the audio mixer release the streamed song.
	print("UI_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
