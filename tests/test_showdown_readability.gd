extends SceneTree
const Main = preload("res://scripts/main.gd")
const Card = preload("res://scripts/card_view.gd")
const Themes = preload("res://scripts/card_themes.gd")
const Winning = preload("res://scripts/winning_hand.gd")
var app: Control
var checks := 0
var failures := 0
class Probe extends Main:
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.level = 0
		music.paused = true
	func _save_settings() -> void: pass
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func touch(point: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = root.get_final_transform() * point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://readability_%s.png" % label) == OK, "capture " + label)
func _run() -> void:
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	var players: Array = []
	for i in 6: players.append({"name": "玩家 Player %d" % i, "cards": [i * 2, i * 2 + 1], "folded": i == 5})
	var state := {"phase": "showdown", "players": players, "board": [12, 25, 38, 51, 8], "pot": 6000000, "result": [{"seat": 0, "amount": 6000000}]}
	app.session.is_host = true
	for profile in ["iphone", "android", "kpad", "sqrt2"]:
		app._set_preview_profile(profile)
		await process_frame
		for lang in ["zh", "en"]:
			app.language = lang
			app._show_showdown(state)
			await process_frame
			var board: Control = app.modal.find_child("ShowdownBoard", true, false)
			var box: Control = board.get_parent()
			check(board.cards == state.board and board.get_child_count() == 5, "exactly five original public cards, no preview nodes")
			check(board.mouse_filter == Control.MOUSE_FILTER_IGNORE, "public row is passive")
			var player_cards := 0
			var scroll: ScrollContainer = app.modal.find_child("SettlementScroll", true, false)
			var content := scroll.get_child(0)
			for node in content.find_children("*", "Control", true, false):
				if node is Card:
					player_cards += 1
					check(node.size == Vector2(108, 151) and not node.interactive, "player cards enlarged without input")
					check(node.size == board.get_child(0).size and is_equal_approx(node.card_scale, board.get_child(0).card_scale), "public and player cards have identical rendered dimensions")
					check(node.position.y + node.size.y <= content.size.y, "player cards fit scrollable settlement content")
			check(board.get_global_rect().end.y <= scroll.get_global_rect().position.y, "large public cards stay above player scroll viewport")
			check(scroll.position.y + scroll.size.y <= box.size.y - 96, "scroll viewport clears fixed next-hand footer")
			check(content.find_child("WinningHand0", true, false) == null, "no duplicate winning-hand ribbon")
			_audit_highlights(state, board, content)
			check(player_cards == 12, "all player cards are rendered")
			await _capture(profile + "_" + lang + "_rest")
			var original_transforms: Array[Transform2D] = []
			for card in board.get_children():
				check(card is Card and not card.interactive, "community cards have no press-to-zoom interaction")
				original_transforms.append(card.get_transform())
			var original_nodes: int = app.modal.find_children("*", "", true, false).size()
			var first_card: Control = board.get_child(0)
			var last_card: Control = board.get_child(4)
			var point: Vector2 = first_card.get_global_rect().get_center()
			touch(point, true)
			await process_frame
			check(app.modal.find_children("*", "", true, false).size() == original_nodes, "press creates no enlargement overlay")
			var drag := InputEventScreenDrag.new()
			drag.index = 0
			drag.position = root.get_final_transform() * last_card.get_global_rect().get_center()
			drag.relative = drag.position - root.get_final_transform() * point
			Input.parse_input_event(drag)
			Input.flush_buffered_events()
			touch(last_card.get_global_rect().get_center(), false)
			await process_frame
			check(board.get_child_count() == 5 and app.modal.find_children("*", "", true, false).size() == original_nodes, "drag and release create no alternate card presentation")
			for index in 5:
				check(board.get_child(index).card_id == state.board[index] and board.get_child(index).get_transform() == original_transforms[index], "touch preserves each original public card identity and geometry")
			await _capture(profile + "_" + lang + "_touch")
			if content.size.y > scroll.size.y:
				var scroll_start: Vector2 = scroll.get_global_rect().position + scroll.get_global_rect().size * Vector2(0.8, 0.85)
				touch(scroll_start, true)
				for step in 8:
					var swipe := InputEventScreenDrag.new()
					swipe.index = 0
					swipe.relative = Vector2(0, -24) * app.canvas.scale
					swipe.position = root.get_final_transform() * (scroll_start + Vector2(0, -24 * (step + 1)) * app.canvas.scale)
					Input.parse_input_event(swipe)
					Input.flush_buffered_events()
					await process_frame
				touch(scroll_start + Vector2(0, -192) * app.canvas.scale, false)
				check(scroll.scroll_vertical > 0, "native swipe reveals lower player row")
				scroll.scroll_vertical = int(content.size.y)
				await process_frame
				var final_card: Control = content.find_child("ShowdownHole5_1", true, false)
				check(scroll.get_global_rect().encloses(final_card.get_global_rect()), "last player's full-size cards remain reachable above fixed footer")
				await _capture(profile + "_" + lang + "_bottom")
			app._close_modal()
			await process_frame
	# Board-only split, distinct side-pot winners, and uncontested hidden cards.
	var extra_states := [
		{"phase": "showdown", "board": [8, 9, 10, 11, 12], "pot": 400, "players": [
			{"name": "Tie A", "cards": [13, 14], "folded": false}, {"name": "Tie B", "cards": [26, 27], "folded": false}],
			"result": [{"seat": 0, "amount": 200}, {"seat": 1, "amount": 200}]},
		{"phase": "showdown", "board": [0, 14, 28, 42, 11], "pot": 600, "players": [
			{"name": "Main", "cards": [12, 24], "folded": false}, {"name": "Side", "cards": [10, 23], "folded": false},
			{"name": "Lost", "cards": [7, 20], "folded": false}], "result": [{"seat": 0, "amount": 300}, {"seat": 1, "amount": 300}]},
		{"phase": "showdown", "board": [0, 14, 28, 42, 11], "pot": 100, "players": [
			{"name": "Uncontested", "cards": [12, 24], "folded": false}, {"name": "Hidden", "cards": [-1, -1], "folded": true}],
			"result": [{"seat": 0, "amount": 100}]}]
	for index in extra_states.size():
		app._show_showdown(extra_states[index])
		await process_frame
		var extra_board: Control = app.modal.find_child("ShowdownBoard", true, false)
		var extra_scroll: ScrollContainer = app.modal.find_child("SettlementScroll", true, false)
		_audit_highlights(extra_states[index], extra_board, extra_scroll.get_child(0))
		await _capture("original_winners_%d" % index)
		app._close_modal()
		await process_frame
	var original_theme := Themes.active_id
	for theme in Themes.COUNT:
		Themes.active_id = theme
		app._show_showdown(extra_states[1])
		await process_frame
		var theme_board: Control = app.modal.find_child("ShowdownBoard", true, false)
		var theme_scroll: ScrollContainer = app.modal.find_child("SettlementScroll", true, false)
		_audit_highlights(extra_states[1], theme_board, theme_scroll.get_child(0))
		await _capture("theme_%d_winning_frames" % theme)
		app._close_modal()
		await process_frame
	Themes.active_id = original_theme
	for host in [true, false]:
		app.session.is_host = host
		app._set_preview_profile("kpad")
		await process_frame
		app._show_showdown(state)
		await process_frame
		var same_modal: Control = app.modal
		for profile in ["iphone", "kpad"]:
			app._set_preview_profile(profile)
			await process_frame
			var resized_board: Control = app.modal.find_child("ShowdownBoard", true, false)
			var resized_scroll: ScrollContainer = app.modal.find_child("SettlementScroll", true, false)
			var footer: Control = app.modal.find_child("SettlementFooter", true, false)
			check(app.modal == same_modal, "live aspect resize preserves open settlement")
			check(app.canvas.get_global_rect().encloses(footer.get_global_rect()), "resized host or guest footer stays inside safe canvas")
			check(resized_scroll.get_global_rect().end.y <= footer.get_global_rect().position.y, "resized player scroll clears persistent footer")
			check(resized_board.get_global_rect().end.y <= resized_scroll.get_global_rect().position.y, "resized large community cards clear player list")
			check((footer is Button) == host, "only host receives next-hand action")
			_audit_highlights(state, resized_board, resized_scroll.get_child(0))
			await _capture("live_resize_%s_%s" % ["host" if host else "guest", profile])
		app._close_modal()
		await process_frame
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SHOWDOWN_READABILITY_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _audit_highlights(state: Dictionary, board: Control, content: Control) -> void:
	var expected_board: Array = []
	var expected_holes: Dictionary = {}
	var texts: Array[String] = []
	for node in content.find_children("*", "Label", true, false): texts.append(node.text)
	var all_text := "\n".join(texts)
	for winner in Winning.winners(state, app.language):
		check(all_text.contains(winner.category), "winning category shown in original player content")
		check(all_text.contains("+" + str(winner.amount)), "winner award shown without duplicated card row")
		var result_label: Label = content.find_child("ShowdownResult%d" % winner.seat, true, false)
		check(result_label != null and result_label.text.contains(winner.category), "category belongs to correct original winner panel")
		var accent := result_label.get_theme_color("font_color")
		var connected := 0
		for index in state.board.size():
			var public_card: Control = board.get_child(index)
			if public_card.winning_colors.has(accent): connected += 1
		for index in 2:
			var hole: Control = content.find_child("ShowdownHole%d_%d" % [winner.seat, index], true, false)
			if hole.winning_colors.has(accent): connected += 1
		check(connected == winner.cards.size(), "winner color connects exactly their five original cards, zero for uncontested")
		expected_holes[winner.seat] = winner.cards
		for card_id in winner.cards:
			if state.board.has(card_id) and not expected_board.has(card_id): expected_board.append(card_id)
	var original_cards: Array = []
	for node in content.find_children("*", "Control", true, false):
		if node is Card: original_cards.append(node)
	check(original_cards.size() == state.players.size() * 2, "only original hole cards rendered, no duplicated best-five cards")
	for seat in state.players.size():
		for index in 2:
			var card: Control = original_cards[seat * 2 + index]
			var expected: bool = expected_holes.get(seat, []).has(card.card_id)
			check(not card.winning_colors.is_empty() == expected, "only winning five's original hole cards highlighted")
			if state.players[seat].folded:
				check(not card.face_up and card.winning_colors.is_empty(), "folded cards stay hidden without winning frames")
	for index in state.board.size():
		var card: Control = board.get_child(index)
		check(not card.winning_colors.is_empty() == expected_board.has(card.card_id), "original public board highlights exactly union of winning fives")
		check(card.size == Vector2(108, 151), "highlighting preserves full-size public card geometry")
