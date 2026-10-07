extends SceneTree
## Settings are simulated in a subclass, never written over the user's settings file.
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0

class StartupProbe extends Main:
	var music_started_before_preferences := false
	func _load_settings() -> void:
		music_started_before_preferences = is_instance_valid(music._player) and music._player.playing
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
		music.select_track(0)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("INTERACTION_LIFECYCLE: " + message)

func _idle(app: Control) -> void:
	var until := Time.get_ticks_msec() + 5000
	while app.presentation_busy and Time.get_ticks_msec() < until:
		await process_frame
	check(not app.presentation_busy, "presentation becomes idle")

func _run() -> void:
	var app := StartupProbe.new()
	root.add_child(app)
	await process_frame
	check(not app.music_started_before_preferences, "saved mute/pause preferences apply before any music playback starts")
	check(app.music.level == 0 and app.music.paused and not app.music._player.playing, "muted paused preferences survive startup")
	app._on_chip_gesture(0, 1)
	check(app.presentation_events.is_empty(), "empty scene rejects gestures safely")
	app.session.start_local(["Alice", "Bob"], 1000)
	await _idle(app)
	var before: Dictionary = app.session.state.duplicate(true)
	app.session.request_chip_gesture()
	app.session.request_chip_gesture()
	var count := 0
	for item in app.presentation_events:
		if item.kind == "fidget": count += 1
	check(count == 1, "duplicate UI input produces one authoritative fidget")
	check(app.session.state == before, "gesture leaves full authoritative state untouched")
	app._on_chip_gesture(1, 2)
	check(app._fidget_nodes.has(1), "remote gesture creates an owned temporary pile")
	app._build_ui()
	await process_frame
	check(app._fidget_nodes.is_empty() and app.flight_layer.get_child_count() == 0, "UI rebuild removes peer fidgets and their tweens")
	check(app.session.state == before, "UI reconstruction preserves balances and private snapshot")
	var music_id: int = app.music.get_instance_id()
	var stream = app.music._player.stream
	app._show_settings()
	await process_frame
	app._close_modal()
	await process_frame
	app.music.next_track()
	check(app.music.paused and not app.music._player.playing, "track change after closing mixer respects pause without stale control access")
	app._show_settings()
	await process_frame
	check(app.music_slider.value == 0, "rebuilt music slider retains mute level")
	app._close_modal()
	stream = app.music._player.stream
	app._build_ui()
	check(app.music.get_instance_id() == music_id and app.music._player.stream == stream, "UI rebuild keeps current music node and stream")
	app.session.begin_hand()
	await _idle(app)
	var own_ids: Array = []
	for card in app.own_cards:
		own_ids.append(card.card_id)
		check(not card.face_up, "own cards concealed before gesture")
	app._on_chip_gesture(1, 10)
	app._show_settings()
	for index in app.own_cards.size():
		check(not app.own_cards[index].face_up and app.own_cards[index].card_id == own_ids[index], "peer feedback and mixer never reveal or replace private cards")
	app._close_modal()
	var paused := app.shown_state.duplicate(true)
	paused.paused = true
	paused.revision += 1
	app._on_state(paused)
	var event_count: int = app.presentation_events.size()
	app._on_chip_gesture(1, 11)
	await process_frame
	check(app.presentation_events.size() == event_count and app._fidget_nodes.is_empty(), "paused table suppresses gesture and clears peer geometry")
	app._on_state({})
	app._on_chip_gesture(1, 12)
	check(app.presentation_events.size() == event_count, "empty-state gesture cannot reuse old identity")
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.7).timeout
	print("INTERACTION_LIFECYCLE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
