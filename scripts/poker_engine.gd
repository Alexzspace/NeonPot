class_name PokerEngine
extends RefCounted
## Host-only no-limit Hold'em state. Expose only snapshot(recipient_seat) to clients.

const MAX_STACK := 1000000000
const STREETS := ["preflop", "flop", "turn", "river"]
var last_error: String = ""
var _players: Array = []
var _phase: String = "lobby"
var _hand_id: int = 0
var _dealer: int = -1
var _first_dealer: int = -1
var _small_blind_seat: int = -1
var _big_blind_seat: int = -1
var _last_big_blind_seat: int = -1
var _last_hand_seats: int = 0
var _actor: int = -1
var _board: Array = []
var _deck: Array = []
var _small_blind: int = 5
var _big_blind: int = 10
var _current_bet: int = 0
var _last_full_raise: int = 10
var _pending: Array = []
var _acted_at: Array = []
var _result: Array = []
var _settled_pot: int = 0
var _reveal_showdown: bool = false
var _crypto := Crypto.new()


func configure(names: Array, starting_stack: int, small_blind: int = 5, big_blind: int = 10, first_dealer: int = -1) -> bool:
	if STREETS.has(_phase):
		return _fail("A hand is already in progress.")
	if names.size() < 2 or names.size() > 6:
		return _fail("Use 2 to 6 seats.")
	if starting_stack < 1 or starting_stack > MAX_STACK:
		return _fail("Starting stack is out of range.")
	if small_blind < 1 or big_blind < small_blind or big_blind > MAX_STACK:
		return _fail("Invalid blinds.")
	if first_dealer < -1 or first_dealer >= names.size():
		return _fail("Invalid first dealer.")
	for entry in names:
		if not entry is String or str(entry).strip_edges().is_empty():
			return _fail("Every seat needs a name.")
	_players.clear()
	for entry in names:
		_players.append({"name": str(entry).strip_edges().left(32), "stack": starting_stack,
			"bet": 0, "committed": 0, "folded": false, "all_in": false, "cards": []})
	_small_blind = small_blind
	_big_blind = big_blind
	_last_full_raise = big_blind
	_phase = "lobby"
	_hand_id = 0
	_dealer = -1
	_first_dealer = first_dealer
	_small_blind_seat = -1
	_big_blind_seat = -1
	_last_big_blind_seat = -1
	_last_hand_seats = 0
	_actor = -1
	_current_bet = 0
	_board.clear()
	_deck.clear()
	_pending.clear()
	_acted_at.clear()
	_result.clear()
	_settled_pot = 0
	_reveal_showdown = false
	last_error = ""
	return true


func start_hand() -> bool:
	if STREETS.has(_phase):
		return _fail("Finish the current hand first.")
	var funded: Array = []
	for seat in range(_players.size()):
		if int(_players[seat].stack) > 0:
			funded.append(seat)
	if funded.size() < 2:
		return _fail("At least two players need chips. Start a new session to reset stacks.")
	# Obtain all entropy before changing game state. No time seed or deterministic fallback.
	var shuffled := _shuffled_deck()
	if shuffled.size() != 52:
		return _fail("Secure random source is unavailable.")
	_deck = shuffled
	_hand_id += 1
	_phase = "preflop"
	_board.clear()
	_result.clear()
	_settled_pot = 0
	_reveal_showdown = false
	_pending.clear()
	_acted_at.clear()
	for seat in range(_players.size()):
		var p: Dictionary = _players[seat]
		p.bet = 0
		p.committed = 0
		p.folded = not funded.has(seat)
		p.all_in = false
		p.cards = []
		_acted_at.append(-1)
	_dealer = _first_dealer if _hand_id == 1 and funded.has(_first_dealer) else _next_in(_dealer, funded)
	if funded.size() == 2 and _last_hand_seats > 2:
		# At the heads-up transition, keep the big blind advancing, even if this
		# requires adjusting the button to avoid the same player posting BB twice.
		_dealer = _next_in(_next_in(_last_big_blind_seat, funded), funded)
	var small_seat: int = _dealer if funded.size() == 2 else _next_in(_dealer, funded)
	var big_seat := _next_in(small_seat, funded)
	_small_blind_seat = small_seat
	_big_blind_seat = big_seat
	_last_big_blind_seat = big_seat
	_last_hand_seats = funded.size()
	var deal_seat := _next_in(_dealer, funded)
	for _round in range(2):
		for _index in range(funded.size()):
			_players[deal_seat].cards.append(_draw())
			deal_seat = _next_in(deal_seat, funded)
	_pay(small_seat, _small_blind)
	_pay(big_seat, _big_blind)
	# A short big blind does not reduce the bring-in for other players.
	_current_bet = _big_blind
	_last_full_raise = _big_blind
	_pending = _actionable()
	_progress(big_seat)
	last_error = ""
	return true


func act(seat: int, action: String, raise_to: int = 0) -> bool:
	if not STREETS.has(_phase) or seat != _actor or seat < 0 or seat >= _players.size():
		return _fail("It is not this seat's turn.")
	var legal := _legal(seat)
	if not ["fold", "check", "call", "raise", "all_in"].has(action) or not bool(legal.get(action, false)):
		return _fail("This action is not legal now.")
	var p: Dictionary = _players[seat]
	if action == "raise" and (raise_to < int(legal.min_raise_to) or raise_to > int(legal.max_raise_to)):
		return _fail("Raise-to amount is outside the legal range.")
	var previous_bet := _current_bet
	match action:
		"fold":
			p.folded = true
		"check":
			pass
		"call":
			_pay(seat, _current_bet - int(p.bet))
		"raise":
			_pay(seat, raise_to - int(p.bet))
		"all_in":
			_pay(seat, int(p.stack))
	if int(p.bet) > _current_bet:
		_current_bet = int(p.bet)
		var increment := _current_bet - previous_bet
		if increment >= _last_full_raise:
			_last_full_raise = increment
		# Even a short all-in requires players who owe chips to respond again.
		for other in _actionable():
			if other != seat and int(_players[other].bet) < _current_bet and not _pending.has(other):
				_pending.append(other)
	_acted_at[seat] = _current_bet
	_pending.erase(seat)
	_progress(seat)
	last_error = ""
	return true


func snapshot(for_seat: int) -> Dictionary:
	var visible_players: Array = []
	for seat in range(_players.size()):
		var p: Dictionary = _players[seat]
		var show: bool = seat == for_seat or (_reveal_showdown and not bool(p.folded))
		var cards: Array = p.cards.duplicate() if show and p.cards.size() == 2 else [-1, -1]
		visible_players.append({"name": p.name, "stack": int(p.stack), "bet": int(p.bet),
			"committed": int(p.committed), "folded": bool(p.folded), "all_in": bool(p.all_in), "cards": cards})
	return {"phase": _phase, "hand_id": _hand_id, "dealer": _dealer, "actor": _actor,
		"small_blind_seat": _small_blind_seat, "big_blind_seat": _big_blind_seat,
		"small_blind": _small_blind, "big_blind": _big_blind,
		"board": _board.duplicate(), "pot": _settled_pot if _phase == "showdown" else _pot(),
		"current_bet": _current_bet, "min_raise_to": _current_bet + _last_full_raise,
		"players": visible_players, "you": for_seat, "legal": _legal(for_seat),
		"result": _result.duplicate(true)}


func _legal(seat: int) -> Dictionary:
	var legal := {"fold": false, "check": false, "call": false, "raise": false, "all_in": false,
		"call_amount": 0, "min_raise_to": _current_bet + _last_full_raise, "max_raise_to": 0}
	if seat < 0 or seat >= _players.size():
		return legal
	var p: Dictionary = _players[seat]
	legal.max_raise_to = int(p.bet) + int(p.stack)
	if seat != _actor or not STREETS.has(_phase) or bool(p.folded) or bool(p.all_in):
		return legal
	var owing: int = maxi(0, _current_bet - int(p.bet))
	var reopened: bool = int(_acted_at[seat]) < 0 or _current_bet - int(_acted_at[seat]) >= _last_full_raise
	var opponent_can_call: bool = _actionable().size() >= 2
	legal.fold = true
	legal.check = owing == 0
	legal.call = owing > 0
	legal.call_amount = mini(owing, int(p.stack))
	legal.raise = reopened and opponent_can_call and int(legal.max_raise_to) >= int(legal.min_raise_to)
	legal.all_in = int(p.stack) > 0 and (int(legal.max_raise_to) <= _current_bet or (reopened and opponent_can_call))
	return legal


func _progress(after_seat: int) -> void:
	var live := _live_seats()
	if live.size() == 1:
		_refund_uncalled()
		_settled_pot = _pot()
		_players[live[0]].stack += _settled_pot
		_result = [{"seat": int(live[0]), "amount": _settled_pot}]
		_phase = "showdown"
		_actor = -1
		_pending.clear()
		return
	var actionable := _actionable()
	for index in range(_pending.size() - 1, -1, -1):
		if not actionable.has(_pending[index]):
			_pending.remove_at(index)
	if actionable.size() <= 1:
		if actionable.size() == 1:
			var only: int = actionable[0]
			# Once all opponents are all-in, a short blind's nominal bring-in no longer
			# requires an uncallable extra contribution from the remaining player.
			_current_bet = 0
			for player in _players:
				_current_bet = maxi(_current_bet, int(player.bet))
			if int(_players[only].bet) < _current_bet and _pending.has(only):
				_actor = only
				return
		_advance_street()
	elif _pending.is_empty():
		_advance_street()
	else:
		_actor = _next_in(after_seat, _pending)


func _advance_street() -> void:
	_refund_uncalled()
	if _phase == "river":
		_finish_showdown()
		return
	if _actionable().size() <= 1:
		while _board.size() < 5:
			_deal_board()
		_finish_showdown()
		return
	_deal_board()
	_phase = "flop" if _board.size() == 3 else ("turn" if _board.size() == 4 else "river")
	for p in _players:
		p.bet = 0
	_current_bet = 0
	_last_full_raise = _big_blind
	_acted_at.fill(-1)
	_pending = _actionable()
	_actor = _next_in(_dealer, _pending)


func _deal_board() -> void:
	_draw() # Burn one card on each street.
	var count: int = 3 if _board.is_empty() else 1
	for _index in range(count):
		_board.append(_draw())


func _refund_uncalled() -> void:
	var largest := 0
	var second := 0
	var largest_seat := -1
	for seat in range(_players.size()):
		var amount: int = _players[seat].bet
		if amount > largest:
			second = largest
			largest = amount
			largest_seat = seat
		else:
			second = maxi(second, amount)
	if largest_seat >= 0 and largest > second:
		var refund := largest - second
		var p: Dictionary = _players[largest_seat]
		p.stack += refund
		p.bet -= refund
		p.committed -= refund
		p.all_in = int(p.stack) == 0


func _finish_showdown() -> void:
	_settled_pot = _pot()
	var levels: Array = []
	for p in _players:
		if int(p.committed) > 0 and not levels.has(int(p.committed)):
			levels.append(int(p.committed))
	levels.sort()
	var previous_level := 0
	var awards: Dictionary = {}
	var scores: Dictionary = {}
	for seat in _live_seats():
		scores[seat] = _evaluate(_players[seat].cards + _board)
	for level in levels:
		var contributors: Array = []
		var eligible: Array = []
		for seat in range(_players.size()):
			if int(_players[seat].committed) >= int(level):
				contributors.append(seat)
				if not bool(_players[seat].folded):
					eligible.append(seat)
		var amount: int = (int(level) - previous_level) * contributors.size()
		previous_level = int(level)
		# A single contributor's excess is an uncalled refund, not a contested side pot.
		if contributors.size() == 1:
			var sole: int = contributors[0]
			_players[sole].stack += amount
			_settled_pot -= amount
			continue
		var best := -1
		var winners: Array = []
		for seat in eligible:
			var score: int = scores[seat]
			if score > best:
				best = score
				winners = [seat]
			elif score == best:
				winners.append(seat)
		# Valid betting cannot leave a pot level without a live claimant.
		assert(not winners.is_empty(), "Side pot has no eligible player")
		if winners.is_empty():
			return
		var share: int = amount / winners.size()
		var odd: int = amount % winners.size()
		var seat_cursor := _dealer
		for _index in range(winners.size()):
			seat_cursor = _next_in(seat_cursor, winners)
			var award := share + (1 if odd > 0 else 0)
			odd = maxi(0, odd - 1)
			awards[seat_cursor] = int(awards.get(seat_cursor, 0)) + award
	_result.clear()
	for seat in range(_players.size()):
		if awards.has(seat):
			var amount: int = awards[seat]
			_players[seat].stack += amount
			_result.append({"seat": seat, "amount": amount})
	_reveal_showdown = true
	_phase = "showdown"
	_actor = -1
	_pending.clear()


func _pay(seat: int, amount: int) -> void:
	var p: Dictionary = _players[seat]
	var paid: int = mini(maxi(amount, 0), int(p.stack))
	p.stack -= paid
	p.bet += paid
	p.committed += paid
	p.all_in = int(p.stack) == 0


func _live_seats() -> Array:
	var seats: Array = []
	for seat in range(_players.size()):
		if not bool(_players[seat].folded):
			seats.append(seat)
	return seats


func _actionable() -> Array:
	var seats: Array = []
	for seat in _live_seats():
		if int(_players[seat].stack) > 0:
			seats.append(seat)
	return seats


func _next_in(after_seat: int, seats: Array) -> int:
	for offset in range(1, _players.size() + 1):
		var candidate := (after_seat + offset) % _players.size()
		if seats.has(candidate):
			return candidate
	return -1


func _pot() -> int:
	var total := 0
	for p in _players:
		total += int(p.committed)
	return total


func _draw() -> int:
	return int(_deck.pop_back())


func _shuffled_deck() -> Array:
	var deck: Array = range(52)
	for index in range(51, 0, -1):
		var other := _random_below(index + 1)
		if other < 0:
			return []
		var card: int = deck[index]
		deck[index] = deck[other]
		deck[other] = card
	return deck


func _random_below(bound: int) -> int:
	while true:
		var bytes := _crypto.generate_random_bytes(4)
		if bytes.size() != 4:
			return -1
		var candidate := _bounded_candidate(bytes.decode_u32(0), bound)
		if candidate >= 0:
			return candidate
	return -1


func _bounded_candidate(raw: int, bound: int) -> int:
	# Discard the incomplete modulo bucket; every accepted residue has equal probability.
	if bound < 1 or bound > 52 or raw < 0 or raw >= 4294967296:
		return -1
	var limit: int = 4294967296 - (4294967296 % bound)
	return raw % bound if raw < limit else -1


func _evaluate(cards: Array) -> int:
	assert(cards.size() >= 5 and cards.size() <= 7)
	var best := -1
	for a in range(cards.size() - 4):
		for b in range(a + 1, cards.size() - 3):
			for c in range(b + 1, cards.size() - 2):
				for d in range(c + 1, cards.size() - 1):
					for e in range(d + 1, cards.size()):
						best = maxi(best, _evaluate_five([cards[a], cards[b], cards[c], cards[d], cards[e]]))
	return best


func _evaluate_five(cards: Array) -> int:
	var ranks: Array = []
	var counts: Dictionary = {}
	var flush := true
	var suit: int = int(cards[0]) / 13
	for card in cards:
		var rank: int = int(card) % 13 + 2
		ranks.append(rank)
		counts[rank] = int(counts.get(rank, 0)) + 1
		if int(int(card) / 13) != suit:
			flush = false
	ranks.sort()
	ranks.reverse()
	var straight := 0
	if counts.size() == 5:
		if int(ranks[0]) - int(ranks[4]) == 4:
			straight = int(ranks[0])
		elif ranks == [14, 5, 4, 3, 2]:
			straight = 5
	var groups: Array = counts.keys()
	groups.sort_custom(func(a: int, b: int) -> bool:
		return int(counts[a]) > int(counts[b]) if counts[a] != counts[b] else a > b)
	if flush and straight > 0:
		return _score(8, [straight])
	if int(counts[groups[0]]) == 4:
		return _score(7, groups)
	if int(counts[groups[0]]) == 3 and int(counts[groups[1]]) == 2:
		return _score(6, groups)
	if flush:
		return _score(5, ranks)
	if straight > 0:
		return _score(4, [straight])
	if int(counts[groups[0]]) == 3:
		return _score(3, groups)
	if int(counts[groups[0]]) == 2:
		return _score(2 if int(counts[groups[1]]) == 2 else 1, groups)
	return _score(0, ranks)


func _score(category: int, kickers: Array) -> int:
	var score := category
	for index in range(5):
		score = score * 15 + (int(kickers[index]) if index < kickers.size() else 0)
	return score


func _fail(message: String) -> bool:
	last_error = message
	return false
