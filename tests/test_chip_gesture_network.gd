extends SceneTree
const Session = preload("res://scripts/table_session.gd")
const Styles = preload("res://scripts/chip_gestures.gd")
class NetworkRng extends RefCounted:
	var picks := 0
	func randi_range(low: int, high: int) -> int:
		if high == 99:
			picks += 1
			return 0 if picks == 1 else 1
		return low
var session
var role := "host"
var port := 27949
var checks := 0
var failures := 0
var started_at := 0
var events: Array = []
var requested: Dictionary = {}
var seen_revision := -1
var lobby_ready_at := -1
var finishing := false
var before_gesture: Dictionary = {}
var completed_hand := false
var non_actor_gesture := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GESTURE_NETWORK %s: %s" % [role, message])

func _run() -> void:
	started_at = Time.get_ticks_msec()
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.chip_gesture.connect(_gesture)
	if role == "host":
		session._gesture_rng = NetworkRng.new()
		check(session.host_game("Host", 1000, port) == OK, "server ready")
		print("GESTURE_HOST_READY")
	else:
		check(session.join_game("127.0.0.1", "Client", port) == OK, "client connecting")

func _gesture(seat: int, sequence: int, style: int) -> void:
	var hand: int = session.state.hand_id
	if hand == 1 and seat != int(session.state.actor): non_actor_gesture = true
	check(seat in [0, 1], "authority supplies registered seat")
	check(Styles.is_valid_style(style), "authority supplies valid shared style")
	check(sequence < 999, "client cannot forge an authority broadcast or rare style")
	check(not events.any(func(item): return item.hand == hand and item.sequence == sequence), "authoritative broadcast sequence is unique")
	check(not session.state.has("deck"), "event does not add private deck to snapshot")
	check(before_gesture.is_empty() or before_gesture.hand_id != hand or session.state == before_gesture, "gesture leaves full recipient snapshot unchanged")
	events.append({"seat": seat, "sequence": sequence, "hand": hand, "style": style})
	print("GESTURE_STYLE hand=%d sequence=%d seat=%d style=%d" % [hand, sequence, seat, style])

func _hand_events(hand: int) -> Array:
	return events.filter(func(item): return item.hand == hand)

func _request_and_attack(state: Dictionary) -> void:
	var hand: int = state.hand_id
	requested[hand] = true
	before_gesture = state.duplicate(true)
	if role == "client":
		if hand == 0:
			# Deliberately illegal authority RPC: server must reject before invoking handler.
			session._receive_chip_gesture.rpc_id(1, 0, 999, hand, state.room_id, Styles.RARE)
		# Request has no seat/amount fields. Invalid context must not consume sequence 1.
		session._request_chip_gesture.rpc_id(1, hand, 1, "old-room")
		if hand > 0:
			session._request_chip_gesture.rpc_id(1, hand - 1, 1, state.room_id)
			session._request_chip_gesture.rpc_id(1, hand, -1, state.room_id)
	session.request_chip_gesture()
	for index in 15:
		session.request_chip_gesture()
	if role == "client":
		# Bypass local limiter to exercise the independent authority limiter and replay gate.
		for sequence in range(1, 21):
			session._request_chip_gesture.rpc_id(1, hand, sequence, state.room_id)
		check(hand == 0 or state.actor in [0, 1], "random first dealer supplies a valid actor while both seats gesture")

func _process(_delta: float) -> bool:
	if finishing or session == null: return false
	if Time.get_ticks_msec() - started_at > 20000:
		check(false, "network timeout")
		_finish()
		return false
	var state: Dictionary = session.state
	if state.is_empty() or state.players.size() != 2: return false
	if state.get("paused", false):
		var count := events.size()
		session.request_chip_gesture()
		session._receive_chip_gesture(0, 100, state.hand_id, state.room_id)
		check(events.size() == count, "disconnected table suppresses requests and delayed echoes")
		check(completed_hand, "normal betting still completed an entire hand")
		_finish()
		return false
	var hand: int = state.hand_id
	if hand in [0, 1] and not requested.has(hand):
		_request_and_attack(state)
	if hand == 0:
		if _hand_events(0).size() >= 2:
			if lobby_ready_at < 0: lobby_ready_at = Time.get_ticks_msec()
			if role == "host" and Time.get_ticks_msec() - lobby_ready_at > 430:
				check(_hand_events(0).size() == 2, "lobby flood produced exactly one echo per player")
				check(_hand_events(0).map(func(item): return item.seat).has(1), "client cannot impersonate host seat")
				before_gesture = {}
				session.begin_hand()
		return false
	if hand == 1 and _hand_events(1).size() < 2: return false
	before_gesture = {}
	if hand == 1 and state.revision != seen_revision:
		seen_revision = state.revision
		if state.phase == "showdown":
			completed_hand = true
			check(non_actor_gesture, "non-actor can gesture regardless of the random first button")
			check(state.board.size() == 5, "normal five-card showdown")
			check(_hand_events(0).size() == 2 and _hand_events(1).size() == 2, "no queued or duplicate gesture escaped limits")
			var total := 0
			for player in state.players: total += int(player.stack)
			check(total == 2000, "gestures preserve chip conservation")
			if role == "host": _next_hand.call_deferred()
		elif state.actor == state.you:
			session.submit_action("check" if state.legal.get("check", false) else "call")
	if hand == 2 and role == "client":
		check(completed_hand, "client observed completed hand before disconnect")
		_finish()
	return false

func _next_hand() -> void:
	await create_timer(0.15).timeout
	if not finishing: session.begin_hand()

func _finish() -> void:
	if finishing: return
	finishing = true
	session.leave_game()
	session.queue_free()
	await process_frame
	print("CHIP_GESTURE_NETWORK role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)
