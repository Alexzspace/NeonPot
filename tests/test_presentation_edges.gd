extends SceneTree
## Presentation-only fixtures: no engine or production shuffle is modified.
const Scene = preload("res://scenes/main.tscn")
var app: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PRESENTATION_EDGE: " + message)

func _fixture(hand: int, revision: int, committed: Array, stacks: Array) -> Dictionary:
	var players: Array = []
	var pot := 0
	for seat in 3:
		pot += int(committed[seat])
		players.append({"name": ["Alice", "Bob", "Carol"][seat], "stack": stacks[seat], "bet": committed[seat], "committed": committed[seat], "folded": false, "all_in": false, "cards": [12, 25] if seat == 0 else [-1, -1], "connected": true})
	return {"phase": "flop", "hand_id": hand, "revision": revision, "dealer": 0, "actor": 0, "board": [0, 14, 28], "pot": pot, "current_bet": 100, "min_raise_to": 200, "players": players, "you": 0, "legal": {"check": true}, "result": [], "paused": false, "can_start": false}

func _baseline(state: Dictionary) -> void:
	# Let the real new-hand path reset all private presentation bookkeeping.
	app._on_state(state.duplicate(true))
	app._cancel_presentation()
	app._build_ui()
	app.presentation_events.clear()

func _settle(before: Dictionary, results: Array, stacks: Array) -> Dictionary:
	var after := before.duplicate(true)
	after.phase = "showdown"
	after.revision += 1
	after.actor = -1
	after.legal = {}
	after.result = results
	after.can_start = true
	for seat in after.players.size():
		after.players[seat].stack = stacks[seat]
	return after

func _events(kind: String) -> Array:
	return app.presentation_events.filter(func(item): return item.kind == kind)

func _until_event(kind: String, count: int, timeout: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while _events(kind).size() < count and Time.get_ticks_msec() < deadline:
		await create_timer(0.025).timeout
	return _events(kind).size() >= count

func _until_idle() -> void:
	var deadline := Time.get_ticks_msec() + 7000
	while app.presentation_busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.025).timeout
	check(not app.presentation_busy, "presentation queue settles within its animation budget")

func _run() -> void:
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app.feedback.volume = 0
	app.feedback.haptic_strength = 0
	var before := _fixture(41, 100, [100, 100, 100], [900, 900, 900])
	_baseline(before)
	var after := _settle(before, [{"seat": 0, "amount": 150}, {"seat": 0, "amount": 50}, {"seat": 1, "amount": 100}], [1100, 1000, 900])
	app._on_state(after)
	check(app._displayed_pot == 300 and app.pot_display._amount == 300, "pot persists before any award")
	check(app.chip_display._amount == 900, "own bankroll must not receive winnings before award arrives")
	check("900" in app.balance_label.text, "numeric bankroll stays synchronized with unawarded chips")
	app._on_state(after.duplicate(true))
	check(await _until_event("award", 1), "first split award arrives")
	check(app._displayed_pot == 100, "first winner receives aggregated 200 leaving 100 in pot")
	check(app.chip_display._amount == 1100, "own bankroll updates when own award arrives")
	check(not is_instance_valid(app.modal), "showdown waits for all payouts and organizing")
	await _until_idle()
	check(_events("collect").size() == 1 and _events("award").size() == 2, "duplicate snapshot cannot replay split settlement")
	check(_events("organized").size() == 2, "both winners organize before completion")
	check(app._displayed_pot == 0 and app.pot_display._amount == 0, "all awards fully empty pot")
	check(is_instance_valid(app.modal), "showdown appears after organizing")
	app._close_modal()
	app._on_state(after.duplicate(true))
	check(not app.presentation_busy and _events("collect").size() == 1, "post-settlement duplicate remains idempotent")

	# Uncalled excess is returned separately from the contested 20-chip award.
	before = _fixture(42, 200, [100, 10, 0], [900, 990, 1000])
	_baseline(before)
	after = _settle(before, [{"seat": 0, "amount": 20}], [1010, 990, 1000])
	after.players[0].committed = 10
	after.players[0].bet = 10
	after.pot = 20
	app._on_state(after)
	check(app._displayed_pot == 110, "uncalled refund starts from full visible pot")
	check(app.chip_display._amount == 900, "uncalled refund is not credited before its flight arrives")
	check(await _until_event("refund", 1), "uncalled refund animates")
	check(_events("refund")[0].amount == 90 and app._displayed_pot == 20, "90-chip refund preserves 20 contested chips")
	check(app.chip_display._amount == 990, "refund arrives before separate winnings")
	await _until_idle()
	check(_events("award").size() == 1 and _events("award")[0].amount == 20, "only contested pot is paid as award")
	check(app.chip_display._amount == 1010 and app._displayed_pot == 0, "refund plus award reconciles bankroll")
	app._close_modal()

	# Rebuilding for language/preview changes must not erase pending real chips.
	before = _fixture(43, 300, [100, 100, 100], [900, 900, 900])
	_baseline(before)
	after = _settle(before, [{"seat": 0, "amount": 200}, {"seat": 1, "amount": 100}], [1100, 1000, 900])
	app._on_state(after)
	await create_timer(0.1).timeout
	app._build_ui()
	check(app._displayed_pot == 300 and app.pot_display._amount == 300, "UI rebuild retains unawarded pot")
	check(app.presentation_busy, "UI rebuild resumes pending settlement")
	await _until_idle()
	var delivered := 0
	for award in _events("award"):
		delivered += int(award.amount)
	check(delivered == 300 and _events("organized").size() == 2, "UI rebuild neither loses nor duplicates awards")
	check(is_instance_valid(app.modal), "deferred preview rebuild preserves final showdown overlay")

	# Disconnect can arrive after authority has settled but before visual awards.
	before = _fixture(46, 350, [100, 100, 100], [900, 900, 900])
	_baseline(before)
	after = _settle(before, [{"seat": 0, "amount": 200}, {"seat": 1, "amount": 100}], [1100, 1000, 900])
	app._on_state(after)
	await create_timer(0.1).timeout
	var paused := after.duplicate(true)
	paused.paused = true
	paused.revision += 1
	app._on_state(paused)
	var visible_total: int = app._displayed_pot
	for seat in 3:
		visible_total += app._visual_stack(paused, seat)
	check(visible_total == 3000, "disconnect during payout preserves visible chip conservation")
	check(not app.presentation_busy, "disconnect stops active presentation queue")

	before = _fixture(47, 370, [100, 100, 100], [900, 900, 900])
	_baseline(before)
	after = _settle(before, [{"seat": 1, "amount": 300}], [900, 1200, 900])
	app._on_state(after)
	check(await _until_event("award", 1), "remote winner receives pot before organizing")
	var remote_organizing := false
	for child in app.flight_layer.get_children():
		remote_organizing = remote_organizing or child.get("_animation_kind") == "organize"
	check(remote_organizing, "remote winner has an actual 3D organizing component")
	paused = after.duplicate(true)
	paused.paused = true
	paused.revision += 1
	app._on_state(paused)
	await create_timer(0.5).timeout
	check(app.flight_layer.get_child_count() == 0, "disconnect destroys temporary remote organizing chips")
	check(_events("organized").is_empty(), "cancelled organizing continuation cannot fire after disconnect")

	app._cancel_presentation()
	before = _fixture(44, 400, [10, 10, 10], [990, 990, 990])
	_baseline(before)
	after = before.duplicate(true)
	after.revision += 1
	after.players[0].committed = 20
	after.players[0].stack = 980
	after.pot = 40
	app._on_state(after)
	check(app.presentation_busy, "bet flight begins before cancellation test")
	app._cancel_presentation()
	_baseline(_fixture(45, 500, [20, 20, 20], [980, 980, 980]))
	await create_timer(0.7).timeout
	check(app._displayed_pot == 60 and app.pot_display._amount == 60, "cancelled old flight cannot alter new table")
	check(app.flight_layer.get_child_count() == 0, "cancelled flight nodes are destroyed")
	after = app.shown_state.duplicate(true)
	after.revision += 1
	after.players[0].committed += 10
	after.players[0].stack -= 10
	after.pot += 10
	app._on_state(after)
	check(app.presentation_busy, "destroy scene while final flight is still active")
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.7).timeout
	print("PRESENTATION_EDGES_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
