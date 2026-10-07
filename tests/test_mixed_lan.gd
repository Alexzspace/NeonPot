extends SceneTree
const Session = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0

class Probe extends Session:
	func _publish() -> void:
		_revision += 1
		state = _snapshot_for(local_seat)
		state_changed.emit(state.duplicate(true))

class BotProbe extends RefCounted:
	var received: Array = []
	var aggression := 6
	func choose(snapshot: Dictionary) -> Dictionary:
		received.append(snapshot.duplicate(true))
		return {"action": "check" if snapshot.legal.check else "call", "amount": 0}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIXED_LAN: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _fixture_human(session, peer: int, player_name: String) -> void:
	session._peer_seats[peer] = session._names.size()
	session._names.append(player_name)
	session._connected.append(true)
	session._publish()

func _run() -> void:
	var session := Probe.new()
	root.add_child(session)
	check(not session.add_bot() and not session.remove_bot(0) and not session.set_bot_aggression(0, 5), "unseated cannot manage bots")
	check(session.host_game("Table Host", 1000, 27961) == OK, "single-player room starts")
	check(session.state.players.size() == 1 and not session.state.can_start and not session.is_bot_turn() and not session.advance_bots(), "single-person lobby remains idle without division or bot work")
	check(session.host_name == "Table Host" and session.state.room_name == "Table Host" and session.host_port == 27961, "host room metadata is public")
	check(not session.add_bot(-1) and not session.add_bot(11), "invalid aggression rejected")
	check(session.add_bot(2), "host adds first bot")
	_fixture_human(session, 20, "Human B")
	check(session.add_bot(8), "host adds second independently tuned bot")
	_fixture_human(session, 30, "Human C")
	check(session.state.players[1].ai_aggression == 2 and session.state.players[3].ai_aggression == 8 and session.state.players[2].ai_aggression == -1, "individual bot settings coexist with human seats")
	var other_policy = session._bot_policies[3]
	check(session.remove_bot(1), "host removes bot in front of seated humans")
	check(session._peer_seats[20] == 1 and session._peer_seats[30] == 3 and session._bot_policies[2] == other_policy, "compaction preserves human identities and remaining policy")
	session._on_peer_disconnected(20)
	check(not session.state.paused and session._peer_seats[30] == 2 and session.state.players.size() == 3, "lobby human disconnect frees a seat without pausing")
	check(session.state.players[1].is_bot and session.state.players[1].ai_aggression == 8 and session._bot_policies[1] == other_policy, "bot settings follow their shifted seat")
	check(session.add_bot(4), "new bot occupies a free seat")
	_fixture_human(session, 40, "Human B returned")
	check(session.state.players.size() == 5 and session.state.players[2].name == "Human C" and session._peer_seats[30] == 2, "joining human appends without evicting anybody")
	check(session.add_bot() and not session.add_bot(), "six total seats is a hard limit")
	check(session.remove_bot(5), "remove extra bot")
	check(not session.remove_bot(0) and not session.remove_bot(2) and not session.set_bot_aggression(2, 9), "human seats cannot be removed or converted by bot APIs")
	check(session.set_bot_aggression(1, 10) and not session.set_bot_aggression(1, 99), "host tunes an existing bot in lobby with validated level")
	check(session._bot_policies[1].aggression == 10 and session._bot_policies[3].aggression == 4, "changing one bot does not change the other")
	var before := session.state.duplicate(true)
	session.is_host = false
	check(not session.add_bot() and not session.remove_bot(1) and not session.set_bot_aggression(1, 0), "client cannot change mixed table settings")
	check(session.state == before, "unauthorized configuration attempts are side-effect free")
	session.is_host = true
	var first := BotProbe.new()
	var second := BotProbe.new()
	session._bot_policies[1] = first
	session._bot_policies[3] = second
	session.begin_hand()
	check(not session.add_bot() and not session.remove_bot(1) and not session.set_bot_aggression(1, 0), "first deal locks every lobby setting")
	var client := Probe.new()
	root.add_child(client)
	var guard := 0
	while session.state.actor >= 0 and guard < 100:
		var actor: int = session.state.actor
		var revision: int = session.state.revision
		var hand: int = session.state.hand_id
		var own: Dictionary = session._snapshot_for(actor)
		client._receive_state(session._snapshot_for(2))
		check(not client.advance_bots(), "client cannot execute host-side policies")
		if session.is_bot_turn():
			check(client.is_bot_turn(), "clients can display the authoritative bot turn")
			session._apply_action(actor, "all_in", 0, hand, revision, 1)
			session._apply_action(actor, "all_in", 0, hand, revision, 30)
			check(session.state.revision == revision, "neither host-human nor remote-human path may impersonate a bot")
			check(session.advance_bots(), "host advances exactly one legal bot action")
		else:
			check(not session.advance_bots(), "bot runner cannot act for a human")
			session._apply_action(actor, "fold", 0, hand, revision, 999)
			check(session.state.revision == revision, "unknown human sender rejected at mutation boundary")
			var peer_id := 1 if actor == 0 else (30 if actor == 2 else 40)
			session._apply_action(actor, "check" if own.legal.check else "call", 0, hand, revision, peer_id)
		check(session.state.revision == revision + 1 and session.state.you == 0, "one action per advance and fixed host private view")
		guard += 1
	check(session.state.phase == "showdown" and session.state.board.size() == 5 and guard < 100, "three humans and two bots complete all streets")
	var total := 0
	for player in session.state.players: total += int(player.stack)
	check(total == 5000, "mixed showdown preserves total chips")
	for policy in [first, second]:
		check(not policy.received.is_empty(), "both bot policies independently act")
		for snapshot in policy.received:
			check(not snapshot.has("deck") and snapshot.players[snapshot.you].cards[0] >= 0, "bot receives its own real private cards without deck")
			for seat in snapshot.players.size():
				if seat != snapshot.you: check(snapshot.players[seat].cards == [-1, -1], "bot never receives another player's hidden cards")
	check(not session.remove_bot(1) and not session.set_bot_aggression(1, 0), "showdown does not unlock the original roster")
	session._on_peer_disconnected(30)
	check(session.state.paused and session.state.players.size() == 5 and not session.advance_bots(), "in-game disconnect pauses safely and preserves seats")
	session.leave_game()
	check(session._bot_policies.is_empty() and session._bot_levels.is_empty() and session.host_name.is_empty() and session.host_port == 0, "leave clears all room-owned bot work and metadata")
	session.queue_free()
	client.queue_free()
	await process_frame
	print("MIXED_LAN_SUMMARY checks=%d failures=%d actions=%d" % [checks, failures, guard])
	quit(1 if failures else 0)
