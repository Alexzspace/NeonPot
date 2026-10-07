extends SceneTree

const Idle = preload("res://scripts/ai_chip_idle.gd")
const Session = preload("res://scripts/table_session.gd")
const Styles = preload("res://scripts/chip_gestures.gd")

class FakeSession extends RefCounted:
	var is_host := true
	var state := {"room_id": "test", "hand_id": 1, "actor": 0, "phase": "flop", "players": [{"stack": 100}, {"is_bot": true, "stack": 100}, {"is_bot": true, "stack": 100}]}
	var gestures: Array[int] = []
	func play_bot_chip_gesture(seat: int) -> bool:
		gestures.append(seat)
		return true

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AI_CHIP_IDLE: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var idle := Idle.new()
	var fake := FakeSession.new()
	root.add_child(idle)
	idle._rng.seed = 73
	idle.tick(0.0, fake, true)
	check(idle._remaining >= 7.0 and idle._remaining <= 15.0, "human thinking first delay is 7-15s")
	for step in 6: idle.tick(1.0, fake, true)
	check(fake.gestures.is_empty(), "never pressures immediate decisions")
	for step in 10: idle.tick(1.0, fake, true)
	check(fake.gestures.size() == 1 and fake.gestures[0] in [1, 2], "one idle bot responds during sustained human thinking")
	check(idle._remaining > 5.0, "no burst after first event")
	idle._remaining = 0.01
	idle.tick(0.02, fake, true)
	check(fake.gestures.size() == 2 and fake.gestures[0] != fake.gestures[1], "alternates available bot seats")
	idle.tick(1.0, fake, false)
	check(idle._context.is_empty(), "modal entry background presentation reset cooldown")
	idle.tick(0.0, fake, true)
	check(idle._remaining >= 7.0, "resume begins fresh delay")
	idle.tick(30.0, fake, true)
	check(fake.gestures.size() == 2 and idle._context.is_empty(), "long suspended frame cannot emit backlog")
	fake.is_host = false
	for step in 35: idle.tick(1.0, fake, true)
	check(fake.gestures.size() == 2, "clients cannot autonomously trigger bots")
	fake.is_host = true
	fake.state.paused = true
	idle.tick(1.0, fake, true)
	check(idle._context.is_empty(), "paused state suppresses cosmetics")
	fake.state.paused = false
	fake.state.actor = 1
	idle.tick(0.0, fake, true)
	check(idle._remaining >= 20.0, "bot thinking uses slower incidental cadence")
	fake.state.phase = "showdown"
	idle.tick(1.0, fake, true)
	check(idle._context.is_empty(), "showdown has no teasing")
	var session := Session.new()
	root.add_child(session)
	var events: Array = []
	session.chip_gesture.connect(func(seat: int, sequence: int, style: int): events.append([seat, sequence, style]))
	session.start_solo("Human", 1000, 3)
	check(not session.play_bot_chip_gesture(1), "lobby bots cannot gesture autonomously")
	session.begin_hand()
	var before: Dictionary = session.state.duplicate(true)
	check(session.play_bot_chip_gesture(1), "host can emit funded bot gesture")
	check(events.size() == 1 and events[0][0] == 1 and Styles.is_valid_style(events[0][2]), "uses existing authoritative event and styles")
	check(session.state == before, "no gameplay revision cards or stack mutation")
	check(not session.play_bot_chip_gesture(1), "session rate limit rejects bot floods")
	check(not session.play_bot_chip_gesture(0) and not session.play_bot_chip_gesture(99), "bot hook cannot target human or invalid seat")
	session._accept_chip_gesture(2, -3, session.state.hand_id, 1, session.state.room_id)
	check(events.size() == 1, "human request path cannot impersonate bot even in local mode")
	session.is_host = false
	check(not session.play_bot_chip_gesture(2), "non-host bot hook rejected")
	session.is_host = true
	session._paused = true
	check(not session.play_bot_chip_gesture(2), "authoritative pause rejects bot gesture")
	session.leave_game()
	session.free()
	idle.free()
	print("AI_CHIP_IDLE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
