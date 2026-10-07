extends SceneTree
const Session = preload("res://scripts/table_session.gd")
const Rules = preload("res://scripts/poker_engine.gd")
const AI = preload("res://scripts/poker_ai.gd")
var checks := 0
var failures := 0
var steps := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOLO: " + why)
func _initialize() -> void:
	_run.call_deferred()
func _finish(engine) -> void:
	var guard := 0
	while engine.snapshot(0).actor >= 0 and guard < 100:
		var state: Dictionary = engine.snapshot(engine.snapshot(0).actor)
		check(engine.act(state.actor, "fold"), "fixture folds legally")
		guard += 1
func _run() -> void:
	# Every possible initial button, consecutive rotation and blind posting.
	for initial in 5:
		var engine = Rules.new()
		check(engine.configure(["A", "B", "C", "D", "E"], 1000, 5, 10, initial), "configured first dealer")
		for hand in 3:
			check(engine.start_hand(), "next hand starts")
			var state: Dictionary = engine.snapshot(0)
			var dealer := (initial + hand) % 5
			check(state.dealer == dealer and state.small_blind_seat == (dealer + 1) % 5 and state.big_blind_seat == (dealer + 2) % 5, "button SB BB advance together")
			check(state.players[state.small_blind_seat].bet == 5 and state.players[state.big_blind_seat].bet == 10 and state.actor == (dealer + 3) % 5, "blinds and preflop first action")
			_finish(engine)
	# Heads-up transition skips busted players without repeating the previous BB.
	var heads = Rules.new()
	heads.configure(["A", "B", "C"], 1000, 5, 10, 0)
	heads.start_hand()
	_finish(heads)
	heads._players[1].stack += heads._players[0].stack
	heads._players[0].stack = 0
	check(heads.start_hand(), "heads-up transition starts")
	var hs: Dictionary = heads.snapshot(0)
	check(hs.dealer == 2 and hs.small_blind_seat == 2 and hs.big_blind_seat == 1 and hs.actor == 2, "heads-up dealer posts SB and acts first; BB advances")
	heads.act(2, "call")
	heads.act(1, "check")
	check(heads.snapshot(0).actor == 1, "heads-up BB acts first after flop")
	var session = Session.new()
	root.add_child(session)
	var selected: Dictionary = {}
	check(session.ai_aggression == 6, "default aggression level six")
	session.set_ai_aggression(20)
	check(session.ai_aggression == 10 and session._solo_ai.aggression == 10, "aggression upper clamp")
	session.set_ai_aggression(-2)
	check(session.ai_aggression == 0, "aggression lower clamp")
	session.set_ai_aggression(8)
	for trial in 50:
		session._solo_rng.seed = trial + 20
		session.start_solo("Human")
		selected[session._solo_first_dealer] = true
	check(selected.size() == 5, "initial button selection reaches all five seats")
	check(session.is_solo and session.state.players.size() == 5 and session.state.you == 0, "default table human plus four bots")
	check(session.ai_aggression == 8 and session._solo_ai.aggression == 8, "new rooms retain aggression")
	session.set_local_seat(3)
	check(session.local_seat == 0, "solo cannot switch into a bot viewpoint")
	check(not session.advance_solo(), "no AI acts in lobby")
	var human_ai = AI.new()
	human_ai.rng.seed = 31
	var decisions: Dictionary = {}
	var hands := 0
	for match_index in 12:
		session.set_ai_aggression(match_index % 11)
		session.start_solo("Human", 150, 5)
		session._solo_ai.rng.seed = match_index + 40
		for hand in 8:
			if not session.state.can_start: break
			session.begin_hand()
			var guard := 0
			while session.state.actor >= 0 and guard < 150:
				var current: Dictionary = session.state
				var actor: int = current.actor
				var snap: Dictionary = session._snapshot_for(actor)
				var private_ok := true
				for other in 5:
					if other != actor: private_ok = private_ok and snap.players[other].cards == [-1, -1]
				check(private_ok and not snap.has("deck"), "policy receives only acting bot cards")
				var total := 0
				for player in current.players: total += int(player.stack) + int(player.committed)
				check(total == 750, "stack plus committed chips conserved")
				var revision: int = current.revision
				if actor == 0:
					check(not session.advance_solo(), "AI never takes human turn")
					var action: Dictionary = human_ai.choose(current)
					decisions[action.action] = true
					session.submit_action(action.action, action.amount)
				else:
					check(session.advance_solo(), "bot advances one legal action")
				check(session.state.revision == revision + 1 and session.state.you == 0, "one revision only and fixed human viewpoint")
				steps += 1
				guard += 1
			check(session.state.phase == "showdown" and guard < 150, "complete bounded hand")
			var total := 0
			for player in session.state.players: total += int(player.stack)
			check(total == 750, "settlement conserves all chips")
			hands += 1
	# Policy output is invariant to unavailable opponent cards, even if caller adds them.
	var engine = Rules.new()
	engine.configure(["A", "B", "C"], 1000)
	engine.start_hand()
	var snap: Dictionary = engine.snapshot(engine.snapshot(0).actor)
	var corrupt := snap.duplicate(true)
	for other in 3:
		if other != snap.you: corrupt.players[other].cards = [12, 25]
	var policy = AI.new()
	policy.rng.seed = 9
	var decision: Dictionary = policy.choose(snap)
	policy.rng.seed = 9
	check(policy.choose(corrupt) == decision, "AI ignores opponent hidden fields")
	session.leave_game()
	check(not session.is_solo and not session.advance_solo(), "leave cancels solo authority")
	session.start_local(["A", "B"], 1000)
	check(not session.is_solo and not session.advance_solo(), "legacy fixture cannot run bots")
	session.begin_hand()
	check(session.state.dealer == 0, "local harness retains deterministic first dealer")
	selected.clear()
	for trial in 24:
		session._lan_dealer_rng.seed = trial + 19
		check(session.host_game("Host", 1000, 27953) == OK, "LAN host starts for first-button fixture")
		# Fixture seats simulate registered peers; public-only live ENet paths run separately.
		session._names = ["Host", "Peer A", "Peer B"]
		session._connected = [true, true, true]
		session.begin_hand()
		selected[session.state.dealer] = true
		check(session.state.mode == "lan" and not session.state.players.any(func(p): return p.is_bot), "LAN remains human-only")
	check(selected.size() == 3, "LAN first dealer reaches every registered seat")
	session.leave_game()
	session.queue_free()
	await process_frame
	print("SOLO_TEST_SUMMARY checks=%d failures=%d hands=%d actions=%d" % [checks, failures, hands, steps])
	quit(1 if failures else 0)
