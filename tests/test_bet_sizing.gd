extends SceneTree
const Sizing = preload("res://scripts/bet_sizing.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var base := {"pot": 15, "current_bet": 10, "street_bet": 0, "min_raise_to": 20, "max_raise_to": 1000, "big_blind": 10, "street": "preflop"}
	var points: Array = Sizing.magnets(base)
	check(points.map(func(x): return x.value) == [20, 25, 30], "opening BB landmarks")
	base.merge({"street": "flop", "pot": 100, "current_bet": 0, "min_raise_to": 10}, true)
	points = Sizing.magnets(base)
	check(points.map(func(x): return x.value) == [33, 50, 75, 100], "unopened postflop fractions")
	base.merge({"current_bet": 40, "street_bet": 10, "min_raise_to": 80}, true)
	points = Sizing.magnets(base)
	check(points.map(func(x): return x.value) == [80, 105, 138, 170], "raise includes call in reference pot and current total")
	base.max_raise_to = 90
	check(Sizing.magnets(base).size() == 1, "illegal sizes are excluded")
	base.max_raise_to = 50
	check(Sizing.magnets(base).is_empty(), "short all-in has no pretend legal raise")
	print("BET_SIZING_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
