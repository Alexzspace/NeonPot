extends RefCounted
class_name ChipInventory

const DENOMINATIONS := [500, 100, 50, 10, 5, 1]

static func valid(chips: Dictionary) -> bool:
	if chips.size() > DENOMINATIONS.size(): return false
	for key in chips:
		if not key is String or not key in ["500", "100", "50", "10", "5", "1"]: return false
		if not chips[key] is int or chips[key] < 0 or chips[key] > 6000000: return false
	return value(chips) <= 6000000

static func value(chips: Dictionary) -> int:
	var total := 0
	for denomination in DENOMINATIONS:
		total += denomination * int(chips.get(str(denomination), 0))
	return total

static func add(target: Dictionary, chips: Dictionary) -> Dictionary:
	var result := target.duplicate()
	for key in chips:
		result[key] = int(result.get(key, 0)) + int(chips[key])
	return result

static func contains(target: Dictionary, chips: Dictionary) -> bool:
	if not valid(chips): return false
	for key in chips:
		if int(chips[key]) > int(target.get(key, 0)): return false
	return true

static func subtract(target: Dictionary, chips: Dictionary) -> Dictionary:
	var result := target.duplicate()
	for key in chips:
		result[key] = int(result.get(key, 0)) - int(chips[key])
		if result[key] == 0: result.erase(key)
	return result

static func compact(amount: int) -> Dictionary:
	var result := {}
	for denomination in DENOMINATIONS:
		var count: int = amount / denomination
		if count > 0: result[str(denomination)] = count
		amount %= denomination
	return result

static func balanced(amount: int) -> Dictionary:
	var result := {}
	# Keep every affordable denomination available for individual chip selection.
	for denomination in [1, 5, 10, 50, 100]:
		var budget: int = amount / 4
		var count := mini(10, budget / denomination)
		if count > 0:
			result[str(denomination)] = count
			amount -= count * denomination
	return add(result, compact(amount))

# Returns exact payment and remaining inventory. Only breaks one necessary chip
# at a time; unrelated stacks remain untouched. Never mutates caller dictionaries.
static func take(inventory: Dictionary, amount: int) -> Dictionary:
	if amount < 0 or amount > value(inventory): return {}
	var remaining := inventory.duplicate()
	var paid := {}
	var needed := amount
	for denomination in DENOMINATIONS:
		var key := str(denomination)
		var count := mini(int(remaining.get(key, 0)), needed / denomination)
		if count > 0:
			paid[key] = count
			remaining = subtract(remaining, {key: count})
			needed -= denomination * count
	if needed > 0:
		# Greedy payment leaves only denominations larger than the remainder.
		for index in range(DENOMINATIONS.size() - 1, -1, -1):
			var denomination: int = DENOMINATIONS[index]
			var key := str(denomination)
			if denomination > needed and int(remaining.get(key, 0)) > 0:
				remaining = subtract(remaining, {key: 1})
				paid = add(paid, compact(needed))
				remaining = add(remaining, compact(denomination - needed))
				needed = 0
				break
	assert(needed == 0)
	return {"chips": paid, "remaining": remaining}
