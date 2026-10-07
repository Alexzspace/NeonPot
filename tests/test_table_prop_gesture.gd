extends SceneTree
const Session = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0
var events: Array = []
var session
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TABLE_PROP: " + message)
func accept(seat: int, sequence: int, kind: String, hand: int = -99, room: String = "") -> void:
	session._accept_table_prop_gesture(seat, -seat - 1, session.state.hand_id if hand == -99 else hand, sequence, session.state.room_id if room.is_empty() else room, kind)
func _run() -> void:
	session = Session.new()
	root.add_child(session)
	session.table_prop_gesture.connect(func(seat, sequence, kind): events.append([seat, sequence, kind]))
	session.request_table_prop_gesture("deck")
	check(events.is_empty(), "unseated cannot request")
	session.start_local(["Alice", "Bob"])
	for kind in ["pot", "deck"]: session.request_table_prop_gesture(kind)
	check(events.is_empty(), "lobby props rejected")
	session.begin_hand()
	session.set_local_seat(1 - session.state.actor)
	var original: Dictionary = session.state.duplicate(true)
	var engine_original: Dictionary = session._engine.snapshot(0).duplicate(true)
	var deck_original: Array = session._engine._deck.duplicate()
	session.request_table_prop_gesture("pot")
	session.request_table_prop_gesture("deck")
	check(events.size() == 2 and events[0][2] == "pot" and events[1][2] == "deck", "non-actor may touch pot and deck independently")
	check(events[0][0] == session.local_seat and events[1][1] == 2, "authority supplies seat and independent monotonic sequence")
	for index in 100:
		session.request_table_prop_gesture("pot")
		session.request_table_prop_gesture("deck")
	check(events.size() == 202 and session._prop_request_sequence == 202, "200 rapid taps have no local cooldown or lost events")
	var other: int = 1 - session.local_seat
	for sequence in range(1, 100): accept(other, sequence, "pot")
	check(events.size() == 301, "another seat may tap the same object without shared cooldown")
	var burst_count := events.size()
	check(session.state == original and session._engine.snapshot(0) == engine_original, "gesture changes no gameplay state or private outcome")
	check(session._engine._deck == deck_original, "cosmetic shuffle never shuffles the authoritative deck")
	var room: String = session.state.room_id
	var hand: int = session.state.hand_id
	for kind in ["", "POT", "shuffle", "flip"]: accept(other, 100, kind)
	accept(other, 100, "pot", 0)
	accept(other, 100, "pot", -99, "old-room")
	accept(99, 100, "pot")
	accept(other, -1, "pot")
	accept(other, 2147483648, "pot")
	session._accept_table_prop_gesture(other, -session.local_seat - 1, hand, 100, room, "pot")
	session.is_local = false
	session._peer_seats = {1: 0, 7: 1}
	session._accept_table_prop_gesture(0, 7, hand, 100, room, "pot")
	session._accept_table_prop_gesture(1, 99, hand, 100, room, "pot")
	session._request_table_prop_gesture(hand, 100, room, "pot")
	session.is_local = true
	session._peer_seats.clear()
	check(events.size() == burst_count + 0, "invalid kinds, context, sequence and identities are rejected")
	var deadline := Time.get_ticks_msec() + 650
	while Time.get_ticks_msec() < deadline: await create_timer(0.03).timeout
	accept(other, 99, "pot")
	check(events.size() == burst_count + 0, "accepted rapid request cannot replay later")
	accept(other, 100, "pot")
	check(events.size() == burst_count + 1 and events[-1][0] == other, "legal fresh request survives earlier invalid traffic")
	session._receive_table_prop_gesture(other, 3, hand, room, "pot")
	session._receive_table_prop_gesture(other, 999, 0, room, "pot")
	session._receive_table_prop_gesture(other, 999, hand, "old-room", "pot")
	session._receive_table_prop_gesture(other, 999, hand, room, "invalid")
	check(events.size() == burst_count + 1, "duplicate and stale authority echoes rejected")
	# Board interaction has its own sequence and ownership; prop events cannot clear it.
	session.request_board_gesture(0, "press", Vector2.ZERO)
	session._board_next_tick = 0
	session._process(0.0)
	session.request_table_prop_gesture("deck")
	check(session._board_owners.get(0, -1) == session.local_seat and events.size() == burst_count + 2, "deck event coexists with held board card")
	session.set_local_seat(session.state.actor)
	session._prop_request_sequence = 203
	session.submit_action("all_in")
	session.request_table_prop_gesture("pot")
	check(session.state.players[session.local_seat].stack == 0 and events.size() == burst_count + 3, "zero-chip human can tap existing pot")
	session.set_local_seat(session.state.actor)
	session.submit_action("fold")
	check(session.state.phase == "showdown", "real hand settles pot")
	session.request_table_prop_gesture("pot")
	session.request_table_prop_gesture("deck")
	check(events.size() == burst_count + 4 and events[-1][2] == "deck", "settled empty pot rejects while showdown deck remains available")
	session.begin_hand()
	session.request_table_prop_gesture("pot")
	check(events.size() == burst_count + 5 and events[-1][1] == 1, "next hand resets limits and sequence")
	accept(0, 900, "deck", hand, room)
	check(events.size() == burst_count + 5, "previous hand request stays invalid after reset")
	session._on_server_disconnected()
	session.request_table_prop_gesture("deck")
	session._receive_table_prop_gesture(0, 999, session.state.hand_id, room, "deck")
	check(events.size() == burst_count + 5 and session._prop_last_request.is_empty(), "disconnect resets and latches later input")
	session.start_solo("Human")
	session.begin_hand()
	accept(1, 1, "deck")
	check(events.size() == burst_count + 5, "bot cannot issue human prop gesture")
	session.request_table_prop_gesture("deck")
	check(events.size() == burst_count + 6 and events[-1][1] == 1, "new room accepts human with clean sequence")
	session.leave_game()
	check(session._prop_last_request.is_empty() and session._prop_server_sequence == 0, "leave cancels all gesture bookkeeping")
	session.queue_free()
	await process_frame
	print("TABLE_PROP_GESTURE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
