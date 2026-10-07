extends SceneTree
## Desktop geometry and presentation checks using explicit, simulated phone profiles.

const Scene = preload("res://scenes/main.tscn")
const Card = preload("res://scripts/card_view.gd")
const TouchSliderScript = preload("res://scripts/touch_slider.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
const NATIVE_SIZES := {"iphone": Vector2i(2622, 1206), "android": Vector2i(2400, 1080), "android195": Vector2i(2340, 1080)}
var app: Control
var profile := "iphone"
var native_size := Vector2i(2622, 1206)
var capture_native := false
var checks := 0
var failures := 0
var target_notes: Array[String] = []
var minimum_target := 1000.0
var minimum_primary := 1000.0
var settings_existed := false
var settings_backup := PackedByteArray()

class HapticProbe extends RefCounted:
	var pulses := 0
	var stops := 0
	func pulse(_kind: String, _strength: float) -> void:
		pulses += 1
	func stop() -> void:
		stops += 1

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[%s] %s" % [profile, message])

func _nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_nodes(child))
	return result

func _wait_idle(label: String) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while (app.presentation_busy or app.input_locked or not app._presentation_queue.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not app.presentation_busy and not app.input_locked and app._presentation_queue.is_empty(), label + ": presentation reaches idle")
	await process_frame

func _inside(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(0.8).encloses(inner)

func _is_target(node: Node) -> bool:
	if node is LineEdit and node.get_parent() is SpinBox:
		return false
	return node is BaseButton or node is SpinBox or node is LineEdit or node is HSlider or node is TouchSliderScript or (node is Card and node.interactive)

func _slider_touch(slider: Range, index: int, pressed: bool, point: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = pressed
	touch.position = slider.get_global_transform() * point
	root.push_input(touch, true)

func _slider_drag(slider: Range, index: int, point: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = slider.get_global_transform() * point
	root.push_input(drag, true)

func _tap_button(button: BaseButton) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = button.get_global_rect().get_center()
	touch.pressed = true
	root.push_input(touch, true)
	touch.pressed = false
	root.push_input(touch, true)
	await process_frame

func _test_pixel_transport(player: Control, stage: String) -> void:
	app.music.set_level(0)
	app.music.set_paused(true)
	app.music.select_track(2)
	var table_before: Dictionary = app.session.state.duplicate(true)
	await _tap_button(player.next_button)
	check(app.music.index == 3 and app.music.paused, stage + " next touch advances exactly once and preserves pause")
	check(player.title_label.text == app.music.title(), stage + " actual song title follows next")
	await _tap_button(player.previous_button)
	check(app.music.index == 2, stage + " previous touch returns exactly one track")
	await _tap_button(player.pause_button)
	check(not app.music.paused and app.music._player.playing, stage + " play touch starts playback")
	# Independent human taps must clear the transport's 120 ms duplicate-input guard.
	await create_timer(0.15).timeout
	await _tap_button(player.pause_button)
	check(app.music.paused, stage + " pause touch suspends playback")
	check(app.session.state == table_before, stage + " transport touches never change poker state")
	check(player.title_label.clip_contents and player.title_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		stage + " real title is clipped and never captures touches")
	for button in [player.previous_button, player.pause_button, player.next_button]:
		check(not player.title_label.get_global_rect().intersects(button.get_global_rect()), stage + " title clipping region excludes transport target")

func _test_raise_drag(language: String) -> void:
	var slider: Range = app.amount_input
	check(slider is TouchSliderScript and slider.editable, language + " exact amount uses active large touch slider")
	var prior_state: Dictionary = app.session.state.duplicate(true)
	var throws_before := _event_count("throw")
	_slider_touch(slider, 8, true, Vector2(30, slider.size.y * 0.7))
	check(slider.value == slider.min_value, language + " viewport press selects legal minimum")
	_slider_drag(slider, 8, Vector2(slider.size.x - 30, slider.size.y * 0.7))
	check(slider.value == slider.max_value, language + " viewport drag selects legal maximum")
	_slider_drag(slider, 8, Vector2(slider.size.x * 0.5, slider.size.y * 0.7))
	var midpoint: float = roundf((slider.min_value + slider.max_value) * 0.5)
	check(absf(slider.value - midpoint) <= 1.0, language + " viewport drag maps midpoint to exact integer")
	_slider_touch(slider, 8, false, Vector2(slider.size.x * 0.5, slider.size.y * 0.7))
	await process_frame
	check(app.session.state == prior_state and _event_count("throw") == throws_before,
		language + " slider drag and release never submit an action or launch chips")
	check(slider.value >= slider.min_value and slider.value <= slider.max_value and slider.value == roundf(slider.value),
		language + " released raise amount remains within legal integer range")

func _test_setting_steps(language: String) -> void:
	var real_haptics = app.feedback.haptics
	var probe := HapticProbe.new()
	app.feedback.haptics = probe
	app.music.set_paused(true)
	app.feedback.haptic_strength = 0.7
	app.haptic_slider.value = 7
	for slider in [app.sfx_slider, app.music_slider, app.haptic_slider]:
		check(slider is TouchSliderScript and slider.min_value == 0 and slider.max_value == 10 and slider.step == 1 and slider.notches,
			language + " settings use eleven notched integer levels")
		slider.value = 10
		for level in range(11):
			var sounds_before: int = app.feedback._voice
			var pulses_before: int = probe.pulses
			var stops_before: int = probe.stops
			var x: float = lerpf(30.0, slider.size.x - 30.0, float(level) / 10.0)
			_slider_touch(slider, 9, true, Vector2(x, slider.size.y * 0.7))
			_slider_touch(slider, 9, false, Vector2(x, slider.size.y * 0.7))
			check(slider.value == level, language + " settings touch reaches level %d" % level)
			if slider == app.sfx_slider:
				check(is_equal_approx(app.feedback.volume, float(level) / 10.0), language + " SFX level maps to volume")
			elif slider == app.music_slider:
				check(app.music.level == level, language + " music level remains integer")
			else:
				check(is_equal_approx(app.feedback.haptic_strength, float(level) / 10.0), language + " haptic level maps to strength")
			check(app.feedback._voice == sounds_before + (1 if app.feedback.volume > 0.0 else 0),
				language + " every changed level previews sound without breaking mute")
			check(probe.pulses == pulses_before + (1 if app.feedback.haptic_strength > 0.0 else 0),
				language + " every changed level previews only enabled haptics")
			if app.feedback.haptic_strength == 0.0:
				check(probe.stops == stops_before + 1, language + " haptic zero level stops vibration")
	app.feedback.volume = 0.0
	app.feedback.haptic_strength = 0.0
	app.sfx_slider.value = 0
	app.haptic_slider.value = 0
	app.music.set_level(0)
	app.music_slider.value = 0
	app.feedback.haptics = real_haptics
	app.music_title.text = "A deliberately long jazz track title — midnight ceramic chips and a very quiet table — 测试长曲名滚动且不遮挡控制按钮"
	check(app.music_title.clip_contents and app.music_title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		language + " music marquee clips its drawing and cannot intercept transport buttons")
	var title_font: Font = app.music_title.get_theme_default_font()
	check(title_font.get_string_size(app.music_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x > app.music_title.size.x,
		language + " long-title fixture actually overflows marquee width")
	app.music_title._process(5.0)
	check(app.music_title._elapsed >= 5.0, language + " long title advances beyond initial reading pause")
	await create_timer(0.08).timeout
	for voice in app.feedback._voices:
		voice.stop()
	await create_timer(0.08).timeout

func _audit(scope: Node, stage: String, modal_scope: bool = false) -> void:
	var safe: Rect2 = app.get_global_transform() * app.safe_rect
	var units_per_pixel := float(native_size.x) / app.size.x / 3.0
	var targets: Array[Control] = []
	for node in _nodes(scope):
		if not node is Control or not node.is_visible_in_tree():
			continue
		if _is_target(node):
			targets.append(node)
			var rect: Rect2 = node.get_global_rect()
			var label: String = node.text if node is BaseButton or node is LineEdit else node.get_class()
			label = label.replace("\n", " ").left(50)
			check(_inside(safe, rect), "%s target in safe area: %s %s" % [stage, label, rect])
			var physical := minf(rect.size.x, rect.size.y) * units_per_pixel
			minimum_target = minf(minimum_target, physical)
			if node in [app.fold_button, app.call_button, app.raise_button, app.deal_button]:
				minimum_primary = minf(minimum_primary, physical)
			check(physical >= 43.9, "%s target reaches 44pt/dp model: %s = %.2f" % [stage, label, physical])
			if profile != "iphone" and physical < 47.9:
				var note := "%s: %s %.2fdp (<48dp recommendation)" % [stage, label, physical]
				if not note in target_notes:
					target_notes.append(note)
		if node is Button:
			var font: Font = node.get_theme_font("font")
			var font_size: int = node.get_theme_font_size("font_size")
			var text_width := font.get_string_size(node.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var padding: float = node.get_theme_stylebox("normal").get_minimum_size().x
			check(text_width + padding <= node.size.x + 1.0, "%s button text and padding fit: %s" % [stage, node.text])
		if modal_scope and node is Label:
			var ancestor: Node = node.get_parent()
			var scroll_content: Control = null
			while ancestor != null and not ancestor is Panel and not ancestor is ScrollContainer:
				if ancestor is Control: scroll_content = ancestor
				ancestor = ancestor.get_parent()
			if ancestor is Panel:
				check(_inside(ancestor.get_global_rect(), node.get_global_rect()), "%s modal label stays inside panel: %s" % [stage, node.text.left(50)])
			elif ancestor is ScrollContainer and scroll_content != null:
				check(_inside(scroll_content.get_global_rect(), node.get_global_rect()), "%s scrolling label stays inside content: %s" % [stage, node.text.left(50)])
	for i in range(targets.size()):
		for j in range(i + 1, targets.size()):
			if not targets[i] is BaseButton or not targets[j] is BaseButton or targets[i].get_parent() != targets[j].get_parent():
				continue
			var overlap := targets[i].get_global_rect().intersection(targets[j].get_global_rect())
			var first: String = targets[i].text if targets[i] is BaseButton else targets[i].get_class()
			var second: String = targets[j].text if targets[j] is BaseButton else targets[j].get_class()
			check(overlap.get_area() < 0.5, "%s touch targets do not overlap: %s / %s" % [stage, first, second])

func _capture(stage: String) -> void:
	if "--capture-phone" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var expected := native_size if capture_native else Vector2i(native_size.x / 2, native_size.y / 2)
	check(picture.get_size() == expected, "Actual capture dimensions %s equal requested %s" % [picture.get_size(), expected])
	var path := "user://phone_%s_%s_%s.png" % [profile, "native" if capture_native else "half", stage]
	check(picture.save_png(path) == OK, "Save " + stage)
	print("PHONE_CAPTURE %s %s" % [picture.get_size(), ProjectSettings.globalize_path(path)])

func _event_total(kind: String) -> int:
	var amount := 0
	for event in app.presentation_events:
		if event.get("kind", "") == kind:
			amount += int(event.get("amount", 0))
	return amount

func _event_count(kind: String) -> int:
	var count := 0
	for event in app.presentation_events:
		if event.get("kind", "") == kind:
			count += 1
	return count

func _run() -> void:
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phone="):
			profile = arg.trim_prefix("--phone=")
	if not NATIVE_SIZES.has(profile):
		push_error("Unknown test phone profile")
		quit(1)
		return
	native_size = NATIVE_SIZES[profile]
	capture_native = "--native-size" in OS.get_cmdline_user_args()
	app = Scene.instantiate()
	root.add_child(app)
	await process_frame
	app.feedback.volume = 0.0
	app.feedback.haptic_strength = 0.0
	app.music.set_paused(true)
	app._set_preview_profile(profile, true)
	# Native viewport rendering may exceed the desktop width; keep the OS window half size.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if capture_native else Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = native_size if capture_native else Vector2i.ZERO
	root.size = Vector2i(native_size.x / 2, native_size.y / 2)
	await process_frame
	await process_frame
	app._layout()
	check(app.preview_profile == profile, "Requested preview profile applied")
	check(app.canvas.size.x == 1440 and app.canvas.size.y >= 660, "Responsive logical canvas retains aspect-correct controls")
	check(app.safe_rect.size.x > 0 and app.safe_rect.size.y > 0, "Nonempty simulated safe rectangle")
	check(absf(app.safe_rect.position.x / app.size.x * native_size.x - 72.0) < 0.1,
		"simulated phone uses unified 72-native-pixel left inset")
	check(absf((app.size.x - app.safe_rect.end.x) / app.size.x * native_size.x - 72.0) < 0.1,
		"simulated phone uses unified 72-native-pixel right inset")
	check(absf((app.size.y - app.safe_rect.end.y) / app.size.y * native_size.y - 36.0) < 0.1,
		"simulated phone uses unified 36-native-pixel bottom inset")
	var coverage: float = app.canvas.get_global_rect().get_area() / app.get_global_rect().get_area()
	var native_factor: float = minf(float(native_size.x - 144) / 1440.0, float(native_size.y - 36) / app.canvas.size.y)
	var expected_coverage: float = 1440.0 * app.canvas.size.y * native_factor * native_factor / (float(native_size.x) * native_size.y)
	check(absf(coverage - expected_coverage) < 0.001 and coverage > 0.87,
		"design canvas fills the unified safe area at maximal aspect-preserving scale")
	print("PHONE_CANVAS_COVERAGE profile=%s ratio=%.4f" % [profile, coverage])
	var names := ["玩家甲甲甲甲甲甲甲甲甲甲甲甲", "Birmingham Player Two", "玩家三", "Player Four", "玩家五", "Last Player Six"]
	for language in ["zh", "en"]:
		app.language = language
		app.shown_state = {}
		app._build_ui()
		app._layout()
		await process_frame
		_audit(app.canvas, language + " home")
		await _capture(language + "_home")
		app.session.start_local(names, 1000000)
		app.session.begin_hand()
		await _wait_idle(language + " six-player deal")
		app.session.set_local_seat(int(app.session.state.actor))
		await _wait_idle(language + " own seat")
		await _test_raise_drag(language)
		app.amount_input.value = 999999
		check(int(app.amount_input.value) == 999999, "Large exact raise value survives entry")
		var touch := InputEventScreenTouch.new()
		touch.index = 7
		touch.pressed = true
		touch.position = app.own_cards[0].get_global_rect().get_center()
		root.push_input(touch, true)
		await process_frame
		check(app.own_cards[0]._peeking, "Phone-scaled viewport touch reaches own card")
		touch.pressed = false
		touch.position = Vector2.ONE
		root.push_input(touch, true)
		await process_frame
		check(not app.own_cards[0]._peeking, "Phone-scaled release outside card hides it")
		_audit(app.canvas, language + " six-player table")
		check(app.seats.size() == 6, "Six seat views exist")
		await _capture(language + "_table6")
		var big_call: Dictionary = app.shown_state.duplicate(true)
		big_call.legal.call_amount = 999999
		big_call.legal.call = true
		big_call.legal.check = false
		big_call.current_bet = 999999
		big_call.revision = int(big_call.get("revision", 0)) + 1
		app._on_state(big_call)
		await _wait_idle(language + " large call label")
		_audit(app.canvas, language + " large call")
		app._show_settings()
		await process_frame
		await _test_pixel_transport(app.music_title.get_parent(), language + " settings deck")
		await _capture(language + "_settings_actual_title")
		await _test_setting_steps(language)
		_audit(app.modal, language + " settings", true)
		await _capture(language + "_settings")
		app._close_modal()
		check(not app.has_method("_show_observer"), language + " obsolete observer replay removed")
		app._show_reference()
		await process_frame
		touch.pressed = true
		touch.position = app.own_cards[0].get_global_rect().get_center()
		root.push_input(touch, true)
		await process_frame
		check(not app.own_cards[0]._peeking, "Reference overlay intercepts touches to private cards underneath")
		touch.pressed = false
		root.push_input(touch, true)
		_audit(app.modal, language + " reference", true)
		await _capture(language + "_reference")
		app._close_modal()
		app._confirm_allin()
		await process_frame
		_audit(app.modal, language + " all-in", true)
		await _capture(language + "_allin")
		app._close_modal()
		app.session.leave_game()
	# Deterministic presentation fixtures, separate from gameplay adjudication.
	app.session.start_local(names, 1000000)
	app.session.begin_hand()
	await _wait_idle("presentation fixture baseline")
	app.session.set_local_seat(int(app.session.state.actor))
	await _wait_idle("rebuild fixture actor")
	app.session.submit_action("raise", 137)
	# Language/layout rebuilds are possible while confirmed chips are still in flight.
	app._build_ui()
	await _wait_idle("rebuild during confirmed contribution")
	check(app.shown_state.current_bet == app.session.state.current_bet and app.shown_state.current_bet == 137, "UI rebuild preserves the newest confirmed action")
	check(app.pot_display._amount == app.session.state.pot, "UI rebuild restores persistent pot from authoritative state")
	var baseline: Dictionary = app.shown_state.duplicate(true)
	var duplicate_events: int = app.presentation_events.size()
	app._on_state(baseline.duplicate(true))
	await _wait_idle("duplicate active state")
	check(app.presentation_events.size() == duplicate_events, "Duplicate active state creates no repeated chip flights")
	var river: Dictionary = baseline.duplicate(true)
	river.phase = "river"
	river.actor = -1
	river.you = 0
	river.board = [20, 21, 22, 23, 24]
	river.pot = 6000000
	river.legal = {}
	river.revision = int(river.get("revision", 0)) + 1
	for seat in range(6):
		river.players[seat].stack = 0
		river.players[seat].committed = 1000000
		river.players[seat].bet = 0
		river.players[seat].all_in = true
		river.players[seat].folded = false
		river.players[seat].cards = [seat * 2, seat * 2 + 1] if seat == 0 else [-1, -1]
	var throws_before := _event_count("throw")
	var land_before := _event_total("land")
	app._on_state(river)
	await _wait_idle("all six seat contributions")
	check(_event_count("throw") - throws_before == 6, "Confirmed contributions animate from all six seats")
	check(_event_total("land") - land_before == 6000000 - int(baseline.pot), "Landed chip amounts equal the new confirmed contributions")
	check(app.pot_display._amount == 6000000, "Persistent pot display holds total confirmed chips")
	await _capture("pot6000000")
	var showdown: Dictionary = river.duplicate(true)
	showdown.phase = "showdown"
	showdown.revision += 1
	showdown.result = [{"seat": 0, "amount": 3000000}, {"seat": 5, "amount": 3000000}]
	for seat in range(6):
		showdown.players[seat].cards = [seat * 2, seat * 2 + 1]
	showdown.players[0].stack = 3000000
	showdown.players[5].stack = 3000000
	var awards_before := _event_total("award")
	var collect_before := _event_count("collect")
	var award_event_start: int = app.presentation_events.size()
	app._on_state(showdown)
	check(not is_instance_valid(app.modal), "Settlement modal waits for chip collection and distribution")
	await _wait_idle("split-pot award and organization")
	check(_event_count("collect") == collect_before + 1, "Pot is collected exactly once")
	check(_event_total("award") - awards_before == 6000000, "Award animations distribute the exact split-pot total")
	var recipients: Dictionary = {}
	for event in app.presentation_events.slice(award_event_start):
		if event.get("kind", "") == "award":
			recipients[event.seat] = int(recipients.get(event.seat, 0)) + int(event.amount)
	check(recipients == {0: 3000000, 5: 3000000}, "Split-pot flights target exactly the two winning seats")
	check(app.pot_display._amount == 0, "Pot display clears after distribution")
	check(app.chip_display._amount == 3000000, "Own winnings finish in organized stack")
	check(is_instance_valid(app.modal), "Showdown panel appears after settlement presentation")
	check(app.flight_layer.get_child_count() == 0, "No flying chip nodes remain after settlement")
	_audit(app.modal, "six-player settlement", true)
	await _capture("showdown6")
	var final_events: int = app.presentation_events.size()
	app._on_state(showdown.duplicate(true))
	await _wait_idle("duplicate settlement")
	check(app.presentation_events.size() == final_events, "Duplicate showdown never replays collection or awards")
	app._close_modal()
	app.session.leave_game()
	var final_song: WeakRef = weakref(app.music._player.stream)
	app.queue_free()
	await process_frame
	await process_frame
	# Let the real audio thread acknowledge stop; headless frames can run much faster.
	var audio_deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < audio_deadline:
		await process_frame
	check(final_song.get_ref() == null, "Active transport playback releases its song during shutdown")
	if settings_existed:
		var settings_file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		settings_file.store_buffer(settings_backup)
		settings_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	check(FileAccess.file_exists("user://settings.cfg") == settings_existed, "Original settings-file presence is restored")
	if settings_existed:
		check(FileAccess.get_file_as_bytes("user://settings.cfg") == settings_backup, "Original settings bytes are restored exactly")
	for note in target_notes.slice(0, 6):
		print("PHONE_TARGET_NOTE " + note)
	if target_notes.size() > 6:
		print("PHONE_TARGET_NOTE %d additional stage/target combinations below 48dp; all are checked against the 44dp floor." % (target_notes.size() - 6))
	print("PHONE_TEST_SUMMARY profile=%s checks=%d failures=%d minimum_target=%.2f primary=%.2f %s" % [profile, checks, failures, minimum_target, minimum_primary, "pt" if profile == "iphone" else "dp_assumed"])
	quit(1 if failures else 0)
