extends SceneTree

const SessionScript = preload("res://scripts/table_session.gd")
var session
var role := "host"
var port := 27946
var checks := 0
var failures := 0
var seen_revision := -1
var phases: Dictionary = {}
var saw_invalid := false
var saw_stale := false
var sent_attacks := false
var finishing := false
var started_at := 0
var second_started := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL %s: %s" % [role, label])

func _run() -> void:
	started_at = Time.get_ticks_msec()
	session = SessionScript.new()
	session.name = "TableSession"
	root.add_child(session)
	session.status_changed.connect(_status)
	if role == "host":
		check(session.host_game("Host", 1000, port) == OK, "server start")
		print("NETWORK_HOST_READY port=%d" % port)
	else:
		check(session.join_game("127.0.0.1", "Client", port) == OK, "client start")

func _status(message: String) -> void:
	if message == "Invalid action.":
		saw_invalid = true
	if message.begins_with("Action expired"):
		saw_stale = true
	print("NETWORK_STATUS %s %s" % [role, message])

func _process(_delta: float) -> bool:
	if finishing or session == null:
		return false
	if Time.get_ticks_msec() - started_at > 20000:
		check(false, "network test timeout")
		_finish()
		return false
	var state: Dictionary = session.state
	if state.is_empty() or state.get("revision", -1) == seen_revision:
		return false
	seen_revision = state.revision
	phases[state.phase] = true
	check(not state.has("deck"), "deck absent")
	check(state.you == (0 if role == "host" else 1), "recipient seat binding")
	if state.phase == "lobby":
		if role == "host" and state.players.size() == 2:
			session.begin_hand()
		return false
	if state.phase != "showdown":
		for seat in state.players.size():
			var cards: Array = state.players[seat].cards
			if seat == state.you:
				check(cards.size() == 2 and cards[0] >= 0 and cards[1] >= 0, "own two cards")
			else:
				check(cards == [-1, -1], "opponent cards redacted")
	if state.get("paused", false):
		check(role == "host" and second_started, "host pauses on disconnect")
		check(not state.players[1].connected, "disconnect marked")
		check(state.legal.is_empty(), "paused has no legal actions")
		var before: int = state.revision
		session.submit_action("fold")
		session.begin_hand()
		check(session.state.revision == before, "disconnect freezes hand")
		_finish()
		return false
	if state.hand_id >= 2:
		second_started = true
		if role == "client":
			check(saw_invalid, "server rejected malformed action")
			check(saw_stale, "server rejected stale action")
			_finish()
		return false
	if state.phase == "showdown":
		check(state.board.size() == 5, "complete five-card board")
		var total := 0
		for player in state.players:
			total += int(player.stack)
		check(total == 2000, "chips conserved")
		for phase in ["preflop", "flop", "turn", "river", "showdown"]:
			check(phases.has(phase), "observed " + phase)
		if role == "host":
			# Give the remote process a frame to observe showdown; this is a test driver only.
			_deal_next.call_deferred()
		return false
	if state.actor == state.you:
		if role == "client" and not sent_attacks:
			sent_attacks = true
			session._request_action.rpc_id(1, "hack", 0, state.hand_id, state.revision)
			session._request_action.rpc_id(1, "fold", 0, state.hand_id - 1, state.revision)
		var action := "check" if state.legal.get("check", false) else "call"
		session.submit_action(action)
	return false

func _deal_next() -> void:
	await create_timer(0.15).timeout
	if not finishing:
		session.begin_hand()

func _finish() -> void:
	if finishing:
		return
	finishing = true
	session.leave_game()
	session.queue_free()
	await process_frame
	print("NETWORK_TEST role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(0 if failures == 0 else 1)
