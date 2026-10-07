extends SceneTree
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.level = 0
		music.paused = true
	func _save_settings() -> void: pass
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until: await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/v130-entry-%s.png" % label)
func run() -> void:
	var app := Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app._start_solo()
	check(app._table_entering and app.input_locked, "solo entry locks actions")
	check(app.own_panel.modulate.a == 0.0, "table cannot flash final UI")
	check(app.chip_display._animation_kind == "table_entry", "entry stacks actual ceramic chips")
	var poses: Array = app._table_entry_poses.duplicate()
	var revision: int = app.session.state.revision
	app._begin_hand()
	check(app.session.state.hand_id == 0, "early tap cannot deal through ceremony")
	await wait_ms(650)
	check(app.own_panel.modulate.a > 0.0 and app.own_panel.modulate.a < 1.0, "table progressively fades")
	await capture("mid")
	check(app.deck_cards[0].position != poses.filter(func(p): return p.node == app.deck_cards[0])[0].position, "undealt deck shuffles during entry")
	await wait_ms(650)
	check(app._table_entering, "table entry outlasts home entry")
	app._on_state(app.session.state)
	await wait_ms(650)
	check(not app._table_entering and not app.input_locked, "entry releases without stale snapshot lock")
	check(app.session.state.revision == revision, "ceremony never mutates poker revision")
	await capture("seated")
	for pose in poses:
		check(pose.node.position.is_equal_approx(pose.position) and pose.node.modulate.is_equal_approx(pose.modulate), "final UI has exact layout and opacity")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = app.settings_button.get_global_rect().get_center()
	touch.pressed = true
	root.push_input(touch, true)
	touch.pressed = false
	root.push_input(touch, true)
	var mouse := InputEventMouseButton.new()
	mouse.position = touch.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse.pressed = false
	root.push_input(mouse, true)
	check(is_instance_valid(app.modal), "real touch opens settings after entry")
	if not is_instance_valid(app.modal): app._show_settings()
	check(app.modal.modulate.a == 0.0, "settings starts transparent")
	await wait_ms(120)
	check(app.modal.modulate.a > 0.0 and app.modal.modulate.a < 1.0, "settings fades")
	app._show_reference()
	await wait_ms(300)
	check(is_equal_approx(app.modal.modulate.a, 1.0), "replacement modal finishes cleanly")
	app._close_modal()
	app._leave_to_home()
	app._start_solo()
	app.session.set_deck_theme(1)
	await wait_ms(100)
	app._layout()
	check(not app._table_entering and not app.input_locked, "resize reconciles entry")
	check(not app.deal_button.disabled, "theme change during entry cannot leave deal disabled")
	app._on_chip_gesture(1, 1, 0)
	check(not app._fidget_nodes.is_empty(), "AI fidget reaches presentation")
	app._show_settings()
	app._on_chip_gesture(2, 2, 0)
	check(app._fidget_nodes.is_empty(), "modal clears and suppresses remote fidgets")
	app._close_modal()
	app._leave_to_home()
	app._start_solo()
	app._leave_to_home()
	await wait_ms(2000)
	check(app.home.visible and not app.table.visible and app.session.state.is_empty(), "leave cancels pending entry and deal")
	# A host's first hand takes the same ceremony as a joining peer's snapshot.
	app.session.start_local(["A", "B"], 1000)
	app.session.is_local = false
	app.session.begin_hand()
	check(app._table_entering and app._presentation_queue.size() > 0 and not app.presentation_busy, "LAN first hand queues blind flights until seating")
	app.session.set_deck_theme(2)
	await wait_ms(2000)
	check(not app._table_entering, "LAN first hand finishes entry")
	check(app.presentation_busy or app._presentation_queue.is_empty(), "LAN theme change cannot strand blind queue")
	app._leave_to_home()
	app.queue_free()
	await process_frame
	await process_frame
	print("TABLE_ENTRY_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
