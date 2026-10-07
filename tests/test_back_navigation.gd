extends SceneTree
const Main = preload("res://scripts/main.gd")
const Timing = preload("res://scripts/presentation_timing.gd")
class Probe extends Main:
	var exit_requests := 0
	func _exit_game() -> void: exit_requests += 1
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
var app: Probe
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BACK_NAVIGATION: " + message)
func back() -> void:
	root.go_back_requested.emit()
func find_button(parent: Node, text: String) -> Button:
	if parent is Button and parent.text == text: return parent
	for child in parent.get_children():
		var found := find_button(child, text)
		if found != null: return found
	return null
func tap(control: Control) -> void:
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
func idle() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline: await process_frame
	check(not app.presentation_busy and not app.input_locked, "table reaches stable input state")
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://back_%s.png" % label) == OK, "capture " + label)

func run() -> void:
	root.size = Vector2i(1440, 660)
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	await process_frame
	check(not quit_on_go_back, "system back cannot automatically terminate application")
	back()
	await process_frame
	check(is_instance_valid(app.modal) and app.home.visible, "home back asks before exiting")
	await capture("exit_confirmation")
	back()
	await process_frame
	check(app.modal == null and app.home.visible, "second back cancels exit confirmation")
	back()
	await process_frame
	var close := find_button(app.modal, "×")
	check(close != null, "exit confirmation has touch close")
	if close != null: await tap(close)
	check(app.modal == null, "native touch cancels confirmation without quitting")
	check(app.exit_requests == 0, "return and dismiss never request exit")
	back()
	await process_frame
	await tap(find_button(app.modal, "退出游戏"))
	check(app.exit_requests == 1, "only explicit native touch on Exit Game requests exit")
	back()
	await process_frame
	app._show_room_search()
	await process_frame
	check(app.discovery._search_socket != null, "room search opens actual discovery socket")
	back()
	await process_frame
	check(app.modal == null and app.discovery._search_socket == null and app.home.visible, "back cancels search and closes UDP discovery")
	app._join_room({"address": "127.0.0.1", "port": 39973, "host_name": "Back test", "room_id": "test"})
	check(app._joining, "connection attempt is active")
	back()
	await process_frame
	check(not app._joining and app.session._peer == null and app.session.state.is_empty(), "back cancels in-flight ENet connection")
	check(app.home.visible and app.modal == null, "cancelled join returns to home")
	app._host()
	await process_frame
	check(app.lobby.visible and app.session.is_host, "host is seated in real LAN waiting room")
	back()
	await process_frame
	check(app.home.visible and not app.lobby.visible and app.modal == null, "back leaves waiting room directly for home")
	check(app.session._peer == null and app.session.state.is_empty() and app.discovery._host_socket == null and app.discovery._search_socket == null, "leaving lobby releases session and all discovery sockets")
	Timing.rate = 2.0
	app.session.start_local(["Alice", "Bob"], 1000)
	app.session.begin_hand()
	await idle()
	var before: Dictionary = app.session.state.duplicate(true)
	back()
	await process_frame
	check(is_instance_valid(app.modal) and find_button(app.modal, "游戏") != null, "active hand back opens settings")
	check(app.session.state == before, "opening settings cannot bet or advance hand")
	await capture("table_settings")
	back()
	await process_frame
	check(app.modal == null and app.table.visible and app.session.state == before, "second back closes settings without leaving or acting")
	# A settlement back must never trigger the explicit Next Hand button.
	app.session.set_local_seat(int(app.session.state.actor))
	app.session.submit_action("fold")
	await idle()
	check(app.session.state.phase == "showdown", "real fold reaches settlement")
	if app.modal == null: app._show_showdown(app.session.state)
	var settled: Dictionary = app.session.state.duplicate(true)
	back()
	await process_frame
	check(app.modal == null and app.session.state == settled, "settlement back closes only, never advances next hand")
	back()
	await process_frame
	check(is_instance_valid(app.modal) and app.session.state == settled, "back from settled table opens settings, still no next hand")
	app._close_modal()
	app.session.leave_game()
	app.discovery.stop_host()
	app.discovery.stop_search()
	check(app.exit_requests == 1, "search, lobby and table back never issue additional exit")
	app.queue_free()
	await process_frame
	await process_frame
	Timing.rate = 1.0
	print("BACK_NAVIGATION_SUMMARY checks=%d failures=%d graphical=%s" % [checks, failures, DisplayServer.get_name() != "headless"])
	quit(0 if failures == 0 else 1)


