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

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENTRY_LIFECYCLE: " + label)

func run() -> void:
	var app := Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app._set_mixflip_test_geometry(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)])
	app.player_count.value = 6
	app._start_solo()
	var aux: Rect2 = app.mixflip_outer_profile.aux_rect
	var seat_rests: Array[Vector2] = []
	for slot in app.seats:
		var pose: Dictionary = app._table_entry_poses.filter(func(item): return item.node == slot.panel)[0]
		seat_rests.append(pose.position)
		check(aux.grow(1).encloses(Rect2(pose.position, slot.panel.size)), "entry captures each seat in outer camera-safe grid")
	check(seat_rests[0].y != seat_rests[5].y, "outer entry seats use multiple rows from their first pose")
	await create_timer(2.1).timeout
	for index in app.seats.size():
		check(app.seats[index].panel.position.is_equal_approx(seat_rests[index]), "outer entry settles exactly at captured seat position")
	app._leave_to_home()
	app._clear_mixflip_test_geometry()
	check(app.mixflip_outer_profile.is_empty(), "return to inner display restores ordinary layout")
	app._start_solo()
	app._show_settings()
	app._change_language("en")
	check(app._settings_after_rebuild and app._table_entering, "language change schedules settings restoration after entry")
	var old_revision: int = app.session.state.revision
	check(app._table_entering and is_instance_valid(app.modal), "settings can cover ongoing entry")
	check(app.session.set_deck_theme((int(app.session.state.deck_theme) + 1) % 4), "theme change accepted during entry")
	check(app.session.state.revision == old_revision, "theme metadata leaves gameplay revision intact")
	await create_timer(2.1).timeout
	check(not app._table_entering and not app.input_locked, "entry reconciles despite open settings and theme metadata")
	check(app._presentation_queue.is_empty() and not app.presentation_busy, "same-revision theme update cannot strand initial presentation")
	check(not app.deal_button.disabled and app.shown_state.deck_theme == app.session.state.deck_theme, "final theme and deal availability reconciled")
	check(is_instance_valid(app.modal) and app.language == "en" and not app._settings_after_rebuild, "language rebuild keeps settings open after entry")
	app._close_modal()
	# A completed/busted solo table fixture activates the real restart request.
	app.shown_state = app.shown_state.duplicate(true)
	app.shown_state.phase = "showdown"
	app.shown_state.players[0].stack = 0
	app._begin_hand()
	check(app._table_entering and app._deal_after_entry, "restart schedules deal after seating")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(2.2).timeout
	check(not app._table_entering and app._deal_after_entry, "background completion preserves deferred request")
	check(app.session.state.hand_id == 0 and app.session.state.phase == "lobby", "background seating never deals")
	app._show_settings()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.7).timeout
	check(app.session.state.hand_id == 0 and app._deal_after_entry, "foreground modal continues to defer requested deal")
	app._close_modal()
	await create_timer(1.1).timeout
	check(app.session.state.hand_id == 1 and not app._deal_after_entry, "closing foreground modal consumes restart exactly once")
	app._leave_to_home()
	app._start_solo()
	app._deal_after_entry = true
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._leave_to_home()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(2.0).timeout
	check(app.session.state.is_empty() and not app._deal_after_entry and app.home.visible, "leave discards deferred restart even across focus changes")
	app.queue_free()
	await process_frame
	await process_frame
	print("ENTRY_LIFECYCLE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
