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
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end: await process_frame
func run() -> void:
	var app := Probe.new()
	app.animate_on_start = true
	app.defer_home_entrance = true
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	check(app._entrance_pending, "video defers entry")
	check(app.home_cards[0].modulate.a == 0, "no flash of final home before entry")
	var poses: Array = app._entrance_poses.duplicate()
	app.play_home_entrance()
	await wait_ms(400)
	check(app.home_cards[0].modulate.a > 0 and app.home_cards[0].modulate.a < 1, "cards progressively enter")
	check(app.home_cards[0].position.distance_to(poses[3].position) > 0, "fan has intermediate motion")
	await wait_ms(850)
	for item in poses:
		check(item.node.position.is_equal_approx(item.position) and is_equal_approx(item.node.rotation, item.rotation), "all panels and cards return to exact layout")
	check(app._entrance_poses.is_empty() and not app.home_chip_touch.disabled, "entry cleanup releases input")
	app._prepare_home_entrance()
	app.play_home_entrance()
	await wait_ms(150)
	app._layout()
	check(app._entrance_poses.is_empty(), "resize cancels entry before reflow")
	for ratio in [Vector2i(1200, 550), Vector2i(1200, 750), Vector2i(1000, 707)]:
		root.size = ratio
		await process_frame
		app._layout()
		check(app.home_chip_display.position == app.home_chip_touch.position, "responsive chip touch remains aligned")
	app.queue_free()
	await process_frame
	await process_frame
	print("HOME_ENTRANCE_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
