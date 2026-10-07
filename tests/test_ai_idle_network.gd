extends SceneTree
const Session = preload("res://scripts/table_session.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
const TEST_PORT := 27987
var checks := 0
var failures := 0
var host_events: Array = []
var client_events: Array = []
var host: Node
var client: Node
var host_scope: Node
var client_scope: Node
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AI_IDLE_NETWORK: " + label)
func _make_scope(scope_name: String) -> Node:
	var scope := Node.new()
	scope.name = scope_name
	root.add_child(scope)
	set_multiplayer(SceneMultiplayer.new(), scope.get_path())
	return scope
func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()
func _finish() -> void:
	client.leave_game()
	host.leave_game()
	client_scope.queue_free()
	host_scope.queue_free()
	await process_frame
	await process_frame
	print("AI_IDLE_NETWORK_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
func _run() -> void:
	host_scope = _make_scope("IdleHost")
	client_scope = _make_scope("IdleClient")
	host = Session.new()
	host.name = "Session"
	host_scope.add_child(host)
	client = Session.new()
	client.name = "Session"
	client_scope.add_child(client)
	host.chip_gesture.connect(func(seat: int, sequence: int, style: int): host_events.append([seat, sequence, style]))
	client.chip_gesture.connect(func(seat: int, sequence: int, style: int): client_events.append([seat, sequence, style]))
	check(host.host_game("Host", 1000, TEST_PORT) == OK, "real host opens ENet socket")
	check(client.join_game("127.0.0.1", "Guest", TEST_PORT) == OK, "real client connects")
	var joined: bool = await _wait_until(func(): return client.state.get("players", []).size() == 2)
	check(joined, "independent SceneMultiplayer peers register both human seats")
	if not joined:
		await _finish()
		return
	check(host.add_bot(5), "host adds third seat as AI")
	host.begin_hand()
	var dealt: bool = await _wait_until(func(): return client.state.get("phase", "") == "preflop" and client.state.get("revision", -1) == host.state.get("revision", -2))
	check(dealt, "actual private opening snapshots reach both peers")
	if not dealt:
		await _finish()
		return
	var host_before: Dictionary = host.state.duplicate(true)
	var client_before: Dictionary = client.state.duplicate(true)
	var engine_before: Array = []
	for seat in 3: engine_before.append(host._engine.snapshot(seat).duplicate(true))
	check(not host.play_bot_chip_gesture(0) and not host.play_bot_chip_gesture(1), "host cosmetic hook rejects human seats")
	check(not client.play_bot_chip_gesture(2), "client cannot originate host bot gesture")
	check(host_events.is_empty() and client_events.is_empty(), "rejected requests emit no local event")
	check(host.play_bot_chip_gesture(2), "host accepts live AI seat idle gesture")
	check(await _wait_until(func(): return client_events.size() == 1), "real authority RPC delivers idle gesture")
	check(host_events.size() == 1 and client_events == host_events, "host and client observe identical seat sequence and style")
	if host_events.size() == 1:
		check(host_events[0][0] == 2 and host_events[0][1] > 0 and Gestures.is_valid_style(host_events[0][2]), "event identifies AI seat with valid shared choreography")
	check(not host.play_bot_chip_gesture(2), "cooldown prevents duplicate AI flourish burst")
	await create_timer(0.1).timeout
	check(host_events.size() == 1 and client_events.size() == 1, "cooldown emits no extra network or local event")
	check(host.state == host_before and client.state == client_before, "cosmetic event preserves entire private snapshots and revisions")
	for seat in 3:
		check(host._engine.snapshot(seat) == engine_before[seat], "cosmetic event preserves engine cards chips and turn for every viewpoint")
	for seat in 3:
		var received: Array = client.state.players[seat].cards
		check(received.size() == 2 and (seat == client.local_seat or received == [-1, -1]), "client retains only its own private cards")
	await _finish()
