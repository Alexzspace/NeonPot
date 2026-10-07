extends RefCounted
## A bounded, imperfect policy. Never receives a live engine or reads opponents' cards.
const POSTFLOP_SAMPLES := 64
const RANGE_ATTEMPTS := 4
var rng := RandomNumberGenerator.new()
var aggression := 6:
	set(value): aggression = clampi(value, 0, 10)

func choose(snapshot: Dictionary) -> Dictionary:
	var seat: int = snapshot.get("you", -1)
	var players: Array = snapshot.get("players", [])
	if players.size() < 2 or players.size() > 6 or seat < 0 or seat >= players.size() or int(snapshot.get("actor", -1)) != seat:
		return {}
	var legal: Dictionary = snapshot.get("legal", {})
	var cards: Array = players[seat].get("cards", [])
	var board: Array = snapshot.get("board", [])
	if cards.size() != 2 or not board.size() in [0, 3, 4, 5] or not _valid_known_cards(cards + board):
		return _safe_action(legal)
	var pot := maxi(1, int(snapshot.get("pot", 0)))
	var big_blind := maxi(1, int(snapshot.get("big_blind", 10)))
	var ranges: Array = []
	for other in range(players.size()):
		if other != seat and not players[other].get("folded", false):
			# Public investment suggests a stronger range; it never identifies the actual hand.
			var investment := maxf(float(players[other].get("bet", 0)), float(players[other].get("committed", 0)) * 0.25)
			ranges.append(clampf(0.2 + investment / float(big_blind * 24) + investment / float(pot + 1) * 0.22, 0.2, 0.9))
	if ranges.is_empty(): return _safe_action(legal)
	var preflop := board.is_empty()
	var strength := _preflop_strength(cards, ranges.size()) if preflop else _sample_strength(cards, board, ranges)
	var call_amount := maxi(0, int(legal.get("call_amount", 0)))
	var stack := maxi(1, int(players[seat].get("stack", 0)))
	var price := float(call_amount) / float(pot + call_amount)
	var commitment := float(call_amount) / float(stack)
	var a := float(aggression) / 10.0
	var required := price + 0.035 + commitment * 0.07 - a * 0.025
	var roll := rng.randf()
	var draw := _draw_quality(cards, board)
	var texture := _board_texture(board)
	var cheap_pressure := commitment < 0.3 and call_amount <= pot / 2
	var semi_bluff := draw > 0 and ranges.size() <= 3 and cheap_pressure and strength > required - 0.08 and roll < draw * (0.025 + a * 0.26)
	if call_amount > 0:
		if strength < required and not semi_bluff and legal.get("fold", false):
			return {"action": "fold", "amount": 0}
		if preflop:
			var opening_floor := 0.30 + 0.035 * maxi(0, ranges.size() - 1) - 0.065 * a
			var expensive_floor := 0.61 - 0.06 * a
			if (strength < opening_floor or (commitment > 0.28 and strength < expensive_floor)) and legal.get("fold", false):
				return {"action": "fold", "amount": 0}
	var value_threshold := (0.66 if preflop else 0.64) - a * 0.16
	var value_raise := strength > value_threshold and roll < 0.20 + 0.70 * a
	# Dry boards and fewer opponents offer more plausible steals; no bet is a known bluff.
	var bluff_frequency := (0.008 + 0.145 * a) * (1.0 - texture * 0.45)
	var bluff := call_amount == 0 and ranges.size() <= 2 and roll < bluff_frequency
	var premium := strength > (0.83 if preflop else 0.85)
	if premium and stack <= maxi(big_blind * 12, pot) and legal.get("all_in", false):
		return {"action": "all_in", "amount": 0}
	if legal.get("raise", false) and (value_raise or bluff or semi_bluff):
		var current: int = snapshot.get("current_bet", 0)
		var target: int
		if preflop and current <= big_blind:
			target = int(round(big_blind * (2.2 + a * 1.25 + rng.randf_range(0.0, 0.35))))
		else:
			var fraction := 0.38 + 0.42 * a + texture * 0.1 + rng.randf_range(0.0, 0.14)
			target = current + maxi(big_blind, int(round((pot + call_amount) * fraction)))
		target = clampi(target, int(legal.min_raise_to), int(legal.max_raise_to))
		return {"action": "raise", "amount": target}
	return _safe_action(legal)

func _safe_action(legal: Dictionary) -> Dictionary:
	for action in ["check", "call", "fold", "all_in"]:
		if legal.get(action, false): return {"action": action, "amount": 0}
	return {}

func _valid_known_cards(cards: Array) -> bool:
	if cards.size() < 2 or cards.size() > 7: return false
	var seen: Dictionary = {}
	for card in cards:
		if not card is int or card < 0 or card >= 52 or seen.has(card): return false
		seen[card] = true
	return true

func _preflop_strength(cards: Array, opponents: int) -> float:
	var high := maxi(int(cards[0]) % 13, int(cards[1]) % 13) + 2
	var low := mini(int(cards[0]) % 13, int(cards[1]) % 13) + 2
	var strength := 0.15 + float(high - 2) / 36.0 + float(low - 2) / 70.0
	if high == low:
		strength = 0.46 + float(high) / 30.0
	else:
		if int(int(cards[0]) / 13) == int(int(cards[1]) / 13): strength += 0.065
		if high - low == 1: strength += 0.045
		if high - low >= 5: strength -= 0.05
		if high == 14 and low <= 5: strength += 0.025
	return clampf(strength - 0.035 * maxi(0, opponents - 1), 0.05, 0.95)

func _board_texture(board: Array) -> float:
	if board.is_empty(): return 0.0
	var suits := [0, 0, 0, 0]
	var ranks: Array = []
	for card in board:
		suits[int(int(card) / 13)] += 1
		ranks.append(int(card) % 13)
	var close := 0
	for i in ranks.size():
		for j in range(i + 1, ranks.size()):
			if absi(ranks[i] - ranks[j]) <= 2: close += 1
	return clampf(float(suits.max() - 1) * 0.2 + float(close) * 0.08, 0.0, 1.0)

func _draw_quality(cards: Array, board: Array) -> float:
	if board.size() < 3 or board.size() >= 5: return 0.0
	var ranks: Dictionary = {}
	var suits := [0, 0, 0, 0]
	for card in cards + board:
		var rank: int = int(card) % 13 + 2
		ranks[rank] = true
		if rank == 14: ranks[1] = true
		suits[int(int(card) / 13)] += 1
	var draw := 0.0
	for card in cards:
		if suits[int(int(card) / 13)] == 4: draw = 0.85
	for low in range(1, 11):
		var hits := 0
		for rank in range(low, low + 5):
			if ranks.has(rank): hits += 1
		if hits == 4:
			for card in cards:
				var rank: int = int(card) % 13 + 2
				if (rank >= low and rank < low + 5) or (rank == 14 and low == 1): draw = maxf(draw, 0.65)
	return draw

func _sample_strength(cards: Array, board: Array, ranges: Array) -> float:
	var unknown: Array = []
	for card in 52:
		if not cards.has(card) and not board.has(card): unknown.append(card)
	var wins := 0.0
	for _sample in POSTFLOP_SAMPLES:
		var pool := unknown.duplicate()
		var opponents: Array = []
		for tightness in ranges:
			opponents.append(_take_range_hand(pool, board, float(tightness)))
		var visible := board.duplicate()
		while visible.size() < 5: visible.append(_take_unknown(pool))
		var our_score := _rank(cards + visible)
		var tied := 1
		var beaten := false
		for hand in opponents:
			var score := _rank(hand + visible)
			if score > our_score: beaten = true
			elif score == our_score: tied += 1
		if not beaten: wins += 1.0 / float(tied)
	return wins / POSTFLOP_SAMPLES

func _take_range_hand(pool: Array, board: Array, tightness: float) -> Array:
	var hand: Array = []
	for _attempt in RANGE_ATTEMPTS:
		var first := rng.randi_range(0, pool.size() - 1)
		var second := rng.randi_range(0, pool.size() - 2)
		if second >= first: second += 1
		hand = [pool[first], pool[second]]
		var category: int = _rank(hand + board) / 759375 # 15^5
		var made: float = [0.16, 0.50, 0.72, 0.80, 0.89, 0.93, 0.96, 0.99, 1.0][category]
		var quality := maxf(_preflop_strength(hand, 1), made + _draw_quality(hand, board) * 0.16)
		var weight := lerpf(1.0, pow(clampf(quality / 0.8, 0.08, 1.0), 2), tightness)
		if rng.randf() <= weight: break
	for card in hand: pool.erase(card)
	return hand

func _take_unknown(pool: Array) -> int:
	var index := rng.randi_range(0, pool.size() - 1)
	var card: int = pool[index]
	pool[index] = pool[-1]
	pool.pop_back()
	return card

func _rank(cards: Array) -> int:
	# Direct 5-7-card evaluator avoids enumerating 21 five-card subsets per rollout.
	var counts := PackedInt32Array()
	counts.resize(15)
	var suits: Array = [[], [], [], []]
	for card in cards:
		var rank: int = int(card) % 13 + 2
		counts[rank] += 1
		suits[int(int(card) / 13)].append(rank)
	var ranks: Array = []
	var pairs: Array = []
	var trips: Array = []
	var quads := 0
	for rank in range(14, 1, -1):
		if counts[rank] > 0: ranks.append(rank)
		if counts[rank] >= 2: pairs.append(rank)
		if counts[rank] >= 3: trips.append(rank)
		if counts[rank] == 4: quads = rank
	var flush: Array = []
	for suited in suits:
		if suited.size() >= 5:
			flush = suited.duplicate()
			flush.sort()
			flush.reverse()
			var straight_flush := _straight(flush)
			if straight_flush > 0: return _score(8, [straight_flush])
	if quads > 0:
		ranks.erase(quads)
		return _score(7, [quads, ranks[0]])
	if not trips.is_empty():
		var full_pairs := pairs.duplicate()
		full_pairs.erase(trips[0])
		if not full_pairs.is_empty(): return _score(6, [trips[0], full_pairs[0]])
	if not flush.is_empty(): return _score(5, flush)
	var straight := _straight(ranks)
	if straight > 0: return _score(4, [straight])
	if not trips.is_empty():
		ranks.erase(trips[0])
		return _score(3, [trips[0]] + ranks.slice(0, 2))
	if pairs.size() >= 2:
		ranks.erase(pairs[0])
		ranks.erase(pairs[1])
		return _score(2, [pairs[0], pairs[1], ranks[0]])
	if pairs.size() == 1:
		ranks.erase(pairs[0])
		return _score(1, [pairs[0]] + ranks.slice(0, 3))
	return _score(0, ranks)

func _straight(ranks: Array) -> int:
	var present := ranks.duplicate()
	if present.has(14): present.append(1)
	for high in range(14, 4, -1):
		var found := true
		for rank in range(high - 4, high + 1):
			if not present.has(rank):
				found = false
				break
		if found: return high
	return 0

func _score(category: int, ranks: Array) -> int:
	var score := category
	for index in 5: score = score * 15 + (int(ranks[index]) if index < ranks.size() else 0)
	return score
