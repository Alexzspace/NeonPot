extends SceneTree
const Main = preload("res://scripts/main.gd")
const TEST_PORT := 27974
var checks := 0
var failures := 0
var host_app: Control
var client_app: Control

class Probe extends Main:
	var legacy_marker := false
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
	func _accept_presentation(_old: Dictionary, state: Dictionary) -> void:
		# Network/gameplay stays real. Skip chip flights so the test isolates overlay ownership.
		_presented_revision = int(state.get("revision", -1))
		_displayed_pot = 0 if state.get("phase", "") == "showdown" else int(state.get("pot", 0))
		_settlement_key = _hand_key(state) if state.get("phase", "") == "showdown" else ""
		pot_display.set_amount(_displayed_pot, false)
	func _show_showdown(state: Dictionary) -> void:
		super._show_showdown(state)
		if legacy_marker: modal.remove_meta("settlement_hand")

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LAN_SHOWDOWN_TRANSITION: " + description)

func _tap(button: Control) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = button.get_global_rect().get_center()
	touch.pressed = true
	root.push_input(touch, true)
	touch.pressed = false
	root.push_input(touch, true)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = touch.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse.pressed = false
	root.push_input(mouse, true)

func _sync() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while client_app.session.state.get("revision", -1) < host_app.session.state.get("revision", -1) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client_app.session.state.get("revision", -1) == host_app.session.state.get("revision", -1), "real RPC snapshot reaches client")

func _finish_hand() -> void:
	var guard := 0
	while host_app.session.state.actor >= 0 and guard < 40:
		var current: Dictionary = host_app.session.state
		var actor: int = current.actor
		var actor_session = host_app.session if actor == 0 else client_app.session
		var legal: Dictionary = actor_session.state.legal
		actor_session.submit_action("check" if legal.check else "call")
		var deadline := Time.get_ticks_msec() + 3000
		while host_app.session.state.revision == current.revision and Time.get_ticks_msec() < deadline:
			await process_frame
		check(host_app.session.state.revision > current.revision, "human action advances actual host engine")
		await _sync()
		guard += 1
	check(host_app.session.state.phase == "showdown" and client_app.shown_state.phase == "showdown", "both real Main instances finish the same hand")

func _run() -> void:
	root.size = Vector2i(1440, 660)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	for legacy in [true, false]:
		var host_scope := Node.new()
		host_scope.name = "TransitionHost"
		root.add_child(host_scope)
		set_multiplayer(SceneMultiplayer.new(), host_scope.get_path())
		host_app = Probe.new()
		host_app.name = "App"
		host_scope.add_child(host_app)
		host_app.size = Vector2(1440, 660)
		host_app.hide()
		var client_scope := Node.new()
		client_scope.name = "TransitionClient"
		root.add_child(client_scope)
		set_multiplayer(SceneMultiplayer.new(), client_scope.get_path())
		client_app = Probe.new()
		client_app.name = "App"
		client_app.legacy_marker = legacy
		client_scope.add_child(client_app)
		client_app.size = Vector2(1440, 660)
		await process_frame
		check(host_app.session.host_game("Host", 1000, TEST_PORT) == OK, "host opens isolated real network")
		client_app.name_edit.text = "Client"
		client_app._join_room({"address": "127.0.0.1", "port": TEST_PORT})
		var deadline := Time.get_ticks_msec() + 3000
		while client_app.session.state.get("players", []).size() != 2 and Time.get_ticks_msec() < deadline:
			await process_frame
		check(client_app.session.local_seat == 1 and not is_instance_valid(client_app.modal), "client entered actual lobby before playing")
		host_app.session.begin_hand()
		await _sync()
		while host_app._table_entering or client_app._table_entering: await process_frame
		await _finish_hand()
		client_app._show_showdown(client_app.shown_state)
		var settlement: Control = client_app.modal
		check(is_instance_valid(settlement) and settlement.is_visible_in_tree(), "client leaves its old settlement open")
		var old_hand: int = client_app.shown_state.hand_id
		host_app.session._publish()
		await _sync()
		check(client_app.modal == settlement, "same-hand settlement update does not dismiss its overlay")
		host_app.session.begin_hand()
		await _sync()
		check(client_app.shown_state.hand_id == old_hand + 1 and client_app.shown_state.phase == "preflop", "host next hand reaches client underneath any overlay")
		# Move the host's turn if necessary so the client has a real legal input to exercise.
		if host_app.session.state.actor == 0:
			host_app.session.submit_action("call")
			await _sync()
		check(client_app.shown_state.actor == 1 and not client_app.call_button.disabled and not client_app.input_locked, "client's new betting turn is ready")
		var revision: int = host_app.session.state.revision
		_tap(client_app.call_button)
		await create_timer(0.12).timeout
		if legacy:
			check(is_instance_valid(settlement) and client_app.modal == settlement, "legacy control reproduces stale settlement overlay")
			check(host_app.session.state.revision == revision, "legacy stale overlay blocks an otherwise legal touch")
			print("LAN_SHOWDOWN_LEGACY_REPRODUCED stale_overlay=true blocked_touch=true")
			client_app._close_modal()
		else:
			check(not is_instance_valid(client_app.modal) and not is_instance_valid(settlement), "new-hand RPC automatically destroys only the old settlement")
			check(host_app.session.state.revision == revision + 1, "client touch immediately submits one legal action after transition")
			await _sync()
			# A settings panel is user-owned, so a different hand must not silently dismiss it.
			client_app._show_settings()
			var settings: Control = client_app.modal
			await _finish_hand()
			host_app.session.begin_hand()
			await _sync()
			check(is_instance_valid(settings) and client_app.modal == settings, "unrelated settings overlay survives a new hand")
		host_app.session.leave_game()
		client_app.session.leave_game()
		host_scope.queue_free()
		client_scope.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.3).timeout
	print("LAN_SHOWDOWN_TRANSITION_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
