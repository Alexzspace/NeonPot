extends SceneTree
const Main = preload("res://scripts/main.gd")
class Probe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void: pass
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "res://test-results/chip-main-%s.png" % name
	print("MAIN_CHIP_CAPTURE error=%d path=%s" % [root.get_texture().get_image().save_png(path), ProjectSettings.globalize_path(path)])
func run() -> void:
	root.size = Vector2i(1440, 660)
	var app := Probe.new()
	app.defer_home_entrance = true
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	app._cancel_home_entrance()
	app.home_chip_display.set_amount(7500, false)
	var home_at: Vector2 = app.home_chip_display.position
	var home_size: Vector2 = app.home_chip_display.size
	app.home_chip_display.flourish(4)
	app.home_chip_display._animation.pause()
	app.home_chip_display._pose_flourish(0.54)
	await capture("home-rare")
	app.home_chip_display.cancel_flourish()
	assert(app.home_chip_display.position == home_at and app.home_chip_display.size == home_size)
	app.session.start_local(["Alex", "Friend", "Guest"], 10000)
	app.session.begin_hand()
	var deadline := Time.get_ticks_msec() + 12000
	while (app.presentation_busy or app.input_locked) and Time.get_ticks_msec() < deadline: await process_frame
	app._on_chip_gesture(app.shown_state.you, 1, 3)
	app.chip_display._animation.pause()
	app.chip_display._pose_flourish(0.54)
	await capture("local-fan")
	app.chip_display.cancel_flourish()
	var other := (int(app.shown_state.you) + 1) % 3
	app._on_chip_gesture(other, 2, 4)
	var peer = app._fidget_nodes[other]
	peer._animation.pause()
	peer._pose_flourish(0.54)
	await capture("peer-rare")
	peer.cancel_flourish()
	app.session.leave_game()
	app.queue_free()
	await process_frame
	await process_frame
	print("MAIN_CHIP_CAPTURE_COMPLETE")
	quit()
