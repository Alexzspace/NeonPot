extends SceneTree
const Main = preload("res://scripts/main.gd")
const Guide = preload("res://scripts/tutorial_view.gd")
var checks := 0
var failures := 0
var app: Control
class Probe extends Main:
	func _load_settings() -> void:
		# This fixture intentionally checks Chinese labels; English defaults have a separate test.
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOLO_UI: " + why)
func _initialize() -> void: _run.call_deferred()
func _idle() -> void:
	var start := Time.get_ticks_msec()
	while app.presentation_busy or app.input_locked or app._deal_after_entry or not app._presentation_queue.is_empty():
		if app._deal_after_entry: app._process(0.0) # This fixture disables automatic processing.
		if Time.get_ticks_msec() - start > 20000:
			check(false, "presentation timed out")
			break
		await process_frame
func _tap(button: Control) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	var mouse := InputEventMouseButton.new()
	mouse.position = event.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse.pressed = false
	root.push_input(mouse, true)
func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "user://solo_%s_%s.png" % [app.preview_profile, label]
	check(root.get_texture().get_image().save_png(path) == OK, "save visual evidence")
	print("SOLO_CAPTURE " + ProjectSettings.globalize_path(path))
func _run() -> void:
	root.size = Vector2i(1311, 603)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	app = Probe.new()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set_process(false)
	var profile := "iphone"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phone="): profile = arg.trim_prefix("--phone=")
	app._set_preview_profile(profile, true)
	await process_frame
	check(app.player_count.value == 5, "five seats by default")
	var menu_text := ""
	for button in app.home.find_children("*", "Button", true, false): menu_text += button.text
	check("单人模式" in menu_text and "同屏" not in menu_text, "solo replaces pass-and-play menu")
	_tap(app.home_chip_touch)
	check(app.home_chip_display._animation_kind == "flourish", "actual home touch animates chips")
	app.stack_input.value = 500
	check(app.home_chip_display._amount == 500 and app.home_chip_display._animation == null, "home amount change updates and cancels old flourish")
	app._show_reference()
	var entry: Button
	for button in app.modal.find_children("*", "Button", true, false):
		if "新手教学" in button.text: entry = button
	check(is_instance_valid(entry), "reference contains tutorial entry")
	_tap(entry)
	await process_frame
	check(app.modal.get_script() == Guide and app.modal.size == app.canvas.size, "entry opens full-canvas tutorial")
	var music_id: int = app.music.get_instance_id()
	for lang in ["zh", "en"]:
		app.modal.language = lang
		app.modal.show_page(0)
		for page in Guide.PAGE_COUNT:
			await process_frame
			check(app.modal.page_index == page, "touch changes page exactly once")
			check(app.modal.previous_button.disabled == (page == 0), "previous boundary")
			for label in app.modal.detail_labels + app.modal.row_titles + [app.modal.title_label, app.modal.intro_label]:
				check(label.get_minimum_size().y <= label.size.y + 1, "tutorial text fits allocated height")
				check(label.get_global_rect().end.x <= app.safe_rect.end.x + 1, "tutorial text inside safe horizontal extent")
			await _capture("tutorial_%s_%d" % [lang, page])
			if page < Guide.PAGE_COUNT - 1:
				_tap(app.modal.next_button)
		_tap(app.modal.next_button)
		await process_frame
		check(app.modal.get_script() != Guide, "last page returns to hand chart")
		app._show_tutorial()
	app._close_modal()
	check(app.music.get_instance_id() == music_id, "tutorial preserves music node")
	app._start_solo()
	await _idle()
	check(app.session.is_solo and app.shown_state.players.size() == 5 and app.shown_state.you == 0, "solo UI creates default table")
	app._begin_hand()
	await _idle()
	var guard := 0
	while app.shown_state.actor == 0 and guard < 10:
		app._act("check" if app.shown_state.legal.check else "call")
		await _idle()
		guard += 1
	check(app.shown_state.actor > 0, "bot turn reached")
	var revision: int = app.shown_state.revision
	app._show_tutorial()
	app._process(2.0)
	check(app.shown_state.revision == revision, "tutorial pauses AI")
	app._close_modal()
	app._application_active = false
	app._process(2.0)
	check(app.shown_state.revision == revision, "background pauses AI")
	app._application_active = true
	app.input_locked = true
	app._process(2.0)
	check(app.shown_state.revision == revision, "input transition pauses AI")
	app.input_locked = false
	app.presentation_busy = true
	app._process(2.0)
	check(app.shown_state.revision == revision, "chip presentation pauses AI")
	app.presentation_busy = false
	app._process(0.4)
	check(app.shown_state.revision == revision, "bot pacing waits")
	app._process(0.4)
	check(app.shown_state.revision == revision + 1 and app.shown_state.you == 0, "bot advances exactly one action without changing viewpoint")
	await _idle()
	var roles := ""
	for slot in app.seats: roles += " ".join(slot.badge.roles) + " "
	check("D " in roles and "SB " in roles and "BB " in roles, "dealer and blind badges visible")
	await _capture("table")
	# Complete the actual UI hand, including the human folding and AI finishing.
	guard = 0
	while app.shown_state.phase != "showdown" and guard < 100:
		if app.shown_state.actor == 0:
			app._act("fold")
		else:
			app._application_active = true
			app._process(1.0)
		await _idle()
		guard += 1
	check(app.shown_state.phase == "showdown", "AI opponents finish after human folds")
	await _capture("showdown")
	app._close_modal()
	# End-of-match restart stays available even when can_start is false.
	for seat in app.session._engine._players.size():
		app.session._engine._players[seat].stack = 3250 if seat == 0 else 0
	app.session._publish()
	await _idle()
	app._close_modal()
	check(app._solo_finished() and not app.deal_button.disabled and app.deal_button.text == "重新开局", "winner can start a new match with only one funded seat")
	app._begin_hand()
	await _idle()
	check(app.session.state.hand_id == 1 and app.session.state.players.size() == 5 and app.session.is_solo, "restart creates fresh solo session and deals")
	app.session.leave_game()
	app._process(2.0)
	check(app.session.state.is_empty(), "leaving cannot schedule further AI")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("SOLO_UI_TEST_SUMMARY checks=%d failures=%d renderer=%s" % [checks, failures, DisplayServer.get_name()])
	quit(1 if failures else 0)
