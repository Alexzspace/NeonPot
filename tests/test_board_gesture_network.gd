extends SceneTree
const Session = preload("res://scripts/table_session.gd")
class Wire extends Node:
	signal command_received(step: int)
	signal acknowledged(step: int)
	@rpc("authority", "call_remote", "reliable")
	func command(step: int) -> void: command_received.emit(step)
	@rpc("any_peer", "call_remote", "reliable")
	func ack(step: int) -> void: acknowledged.emit(step)

var session
var wire: Wire
var role := "host"
var port := 27978
var checks := 0
var failures := 0
var events: Array = []
var acknowledgments: Dictionary = {}
var baseline: Dictionary = {}
var remote := 0
var finished := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	_run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOARD_NETWORK %s: %s" % [role, description])
func pause(seconds: float) -> void: await create_timer(seconds).timeout
func until(predicate: Callable, description: String, seconds: float = 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await pause(0.02)
	check(predicate.call(), description)
func command(step: int) -> void:
	wire.command.rpc_id(remote, step)
	await until(func(): return acknowledgments.has(step), "client completed step %d" % step)
func gesture(seat: int, sequence: int, index: int, kind: String, offset: Vector2) -> void:
	check(seat in [0, 1] and index >= 0 and index < 5 and kind in ["press", "drag", "release"] and offset.is_finite(), "event carries only valid public interaction fields")
	check(sequence < 999, "forged authority sequence never reaches handler")
	events.append([seat, sequence, index, kind, offset])
	print("BOARD_EVENT hand=%d board=%d seat=%d sequence=%d index=%d kind=%s x=%.2f y=%.2f" % [session.state.hand_id, session.state.board.size(), seat, sequence, index, kind, offset.x, offset.y])
func _run() -> void:
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.board_gesture.connect(gesture)
	wire = Wire.new()
	wire.name = "Wire"
	root.add_child(wire)
	wire.acknowledged.connect(func(step): acknowledgments[step] = true)
	wire.command_received.connect(client_command)
	if role == "client":
		check(session.join_game("127.0.0.1", "Client", port) == OK, "client transport created")
		await until(func(): return finished, "host completed protocol", 18.0)
		_finish()
		return
	check(session.host_game("Host", 1000, port) == OK, "host transport created")
	print("BOARD_HOST_READY")
	await until(func(): return session.state.players.size() == 2, "human client registered")
	for peer in session._peer_seats:
		if peer != 1: remote = peer
	session.begin_hand()
	baseline = session.state.duplicate(true)
	await command(1)
	await until(func(): return session._board_visible_owners.get(4, -1) == 1, "client owns unrevealed fifth board card")
	session.request_board_gesture(4, "press", Vector2.ZERO)
	await command(2)
	await until(func(): return not events.is_empty() and events[-1][3] == "drag", "latest client drag echoed")
	check(events[-1][4].is_equal_approx(Vector2(0.9, -0.8)), "coalesced position matches final sample")
	check(events.size() == 2, "100 input samples produce one press plus one drag")
	await command(3)
	await until(func(): return not session._board_visible_owners.has(4), "client release cannot be lost behind throttle")
	check(session.state == baseline, "interactions do not change gameplay snapshot")
	check(session.state.players[1].cards == [-1, -1] and not session.state.has("deck"), "host recipient retains hidden client cards")
	session.request_board_gesture(4, "press", Vector2.ZERO)
	await until(func(): return session._board_visible_owners.get(4, -1) == 0, "host can acquire after release")
	await command(4)
	check(session._board_owners.get(4, -1) == 0, "client cannot move or release host-owned card")
	# No further heartbeat: this tests actual wall-clock TTL on real transport.
	await until(func(): return not session._board_visible_owners.has(4), "abandoned host hold expires", 2.5)
	await command(5)
	await until(func(): return session._board_visible_owners.get(2, -1) == 1, "client reacquires another card after TTL")
	# A complete real hand, with regular action requests while a board card is held.
	await command(6)
	var deadline := Time.get_ticks_msec() + 5000
	while session.state.phase != "showdown" and Time.get_ticks_msec() < deadline:
		if session.state.actor == 0:
			session.submit_action("check" if session.state.legal.get("check", false) else "call")
		await pause(0.03)
	check(session.state.phase == "showdown" and session.state.board.size() == 5, "full real hand completes despite gesture ownership")
	check(session._board_owners.is_empty(), "board reveal clears ownership across streets")
	await command(7)
	await until(func(): return session._board_visible_owners.get(0, -1) == 1, "face-up card accepts gesture at showdown")
	session.begin_hand()
	await command(8)
	check(session.state.hand_id == 2 and session._board_visible_owners.is_empty(), "next hand clears held card and dedupe context")
	await command(9)
	await until(func(): return session._board_visible_owners.get(1, -1) == 1, "new hand accepts fresh client sequence")
	await command(10)
	await until(func(): return session.state.get("paused", false), "real client disconnect pauses host")
	check(session._board_visible_owners.is_empty() and session._board_owners.is_empty(), "disconnect clears every outstanding hold")
	var count := events.size()
	session.request_board_gesture(1, "press", Vector2.ZERO)
	await pause(0.1)
	check(events.size() == count, "paused table cannot start a gesture")
	_finish()

var autoplay := false
var last_action_revision := -1
func _process(_delta: float) -> bool:
	if role == "client" and autoplay and session != null and not session.state.is_empty() and session.state.get("actor", -1) == session.local_seat:
		if session.state.revision != last_action_revision:
			last_action_revision = session.state.revision
			session.submit_action("check" if session.state.legal.get("check", false) else "call")
	return false

func client_command(step: int) -> void:
	if step == 1:
		await until(func(): return not session.state.is_empty() and session.state.hand_id == 1, "client received first hand")
		baseline = session.state.duplicate(true)
		session._receive_board_gesture.rpc_id(1, 0, 999, session.state.hand_id, session.state.room_id, 0, 4, "press", Vector2.ZERO)
		session._request_board_gesture.rpc_id(1, 0, 1, session.state.room_id, 0, 4, "press", Vector2.ZERO)
		session._request_board_gesture.rpc_id(1, 1, 1, "old-room", 0, 4, "press", Vector2.ZERO)
		session._request_board_gesture.rpc_id(1, 1, 1, session.state.room_id, 0, 5, "press", Vector2.ZERO)
		session._request_board_gesture.rpc_id(1, 1, 1, session.state.room_id, 0, 4, "press", Vector2(NAN, 0))
		session.request_board_gesture(4, "press", Vector2(0.1, 0.2))
	elif step == 2:
		for index in 100: session.request_board_gesture(4, "drag", Vector2(float(index + 1) * 0.009, -0.8))
		await pause(0.12)
	elif step == 3:
		session._request_board_gesture.rpc_id(1, 1, 1, session.state.room_id, 0, 0, "press", Vector2.ZERO)
		session.request_board_gesture(4, "release", Vector2.ZERO)
		check(session.state == baseline, "client snapshot unchanged by all gestures")
		check(session.state.players[0].cards == [-1, -1] and not session.state.has("deck"), "client never receives host hidden cards or deck")
	elif step == 4:
		session.request_board_gesture(4, "press", Vector2.ZERO)
		session.request_board_gesture(4, "drag", Vector2.ONE)
		session.request_board_gesture(4, "release", Vector2.ZERO)
	elif step == 5:
		await until(func(): return not session._board_visible_owners.has(4), "client sees TTL release")
		session.request_board_gesture(2, "press", Vector2.ZERO)
		for heartbeat in 8:
			await pause(0.25)
			session.request_board_gesture(2, "drag", Vector2(0.2, -0.1))
		await pause(0.1)
		check(session._board_visible_owners.get(2, -1) == 1, "250 ms heartbeat sustains hold beyond 1500 ms TTL")
	elif step == 6: autoplay = true
	elif step == 7:
		autoplay = false
		await until(func(): return session.state.phase == "showdown", "client receives real showdown")
		session.request_board_gesture(0, "press", Vector2.ZERO)
	elif step == 8:
		await until(func(): return session.state.hand_id == 2, "client receives next hand")
		check(session._board_visible_owners.is_empty(), "client lifecycle cleanup releases previous-hand owner")
		session._request_board_gesture.rpc_id(1, 1, 800, session.state.room_id, 5, 0, "press", Vector2.ZERO)
	elif step == 9: session.request_board_gesture(1, "press", Vector2.ZERO)
	elif step == 10:
		wire.ack.rpc_id(1, step)
		await pause(0.1)
		session.leave_game()
		check(session._board_visible_owners.is_empty(), "client leave immediately clears visual holds")
		finished = true
		return
	wire.ack.rpc_id(1, step)

func _finish() -> void:
	session.leave_game()
	session.queue_free()
	wire.queue_free()
	await process_frame
	print("BOARD_GESTURE_NETWORK role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(0 if failures == 0 else 1)
