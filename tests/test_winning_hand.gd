extends SceneTree
const Winning = preload("res://scripts/winning_hand.gd")
const Rules = preload("res://scripts/poker_engine.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var engine := Rules.new()
	var wheel := Winning.best_five([12, 0, 14, 28, 42, 8, 22])
	check(wheel.category_id == 4, "wheel is a straight")
	check(wheel.cards[-1] % 13 == 12, "wheel ace displayed low")
	var royal := Winning.best_five([8, 9, 10, 11, 12, 24, 37])
	check(royal.royal and royal.category_id == 8, "royal flush label")
	for invalid in [[], [0, 1, 2, 3, -1], [0, 1, 2, 3, 3], [0, 1, 2, 3, 52]]:
		check(Winning.best_five(invalid).is_empty(), "invalid public cards rejected")
	for iteration in 120:
		var deck := range(52)
		deck.shuffle()
		var seven := deck.slice(0, 7)
		var best := Winning.best_five(seven)
		check(best.cards.size() == 5, "five cards selected")
		check(best.score == engine._evaluate(seven), "same score as authoritative evaluator")
		check(engine._evaluate_five(best.cards) == best.score, "displayed five prove score")
		seven.reverse()
		check(Winning.best_five(seven).cards == best.cards, "tie choice deterministic")
	var state := {"phase": "showdown", "board": [8, 9, 10, 11, 12], "players": [
		{"name": "A", "folded": false, "cards": [13, 14]},
		{"name": "B", "folded": false, "cards": [26, 27]},
		{"name": "C", "folded": true, "cards": [-1, -1]}],
		"result": [{"seat": 0, "amount": 100}, {"seat": 1, "amount": 200}]}
	var winners := Winning.winners(state)
	check(winners.size() == 2, "all awarded seats shown including side pots")
	check(winners[0].cards == winners[1].cards, "board-only tie uses same five")
	check(winners[0].category == "皇家同花顺", "Chinese category")
	check(Winning.winners(state, "en")[0].category == "ROYAL FLUSH", "English category")
	state.players[1].cards = [-1, -1]
	check(Winning.winners(state)[1].cards.is_empty(), "hidden opponent cannot fabricate best five")
	state.players[1].folded = true
	state.result = [{"seat": 0, "amount": 300}]
	winners = Winning.winners(state)
	check(winners[0].uncontested and winners[0].cards.is_empty(), "fold win never reveals even own hole cards")
	state.phase = "river"
	check(Winning.winners(state).is_empty(), "no live strength helper")
	print("WINNING_HAND_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
