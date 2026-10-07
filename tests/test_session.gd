extends SceneTree

const SessionScript = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0
var session

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	session = SessionScript.new()
	root.add_child(session)
	check(session.host_game("", 1000) == ERR_INVALID_PARAMETER, "reject empty name")
	check(session.host_game("Valid", -10) == ERR_INVALID_PARAMETER, "reject bad stack")
	check(session.host_game("Valid", 1000, 0) == ERR_INVALID_PARAMETER, "reject bad port")
	check(session.join_game("", "Valid") == ERR_INVALID_PARAMETER, "reject empty IP")
	session.start_local(["One"], 1000)
	check(session.state.is_empty(), "reject one local player")
	session.start_local(["One", 3], 1000)
	check(session.state.is_empty(), "reject nonstring name")
	session.start_local(["One", "Two"], 1000)
	check(session.is_host and session.is_local, "local mode explicit")
	check(session.state.phase == "lobby", "lobby before deal")
	session.begin_hand()
	check(session.state.phase == "preflop", "first hand dealt")
	var revision: int = session.state.revision
	var hand_id: int = session.state.hand_id
	session.is_local = false
	session._request_action("fold", 0, hand_id, revision)
	check(session.state.revision == revision, "unregistered sender cannot act")
	session._register_player("Imposter")
	check(session.state.players.size() == 2, "unregistered local sender cannot claim remote seat")
	session.is_local = true
	check(session.state.players[0].cards[0] >= 0, "own cards visible")
	check(session.state.players[1].cards == [-1, -1], "other cards hidden")
	session.set_local_seat(1)
	check(session.state.revision == revision, "view switch not action revision")
	check(session.state.players[0].cards == [-1, -1], "former seat cards hidden")
	check(session.state.players[1].cards[0] >= 0, "new seat cards visible")
	session.set_local_seat(-1)
	check(session.local_seat == 1, "reject negative seat")
	session.set_local_seat(99)
	check(session.local_seat == 1, "reject large seat")
	var actor: int = session.state.actor
	session._apply_action(actor, "fold", 0, hand_id, revision - 1, 1)
	check(session.state.revision == revision, "reject stale revision")
	session._apply_action(actor, "fold", 0, hand_id - 1, revision, 1)
	check(session.state.revision == revision, "reject stale hand")
	session._apply_action(actor, "hack", 0, hand_id, revision, 1)
	check(session.state.revision == revision, "reject unknown action")
	session._apply_action(actor, "raise", -1, hand_id, revision, 1)
	check(session.state.revision == revision, "reject negative amount")
	session._apply_action(99, "fold", 0, hand_id, revision, 1)
	check(session.state.revision == revision, "reject impossible seat")
	session.set_local_seat(1 - actor)
	session.submit_action("fold")
	check(session.state.revision == revision, "reject out-of-turn action")
	session.set_local_seat(actor)
	session.submit_action("call")
	check(session.state.revision == revision + 1, "valid action advances revision")
	check(session.local_seat == actor, "no automatic private seat switch")
	session._apply_action(actor, "call", 0, hand_id, revision, 1)
	check(session.state.revision == revision + 1, "duplicate action ignored")
	var guard := 0
	while session.state.actor >= 0 and guard < 20:
		guard += 1
		session.set_local_seat(session.state.actor)
		var legal: Dictionary = session.state.legal
		session.submit_action("check" if legal.get("check", false) else "call")
	check(session.state.phase == "showdown", "complete local hand")
	var total := 0
	for player in session.state.players:
		total += int(player.stack)
	check(total == 2000, "local chip conservation")
	session.begin_hand()
	check(session.state.hand_id == hand_id + 1, "manual next hand")
	session._paused = true
	revision = session.state.revision
	session.submit_action("fold")
	session.begin_hand()
	check(session.state.revision == revision, "paused cannot act or deal")
	session.leave_game()
	check(session.state.is_empty() and not session.is_host, "leave clears room")
	session.start_local(["One", "Two"], 1000)
	session.is_host = false
	session.begin_hand()
	check(session.state.phase == "lobby", "client cannot deal")
	session.leave_game()
	session.queue_free()
	await process_frame
	print("SESSION_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
