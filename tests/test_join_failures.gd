extends SceneTree
const Main = preload("res://scripts/main.gd")
const Session = preload("res://scripts/table_session.gd")
const TEST_PORT := 27972
var checks := 0
var failures := 0
var app: Control
var host: Node

class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("JOIN_FAILURES: " + description)

func _room(port: int = TEST_PORT) -> Dictionary:
	return {"room_id": "fixture", "host_name": "Fixture host", "address": "127.0.0.1", "port": port}

func _tap(button: Control) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
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

func _close_button() -> Button:
	if not is_instance_valid(app.modal): return null
	for button in app.modal.find_children("*", "Button", true, false):
		if button.text == "×": return button
	return null

func _failed(reason_fragment: String) -> void:
	check(not app._joining and app.session._peer == null and app.session.state.is_empty(), "failed connection is terminated, not left running")
	check(is_instance_valid(app.modal) and app.modal.is_visible_in_tree(), "failure feedback remains visibly open")
	check(app._join_title.text == app.words("暂时无法入座", "COULD NOT JOIN"), "terminal title replaces joining title")
	check(reason_fragment in app._join_message.text, "specific translated error is inside modal")
	check(app._join_return.text == app.words("返回牌桌列表", "BACK TO TABLES") and not app._join_return.disabled, "failure offers an enabled route back to search")

func _wait_for_terminal() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while app._joining and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not app._joining, "real ENet refusal reaches terminal feedback promptly")

func _run() -> void:
	root.size = Vector2i(1440, 660)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var host_scope := Node.new()
	host_scope.name = "JoinHost"
	root.add_child(host_scope)
	set_multiplayer(SceneMultiplayer.new(), host_scope.get_path())
	var host_container := Node.new()
	host_container.name = "App"
	host_scope.add_child(host_container)
	host = Session.new()
	host.name = "Session"
	host_container.add_child(host)
	var client_scope := Node.new()
	client_scope.name = "JoinClient"
	root.add_child(client_scope)
	set_multiplayer(SceneMultiplayer.new(), client_scope.get_path())
	app = Probe.new()
	app.name = "App"
	client_scope.add_child(app)
	app.size = Vector2(1440, 660)
	await process_frame
	# Both localizations exercise actual join dialogs; settings are never written.
	for locale in ["zh", "en"]:
		app.language = locale
		app.name_edit.text = "Joining guest"
		app._join_room(_room(TEST_PORT + 1))
		check(app._joining and is_instance_valid(app._join_message), "asynchronous connection starts with a live modal")
		# Trigger Godot's documented failure callback, without waiting for its long UDP retry clock.
		app.session._on_connection_failed()
		_failed("连接失败" if locale == "zh" else "Connection failed")
		_tap(app._join_return)
		await process_frame
		check(is_instance_valid(app._search_modal) and app._search_modal == app.modal and app.discovery._search_socket != null, "back button opens a fresh room search")
		app._close_modal()
		check(app.discovery._search_socket == null, "closing search releases its UDP socket")
		app.name_edit.text = ""
		app._join_room(_room())
		_failed("名字" if locale == "zh" else "name")
		app._close_modal()
		app.name_edit.text = "Joining guest"
		app._join_room(_room(0))
		_failed("端口" if locale == "zh" else "port")
		app._close_modal()
		check(host.host_game("Fixture host", 1000, TEST_PORT) == OK, "real server opens for room-full refusal")
		for seat in 5: check(host.add_bot(), "fixture fills a seat")
		app._join_room(_room())
		await _wait_for_terminal()
		_failed("已满" if locale == "zh" else "Room full")
		check(host.state.players.size() == 6, "refused guest does not enter the full roster")
		app._close_modal()
		host.leave_game()
		check(host.host_game("Fixture host", 1000, TEST_PORT) == OK and host.add_bot(), "real server prepares a running hand")
		host.begin_hand()
		app._join_room(_room())
		await _wait_for_terminal()
		_failed("已开始" if locale == "zh" else "already started")
		check(host.state.players.size() == 2, "late join does not alter the started roster")
		app._close_modal()
		host.leave_game()
	check(host.host_game("Fixture host", 1000, TEST_PORT) == OK, "open server for cancellation cases")
	app._join_room(_room())
	var close := _close_button()
	check(is_instance_valid(close), "joining dialog has a close control")
	if is_instance_valid(close): _tap(close)
	check(not app._joining and app.session._peer == null and not is_instance_valid(app.modal), "X cancels the in-flight session immediately")
	await create_timer(0.35).timeout
	check(app.session.state.is_empty() and host.state.players.size() == 1 and app.home.visible, "closed attempt cannot join late or replace home")
	app._join_room(_room())
	_tap(app._join_return)
	check(not app._joining and app.session._peer == null, "Cancel stops the connection before returning to search")
	await create_timer(0.35).timeout
	check(app.session.state.is_empty() and host.state.players.size() == 1 and is_instance_valid(app._search_modal), "cancelled attempt cannot join behind room search")
	app._close_modal()
	# A subsequent fresh attempt still succeeds, without a stale failure or cancellation.
	app._join_room(_room())
	await _wait_for_terminal()
	check(not is_instance_valid(app.modal) and app.session._peer != null and not app.session.state.is_empty(), "successful retry closes modal and retains live transport")
	check(app.lobby.visible and app.session.local_seat == 1 and host.state.players.size() == 2, "successful retry enters the correct human lobby seat")
	app.session.leave_game()
	host.leave_game()
	client_scope.queue_free()
	host_scope.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("JOIN_FAILURES_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
