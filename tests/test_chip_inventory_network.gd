extends SceneTree
const Session = preload("res://scripts/table_session.gd")
const Inventory = preload("res://scripts/chip_inventory.gd")
class Wire extends Node:
	signal command_received(step: int, expected: Dictionary)
	signal acknowledged(step: int)
	@rpc("authority", "call_remote", "reliable")
	func command(step: int, expected: Dictionary) -> void: command_received.emit(step, expected)
	@rpc("any_peer", "call_remote", "reliable")
	func ack(step: int) -> void: acknowledged.emit(step)
var session
var wire: Wire
var role := "host"
var port := 27987
var dealer := 0
var checks := 0
var failures := 0
var acknowledgments := {}
var remote := 0
var finished := false
var before := {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--dealer="): dealer = int(arg.trim_prefix("--dealer="))
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHIP_INVENTORY_NETWORK %s: %s" % [role, message])
func pause(milliseconds: int) -> void:
	await create_timer(milliseconds / 1000.0).timeout
func until(predicate: Callable, message: String, milliseconds: int = 4000) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while not predicate.call() and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(predicate.call(), message)
func public_inventory(snapshot: Dictionary) -> Dictionary:
	var result := {"revision": snapshot.revision, "pot_chips": snapshot.pot_chips, "players": [], "transfers": snapshot.chip_transfers}
	for player in snapshot.players: result.players.append(player.chips)
	return result
func command(step: int) -> void:
	wire.command.rpc_id(remote, step, public_inventory(session.state))
	await until(func(): return acknowledgments.has(step), "client step %d completed" % step)
func _run() -> void:
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
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
	print("CHIP_INVENTORY_HOST_READY")
	await until(func(): return session.state.players.size() == 2, "client registered")
	for peer in session._peer_seats:
		if peer != 1: remote = peer
	# Test-only seed selection covers both randomized heads-up dealer orders.
	var probe := RandomNumberGenerator.new()
	for fixture_seed in range(100):
		probe.seed = fixture_seed
		if probe.randi_range(0, 1) == dealer:
			session._lan_dealer_rng.seed = fixture_seed
			break
	session.begin_hand()
	check(int(session.state.dealer) == dealer, "requested dealer fixture selected")
	if session.state.actor == 0: session.submit_action("call")
	check(session.state.actor == 1, "real remote client owns turn")
	before = session.state.duplicate(true)
	await command(1)
	check(session.state == before, "forged count/denomination/negative/stale requests caused no mutation")
	await command(2)
	await until(func(): return session.state.revision == int(before.revision) + 1, "real exchange RPC accepted once")
	var expected := Inventory.add(Inventory.balanced(Inventory.value(Inventory.subtract(before.players[1].chips, {"10": 3}))), {"10": 3})
	check(session.state.players[1].chips == expected, "host preserves pending selected chips exactly during exchange")
	check(session.state.pot_chips == before.pot_chips and session.state.players[0].chips == before.players[0].chips, "exchange leaves pot and opponent untouched")
	check(session.state.chip_transfers.is_empty(), "exchange publishes no stale movement")
	before = session.state.duplicate(true)
	await command(3)
	await until(func(): return session.state.revision == int(before.revision) + 1, "real manual raise accepted once")
	check(session.state.pot_chips == Inventory.add(before.pot_chips, {"10": 3}), "manual denominations entered pot without conversion")
	check(session.state.players[1].chips == Inventory.subtract(before.players[1].chips, {"10": 3}), "manual payment removes chosen inventory only")
	check(session.state.chip_transfers == [{"seat": 1, "chips": {"10": 3}, "kind": "bet"}], "wire publishes exact one-shot movement")
	before = session.state.duplicate(true)
	await command(4)
	check(session.state == before, "duplicate/stale manual and out-of-turn exchange rejected")
	check(session.state.players[1].cards == [-1, -1] and not session.state.has("deck") and not session.state.has("seed"), "host recipient snapshot remains private")
	session.submit_action("call")
	if session.state.actor == 0: session.submit_action("check")
	check(session.state.actor == 1, "client gets next street turn after host checks if needed")
	var check_revision: int = session.state.revision
	await command(5)
	await until(func(): return session.state.revision == check_revision + 1, "remote zero-payment check accepted")
	check(session.state.chip_transfers.is_empty(), "check clears transfers instead of replaying previous movement")
	await command(6)
	await until(func(): return session.state.get("paused", false), "client disconnect pauses table")
	_finish()
func client_command(step: int, expected: Dictionary) -> void:
	await until(func(): return not session.state.is_empty() and int(session.state.revision) >= int(expected.revision), "authoritative state arrived before step")
	check(public_inventory(session.state) == expected, "client and host inventories/transfers identical step %d" % step)
	check(session.state.players[0].cards == [-1, -1] and not session.state.has("deck") and not session.state.has("seed"), "inventory update does not disclose opponent cards")
	if step == 1:
		before = session.state.duplicate(true)
		for forged in [{"500": 999}, {"25": 2}, {"50": -1}, {"10": 1.5}]:
			session._request_chip_action.rpc_id(1, forged, before.hand_id, before.revision)
		session._request_chip_action.rpc_id(1, {"10": 3}, int(before.hand_id) - 1, before.revision)
		session._request_chip_exchange.rpc_id(1, {}, before.hand_id, int(before.revision) - 1)
		await pause(120)
		check(session.state == before, "rejected RPCs do not emit changed client state")
	elif step == 2:
		session.exchange_chips({"10": 3})
		await until(func(): return session.state.revision > int(expected.revision), "client receives exchange acknowledgment")
	elif step == 3:
		before = session.state.duplicate(true)
		session.submit_chip_action({"10": 3})
		await until(func(): return session.state.revision > int(expected.revision), "client receives manual raise acknowledgment")
	elif step == 4:
		session._request_chip_action.rpc_id(1, {"10": 3}, before.hand_id, before.revision)
		session.exchange_chips({})
		await pause(120)
		check(public_inventory(session.state) == expected, "old action and out-of-turn exchange leave client unchanged")
	elif step == 5:
		check(session.state.legal.get("check", false), "client can check next street")
		session.submit_action("check")
		await until(func(): return session.state.revision > int(expected.revision), "client receives check acknowledgment")
	elif step == 6:
		wire.ack.rpc_id(1, step)
		await pause(100)
		session.leave_game()
		finished = true
		return
	wire.ack.rpc_id(1, step)
func _finish() -> void:
	session.leave_game()
	session.queue_free()
	wire.queue_free()
	await process_frame
	print("CHIP_INVENTORY_NETWORK role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(0 if failures == 0 else 1)
