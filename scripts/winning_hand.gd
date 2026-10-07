extends RefCounted
## Presentation only: reads recipient-safe settled snapshots, never the live deck.
const Rules = preload("res://scripts/poker_engine.gd")
const NAMES_ZH = ["高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"]
const NAMES_EN = ["HIGH CARD", "ONE PAIR", "TWO PAIR", "THREE OF A KIND", "STRAIGHT", "FLUSH", "FULL HOUSE", "FOUR OF A KIND", "STRAIGHT FLUSH"]

static func best_five(cards: Array) -> Dictionary:
	if cards.size() < 5 or cards.size() > 7: return {}
	var unique: Dictionary = {}
	for card in cards:
		if not card is int or card < 0 or card > 51 or unique.has(card): return {}
		unique[card] = true
	var ordered := cards.duplicate()
	ordered.sort()
	var engine := Rules.new()
	var best := -1
	var chosen: Array = []
	for a in range(ordered.size() - 4):
		for b in range(a + 1, ordered.size() - 3):
			for c in range(b + 1, ordered.size() - 2):
				for d in range(c + 1, ordered.size() - 1):
					for e in range(d + 1, ordered.size()):
						var five := [ordered[a], ordered[b], ordered[c], ordered[d], ordered[e]]
						var score: int = engine._evaluate_five(five)
						if score > best:
							best = score
							chosen = five
	var category := int(best / 759375)
	var wheel := category in [4, 8] and int(best / 50625) % 15 == 5
	var counts: Dictionary = {}
	for card in chosen:
		counts[card % 13] = int(counts.get(card % 13, 0)) + 1
	chosen.sort_custom(func(a: int, b: int) -> bool:
		var ar := a % 13
		var br := b % 13
		if counts[ar] != counts[br]: return counts[ar] > counts[br]
		if wheel:
			if ar == 12: ar = -1
			if br == 12: br = -1
		return ar > br if ar != br else a < b)
	return {"cards": chosen, "score": best, "category_id": category,
		"royal": category == 8 and int(best / 50625) % 15 == 14}

static func winners(state: Dictionary, language: String = "zh") -> Array:
	if state.get("phase", "") != "showdown": return []
	var players: Array = state.get("players", [])
	var live := 0
	for player in players:
		if not player.get("folded", false): live += 1
	var entries: Array = []
	var seen: Dictionary = {}
	for award in state.get("result", []):
		var seat := int(award.get("seat", -1))
		if seat < 0 or seat >= players.size() or int(award.get("amount", 0)) <= 0: continue
		if seen.has(seat):
			entries[seen[seat]].amount += int(award.amount)
			continue
		var player: Dictionary = players[seat]
		if player.get("folded", false): continue
		var entry := {"seat": seat, "amount": int(award.amount), "name": str(player.get("name", "")),
			"cards": [], "category": "收下底池" if language == "zh" else "UNCONTESTED", "score": -1, "uncontested": live <= 1}
		if live > 1:
			var holes: Array = player.get("cards", [])
			var board: Array = state.get("board", [])
			# A five-card public board alone cannot establish a hidden player's best hand.
			var best := best_five(holes + board) if holes.size() == 2 and board.size() == 5 else {}
			if best.is_empty():
				entry.category = "赢得底池" if language == "zh" else "POT WINNER"
			else:
				entry.cards = best.cards
				entry.score = best.score
				entry.category = ("皇家同花顺" if language == "zh" else "ROYAL FLUSH") if best.royal else (NAMES_ZH if language == "zh" else NAMES_EN)[best.category_id]
		seen[seat] = entries.size()
		entries.append(entry)
	return entries
