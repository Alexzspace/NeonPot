extends SceneTree
const Session = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SESSION_DECK_THEME: " + message)
func gameplay(snapshot: Dictionary) -> Dictionary:
	var value := snapshot.duplicate(true)
	value.erase("deck_theme")
	value.erase("deck_theme_revision")
	return value
func _run() -> void:
	var host := Session.new()
	var client := Session.new()
	root.add_child(host)
	root.add_child(client)
	client._receive_state({})
	client._receive_state({"revision": "invalid"})
	check(client.state.is_empty(), "missing or malformed gameplay revision cannot create a cosmetic room")
	check(host.deck_theme == 0 and host.set_deck_theme(3), "idle default and next-room preference accepted")
	check(not host.set_deck_theme(-1) and not host.set_deck_theme(4), "invalid theme range rejected")
	host.start_local(["Alice", "Bob"])
	check(host.state.deck_theme == 3 and host.state.deck_theme_revision == 0, "new room preserves selected theme and resets theme revision")
	var initial: Dictionary = host.state.duplicate(true)
	check(host.set_deck_theme(1), "host may change lobby theme")
	check(host.state.revision == initial.revision and host.state.deck_theme_revision == 1, "cosmetic update has separate revision")
	check(gameplay(host.state) == gameplay(initial), "lobby theme changes no lobby data")
	var emissions := [0]
	host.state_changed.connect(func(_state): emissions[0] += 1)
	check(host.set_deck_theme(1) and emissions[0] == 0, "same theme is an idempotent no-op")
	host.begin_hand()
	host.set_local_seat(host.state.actor)
	var action_revision: int = host.state.revision
	var action_hand: int = host.state.hand_id
	var deck: Array = host._engine._deck.duplicate()
	initial = host.state.duplicate(true)
	check(host.set_deck_theme(2), "host may change active theme")
	check(gameplay(host.state) == gameplay(initial) and host._engine._deck == deck, "active theme preserves cards, deck order, balances, turn, and revision")
	client._receive_state(host._snapshot_for(1))
	check(client.deck_theme == 2 and client.state.deck_theme == 2, "joining recipient gets current host theme")
	check(not client.set_deck_theme(0) and client.deck_theme == 2, "client local preference cannot change joined table")
	var private_before := gameplay(client.state)
	check(host.set_deck_theme(3), "host changes theme again without taking action")
	var updated: Dictionary = host._snapshot_for(1)
	client._receive_state(updated)
	check(client.deck_theme == 3 and gameplay(client.state) == private_before, "equal gameplay revision accepts newer cosmetic revision only")
	check(client.state.players[0].cards == [-1, -1] and not client.state.has("deck"), "theme snapshot preserves recipient privacy")
	var accepted: Dictionary = client.state.duplicate(true)
	var received := [0]
	client.state_changed.connect(func(_state): received[0] += 1)
	client._receive_state(updated)
	var bad := updated.duplicate(true)
	bad.deck_theme_revision -= 1
	bad.deck_theme = 0
	client._receive_state(bad)
	for invalid in [-1, 4, "1", 1.0]:
		bad = updated.duplicate(true)
		bad.deck_theme_revision += 20
		bad.deck_theme = invalid
		client._receive_state(bad)
	for invalid in [-1, "2", 2.0]:
		bad = updated.duplicate(true)
		bad.deck_theme_revision = invalid
		client._receive_state(bad)
	bad = updated.duplicate(true)
	bad.deck_theme_revision += 20
	bad.room_id = "old-room"
	client._receive_state(bad)
	bad.room_id = updated.room_id
	bad.hand_id -= 1
	client._receive_state(bad)
	bad.hand_id = updated.hand_id
	bad.revision -= 1
	client._receive_state(bad)
	check(client.state == accepted and received[0] == 0, "duplicate, stale, malformed, old-room and old-hand updates are rejected")
	bad = updated.duplicate(true)
	bad.deck_theme_revision += 1
	bad.deck_theme = 0
	bad.players[0].stack = 777777
	bad.players[0].cards = [50, 51]
	bad.actor = -1
	client._receive_state(bad)
	check(client.deck_theme == 0 and gameplay(client.state) == private_before, "cosmetic branch cannot replace gameplay fields even inside a malformed snapshot")
	# A pending action stamped before the host changed themes must still be valid.
	host._apply_action(host.local_seat, "check" if host.state.legal.get("check", false) else "call", 0, action_hand, action_revision, 1)
	check(host.state.revision == action_revision + 1, "pre-theme action revision remains valid")
	client._on_server_disconnected()
	check(not client.set_deck_theme(1), "disconnected client cannot change table theme")
	accepted = client.state.duplicate(true)
	bad.revision += 50
	bad.deck_theme_revision += 50
	client._receive_state(bad)
	check(client.state == accepted, "disconnect latch blocks delayed theme data")
	client.leave_game()
	check(client.set_deck_theme(1), "after leave main may restore personal preference")
	client._peer = ENetMultiplayerPeer.new()
	check(not client.set_deck_theme(2), "connecting client cannot override a pending host selection")
	client.leave_game()
	host.leave_game()
	host.start_solo("Solo")
	host.begin_hand()
	check(host.set_deck_theme(0) and host.state.deck_theme == 0, "solo active table supports theme changes")
	host.leave_game()
	host.queue_free()
	client.queue_free()
	await process_frame
	print("SESSION_DECK_THEME checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
