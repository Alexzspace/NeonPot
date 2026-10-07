extends SceneTree

const Scene = preload("res://scenes/main.tscn")
const Gestures = preload("res://scripts/chip_gestures.gd")
var checks := 0
var failures := 0
var app: Control
var settings_existed := false
var settings_backup := PackedByteArray()

class HapticProbe extends RefCounted:
	var calls := 0
	var stopped := 0
	func pulse(_kind: String, _strength: float) -> void: calls += 1
	func stop() -> void: stopped += 1

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TACTILE_UI: " + message)

func _idle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not app.presentation_busy and not app.input_locked, "presentation completes")

func _tap(control: Control, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = control.get_global_transform() * at
	touch.pressed = true
	root.push_input(touch, true)
	touch.pressed = false
	root.push_input(touch, true)

func _run() -> void:
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed: settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	root.size = Vector2i(1311, 603)
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app._set_preview_profile("iphone", false)
	app.music.set_level(0)
	app.music.set_paused(true)
	var probe := HapticProbe.new()
	app.feedback.haptics = probe
	app.feedback.volume = 0.7
	app.feedback.haptic_strength = 0.7
	app.session.start_local(["Alice", "Bob"], 1000)
	await _idle()
	var before: Dictionary = app.session.state.duplicate(true)
	var voices: int = app.feedback._voice
	_tap(app.chip_touch, app.chip_touch.size * 0.5)
	await process_frame
	check(app.presentation_events.any(func(e): return e.kind == "fidget"), "touching chips invokes authorized local gesture")
	check(app.chip_display._animation_kind.begins_with("flourish"), "own full chip stack rocks")
	check(app.feedback._voice > voices and probe.calls > 0, "own gesture acknowledges finger contact immediately")
	check(app.session.state == before, "chip play never changes bets, turn, or balances")
	await create_timer(Gestures.duration(app.chip_display._flourish_style) + 0.1).timeout
	var own_pulses: int = probe.calls
	app.feedback.public_audio = false
	voices = app.feedback._voice
	app._on_chip_gesture(1, 500)
	check(app._fidget_nodes.has(1), "peer gesture creates visible chips at peer seat")
	await create_timer(Gestures.duration(0) + 0.3).timeout
	check(app.feedback._voice > voices and probe.calls > own_pulses, "peer ceramic contact synchronizes sound and light haptics even with table sounds off")
	check(app.flight_layer.get_child_count() == 0, "peer transient chips clean up")
	app.session.begin_hand()
	await _idle()
	app.session.set_local_seat(app.session.state.actor)
	await _idle()
	var initial_pot: int = app.shown_state.pot
	_tap(app.amount_input, Vector2(app.amount_input.size.x * 0.65, 66))
	await process_frame
	check(app.amount_input.value > app.amount_input.min_value and app.amount_input.value < app.amount_input.max_value, "large thumb slider selects a raise amount")
	check(app.shown_state.pot == initial_pot, "drag selection does not commit a bet")
	_tap(app.amount_input, Vector2(app.amount_input.size.x - 90, 20))
	await process_frame
	check(is_instance_valid(app.modal), "amount caption opens optional exact entry")
	app._close_modal()
	app._show_settings()
	await process_frame
	for slider in [app.sfx_slider, app.music_slider, app.haptic_slider]:
		check(slider.min_value == 0 and slider.max_value == 10 and slider.step == 1, "mixer exposes ten levels plus off")
	voices = app.feedback._voice
	own_pulses = probe.calls
	_tap(app.sfx_slider, Vector2(30 + (app.sfx_slider.size.x - 60) * 0.4, 80))
	await process_frame
	check(is_equal_approx(app.feedback.volume, 0.4), "SFX touch snaps to level four")
	check(app.feedback._voice > voices and probe.calls > own_pulses, "SFX detent immediately previews sound and haptics")
	voices = app.feedback._voice
	own_pulses = probe.calls
	_tap(app.haptic_slider, Vector2(30 + (app.haptic_slider.size.x - 60) * 0.3, 80))
	await process_frame
	check(is_equal_approx(app.feedback.haptic_strength, 0.3), "haptic touch snaps to level three")
	check(app.feedback._voice > voices and probe.calls > own_pulses, "haptic detent immediately previews both channels")
	_tap(app.sfx_slider, Vector2(30, 80))
	await process_frame
	check(app.feedback.volume == 0, "zero detent mutes SFX")
	voices = app.feedback._voice
	app._preview_setting()
	check(app.feedback._voice == voices, "preview never overrides zero volume")
	check(not app.music.title().is_empty(), "music desk shows the real current title")
	var index: int = app.music.index
	app.music.next_track()
	check(app.music.index != index and app.music.paused, "next selects a track without overriding pause")
	app._on_chip_gesture(1, 501)
	app._cancel_presentation()
	await process_frame
	check(app.flight_layer.get_child_count() == 0, "scene cancellation clears peer gesture during mixer")
	app.session.leave_game()
	app.queue_free()
	await create_timer(0.8).timeout
	if settings_existed:
		var saved := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		saved.store_buffer(settings_backup)
		saved.close()
	else:
		DirAccess.remove_absolute("user://settings.cfg")
	print("TACTILE_UI_SUMMARY checks=%d failures=%d hardware_validated=false" % [checks, failures])
	quit(1 if failures else 0)
