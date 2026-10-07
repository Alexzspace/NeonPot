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
var port := 27986
var checks := 0
var failures := 0
var acknowledgments: Dictionary = {}
var remote := 0
var last_theme_version := -1
var finished := false
var before: Dictionary = {}
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DECK_THEME_NETWORK %s: %s" % [role, message])
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
func gameplay(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("deck_theme")
	result.erase("deck_theme_revision")
	return result
func changed(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): return
	check(snapshot.deck_theme >= 0 and snapshot.deck_theme <= 3 and snapshot.deck_theme_revision < 999, "only valid authoritative theme received")
	if snapshot.deck_theme_revision != last_theme_version:
		last_theme_version = snapshot.deck_theme_revision
		print("DECK_THEME_EVENT theme=%d version=%d" % [snapshot.deck_theme, snapshot.deck_theme_revision])
func _run() -> void:
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.state_changed.connect(changed)
	wire = Wire.new()
	wire.name = "Wire"
	root.add_child(wire)
	wire.command_received.connect(client_command)
	wire.acknowledged.connect(func(step): acknowledgments[step] = true)
	if role == "client":
		check(session.set_deck_theme(1), "client has a different personal preference before joining")
		check(session.join_game("127.0.0.1", "Client", port) == OK, "client transport created")
		check(not session.set_deck_theme(0), "connecting client cannot override host")
		await until(func(): return finished, "protocol completed", 12000)
		_finish()
		return
	check(session.set_deck_theme(2), "host preference set before room creation")
	check(session.host_game("Host", 1000, port) == OK, "host transport created")
	print("DECK_THEME_HOST_READY")
	await until(func(): return session.state.players.size() == 2, "client registered")
	for peer in session._peer_seats:
		if peer != 1: remote = peer
	await command(1)
	check(session.deck_theme == 2, "client API and forged authority packet cannot change host theme")
	before = session.state.duplicate(true)
	check(session.set_deck_theme(3), "host changes lobby theme")
	check(gameplay(session.state) == gameplay(before), "lobby theme does not advance gameplay revision")
	await command(2)
	session.begin_hand()
	if session.state.actor == 0: session.submit_action("call")
	check(session.state.actor == 1, "real client is next actor")
	await command(3)
	var old_snapshot: Dictionary = session._snapshot_for(1)
	before = session.state.duplicate(true)
	var deck: Array = session._engine._deck.duplicate()
	check(session.set_deck_theme(0), "host changes active theme")
	check(gameplay(session.state) == gameplay(before) and session._engine._deck == deck, "active theme preserves all game values and deck order")
	# Replay a genuine older cosmetic snapshot over real reliable transport.
	session._receive_state.rpc_id(remote, old_snapshot)
	await command(4)
	await until(func(): return session.state.revision == int(before.revision) + 1, "client action stamped before theme change remains legal")
	check(session.deck_theme == 0, "stale theme replay cannot affect authority")
	check(session.set_deck_theme(1), "host remains sole theme owner after action")
	await command(5)
	check(session.state.players[1].cards == [-1, -1] and not session.state.has("deck"), "host snapshot remains recipient-private")
	await command(6)
	await until(func(): return session.state.get("paused", false), "client disconnect pauses live room")
	check(not session.set_deck_theme(3), "disconnected room cannot emit more theme updates")
	_finish()
func client_command(step: int) -> void:
	if step == 1:
		await until(func(): return not session.state.is_empty(), "client receives lobby")
		check(session.deck_theme == 2 and session.state.deck_theme == 2, "join uses current host theme over personal choice")
		before = session.state.duplicate(true)
		check(not session.set_deck_theme(0) and session.state == before, "joined client setter rejected without local mutation")
		var forged: Dictionary = session.state.duplicate(true)
		forged.deck_theme = 0
		forged.deck_theme_revision = 999
		forged.revision += 100
		session._receive_state.rpc_id(1, forged)
	elif step == 2:
		await until(func(): return session.deck_theme == 3, "lobby host choice synchronized")
		check(gameplay(session.state) == gameplay(before), "theme-only recipient snapshot keeps gameplay fields unchanged")
	elif step == 3:
		await until(func(): return session.state.hand_id == 1 and session.state.actor == 1, "client receives its actual turn")
		before = session.state.duplicate(true)
	elif step == 4:
		await until(func(): return session.deck_theme == 0, "active host choice synchronized")
		await pause(80)
		check(session.deck_theme == 0 and gameplay(session.state) == gameplay(before), "real stale snapshot is rejected without reverting cards or theme")
		session._request_action.rpc_id(1, "check" if before.legal.get("check", false) else "call", 0, before.hand_id, before.revision)
	elif step == 5:
		await until(func(): return session.deck_theme == 1, "latest host choice synchronized")
		check(not session.set_deck_theme(3) and session.deck_theme == 1, "active client still cannot change theme")
		check(session.state.players[0].cards == [-1, -1] and not session.state.has("deck"), "theme synchronization never discloses host cards")
	elif step == 6:
		wire.ack.rpc_id(1, step)
		await pause(100)
		session.leave_game()
		check(session.set_deck_theme(1), "main can restore own preference after leaving")
		finished = true
		return
	wire.ack.rpc_id(1, step)
func _finish() -> void:
	session.leave_game()
	session.queue_free()
	wire.queue_free()
	await process_frame
	print("DECK_THEME_NETWORK role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(0 if failures == 0 else 1)
