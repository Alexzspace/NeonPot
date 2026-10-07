extends Node

# Cosmetic timing uses its own RNG, never the deck or AI decision policy.
var _rng := RandomNumberGenerator.new()
var _context := ""
var _remaining := 0.0
var _previous_seat := -1

func reset() -> void:
	_context = ""
	_remaining = 0.0
	_previous_seat = -1

func tick(delta: float, session, allowed: bool) -> bool:
	if not allowed or session == null or not session.is_host or not is_finite(delta) or delta < 0.0:
		reset()
		return false
	var state: Dictionary = session.state
	var players: Array = state.get("players", [])
	var actor: int = state.get("actor", -1)
	if state.get("paused", false) or state.get("phase", "") not in ["preflop", "flop", "turn", "river"] or actor < 0 or actor >= players.size():
		reset()
		return false
	var candidates: Array[int] = []
	for seat in players.size():
		var player: Dictionary = players[seat]
		if seat != actor and player.get("is_bot", false) and player.get("connected", true) and int(player.get("stack", 0)) > 0:
			candidates.append(seat)
	if candidates.is_empty():
		reset()
		return false
	var context := "%s:%s:%s" % [state.get("room_id", ""), state.get("hand_id", -1), actor]
	if context != _context:
		_context = context
		_remaining = _rng.randf_range(20.0, 32.0) if players[actor].get("is_bot", false) else _rng.randf_range(7.0, 15.0)
		return false
	# A suspended/long frame cannot spend accumulated time on a surprise flourish.
	if delta > 1.0:
		reset()
		return false
	_remaining -= delta
	if _remaining > 0.0: return false
	_remaining = _rng.randf_range(15.0, 28.0)
	if candidates.size() > 1: candidates.erase(_previous_seat)
	var seat: int = candidates[_rng.randi_range(0, candidates.size() - 1)]
	if session.play_bot_chip_gesture(seat):
		_previous_seat = seat
		return true
	return false
