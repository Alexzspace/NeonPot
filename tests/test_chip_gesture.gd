extends SceneTree
const Session = preload("res://scripts/table_session.gd")
const Styles = preload("res://scripts/chip_gestures.gd")

class BucketRng extends RefCounted:
	var bucket := 1
	var normal_pick := 0
	func randi_range(low: int, high: int) -> int:
		return bucket if high == 99 else clampi(normal_pick, low, high)
var checks := 0
var failures := 0
var events: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CHIP_GESTURE: " + message)

func _cooldown() -> void:
	var deadline := Time.get_ticks_msec() + 370
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout

func _run() -> void:
	var session = Session.new()
	var rng := BucketRng.new()
	session._gesture_rng = rng
	root.add_child(session)
	session.chip_gesture.connect(func(seat: int, sequence: int, style: int): events.append({"seat": seat, "sequence": sequence, "style": style}))
	session.request_chip_gesture()
	check(events.is_empty(), "unseated player cannot gesture")
	session.start_local(["Alice", "Bob"], 1000)
	var original: Dictionary = session.state.duplicate(true)
	var room: String = session.state.room_id
	check(room.length() == 32, "room nonce provided without private game data")
	session.request_chip_gesture()
	check(events.size() == 1 and events[0] == {"seat": 0, "sequence": 1, "style": 0}, "lobby gesture and style echoed by authority")
	check(session.state == original, "gesture changes no stack, turn, hand, or revision")
	for index in 20:
		session.request_chip_gesture()
	check(events.size() == 1, "local flood is dropped immediately")
	session.set_local_seat(1)
	session.request_chip_gesture()
	check(events.size() == 2 and events[1].seat == 1, "pass-and-play switches authenticated local seat")
	session._receive_chip_gesture(1, 2, 0, room)
	check(events.size() == 2, "duplicate broadcast sequence ignored")
	session._receive_chip_gesture(0, 3, -1, room)
	session._receive_chip_gesture(0, 3, 0, "old-room")
	session._receive_chip_gesture(99, 3, 0, room)
	session._receive_chip_gesture(0, 3, 0, room, -1)
	session._receive_chip_gesture(0, 3, 0, room, Styles.DURATIONS.size())
	check(events.size() == 2, "old hand, old room, and invalid seat events ignored")
	session.is_local = false
	session._request_chip_gesture(0, 50, room)
	session._peer_seats = {1: 0, 7: 1}
	session._accept_chip_gesture(0, 7, 0, 50, room)
	session._accept_chip_gesture(0, 99, 0, 50, room)
	check(events.size() == 2, "sender-to-seat binding rejects impersonation and unknown peer")
	session._peer_seats.clear()
	session.is_local = true
	check(events.size() == 2, "unregistered RPC sender has no identity")
	await _cooldown()
	session.set_local_seat(0)
	session._accept_chip_gesture(0, -1, 0, 10, room)
	check(events.size() == 3, "authority accepts new request after interval")
	session._accept_chip_gesture(0, -1, 0, 11, room)
	check(events.size() == 3, "authority separately rate limits requests")
	await _cooldown()
	session._accept_chip_gesture(0, -1, 0, 11, room)
	check(events.size() == 3, "dropped request cannot replay after rate limit expires")
	session._accept_chip_gesture(0, -1, 0, -1, room)
	session._accept_chip_gesture(0, -1, 0, 9223372036854775807, room)
	check(events.size() == 3, "negative and extreme request sequences rejected")
	session.begin_hand()
	var hand: int = session.state.hand_id
	original = session.state.duplicate(true)
	session.set_local_seat(1 - session.state.actor)
	var idle_seat: int = session.local_seat
	session.request_chip_gesture()
	check(events.size() == 4 and events[-1].sequence == 1 and events[-1].seat == idle_seat, "new hand clears limits and permits non-actor gesture")
	check(session.state.revision == original.revision and session.state.actor == original.actor, "non-actor gesture leaves authoritative turn unchanged")
	session._receive_chip_gesture(0, 20, 0, room)
	session._accept_chip_gesture(0, -1, 0, 100, room)
	check(events.size() == 4, "previous-hand request and event cannot cross new hand")
	session.set_local_seat(session.state.actor)
	session.submit_action("all_in")
	var count := events.size()
	session.request_chip_gesture()
	check(events.size() == count and session.state.players[session.local_seat].stack == 0, "empty stack cannot be played with")
	session._paused = true
	session.set_local_seat(1 - session.local_seat)
	session.request_chip_gesture()
	session._receive_chip_gesture(session.local_seat, 100, hand, room)
	check(events.size() == count, "paused request and echoed event are suppressed")
	session.leave_game()
	session.start_local(["New Alice", "New Bob"], 1000)
	check(session.state.room_id != room, "new room receives fresh nonce")
	session._receive_chip_gesture(0, 999, 0, room)
	session._accept_chip_gesture(0, -1, 0, 999, room)
	check(events.size() == count, "old-room requests and echoes cannot affect fresh lobby")
	session.request_chip_gesture()
	check(events.size() == count + 1 and events[-1].sequence == 1, "fresh room resets dedupe sequence")
	session._on_server_disconnected()
	count = events.size()
	session._receive_chip_gesture(0, 2, 0, session.state.room_id)
	check(events.size() == count, "disconnect latch suppresses delayed gestures")
	session.leave_game()
	session.start_local(["Receiver Alice", "Receiver Bob"], 1000)
	count = events.size()
	room = session.state.room_id
	session._receive_chip_gesture(0, 1, 0, room)
	session._receive_chip_gesture(0, 2, 0, room)
	session._receive_chip_gesture(0, 3, 0, room)
	check(events.size() == count + 1, "delayed reliable burst is coalesced at recipient")
	await _cooldown()
	session._receive_chip_gesture(0, 3, 0, room)
	check(events.size() == count + 1, "coalesced broadcast remains consumed after cooldown")
	session._receive_chip_gesture(0, 4, 0, room)
	check(events.size() == count + 2, "fresh authority event plays after recipient cooldown")
	# Exhaust the selector's probability space rather than relying on statistical luck.
	var rare_count := 0
	var previous := -1
	for bucket in 100:
		rng.bucket = bucket
		var style: int = session._choose_chip_style(0)
		check(Styles.is_valid_style(style), "bucket returns a valid style")
		if style == Styles.RARE:
			rare_count += 1
		else:
			check(style != previous, "successive ordinary styles do not repeat")
			previous = style
	check(rare_count == 1, "exactly one of 100 uniform integer buckets selects rare")
	check(Styles.duration(Styles.RARE) == 2.0 and Styles.duration(-1) == 0.0, "hidden gesture lasts two seconds and invalid styles are rejected")
	for style in Styles.NORMAL.values():
		check(Styles.duration(style) == 1.0, "ordinary professional gesture lasts one second")
	rng.bucket = 1
	for pick in Styles.NORMAL.size():
		session._gesture_last_normal.clear()
		rng.normal_pick = pick
		check(session._choose_chip_style(0) == Styles.NORMAL.values()[pick], "every ordinary style is reachable")
	rng.normal_pick = 0
	session.leave_game()
	session.start_local(["Rare Alice", "Rare Bob"], 1000)
	rng.bucket = 0
	count = events.size()
	session.request_chip_gesture()
	check(events.size() == count + 1 and events[-1].style == Styles.RARE, "host selects hidden style")
	await _cooldown()
	session.request_chip_gesture()
	check(events.size() == count + 1, "rare blocks replacement past ordinary 350ms interval")
	session.set_local_seat(1)
	rng.bucket = 1
	session.request_chip_gesture()
	check(events.size() == count + 2, "rare protection is per seat")
	session.begin_hand()
	check(session._gesture_rare_until.is_empty() and session._gesture_last_normal.is_empty(), "new hand clears rare lock and style history")
	session.set_local_seat(session.state.actor)
	rng.bucket = 0
	session.request_chip_gesture()
	var revision: int = session.state.revision
	session.submit_action("call")
	check(session.state.revision > revision, "rare gesture never blocks betting")
	await _cooldown()
	session.request_chip_gesture()
	var consumed: int = session._gesture_request_sequence
	var locked_seat: int = session.local_seat
	var expires: int = session._gesture_rare_until[locked_seat]
	while Time.get_ticks_msec() <= expires + 20:
		await create_timer(0.05).timeout
	rng.bucket = 1
	count = events.size()
	session._accept_chip_gesture(locked_seat, -locked_seat - 1, session.state.hand_id, consumed, session.state.room_id)
	check(events.size() == count, "rare-period dropped tap cannot replay after lock expires")
	session.request_chip_gesture()
	check(events.size() == count + 1 and events[-1].style != Styles.RARE, "gesture resumes after hidden animation duration")
	session.leave_game()
	check(session._gesture_rare_until.is_empty() and session._gesture_last_normal.is_empty(), "leaving clears hidden lock and normal history")
	session.queue_free()
	await process_frame
	print("CHIP_GESTURE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
