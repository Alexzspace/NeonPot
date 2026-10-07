extends SceneTree

const Main = preload("res://scripts/main.gd")
const Session = preload("res://scripts/table_session.gd")
var checks := 0
var failures := 0
var app: Control

class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HOST_LOBBY: " + description)

func _initialize() -> void: _run.call_deferred()

func _tap(button: Control) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = button.get_global_rect().get_center()
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	# Viewport injection bypasses Input's configured touch-to-mouse synthesis.
	# Include the emulated pair delivered to ordinary Godot Buttons on devices.
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = event.position
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse.pressed = false
	root.push_input(mouse, true)

func _button_with_text(parent: Node, text_options: Array) -> Button:
	for button in parent.find_children("*", "Button", true, false):
		if button.text in text_options and button.is_visible_in_tree(): return button
	return null

func _run() -> void:
	root.size = Vector2i(1440, 660)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var host_scope := Node.new()
	host_scope.name = "Host"
	root.add_child(host_scope)
	set_multiplayer(SceneMultiplayer.new(), host_scope.get_path())
	app = Probe.new()
	app.name = "App"
	host_scope.add_child(app)
	app.size = Vector2(1440, 660)
	await process_frame
	app.name_edit.text = "Host test"
	var start := Time.get_ticks_usec()
	app._host()
	var elapsed := Time.get_ticks_usec() - start
	print("HOST_LOBBY host_usec=%d" % elapsed)
	check(app.session.is_host, "host opens UDP server")
	check(app.shown_state.get("phase", "") == "lobby", "initial snapshot is lobby")
	check(app.shown_state.get("players", []).size() == 1, "one occupied seat")
	check(app.lobby.visible and not app.home.visible and not app.table.visible, "dedicated lobby replaces home")
	check(not app.presentation_busy and app._presentation_queue.is_empty(), "lobby sync completes without presentation lock")
	check(not app.input_locked, "input unlocked")
	check(app.lobby.start_button.is_visible_in_tree() and app.lobby.start_button.disabled, "one human cannot deal")
	check(app.lobby.add_button.is_visible_in_tree() and not app.lobby.add_button.disabled, "host can add AI")
	var frame_count := 0
	var frame_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - frame_start < 250:
		await process_frame
		frame_count += 1
	check(frame_count >= 2, "frame loop remains alive")
	var settings := _button_with_text(app.canvas, ["设置", "SETTINGS"])
	check(is_instance_valid(settings), "visible settings button")
	if is_instance_valid(settings): _tap(settings)
	await process_frame
	check(is_instance_valid(app.modal), "touch opens settings in single-player lobby")
	if is_instance_valid(app.modal):
		var close := _button_with_text(app.modal, ["×"])
		check(is_instance_valid(close), "visible modal close button")
		if is_instance_valid(close): _tap(close)
	await process_frame
	check(not is_instance_valid(app.modal), "touch closes settings")

	# Separate SceneMultiplayer roots exercise genuine localhost ENet registration.
	var client_scope := Node.new()
	client_scope.name = "Client"
	root.add_child(client_scope)
	set_multiplayer(SceneMultiplayer.new(), client_scope.get_path())
	var client_app := Probe.new()
	client_app.name = "App"
	client_scope.add_child(client_app)
	client_app.hide()
	var client: Node = client_app.session
	check(client.join_game("127.0.0.1", "Guest test") == OK, "client starts connection")
	var deadline := Time.get_ticks_msec() + 5000
	while client.state.get("players", []).size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.state.get("players", []).size() == 2, "real ENet guest receives two seats")
	check(app.shown_state.get("players", []).size() == 2, "host UI receives guest")
	check(client.local_seat == 1, "guest receives own seat")
	check(client_app.lobby.visible and client_app.lobby.start_button.disabled, "guest UI waits for host to deal")
	check(not client_app.lobby.add_button.visible, "guest UI has no bot administration")
	check(client.state.get("room_id", "client") == app.shown_state.get("room_id", "host"), "same room")
	check(not app.lobby.start_button.disabled, "guest joining enables deal")
	check(not app.presentation_busy and not app.input_locked, "joined lobby stays responsive")
	app._confirm_leave()
	await process_frame
	var leave := _button_with_text(app.modal, ["确认离开", "LEAVE TABLE"])
	check(is_instance_valid(leave), "leave confirmation button exists")
	if is_instance_valid(leave): _tap(leave)
	await process_frame
	check(app.home.visible and not app.table.visible, "leave returns home")
	check(not app.session.is_host and app.shown_state.is_empty(), "leave clears host state")
	check(not app.presentation_busy and not app.input_locked, "leave clears locks")
	client.leave_game()
	client_scope.queue_free()
	host_scope.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("HOST_LOBBY checks=%d failures=%d frames=%d" % [checks, failures, frame_count])
	quit(1 if failures else 0)
