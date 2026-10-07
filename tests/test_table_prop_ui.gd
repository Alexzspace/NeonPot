extends SceneTree
const Main = preload("res://scripts/main.gd")
class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0.2
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
class HapticProbe extends RefCounted:
	var pulses: Array = []
	func pulse(kind: String, strength: float) -> void: pulses.append([kind, strength])
	func stop() -> void: pass
var checks := 0
var failures := 0
var app: Control
var haptics := HapticProbe.new()
var props: Array = []
var public_events: Array = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TABLE_PROP_UI: " + description)
func wait_ms(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline: await process_frame
func idle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline: await process_frame
	check(not app.presentation_busy and not app.input_locked, "presentation completes")
func touch(control: Control, pressed: bool, id: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = control.get_global_transform() * (control.size * 0.5)
	event.pressed = pressed
	root.push_input(event, true)
func tap(control: Control, mouse_too: bool = false) -> void:
	touch(control, true)
	touch(control, false)
	if mouse_too:
		var event := InputEventMouseButton.new()
		event.device = InputEvent.DEVICE_ID_EMULATION
		event.position = control.get_global_transform() * (control.size * 0.5)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		root.push_input(event, true)
		event.pressed = false
		root.push_input(event, true)
func deck_positions() -> Array:
	return app.deck_cards.map(func(card): return [card.position, card.rotation])
func _run() -> void:
	root.size = Vector2i(1440, 660)
	app = Probe.new()
	root.add_child(app)
	app.feedback.haptics = haptics
	await process_frame
	app._prepare_home_entrance()
	check(app._entrance_pending and app.home_chip_touch.disabled, "home entrance starts with chip touch disabled")
	var home_rest: Array = app._entrance_poses.duplicate()
	app.play_home_entrance()
	await wait_ms(1250)
	check(not app._entrance_pending and not app.home_chip_touch.disabled and app._entrance_poses.is_empty(), "entrance completes and enables interaction")
	for pose in home_rest:
		check(pose.node.position.is_equal_approx(pose.position) and is_equal_approx(pose.node.rotation, pose.rotation) and pose.node.modulate == pose.modulate, "entrance restores each original pose and opacity")
	app._prepare_home_entrance()
	app.play_home_entrance()
	app._show_settings()
	check(app._entrance_poses.is_empty() and not app.home_chip_touch.disabled, "opening settings cancels partial entrance safely")
	app._close_modal()
	app.session.table_prop_gesture.connect(func(seat, sequence, kind): props.append([seat, sequence, kind]))
	app.session.board_gesture.connect(func(seat, sequence, index, kind, offset): public_events.append([seat, sequence, index, kind, offset]))
	app.session.start_local(["Alice", "Bob"])
	app.session.begin_hand()
	await idle()
	await wait_ms(200)
	var before: Dictionary = app.session.state.duplicate(true)
	var deck_before: Array = app.session._engine._deck.duplicate()
	var rest := deck_positions()
	haptics.pulses.clear()
	tap(app.deck_touch, true)
	check(props.size() == 1 and props[0][2] == "deck", "ScreenTouch plus emulated mouse produces one authoritative deck echo")
	await wait_ms(100)
	check(deck_positions() != rest, "deck cards really lift and rotate")
	await wait_ms(440)
	check(deck_positions() == rest, "parallel return completes all deck cards within animation duration")
	check(haptics.pulses.filter(func(p): return p[0] == "shuffle").size() == 1, "deck contact produces one tactile event")
	tap(app.pot_touch, true)
	check(props.size() == 2 and props[-1][2] == "pot", "ScreenTouch reaches authoritative pot echo once")
	check(app.pot_display._animation_kind == "nudge", "pot echo starts local 3D nudge")
	await wait_ms(500)
	check(app.pot_display._animation_kind != "nudge", "pot nudge settles")
	check(haptics.pulses.filter(func(p): return p[0] == "pot_touch").size() == 1, "pot contact produces one tactile event")
	check(app.session.state == before and app.session._engine._deck == deck_before, "prop taps never alter state or the real deck order")
	haptics.pulses.clear()
	tap(app.pot_touch)
	tap(app.deck_touch)
	await wait_ms(550)
	check(haptics.pulses.filter(func(p): return p[0] == "pot_touch").size() == 1 and haptics.pulses.filter(func(p): return p[0] == "shuffle").size() == 1, "independent pot and deck taps do not cancel each other's contact")
	# Two valid host events can arrive close together after reliable transport stalls.
	# Reproduce only that delivery timing, without bypassing or changing gameplay.
	app._on_table_prop_gesture(1, 600, "deck")
	await wait_ms(80)
	app._on_table_prop_gesture(1, 601, "deck")
	await wait_ms(550)
	check(deck_positions() == rest, "delayed same-kind echoes restore the canonical deck pose without drift")
	app._cancel_table_props()
	haptics.pulses.clear()
	tap(app.deck_touch)
	await wait_ms(50)
	app._show_settings()
	await wait_ms(550)
	check(deck_positions() == rest and haptics.pulses.filter(func(p): return p[0] == "shuffle").size() == 1, "modal cancels deck pose without replaying the already immediate contact")
	var count := props.size()
	tap(app.deck_touch)
	check(props.size() == count, "modal blocks prop touch")
	app._close_modal()
	tap(app.deck_touch)
	app.notification(Main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await wait_ms(550)
	check(deck_positions() == rest, "focus loss restores deck")
	count = props.size()
	tap(app.pot_touch)
	check(props.size() == count, "unfocused app suppresses new gestures")
	app.notification(Main.NOTIFICATION_APPLICATION_FOCUS_IN)
	haptics.pulses.clear()
	var private_card: Control = app.own_cards[0]
	touch(private_card, true)
	check(private_card._peeking and not private_card.face_up, "private card touch peeks without changing authoritative face")
	touch(private_card, false)
	check(not private_card._peeking and haptics.pulses == [["peek_open", 1.0], ["peek_close", 1.0]], "private press and release use local full-strength haptics")
	check(props.size() == count and public_events.is_empty() and app.session.state == before, "private peek emits no public interaction or gameplay changes")
	var burst_start := props.size()
	haptics.pulses.clear()
	for index in 10:
		tap(app.deck_touch, true)
		tap(app.pot_touch, true)
		check(app._prop_tweens.size() <= 2, "rapid touches keep at most one tween per object")
		await wait_ms(60)
	check(props.size() == burst_start + 20, "native touch path accepts more than ten taps per second per object")
	check(haptics.pulses.filter(func(p): return p[0] == "shuffle").size() == 10 and haptics.pulses.filter(func(p): return p[0] == "pot_touch").size() == 10, "every rapid tap produces an immediate contact")
	await wait_ms(550)
	check(deck_positions() == rest and app.pot_display._animation == null, "rapid burst settles without trailing animation queue")
	tap(app.deck_touch)
	app.session._on_server_disconnected()
	await wait_ms(550)
	check(deck_positions() == rest and app._prop_tweens.is_empty(), "disconnect snapshot cancels pending prop animation")
	app.session.leave_game()
	app.queue_free()
	await wait_ms(100)
	print("TABLE_PROP_UI checks=%d failures=%d hardware_validated=false" % [checks, failures])
	quit(0 if failures == 0 else 1)
