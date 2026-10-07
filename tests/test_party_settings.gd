extends SceneTree
const Main = preload("res://scripts/main.gd")
const Card = preload("res://scripts/card_view.gd")
const Timing = preload("res://scripts/presentation_timing.gd")
class Probe extends Main:
	var saves := 0
	var saved := ConfigFile.new()
	func _load_settings() -> void:
		frame_limit = int(saved.get_value("preferences", "frame_limit", 60))
		Timing.rate = float(saved.get_value("preferences", "animation_rate", 1.0))
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void:
		saves += 1
		saved.set_value("preferences", "frame_limit", frame_limit)
		saved.set_value("preferences", "animation_rate", Timing.rate)
var checks := 0
var failures := 0
var app: Probe
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PARTY_SETTINGS: " + message)
func button(parent: Node, text: String) -> Button:
	if parent is Button and parent.text == text: return parent
	for child in parent.get_children():
		var found := button(child, text)
		if found != null: return found
	return null
func settle_home() -> void:
	await create_timer(1.25).timeout
	check(app._entrance == null, "home entrance settles")
func idle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline: await process_frame
	check(not app.presentation_busy and not app.input_locked, "scripted dealing and chip transfer complete")
func run() -> void:
	root.size = Vector2i(1440, 660)
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	check(app.frame_limit == 60 and Engine.max_fps == 60 and Timing.rate == 1.0, "new profile defaults to60FPS and normal pace")
	await settle_home()
	app.name_edit.text = "Night Guest"
	app.stack_input.value = 7500
	app.player_count.value = 4
	var line := app._home_title_label.text
	var company := app._home_company_label.text
	app._show_settings()
	check(button(app.modal, "旁观视角重看把玩") == null and button(app.modal, "WATCH FROM OTHER SEAT") == null, "observer replay is absent")
	app._show_play_settings()
	await process_frame
	check(app._entrance == null and app._home_title_label.text == line, "changing settings tabs does not restart underlying home")
	for limit in [30, 60, 120]:
		var target := button(app.modal, "%d FPS" % limit)
		check(target != null, "frame limit button exists")
		target.pressed.emit()
		check(app.frame_limit == limit and Engine.max_fps == limit, "frame choice applied immediately")
		app.frame_limit = -1
		app._load_settings()
		check(app.frame_limit == limit, "frame callback persists selected choice through profile reload")
	for pair in [["0.25×", 0.25], ["0.5×", 0.5], ["1×", 1.0], ["1.5×", 1.5], ["2×", 2.0]]:
		button(app.modal, pair[0]).pressed.emit()
		check(is_equal_approx(Timing.duration(1.2), 1.2 / pair[1]), "pace scales cinematic duration")
		Timing.rate = 9
		app._load_settings()
		check(Timing.rate == pair[1] and Engine.time_scale == 1.0, "pace persists without changing global engine time")
		if pair[1] == 0.25 and DisplayServer.get_name() != "headless":
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var capture_path := "user://party_settings_quarter_speed.png"
			check(root.get_texture().get_image().save_png(capture_path) == OK, "capture quarter-speed setting")
			print("PARTY_SETTINGS_CAPTURE " + ProjectSettings.globalize_path(capture_path))
	check(app.saves == 8, "every settings choice saves exactly once")
	app._close_modal()
	await process_frame
	check(app._entrance != null and app._entrance.is_valid(), "closing settings starts home entrance")
	check(app._home_title_label.text != line and app._home_company_label.text != company, "home return refreshes both no-repeat lines")
	check(app.name_edit.text == "Night Guest" and app.stack_input.value == 7500 and app.player_count.value == 4, "home return preserves entered name and both wheels")
	await settle_home()
	Engine.max_fps = 120
	var card := Card.new()
	card.size = Vector2(132, 184)
	root.add_child(card)
	var elapsed: Array[float] = []
	for rate in [0.25, 2.0]:
		Timing.rate = rate
		var start := Time.get_ticks_msec()
		card.deal(0.0)
		await card._deal_tween.finished
		var deal_seconds := (Time.get_ticks_msec() - start) / 1000.0
		check(absf(deal_seconds - 0.48 / rate) < 0.20, "actual deal tween follows chosen pace")
		start = Time.get_ticks_msec()
		card.flip(true)
		await card._flip_tween.finished
		var flip_seconds := (Time.get_ticks_msec() - start) / 1000.0
		check(card.face_up and absf(flip_seconds - 0.31 / rate) < 0.20, "actual flip tween follows chosen pace and reveals")
		app.session.start_local(["Alice", "Bob"])
		start = Time.get_ticks_msec()
		app.session.begin_hand()
		await idle()
		elapsed.append((Time.get_ticks_msec() - start) / 1000.0)
		check(app.shown_state.phase == "preflop" and app._presentation_queue.is_empty(), "real first hand ends its presentation with correct phase")
		app.session.leave_game()
		await process_frame
	check(elapsed[0] > elapsed[1] * 4.0 and elapsed[1] > 0.05, "slow and fast actual presentation elapsed times differ substantially")
	print("PARTY_PACE slow=%.3f fast=%.3f" % [elapsed[0], elapsed[1]])
	card.queue_free()
	app.queue_free()
	await process_frame
	await process_frame
	Timing.rate = 1.0
	Engine.max_fps = 60
	print("PARTY_SETTINGS checks=%d failures=%d settings_io=memory_only graphical=%s" % [checks, failures, DisplayServer.get_name() != "headless"])
	quit(0 if failures == 0 else 1)
