extends SceneTree
const Session = preload("res://scripts/table_session.gd")
var role := "host"
var port := 27962
var session
var control
var checks := 0
var failures := 0
var started_at := 0
var finishing := false
var saw_full_lobby := false
var saw_departure := false
var rejoined := false
var beginning := false
var attacked := false
var attack_revision := -1
var attacks_passed := false
var seen_revision := -1
var completed_hand := false
var next_bot_at := 0

class Coordination extends Node:
	signal command(message: String)
	var reports: Dictionary = {}
	@rpc("any_peer", "call_remote", "reliable")
	func report(revision: int) -> void:
		reports[multiplayer.get_remote_sender_id()] = revision
	@rpc("authority", "call_remote", "reliable")
	func instruct(message: String) -> void:
		command.emit(message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIXED_NETWORK %s: %s" % [role, label])

func _run() -> void:
	started_at = Time.get_ticks_msec()
	control = Coordination.new()
	control.name = "Coordination"
	root.add_child(control)
	control.command.connect(_command)
	session = Session.new()
	session.name = "Session"
	root.add_child(session)
	session.state_changed.connect(_observe)
	if role == "host":
		check(session.host_game("Host", 1000, port) == OK, "host opens room")
		check(session.state.players.size() == 1 and not session.state.can_start, "initial single-person lobby is responsive")
		check(session.add_bot(2) and session.add_bot(8), "host adds two individually configured bots")
		print("MIXED_HOST_READY")
	else:
		check(session.join_game("127.0.0.1", "Client A" if role == "client_a" else "Client B", port) == OK, "human client connects")

func _observe(state: Dictionary) -> void:
	if state.is_empty(): return
	check(state.room_name == "Host" and state.host_port == port, "metadata agrees across clients")
	if state.players.size() == 5 and state.phase == "lobby": saw_full_lobby = true
	if state.phase != "lobby":
		check(state.players.size() == 5 and state.players[1].is_bot and state.players[2].is_bot and not state.players[3].is_bot and not state.players[4].is_bot, "same three-human two-bot roster everywhere")
		check(state.players[1].ai_aggression == 3 and state.players[2].ai_aggression == 9, "each bot setting replicated separately")
		if state.phase != "showdown":
			for seat in 5:
				if seat != state.you: check(state.players[seat].cards == [-1, -1], "no human or bot private cards leaked to another seat")
			check(not state.has("deck") and state.players[state.you].cards[0] >= 0, "recipient gets only own private cards")
		else:
			completed_hand = true
			check(state.board.size() == 5, "real mixed hand reaches five-card showdown")
			var total := 0
			for player in state.players: total += int(player.stack)
			check(total == 5000, "mixed hand chip conservation on every peer")
	if role != "host":
		check(state.players[state.you].name == ("Client A" if role == "client_a" else "Client B"), "sender stays bound to their human seat after lobby compaction")

func _process(_delta: float) -> bool:
	if finishing or session == null: return false
	if Time.get_ticks_msec() - started_at > 20000:
		check(false, "mixed network timeout")
		_finish()
		return false
	var state: Dictionary = session.state
	if state.is_empty(): return false
	if state.paused:
		check(completed_hand and not session.advance_bots() and not session.add_bot(), "disconnect pauses bots and locks roster after the complete hand")
		_finish()
		return false
	if state.phase == "lobby":
		if role == "client_a" and state.players.size() == 5 and not rejoined:
			rejoined = true
			_rejoin.call_deferred()
		if role == "host":
			if saw_full_lobby and not session._names.has("Client A"):
				saw_departure = true
				check(state.players.size() == 4 and not state.paused and state.players[3].name == "Client B", "one human leaves lobby without displacing remaining players")
			if saw_departure and state.players.size() == 5 and not beginning:
				beginning = true
				check(state.players[3].name == "Client B" and state.players[4].name == "Client A", "returning player appends to vacant capacity")
				check(session.set_bot_aggression(1, 3) and session.set_bot_aggression(2, 9), "host configures independent levels before dealing")
				session.begin_hand()
		return false
	if state.phase == "showdown":
		if role == "host" and not attacked:
			attacked = true
			check(attacks_passed, "bot permission attacks were tested during actual play")
			control.instruct.rpc_id(_peer_named("Client A"), "finish")
		return false
	if session.is_bot_turn():
		if role != "host" and not attacked:
			attacked = true
			var before: Dictionary = state.duplicate(true)
			check(not session.add_bot() and not session.remove_bot(1) and not session.set_bot_aggression(1, 10) and not session.advance_bots(), "client cannot manage or drive host bots")
			var rpc_config: Dictionary = session.get_script().get_rpc_config()
			check(not rpc_config.has("set_bot_aggression") and not rpc_config.has("add_bot") and not rpc_config.has("remove_bot") and not rpc_config.has("advance_bots"), "bot control methods are absent from the network RPC surface")
			check(session.state == before, "rejected client bot settings leave state unchanged")
			# A real wire request sent on the bot's turn still authenticates as this human.
			session._request_action.rpc_id(1, "all_in", 0, state.hand_id, state.revision)
			control.report.rpc_id(1, state.revision)
		if role == "host":
			if not attacks_passed:
				if attack_revision < 0: attack_revision = state.revision
				if control.reports.size() < 2: return false
				check(session.state.revision == attack_revision and control.reports.values().all(func(value): return value == attack_revision), "both real human RPC attempts cannot advance a bot turn")
				check(state.players[1].ai_aggression == 3 and state.players[2].ai_aggression == 9, "client attempts cannot change host bot settings")
				attacks_passed = true
			if Time.get_ticks_msec() >= next_bot_at:
				check(session.advance_bots(), "host executes a real AI decision from its own snapshot")
				next_bot_at = Time.get_ticks_msec() + 30
		return false
	if state.actor == state.you and state.revision != seen_revision:
		seen_revision = state.revision
		session.submit_action("check" if state.legal.check else "call")
	return false

func _peer_named(player_name: String) -> int:
	for peer_id in session._peer_seats:
		if session._names[session._peer_seats[peer_id]] == player_name: return peer_id
	return -1

func _rejoin() -> void:
	session.leave_game()
	await create_timer(0.22).timeout
	if not finishing: check(session.join_game("127.0.0.1", "Client A", port) == OK, "departed human can rejoin the still-open lobby")

func _command(message: String) -> void:
	if message == "finish":
		check(completed_hand, "departing client observed its final hand")
		_finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	session.leave_game()
	session.queue_free()
	control.queue_free()
	await process_frame
	print("MIXED_NETWORK_SUMMARY role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)
