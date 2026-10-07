extends SceneTree
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0
class Probe extends Main:
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.level = 0
		music.paused = true
	func _save_settings() -> void: pass
	func _accept_presentation(_old: Dictionary, _state: Dictionary) -> void: pass
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SEAT_PRESENCE: " + message)
func background(slot: Dictionary) -> Color:
	return slot.panel.get_theme_stylebox("panel").bg_color
func run() -> void:
	root.size = Vector2i(1440, 900)
	var app := Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app.session.start_local(["玩家甲", "Folded", "All In", "Out", "玩家戊", "Player Six"], 1000)
	var authority: Dictionary = app.session.state.duplicate(true)
	var state: Dictionary = authority.duplicate(true)
	state.phase = "flop"
	state.hand_id = 1
	state.actor = 4
	state.board = [3, 18, 35]
	state.players[1].folded = true
	state.players[2].stack = 0
	state.players[2].all_in = true
	state.players[3].stack = 0
	state.dealer = 1
	state.small_blind_seat = 2
	state.big_blind_seat = 3
	var before: Dictionary = state.duplicate(true)
	for dimensions in [Vector2i(1440, 900), Vector2i(900, 1440)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for lang in ["zh", "en"]:
			app.language = lang
			app._build_ui()
			app._render_state(state, true)
			await process_frame
			check(background(app.seats[1]) == Color("11121e"), "folded panel dark")
			check(background(app.seats[3]) == Color("11121e"), "empty stack outside hand dark")
			check(background(app.seats[2]) == Main.PANEL and app.seats[2].stack.text.ends_with("ALL IN"), "live zero-stack all-in stays in hand")
			check(app.seats[1].stack.text.ends_with("弃牌" if lang == "zh" else "FOLDED"), "folded state localized")
			check(app.seats[3].stack.text.ends_with("筹码耗尽" if lang == "zh" else "OUT"), "out state localized")
			check(app.seats[1].badge.self_modulate != Color.WHITE and app.seats[2].badge.self_modulate == Color.WHITE, "badge dim follows presence")
			check(app.seats[4].panel.get_theme_stylebox("panel").border_color == Main.GOLD, "actor retains gold border")
			check(app.seats[1].name.get_theme_color("font_color") == Color("9394a5") and app.seats[1].panel.modulate.a == 1.0, "readable muted name without global alpha")
			for slot in app.seats:
				check(slot.panel.visible and app.safe_rect.grow(1).encloses(slot.panel.get_global_rect()), "six seats fit resized safe area")
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.position = app.seats[1].panel.get_global_rect().get_center()
			touch.pressed = true
			root.push_input(touch, true)
			var release := touch.duplicate() as InputEventScreenTouch
			release.pressed = false
			root.push_input(release, true)
			await process_frame
			check(app.session.state == authority and not is_instance_valid(app.modal), "seat touch remains decorative and never acts or opens a modal")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png("res://test-results/seat-presence-%s-%s.png" % [dimensions.x, lang]) == OK, "capture six-seat states")
	check(state == before and app.session.state == authority, "rendering never mutates snapshots or engine")
	state.phase = "showdown"
	state.actor = -1
	state.players[2].stack = 1200
	state.players[3].all_in = true
	state.result = [{"seat": 2, "amount": 1200}]
	app._render_state(state, true)
	check(app._visual_stack(state, 2) == 0 and background(app.seats[2]) == Main.PANEL, "winner eligible before animated chips arrive")
	check(not app.seats[2].stack.text.contains("ALL IN") and app.seats[3].stack.text.ends_with("OUT"), "settled all-in flags cannot hide eliminated loser")
	state.phase = "preflop"
	state.hand_id = 2
	state.players[1].folded = false
	state.players[1].stack = 900
	state.actor = 1
	app._render_state(state, true)
	check(app.seats[1].name.get_theme_color("font_color") == Main.INK and app.seats[1].badge.self_modulate == Color.WHITE and app.seats[1].panel.get_theme_stylebox("panel").border_color == Main.GOLD, "next hand restores name badge and actor")
	state.phase = "lobby"
	state.players[1].folded = true
	app._render_state(state, true)
	check(background(app.seats[1]) == Main.PANEL and not app.seats[1].stack.text.contains("FOLDED"), "lobby ignores stale folded and actor flags")
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SEAT_PRESENCE_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
