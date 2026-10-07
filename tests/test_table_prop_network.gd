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
var port := 27981
var checks := 0
var failures := 0
var events: Array = []
var acknowledgments: Dictionary = {}
var remote := 0
var baseline: Dictionary = {}
var finished := false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PROP_NETWORK %s: %s" % [role, message])
func pause(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
func until(predicate: Callable, message: String, milliseconds: int = 4000) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while not predicate.call() and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(predicate.call(), message)
func command(step: int) -> void:
	wire.command.rpc_id(remote, step)
	await until(func(): return acknowledgments.has(step), "client step %d completed" % step)
func gesture(seat: int, sequence: int, kind: String) -> void:
	check(seat in [0, 1] and kind in ["pot", "deck"] and sequence > 0 and sequence < 999, "only authenticated public gesture fields received")
	check(not events.any(func(event): return event[0] == session.state.hand_id and event[2] == sequence), "echo sequence unique per hand")
	events.append([session.state.hand_id, seat, sequence, kind])
	print("PROP_EVENT hand=%d seat=%d sequence=%d kind=%s" % [session.state.hand_id, seat, sequence, kind])
func _run() -> void:
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.table_prop_gesture.connect(gesture)
	wire = Wire.new()
	wire.name = "Wire"
	root.add_child(wire)
	wire.command_received.connect(client_command)
	wire.acknowledged.connect(func(step): acknowledgments[step] = true)
	if role == "client":
		check(session.join_game("127.0.0.1", "Client", port) == OK, "client transport created")
		await until(func(): return finished, "protocol completed", 15000)
		_finish()
		return
	check(session.host_game("Host", 1000, port) == OK, "host transport created")
	print("PROP_HOST_READY")
	await until(func(): return session.state.players.size() == 2, "client registered")
	for peer in session._peer_seats:
		if peer != 1: remote = peer
	session.begin_hand()
	baseline = session.state.duplicate(true)
	await command(1)
	await until(func(): return events.size() == 12, "ten additional rapid client taps all echoed")
	session.request_table_prop_gesture("pot")
	session.request_table_prop_gesture("deck")
	check(events.size() == 14, "other seat immediately taps both props")
	await pause(700)
	await command(2)
	await until(func(): return events.size() == 16, "fresh gestures accepted without cooldown")
	check(events[14][3] == "deck" and events[15][3] == "pot", "replay did not insert a hidden extra event")
	await pause(700)
	session.request_table_prop_gesture("deck")
	session.request_table_prop_gesture("pot")
	check(events.size() == 18 and events[-1][1] == 0, "host gestures share same authority path")
	check(session.state == baseline and not session.state.has("deck") and session.state.players[1].cards == [-1, -1], "props preserve host snapshot and opponent privacy")
	await command(3)
	if session.state.actor == 0: session.submit_action("fold")
	else: await command(4)
	await until(func(): return session.state.phase == "showdown", "real hand completed")
	await pause(700)
	session.request_table_prop_gesture("pot")
	check(events.size() == 18, "historical settled pot cannot be touched")
	await command(5)
	await until(func(): return events.size() == 19, "deck allowed at showdown")
	session.begin_hand()
	await command(6)
	await until(func(): return events.size() == 21, "new hand accepts both fresh gestures")
	check(events[19][2] == 1 and events[20][2] == 2, "new hand resets cosmetic sequence")
	await command(7)
	await until(func(): return session.state.get("paused", false), "real disconnect pauses host")
	session.request_table_prop_gesture("deck")
	session._receive_table_prop_gesture(0, 999, session.state.hand_id, session.state.room_id, "deck")
	check(events.size() == 21 and session._prop_last_request.is_empty(), "disconnect clears bookkeeping and suppresses later events")
	_finish()
func client_command(step: int) -> void:
	if step == 1:
		await until(func(): return not session.state.is_empty() and session.state.hand_id == 1, "first hand received")
		baseline = session.state.duplicate(true)
		session._receive_table_prop_gesture.rpc_id(1, 0, 999, 1, session.state.room_id, "deck")
		session._request_table_prop_gesture.rpc_id(1, 0, 1, session.state.room_id, "pot")
		session._request_table_prop_gesture.rpc_id(1, 1, 1, "old-room", "pot")
		session._request_table_prop_gesture.rpc_id(1, 1, 1, session.state.room_id, "flip")
		session.request_table_prop_gesture("pot")
		session.request_table_prop_gesture("deck")
		for index in 10: session.request_table_prop_gesture("pot")
		check(session._prop_request_sequence == 12, "rapid taps sent immediately")
		for sequence in range(1, 13): session._request_table_prop_gesture.rpc_id(1, 1, sequence, session.state.room_id, "pot")
	elif step == 2:
		session._request_table_prop_gesture.rpc_id(1, 1, 12, session.state.room_id, "pot")
		session._prop_request_sequence = 12
		session.request_table_prop_gesture("deck")
		session.request_table_prop_gesture("pot")
	elif step == 3:
		await until(func(): return events.size() == 18, "host gestures received identically")
		check(session.state == baseline and session.state.players[0].cards == [-1, -1] and not session.state.has("deck"), "client private snapshot unchanged")
	elif step == 4: session.submit_action("fold")
	elif step == 5:
		await until(func(): return session.state.phase == "showdown", "client receives showdown")
		session.request_table_prop_gesture("pot")
		session.request_table_prop_gesture("deck")
	elif step == 6:
		await until(func(): return session.state.hand_id == 2, "next hand received")
		session._request_table_prop_gesture.rpc_id(1, 1, 900, session.state.room_id, "deck")
		session.request_table_prop_gesture("deck")
		session.request_table_prop_gesture("pot")
	elif step == 7:
		await until(func(): return events.size() == 21, "all authoritative events received before leave")
		wire.ack.rpc_id(1, step)
		await pause(100)
		session.leave_game()
		check(session._prop_received_sequence == 0, "client leave resets prop sequence")
		finished = true
		return
	wire.ack.rpc_id(1, step)
func _finish() -> void:
	session.leave_game()
	session.queue_free()
	wire.queue_free()
	await process_frame
	print("TABLE_PROP_NETWORK role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(0 if failures == 0 else 1)
