extends SceneTree
const AI = preload("res://scripts/poker_ai.gd")
const Rules = preload("res://scripts/poker_engine.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AI_POLICY: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _fixture(cards: Array, board: Array, call_amount: int = 0) -> Dictionary:
	return {"you": 0, "actor": 0, "dealer": 0, "phase": "preflop" if board.is_empty() else "river", "board": board,
		"pot": 800 if call_amount > 0 else 100, "current_bet": call_amount, "big_blind": 10,
		"players": [{"cards": cards, "stack": 1000, "bet": 0, "committed": 0, "folded": false},
			{"cards": [-1, -1], "stack": 1000, "bet": call_amount, "committed": call_amount, "folded": false}],
		"legal": {"fold": true, "check": call_amount == 0, "call": call_amount > 0, "raise": call_amount < 500,
			"all_in": true, "call_amount": call_amount, "min_raise_to": maxi(10, call_amount * 2), "max_raise_to": 1000}}

func _run() -> void:
	var policy = AI.new()
	var rules = Rules.new()
	var random := RandomNumberGenerator.new()
	random.seed = 98173
	# Independent exhaustive engine adjudication verifies the optimized simulation evaluator.
	for sample in 1500:
		var pool: Array = range(52)
		var cards: Array = []
		for _card in 5 + sample % 3:
			var index := random.randi_range(0, pool.size() - 1)
			cards.append(pool[index])
			pool.remove_at(index)
		check(policy._rank(cards) == rules._evaluate(cards), "fast score equals exhaustive authoritative ranking")
	for cards in [[12, 0, 1, 2, 3, 20, 40], [0, 13, 26, 39, 12, 25, 38], [12, 25, 38, 11, 24, 37, 0], [1, 14, 3, 16, 5, 18, 12]]:
		check(policy._rank(cards) == rules._evaluate(cards), "wheel, quads, double trips and three-pair scores")
	var premium := _fixture([12, 25], [])
	var air := _fixture([5, 28], [11, 20, 29, 40, 13])
	var royal := _fixture([12, 11], [10, 9, 8, 20, 40], 600)
	var pressure := _fixture([5, 28], [11, 20, 29, 40, 13], 600)
	var raises := [0, 0]
	var bluffs := [0, 0]
	var sizes := [0, 0]
	var pressure_folds := 0
	var decisions := 0
	var decision_usec := 0
	for level_index in 2:
		policy.aggression = 0 if level_index == 0 else 10
		for trial in 160:
			policy.rng.seed = trial + 200
			var action: Dictionary = policy.choose(premium)
			if action.action == "raise":
				raises[level_index] += 1
				sizes[level_index] += int(action.amount)
			policy.rng.seed = trial + 300
			var started := Time.get_ticks_usec()
			action = policy.choose(air)
			decision_usec += Time.get_ticks_usec() - started
			decisions += 1
			if action.action == "raise": bluffs[level_index] += 1
			check(air.legal.get(action.action, false), "every sampled bluff/check is legal")
			if trial < 24:
				policy.rng.seed = trial + 400
				check(policy.choose(royal).action != "fold", "nuts never fold to a credible large bet")
				policy.rng.seed = trial + 400
				if policy.choose(pressure).action == "fold": pressure_folds += 1
	check(raises[1] > raises[0] + 60, "higher aggression produces materially more value raises at equal cards/seeds")
	check(float(sizes[1]) / raises[1] > float(sizes[0]) / raises[0], "higher aggression increases value sizing")
	check(bluffs[1] > bluffs[0] + 7 and bluffs[1] < 70, "higher aggression adds occasional rather than indiscriminate river bluffs")
	check(pressure_folds >= 40, "weak holdings can fold to credible pressure without seeing the bettor cards")
	# Poison all unavailable information, including the hypothetical human's cards and deck.
	for sample in [premium, air, royal, pressure, _fixture([12, 11], [10, 9, 21])]:
		var poisoned: Dictionary = sample.duplicate(true)
		poisoned.players[1].cards = [12, 25]
		poisoned["deck"] = range(52)
		poisoned["seed"] = 9876
		poisoned["hidden_hand_strength"] = 1.0
		policy.rng.seed = 142
		var expected: Dictionary = policy.choose(sample)
		policy.rng.seed = 142
		check(policy.choose(poisoned) == expected, "preflop and postflop ignore opponents' private information")
	# A weighted range must actually shift toward stronger holdings when public investment grows.
	var range_quality := [0.0, 0.0]
	for tight in 2:
		policy.rng.seed = 775
		for trial in 240:
			var pool: Array = range(52)
			var board: Array = [11, 20, 29]
			for card in board: pool.erase(card)
			var hand: Array = policy._take_range_hand(pool, board, 0.2 if tight == 0 else 0.9)
			range_quality[tight] += policy._preflop_strength(hand, 1)
	check(range_quality[1] > range_quality[0], "public pressure conditions opponent ranges above uniform random hands")
	check(policy._sample_strength([12, 11], [10, 9, 8, 20, 40], [0.9, 0.9]) == 1.0, "rollouts preserve absolute nuts against strong ranges")
	check(is_equal_approx(policy._sample_strength([0, 14], [8, 9, 10, 11, 12], [0.9]), 0.5), "shared royal board splits equity exactly")
	check(policy._draw_quality([12, 11], [10, 9, 21]) > 0 and policy._draw_quality([12, 11], [10, 9, 21, 33, 40]) == 0, "semi-bluffs use live draws, never river phantom outs")
	var max_ms := 0.0
	var six := _fixture([12, 11], [10, 9, 21])
	for seat in 4: six.players.append({"cards": [-1, -1], "stack": 1000, "bet": 20, "committed": 20, "folded": false})
	for trial in 16:
		policy.rng.seed = trial
		var started := Time.get_ticks_usec()
		policy.choose(six)
		max_ms = maxf(max_ms, float(Time.get_ticks_usec() - started) / 1000.0)
	check(max_ms < 120, "six-seat fixed-budget decision completes without blocking for hundreds of ms")
	var completed_matches := 0
	var played_hands := 0
	for level in [0, 6, 10]:
		var game = Rules.new()
		game.configure(["A", "B", "C", "D", "E"], 100, 10, 20, level % 5)
		policy.aggression = level
		policy.rng.seed = 1900 + level
		for hand in 300:
			var funded := 0
			for player in game.snapshot(0).players:
				if player.stack > 0: funded += 1
			if funded == 1:
				completed_matches += 1
				break
			check(game.start_hand(), "complete-match fixture deals legally")
			var guard := 0
			while game.snapshot(0).actor >= 0 and guard < 160:
				var state: Dictionary = game.snapshot(game.snapshot(0).actor)
				var action: Dictionary = policy.choose(state)
				check(not action.is_empty() and game.act(state.actor, action.get("action", ""), action.get("amount", 0)), "policy action accepted by real engine")
				guard += 1
			check(game.snapshot(0).phase == "showdown" and guard < 160, "full match hand never hangs")
			var total := 0
			for player in game.snapshot(0).players: total += int(player.stack)
			check(total == 500, "full match preserves all chips through eliminations")
			played_hands += 1
	check(completed_matches == 3, "low/default/high aggression matches reach one surviving player")
	print("AI_POLICY_METRICS value_raises=%s bluff_raises=%s pressure_folds=%d avg_river_ms=%.2f max_six_player_ms=%.2f" % [raises, bluffs, pressure_folds, float(decision_usec) / decisions / 1000.0, max_ms])
	print("AI_POLICY_SUMMARY checks=%d failures=%d matches=%d hands=%d" % [checks, failures, completed_matches, played_hands])
	quit(1 if failures else 0)
