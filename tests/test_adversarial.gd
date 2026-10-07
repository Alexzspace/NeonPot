extends SceneTree
## Independent boundary/lifecycle probes. Network RPC transport is tested by network_peer.gd.

const SessionScript = preload("res://scripts/table_session.gd")
const EngineScript = preload("res://scripts/poker_engine.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ADVERSARIAL FAILED: " + label)


func _run() -> void:
	var session = SessionScript.new()
	root.add_child(session)
	session.start_local(["Host", "Peer"], 1000)
	session.begin_hand()
	var queued_hand: int = session.state.hand_id
	var queued_revision: int = session.state.revision
	var actor: int = session.state.actor
	var engine_before: Dictionary = session._engine.snapshot(-1)
	session._peer_seats = {1: 0, 22: 1}
	session._on_peer_disconnected(22)
	_check(session._paused and session.state.paused, "host disconnect latches paused state")
	_check(not session.state.players[1].connected, "host flags disconnected seat")
	_check(session.state.legal.is_empty() and not session.state.can_start, "host pause removes action/deal affordances")
	session._apply_action(actor, "fold", 0, queued_hand, queued_revision, 1)
	_check(session._engine.snapshot(-1) == engine_before, "pre-disconnect queued action cannot mutate host")
	session._apply_action(actor, "fold", 0, queued_hand, session.state.revision, 1)
	_check(session._engine.snapshot(-1) == engine_before, "even current-revision action cannot bypass pause")
	session.begin_hand()
	_check(session._engine.snapshot(-1) == engine_before, "begin hand cannot bypass pause")
	session.leave_game()
	session.start_local(["Host", "Peer"], 1000)
	session.begin_hand()
	session.is_host = false
	session.is_local = false
	# Deterministic lifecycle ordering probe, not a claim that a hostile nonauthority
	# RPC can call this method: simulate an already-accepted authoritative callback.
	var delayed_snapshot: Dictionary = session.state.duplicate(true)
	delayed_snapshot.revision += 1
	session._on_server_disconnected()
	_check(session._paused and session.state.legal.is_empty(), "client initially pauses when server disconnects")
	session.submit_action("fold")
	_check(session._paused, "local submit cannot bypass server disconnect pause")
	session._receive_state(delayed_snapshot)
	_check(session._paused and session.state.get("paused", false), "late authoritative snapshot must not undo server disconnect pause")
	_check(session.state.get("legal", {}).is_empty(), "late snapshot must not restore action affordances after disconnect")
	session.leave_game()
	session.queue_free()
	await process_frame
	_test_engine_boundaries()
	print("ADVERSARIAL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_engine_boundaries() -> void:
	var engine = EngineScript.new()
	_check(engine.configure(["A", "B", "C", "D", "E", "F"], 1000000000), "maximum supported engine stacks")
	_check(engine.start_hand(), "maximum stacks hand starts")
	var actor: int = engine.snapshot(-1).actor
	var before: Dictionary = engine.snapshot(actor)
	for value in [-9223372036854775807, -1, 0, 19, 1000000001, 9223372036854775807]:
		_check(not engine.act(actor, "raise", value), "illegal int64 raise rejected: %d" % value)
		_check(engine.snapshot(actor) == before, "illegal raise is atomic: %d" % value)
	_check(not engine.act(-1, "all_in") and not engine.act(6, "all_in"), "out-of-range seats rejected before indexing")
	var spectator: Dictionary = engine.snapshot(-100)
	for p in spectator.players:
		_check(p.cards == [-1, -1], "out-of-range viewpoint cannot reveal any cards")
	_check(engine.act(actor, "raise", 1000000000), "legal maximum raise succeeds")
	var state: Dictionary = engine.snapshot(-1)
	var total: int = state.pot
	for p in state.players:
		total += int(p.stack)
	_check(total == 6000000000, "chip totals use int64 beyond 32-bit capacity")
	_check(state.min_raise_to == 1999999990, "raise increment stays exact at large values")
