extends SceneTree
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
var app: Control
class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		music.level = 0
		music.paused = true
	func _save_settings() -> void: pass
class HapticSpy extends RefCounted:
	var pulses: Array = []
	func pulse(kind: String, strength: float) -> void: pulses.append([kind, strength])
	func stop() -> void: pass
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until: await process_frame
func touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)
func _run() -> void:
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app.session.start_local(["Player", "Friend"], 1000)
	app.session.begin_hand()
	var deadline := Time.get_ticks_msec() + 5000
	while app.presentation_busy and Time.get_ticks_msec() < deadline: await process_frame
	check(not app.presentation_busy, "initial real chip presentation completed")
	await wait_ms(100)
	var spy := HapticSpy.new()
	app.feedback.haptics = spy
	app.feedback.haptic_strength = 0.8
	var state_before: Dictionary = app.session.state.duplicate(true)
	var card: Control = app.board_cards[3]
	var point: Vector2 = card.get_global_rect().get_center()
	check(card.public_interactive and not card.face_up and card.card_id == -1, "unrevealed public card is touchable without private identity")
	touch(point, true)
	await wait_ms(110)
	check(card._public_down and not card.face_up and not card._peeking, "accepted touch lifts the back without revealing")
	check(spy.pulses.size() == 1, "accepted touch drives one haptic")
	var drag := InputEventScreenDrag.new()
	drag.position = point + Vector2(50, 8) * app.canvas.scale
	drag.relative = Vector2(50, 8) * app.canvas.scale
	root.push_input(drag, true)
	await wait_ms(180)
	check(card._public_offset.x > 2.0 and card._public_offset.length() <= 16.1, "real viewport drag moves a bounded card")
	check(spy.pulses.size() >= 2, "actual card movement drives haptic feedback")
	var pulse_count := spy.pulses.size()
	await wait_ms(350)
	check(spy.pulses.size() == pulse_count, "stationary owner heartbeat does not repeat haptics")
	app.session._publish()
	await wait_ms(100)
	check(card._public_pointer != -2 and card._public_down, "real new-revision sync presentation preserves held card")
	check(app.session.state.players == state_before.players and app.session.state.board == state_before.board and app.session.state.pot == state_before.pot, "ordinary publish preserves hand and pot")
	state_before = app.session.state.duplicate(true)
	touch(point, false)
	await wait_ms(500)
	check(not card._public_down and card._public_offset.length() < 0.1, "release springs back to original geometry")
	check(spy.pulses.size() == pulse_count + 1, "release has a single synchronized contact")
	check(app.session.state == state_before, "cosmetic touch never changes cards, pot, actor or revision")
	touch(point, true)
	await wait_ms(100)
	app._show_settings()
	await wait_ms(100)
	check(not card._public_down and card._public_pointer == -2, "modal clears ongoing public touch")
	app._on_board_gesture(1, 999, 3, "press", Vector2.ONE)
	check(not card._public_down, "remote touch cannot restart a card behind a modal")
	app._close_modal()
	check(card.public_interactive, "closing modal restores public-card input")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._on_board_gesture(1, 1000, 3, "press", Vector2.ONE)
	check(not card._public_down, "remote touch cannot restart a backgrounded card")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://board_touch_ui.png") == OK, "capture rendered touch table")
	app.queue_free()
	await process_frame
	await wait_ms(150)
	print("BOARD_TOUCH_UI_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
