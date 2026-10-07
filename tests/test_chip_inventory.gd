extends SceneTree
const I = preload("res://scripts/chip_inventory.gd")
const S = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	check(not I.valid({"25": 1}), "removed denomination rejected")
	check(not I.valid({"50": -1}), "negative rejected")
	check(not I.valid({"50": 1.5}), "fractional count rejected")
	var original := {"500": 2, "100": 1}
	var paid := I.take(original, 10)
	check(paid.remaining == {"500": 2, "50": 1, "10": 4}, "only necessary chip changed")
	check(original == {"500": 2, "100": 1}, "take immutable")
	for stack in [1000, 3000]:
		check(int(I.balanced(stack).get("1", 0)) == 10, "starting and exchanged stacks retain ten unit chips")
	for amount in range(0, 10001, 17):
		var inventory := I.balanced(amount)
		check(I.value(inventory) == amount and I.valid(inventory), "balance conserves")
		var transaction := I.take(inventory, amount / 3)
		check(I.value(transaction.chips) + I.value(transaction.remaining) == amount, "payment conserves")
	var session = S.new()
	root.add_child(session)
	session.start_local(["A", "B", "C"], 1000)
	session.begin_hand()
	var saved: Dictionary = session.state.duplicate(true)
	var actor: int = saved.actor
	session.set_local_seat(actor)
	session._accept_chip_action(actor, {"500": 999}, saved.hand_id, saved.revision, 1)
	check(session.state.revision == saved.revision, "forged inventory rejected")
	session._accept_chip_exchange(actor, {}, saved.hand_id - 1, saved.revision, 1)
	check(session.state.revision == saved.revision, "stale exchange rejected")
	var reserved := {"5": 1, "10": 2}
	var expected_exchange := I.add(I.balanced(I.value(I.subtract(session.state.players[actor].chips, reserved))), reserved)
	session.exchange_chips(reserved)
	check(session.state.players[actor].chips == expected_exchange, "reserved pending chips excluded from exchange")
	check(I.value(session.state.players[actor].chips) == int(saved.players[actor].stack), "exchange conserves")
	var before_exchange: Dictionary = session.state.duplicate(true)
	session._accept_chip_action(actor, {"5": 1}, saved.hand_id, saved.revision, 1)
	check(session.state.revision == before_exchange.revision, "stale selected action rejected")
	for hand in range(15):
		var steps := 0
		while session.state.actor >= 0 and steps < 100:
			actor = session.state.actor
			session.set_local_seat(actor)
			var legal: Dictionary = session.state.legal
			if steps == 0 and legal.get("raise", false):
				session.submit_action("raise", int(legal.min_raise_to))
			else:
				session.submit_action("check" if legal.get("check", false) else "call")
			var sum := I.value(session.state.pot_chips)
			for player in session.state.players:
				check(I.value(player.chips) == int(player.stack), "stack inventory reconciles")
				sum += I.value(player.chips)
			check(sum == 3000, "whole table conserved")
			steps += 1
		check(session.state.phase == "showdown", "hand completes")
		check(I.value(session.state.pot_chips) == 0, "payout empties physical pot")
		if not session.state.can_start: break
		session.begin_hand()
	session.leave_game()
	session.queue_free()
	await process_frame
	print("CHIP_INVENTORY_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
