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
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var session = S.new()
	root.add_child(session)
	for run in range(60):
		session.start_local(["A", "B", "C"], 1001)
		session.begin_hand()
		var actor: int = session.state.actor
		session.set_local_seat(actor)
		var inventory: Dictionary = session.state.players[actor].chips
		var selected := {"10": 3}
		check(I.contains(inventory, selected), "manual test funds")
		var revision: int = session.state.revision
		session.submit_chip_action(selected)
		check(session.state.revision == revision + 1, "manual raise accepted")
		check(session.state.chip_transfers[0].chips == selected, "exact selected denominations retained")
		var pot_before: Dictionary = session.state.pot_chips.duplicate()
		var total_before := pot_before.duplicate()
		for player in session.state.players: total_before = I.add(total_before, player.chips)
		var steps := 0
		while session.state.actor >= 0 and steps < 80:
			actor = session.state.actor
			session.set_local_seat(actor)
			var legal: Dictionary = session.state.legal
			session.submit_action("all_in" if legal.get("all_in", false) else ("check" if legal.get("check", false) else "call"))
			var total := I.value(session.state.pot_chips)
			for player in session.state.players:
				check(I.value(player.chips) == int(player.stack), "all-in/odd payout correct inventory")
				total += I.value(player.chips)
			check(total == 3003, "all-in conservation")
			steps += 1
		check(session.state.phase == "showdown", "all-in completed")
		check(I.value(session.state.settlement_pot_chips) == int(session.state.pot), "settlement pot retained for animation")
		var inventory_before_next: Array = []
		for player in session.state.players: inventory_before_next.append(player.chips.duplicate())
		if session.state.can_start:
			session.begin_hand()
			for seat in session.state.players.size():
				var committed: int = session.state.players[seat].committed
				var expected := I.take(inventory_before_next[seat], committed)
				check(session.state.players[seat].chips == expected.remaining, "next hand only deducts blinds")
	session.leave_game()
	session.queue_free()
	await process_frame
	print("SESSION_INVENTORY_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
