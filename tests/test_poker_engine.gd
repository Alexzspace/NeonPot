extends SceneTree

const EngineScript = preload("res://scripts/poker_engine.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	_test_ranking()
	_test_configuration_and_blinds()
	_test_betting_and_privacy()
	_test_short_all_ins()
	_test_side_pots()
	_test_shuffle()
	_test_random_hands()
	print("POKER_ENGINE_TEST_SUMMARY assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("TEST FAILED: " + message)


func _engine(count: int = 3, stack: int = 1000):
	var engine = EngineScript.new()
	var names: Array = []
	for index in range(count):
		names.append("Seat %d" % index)
	_expect(engine.configure(names, stack), "valid configuration")
	return engine


func _cards(text: String) -> Array:
	var cards: Array = []
	for token in text.split(" ", false):
		cards.append("cdhs".find(token[1]) * 13 + "23456789TJQKA".find(token[0]))
	return cards


func _test_ranking() -> void:
	var engine = _engine()
	var hands: Array = ["Ac Kd 9h 6s 3c", "Ac Ad Kh 6s 3c", "Ac Ad Kh Ks 3c",
		"Ac Ad Ah 6s 3c", "2c 3d 4h 5s 6c", "Ac Jc 9c 6c 3c",
		"Ac Ad Ah Ks Kc", "Ac Ad Ah As 3c", "9c Tc Jc Qc Kc"]
	var previous := -1
	for category in range(hands.size()):
		var score: int = engine._evaluate(_cards(hands[category]))
		_expect(score > previous, "category strictly increases %d" % category)
		_expect(int(score / 759375) == category, "correct category %d" % category)
		previous = score
	_expect(engine._evaluate(_cards("Ac 2d 3h 4s 5c")) == engine._score(4, [5]), "ace-low wheel")
	_expect(engine._evaluate(_cards("Ac 2d 3h 4s 5c")) < engine._evaluate(_cards("2c 3d 4h 5s 6c")), "wheel below six straight")
	_expect(engine._evaluate(_cards("Ac Kd Qh Js 2c")) < engine._score(1, [2]), "ace does not wrap JQKA2")
	_expect(engine._evaluate(_cards("Ac Ad Ah Kc Kd Kh 2s")) == engine._score(6, [14, 13]), "two trips choose ace full house")
	_expect(engine._evaluate(_cards("Ac Ad Kc Kd Qc Qd 2s")) == engine._score(2, [14, 13, 12]), "three pairs select best two plus kicker")
	_expect(engine._evaluate(_cards("Ac Jc 9c 6c 3c Kd 2c")) == engine._score(5, [14, 11, 9, 6, 3]), "best five flush cards")
	_expect(engine._evaluate(_cards("Ac Ad Kh Qs 3c")) > engine._evaluate(_cards("Ah As Kd Js 9c")), "pair second kicker comparison")
	_expect(engine._evaluate(_cards("Ac Ad Kh Ks 3c")) > engine._evaluate(_cards("Ah As Qd Qs Jc")), "two pair lower pair comparison")
	_expect(engine._evaluate(_cards("Ac Ad Kh Qs 3c")) == engine._evaluate(_cards("Ah As Kd Qc 3s")), "suit does not break ties")
	_expect(engine._evaluate(_cards("Ac Kc Qc Jc Tc 2d 2s")) == engine._score(8, [14]), "seven-card royal flush")


func _test_configuration_and_blinds() -> void:
	var engine = EngineScript.new()
	_expect(not engine.configure(["A"], 100), "reject single seat")
	_expect(not engine.configure(["A", "B"], 0), "reject empty stack")
	_expect(not engine.configure(["A", "B"], 100, 10, 5), "reject inverted blinds")
	_expect(not engine.configure(["A", " "], 100), "reject blank name")
	_expect(not engine.start_hand(), "reject unconfigured game")
	engine = _engine(2)
	_expect(engine.start_hand(), "heads-up starts")
	var state: Dictionary = engine.snapshot(0)
	_expect(state.dealer == 0 and state.actor == 0, "heads-up dealer acts preflop first")
	_expect(state.players[0].bet == 5 and state.players[1].bet == 10, "heads-up dealer posts small blind")
	_expect(not engine.start_hand(), "cannot redeal mid-hand")
	_expect(not engine.configure(["X", "Y"], 100), "cannot reset chips mid-hand")
	_expect(engine.act(0, "call"), "small blind calls")
	_expect(engine.snapshot(1).actor == 1, "big blind retains option")
	_expect(engine.act(1, "check"), "big blind checks")
	state = engine.snapshot(1)
	_expect(state.phase == "flop" and state.actor == 1, "heads-up nonbutton acts first after flop")
	_expect(engine.act(1, "fold"), "uncontested fold")
	_expect(engine.start_hand(), "second hand")
	state = engine.snapshot(0)
	_expect(state.dealer == 1 and state.actor == 1, "button rotates")
	_expect(state.players[1].bet == 5 and state.players[0].bet == 10, "blinds rotate")
	engine = _engine(3)
	_expect(engine.start_hand(), "three-player hand")
	state = engine.snapshot(0)
	_expect(state.dealer == 0 and state.actor == 0, "three-player UTG is dealer")
	_expect(state.players[1].bet == 5 and state.players[2].bet == 10, "three-player blinds")
	engine = _engine(2, 3)
	_expect(engine.start_hand(), "short blind hand starts")
	state = engine.snapshot(0)
	_expect(state.phase == "showdown" and state.board.size() == 5, "all-in blinds auto runout")
	_expect(_stack_total(state) == 6, "short blinds conserve chips")
	engine = _engine(2, 20)
	engine._players[1].stack = 3
	_expect(engine.start_hand(), "one short blind starts")
	state = engine.snapshot(0)
	_expect(state.phase == "showdown", "funded small blind need not call phantom nominal big blind")
	_expect(state.pot == 6 and _stack_total(state) == 23, "uncalled blind refunded")
	engine = _engine(3, 20)
	engine._players[2].stack = 3
	_expect(engine.start_hand(), "multiway short big blind starts")
	_expect(engine.snapshot(0).legal.call_amount == 10, "short big blind preserves full multiway bring-in")
	engine = _engine(3)
	_expect(engine.start_hand(), "start three-to-two transition fixture")
	_expect(engine.act(0, "fold"), "button folds in transition fixture")
	_expect(engine.act(1, "fold"), "small blind folds in transition fixture")
	engine._players[0].stack = 0
	_expect(engine.start_hand(), "start heads-up after former button busts")
	state = engine.snapshot(1)
	_expect(state.dealer == 2 and state.players[1].bet == 10, "heads-up transition avoids same big blind twice")
	_expect(state.players[0].folded and state.players[0].cards == [-1, -1], "busted seat sits out without cards")
	engine = _engine(2)
	engine._players[0].stack = 0
	var unchanged: Dictionary = engine.snapshot(1)
	_expect(not engine.start_hand(), "one funded player cannot start hand")
	_expect(engine.snapshot(1) == unchanged, "failed start leaves game unchanged")


func _test_betting_and_privacy() -> void:
	var engine = _engine(3)
	_expect(engine.start_hand(), "start privacy hand")
	var before: Dictionary = engine.snapshot(0)
	_expect(before.players[0].cards[0] >= 0, "own cards visible")
	_expect(before.players[1].cards == [-1, -1] and before.players[2].cards == [-1, -1], "opponent cards hidden")
	_expect(engine.snapshot(-1).players[0].cards == [-1, -1], "spectator has no private cards")
	_expect(not before.has("deck") and not before.has("odds") and not before.has("hand_rank"), "no private deck or assistance")
	_expect(not engine.act(1, "call"), "out-of-turn action rejected")
	_expect(not engine.act(0, "check"), "cannot check facing blind")
	_expect(not engine.act(0, "raise", 19), "reject undersized non-all-in raise")
	_expect(not engine.act(0, "raise", 1001), "cannot raise above stack")
	_expect(not engine.act(0, "dance"), "reject unknown action")
	_expect(engine.snapshot(0) == before, "invalid actions leave state unchanged")
	var altered := engine.snapshot(0)
	altered.players[0].cards[0] = -20
	altered.players[1].stack = 999999
	altered.board.append(51)
	_expect(engine.snapshot(0) == before, "snapshot deeply detached from engine")
	_expect(engine.act(0, "raise", 30), "legal raise to total 30")
	var state: Dictionary = engine.snapshot(1)
	_expect(state.current_bet == 30 and state.min_raise_to == 50, "raise increments determine next min")
	_expect(state.players[0].stack == 970 and state.players[0].bet == 30, "raise is total street commitment")
	_expect(engine.act(1, "fold"), "first fold")
	_expect(engine.act(2, "fold"), "second fold awards pot")
	state = engine.snapshot(1)
	_expect(state.phase == "showdown" and state.actor == -1, "uncontested hand ends")
	_expect(state.pot == 25 and state.result == [{"seat": 0, "amount": 25}], "uncalled 20 refunded, award contested 25")
	_expect(state.players[0].cards == [-1, -1], "uncontested winner does not reveal cards")
	_expect(_stack_total(state) == 3000, "uncontested conservation")
	_expect(state.players[0].stack == 1015, "winner gains other blind chips")
	_expect(not engine.act(0, "all_in"), "cannot act after settlement")
	altered = engine.snapshot(0)
	altered.result[0].amount = 123456
	_expect(engine.snapshot(0).result[0].amount == 25, "settlement snapshot detached")
	engine = _engine(3)
	_expect(engine.start_hand(), "start complete four-street hand")
	_expect(engine.act(0, "call"), "UTG calls")
	_expect(engine.act(1, "call"), "small blind completes")
	_expect(engine.act(2, "check"), "big blind option check")
	for expected_phase in ["flop", "turn", "river"]:
		state = engine.snapshot(1)
		_expect(state.phase == expected_phase and state.actor == 1, "small blind acts first on " + expected_phase)
		_expect(state.current_bet == 0 and state.min_raise_to == 10, "street bet resets on " + expected_phase)
		_expect(state.players[0].bet == 0 and state.players[0].committed == 10, "street and whole-hand contributions separated")
		_expect(engine.act(1, "check") and engine.act(2, "check") and engine.act(0, "check"), "all players check " + expected_phase)
	state = engine.snapshot(0)
	_expect(state.phase == "showdown" and state.board.size() == 5, "river checkdown reaches showdown")
	_expect(_stack_total(state) == 3000 and state.pot == 30, "checkdown pot and conservation")
	var dealt: Array = state.board.duplicate()
	for player in state.players:
		dealt.append_array(player.cards)
	var unique: Dictionary = {}
	for card in dealt:
		unique[card] = true
	_expect(dealt.size() == 11 and unique.size() == 11 and not unique.has(-1), "checkdown reveals distinct cards to all seats")


func _betting_fixture(stacks: Array):
	# Explicit host-only fixtures: no fixed-deck or stack-injection production API.
	var engine = _engine(stacks.size())
	_expect(engine.start_hand(), "fixture starts with secure deck")
	engine._phase = "flop"
	engine._board = _cards("2c 7d Jh")
	engine._current_bet = 0
	engine._last_full_raise = 100
	engine._big_blind = 100
	engine._pending = range(stacks.size())
	engine._acted_at.fill(-1)
	engine._actor = 0
	for seat in range(stacks.size()):
		engine._players[seat].stack = int(stacks[seat])
		engine._players[seat].bet = 0
		engine._players[seat].committed = 0
		engine._players[seat].folded = false
		engine._players[seat].all_in = false
	return engine


func _test_short_all_ins() -> void:
	var engine = _betting_fixture([1000, 150, 1000])
	_expect(engine.act(0, "raise", 100), "opening bet")
	_expect(engine.act(1, "all_in"), "short all-in accepted")
	_expect(engine.snapshot(2).legal.raise, "unacted player can raise over short all-in")
	_expect(engine.snapshot(2).min_raise_to == 250, "short all-in does not shrink min raise")
	_expect(engine.act(2, "call"), "unacted player calls")
	var state: Dictionary = engine.snapshot(0)
	_expect(state.actor == 0 and state.legal.call_amount == 50, "original bettor owes short increase")
	_expect(not state.legal.raise and not state.legal.all_in, "single short raise does not reopen original bettor")
	_expect(not engine.act(0, "raise", 250), "closed raise rejected")
	_expect(engine.act(0, "call"), "original bettor may call")
	_expect(engine.snapshot(0).phase == "turn", "matched short all-in advances street")
	engine = _betting_fixture([1000, 150, 200, 1000])
	_expect(engine.act(0, "raise", 100), "cumulative opening")
	_expect(engine.act(1, "all_in"), "first short increment")
	_expect(engine.act(2, "all_in"), "second short increment")
	_expect(engine.act(3, "call"), "fourth player calls")
	state = engine.snapshot(0)
	_expect(state.legal.raise and state.legal.all_in, "cumulative short raises reopen at full increment")
	_expect(state.min_raise_to == 300, "cumulative reopening uses last full raise")
	_expect(engine.act(0, "raise", 300), "reopened player raises")
	_expect(engine.snapshot(3).legal.raise, "subsequent full raise reopens caller")
	engine = _betting_fixture([1000, 150, 1000, 200, 1000])
	_expect(engine.act(0, "raise", 100), "per-seat opening")
	_expect(engine.act(1, "all_in"), "per-seat short one")
	_expect(engine.act(2, "call"), "middle caller at 150")
	_expect(engine.act(3, "all_in"), "per-seat short two")
	_expect(engine.act(4, "call"), "last caller at 200")
	_expect(engine.snapshot(0).legal.raise, "original bettor faces cumulative 100")
	_expect(engine.act(0, "call"), "original bettor elects call")
	_expect(not engine.snapshot(2).legal.raise, "middle caller faces only 50 and remains closed")
	engine = _betting_fixture([1000, 199, 1000])
	_expect(engine.act(0, "raise", 100), "boundary opening")
	_expect(engine.act(1, "all_in"), "boundary 99 short raise")
	_expect(engine.act(2, "call"), "boundary call")
	_expect(not engine.snapshot(0).legal.raise, "one chip below full raise does not reopen")
	engine = _betting_fixture([1000, 50, 1000])
	_expect(engine.act(0, "check"), "checker before underbet")
	_expect(engine.act(1, "all_in"), "opening all-in below minimum bet")
	_expect(engine.snapshot(2).legal.min_raise_to == 150, "unacted full raise over underbet adds full minimum")
	_expect(engine.act(2, "call"), "underbet call")
	_expect(not engine.snapshot(0).legal.raise, "checker facing less than full bet is not reopened")
	engine = _engine(2, 100)
	_expect(engine.start_hand(), "all-in hand")
	_expect(engine.act(0, "all_in"), "first shove")
	_expect(engine.act(1, "call"), "second calls all-in")
	state = engine.snapshot(0)
	_expect(state.phase == "showdown" and state.board.size() == 5, "all-in action automatically runs five board cards")
	_expect(state.players[1].cards[0] >= 0, "contested showdown exposes live cards")
	_expect(_stack_total(state) == 200, "all-in settlement conserves chips")


func _showdown_fixture(contributions: Array, hands: Array, board: String, folded: Array = []):
	var engine = _engine(contributions.size())
	engine._board = _cards(board)
	engine._phase = "river"
	engine._dealer = 0
	for seat in range(contributions.size()):
		engine._players[seat].committed = contributions[seat]
		engine._players[seat].stack = 0
		engine._players[seat].cards = _cards(hands[seat])
		engine._players[seat].folded = folded.has(seat)
	engine._finish_showdown()
	return engine


func _test_side_pots() -> void:
	var engine = _showdown_fixture([100, 200, 300], ["Ac Ad", "Kc Kd", "Qc Qd"], "2c 4d 7h 9s Jc")
	var state: Dictionary = engine.snapshot(0)
	_expect(state.players[0].stack == 300, "short strongest stack wins main pot")
	_expect(state.players[1].stack == 200, "second strongest wins side pot")
	_expect(state.players[2].stack == 100, "unique excess is returned")
	_expect(state.pot == 500 and _stack_total(state) == 600, "side pot settlement excludes uncalled excess")
	engine = _showdown_fixture([100, 200, 200], ["Ac Ad", "Kc Kd", "Qc Qd"], "2c 4d 7h 9s Jc", [0])
	state = engine.snapshot(1)
	_expect(state.players[1].stack == 500 and state.players[0].stack == 0, "folded best hand cannot win any pot")
	_expect(state.players[0].cards == [-1, -1], "folded cards stay private at showdown")
	engine = _showdown_fixture([101, 101, 101], ["Ac Kd", "Ah Ks", "Qh Jd"], "2c 4d 7h 9s Tc")
	state = engine.snapshot(0)
	_expect(state.players[0].stack == 151 and state.players[1].stack == 152, "odd chip goes first tied seat clockwise after button")
	_expect(_stack_total(state) == 303, "odd-chip tie conserves all chips")
	engine = _showdown_fixture([100, 200, 200], ["2c 3d", "4c 5d", "6c 7d"], "Tc Jc Qc Kc Ac")
	state = engine.snapshot(0)
	_expect(state.players[0].stack == 100 and state.players[1].stack == 200 and state.players[2].stack == 200, "board plays equally for main and side pots")
	engine = _showdown_fixture([50, 100, 150, 150], ["Ac Ad", "Kc Kd", "Qc Qd", "Jc Jd"], "2c 4d 7h 9s Th")
	state = engine.snapshot(0)
	_expect(state.players[0].stack == 200 and state.players[1].stack == 150 and state.players[2].stack == 100, "three contribution tiers resolve independently")
	_expect(_stack_total(state) == 450, "multiple side pots conserve chips")


func _test_shuffle() -> void:
	var engine = _engine()
	var seen: Dictionary = {}
	for _trial in range(100):
		var deck: Array = engine._shuffled_deck()
		_expect(deck.size() == 52, "secure deck has 52 cards")
		var sorted := deck.duplicate()
		sorted.sort()
		_expect(sorted == range(52), "every shuffled card occurs exactly once")
		seen[str(deck)] = true
	_expect(seen.size() == 100, "secure shuffle differs across 100 decks")
	for bound in range(1, 53):
		var limit: int = 4294967296 - 4294967296 % bound
		_expect(engine._bounded_candidate(limit - 1, bound) == bound - 1, "last complete bucket accepted")
		if limit < 4294967296:
			_expect(engine._bounded_candidate(limit, bound) == -1, "incomplete bucket rejected")
		var counts: Array = []
		counts.resize(bound)
		counts.fill(0)
		for raw in range(bound * 20):
			counts[engine._bounded_candidate(raw, bound)] += 1
		for count in counts:
			_expect(count == 20, "bounded sampler has equal accepted residue counts")
	_expect(engine._bounded_candidate(-1, 52) == -1, "reject negative random raw")
	_expect(engine._bounded_candidate(4294967296, 52) == -1, "reject out-of-word raw")
	_expect(engine._bounded_candidate(0, 0) == -1, "reject zero bound")


func _stack_total(state: Dictionary) -> int:
	var total := 0
	for player in state.players:
		total += int(player.stack)
	return total


func _test_random_hands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 884632
	var completed := 0
	var transitions := 0
	for count in range(2, 7):
		for _session in range(12):
			var engine = _engine(count, 200)
			for _hand in range(10):
				if not engine.start_hand():
					break
				var guard := 0
				while engine._phase != "showdown" and guard < 200:
					guard += 1
					transitions += 1
					var seat: int = engine._actor
					var state: Dictionary = engine.snapshot(seat)
					_expect(seat >= 0 and seat < count, "live hand has valid actor")
					_expect(_stack_total(state) + int(state.pot) == count * 200, "chips conserved at every action")
					for player in state.players:
						_expect(int(player.stack) >= 0 and int(player.bet) >= 0, "no negative chips")
					var legal: Dictionary = state.legal
					var options: Array = []
					for action in ["fold", "check", "call", "raise", "all_in"]:
						if legal[action]:
							options.append(action)
					_expect(not options.is_empty(), "actor always has a legal action")
					if options.is_empty():
						break
					var action: String = options[rng.randi_range(0, options.size() - 1)]
					var amount: int = rng.randi_range(int(legal.min_raise_to), int(legal.max_raise_to)) if action == "raise" else 0
					_expect(engine.act(seat, action, amount), "advertised legal action succeeds")
				var final: Dictionary = engine.snapshot(0)
				_expect(guard < 200 and final.phase == "showdown", "hand terminates without timer")
				_expect(_stack_total(final) == count * 200, "settled stacks conserve all session chips")
				var awarded := 0
				for award in final.result:
					awarded += int(award.amount)
				_expect(awarded == int(final.pot), "result awards equal historical settled pot")
				completed += 1
	_expect(completed >= 200, "at least 200 randomized real hands completed")
	print("RANDOM_HANDS completed=%d action_transitions=%d" % [completed, transitions])
