extends RefCounted
## Amount landmarks only; never depend on private cards or advise a decision.
static func magnets(state: Dictionary) -> Array:
	var result: Array = []
	var bb := maxi(1, int(state.get("big_blind", 10)))
	var minimum := int(state.get("min_raise_to", bb * 2))
	var maximum := int(state.get("max_raise_to", 0))
	var current := int(state.get("current_bet", 0))
	var own := int(state.get("street_bet", 0))
	var pot := int(state.get("pot", 0))
	var street := str(state.get("street", "preflop"))
	var candidates: Array = []
	if street in ["preflop", "0"] and current <= bb:
		for multiple in [2.0, 2.5, 3.0]:
			candidates.append({"value": int(round(bb * multiple)), "label": "%s BB" % multiple})
	elif current > own:
		candidates.append({"value": minimum, "label": "MIN"})
		var after_call := pot + maxi(0, current - own)
		for fraction in [[0.5, "1/2"], [0.75, "3/4"], [1.0, "1/1"]]:
			candidates.append({"value": current + int(round(after_call * float(fraction[0]))), "label": str(fraction[1])})
	else:
		for fraction in [[1.0 / 3.0, "1/3"], [0.5, "1/2"], [0.75, "3/4"], [1.0, "1/1"]]:
			candidates.append({"value": own + int(round(pot * float(fraction[0]))), "label": str(fraction[1])})
	var seen: Dictionary = {}
	for item in candidates:
		var value := int(item.value)
		if value < minimum or value > maximum or seen.has(value): continue
		seen[value] = true
		result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.value) < int(b.value))
	return result
