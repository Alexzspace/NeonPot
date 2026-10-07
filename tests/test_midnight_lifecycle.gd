extends SceneTree
const Main = preload("res://scripts/main.gd")
const Player = preload("res://scripts/pixel_player.gd")
const Styles = preload("res://scripts/chip_gestures.gd")
var checks := 0
var failures := 0

class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIDNIGHT_LIFECYCLE: " + message)

func _tap(control: Control, mouse_too: bool = false) -> void:
	var at := control.get_global_transform() * (control.size * 0.5)
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	if mouse_too:
		var mouse := InputEventMouseButton.new()
		mouse.position = at
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = true
		root.push_input(mouse, true)
		mouse.pressed = false
		root.push_input(mouse, true)

func _run() -> void:
	root.size = Vector2i(1440, 660)
	var app := Probe.new()
	root.add_child(app)
	await process_frame
	app.session.start_local(["Alice", "Bob"], 1000)
	await process_frame
	var before: Dictionary = app.session.state.duplicate(true)
	var music_id: int = app.music.get_instance_id()
	var count := [0]
	app._show_settings()
	await process_frame
	var deck: Control
	for child in app.modal.find_children("*", "Control", true, false):
		if child.get_script() == Player: deck = child
	check(is_instance_valid(deck), "expanded cassette deck exists")
	deck.operated.connect(func(): count[0] += 1)
	_tap(deck.pause_button, true)
	check(count[0] == 1 and not app.music.paused, "settings transport deduplicates touch and mouse press")
	app.music.set_paused(true)
	var index: int = app.music.index
	_tap(deck.next_button, true)
	check(count[0] == 2 and app.music.index == (index + 1) % app.music.tracks.size(), "expanded next transport advances once")
	check(app.music.paused, "transport preserves paused preference")
	app._close_modal()
	await process_frame
	app.music.next_track()
	app._build_ui()
	await process_frame
	check(app.music.get_instance_id() == music_id, "layout reconstruction preserves music node")
	check(app.session.state == before, "music inputs never alter table snapshot")
	app._on_chip_gesture(0, 1, Styles.RARE)
	check(app.chip_display._flourish_style == Styles.RARE and app.chip_display._animation_kind == "flourish", "own hidden style begins")
	check(not app.has_method("_show_observer"), "obsolete observer replay removed")
	# Contact callbacks are counted independently of mute, which must not hide a lifecycle bug.
	var contacts := [0]
	app.chip_display.contact.connect(func(_kind): contacts[0] += 1)
	app._on_chip_gesture(1, 2, Styles.RARE)
	var remote = app._fidget_nodes[1]
	await create_timer(1.35).timeout
	check(is_instance_valid(remote) and remote._animation_kind == "flourish", "remote rare survives ordinary-style timeout")
	await create_timer(Styles.duration(Styles.RARE) - 1.35 + 0.3).timeout
	check(not is_instance_valid(remote), "remote rare is destroyed after its full duration and fade")
	app._on_chip_gesture(0, 3, Styles.RARE)
	app._on_chip_gesture(1, 4, Styles.RARE)
	app._cancel_presentation()
	await process_frame
	var at_cancel: int = contacts[0]
	await create_timer(0.85).timeout
	check(contacts[0] == at_cancel, "cancellation stops own hidden-style contact sounds")
	check(app.chip_display._animation_kind.is_empty(), "cancellation stops own flourish")
	check(app._fidget_nodes.is_empty() and app.flight_layer.get_child_count() == 0, "cancellation destroys remote flourishes")
	check(app.session.state == before, "animation lifecycle preserves recipient snapshot")
	app._application_active = false
	app._on_chip_gesture(1, 99, Styles.RARE)
	check(app._fidget_nodes.is_empty(), "background RPC cannot restart chip rendering or contacts")
	app._application_active = true
	app.session.set_local_seat(1)
	check(app.chip_display._animation_kind.is_empty(), "changing local seat does not retain previous flourish")
	app._on_chip_gesture(1, 5, Styles.RARE)
	app.session.start_local(["New Alice", "New Bob"], 2000)
	check(app._fidget_nodes.is_empty(), "new room clears old cosmetic peers")
	app._on_chip_gesture(0, 5, Styles.RARE)
	app._on_chip_gesture(1, 6, Styles.RARE)
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("MIDNIGHT_LIFECYCLE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
