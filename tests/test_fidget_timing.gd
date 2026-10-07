extends SceneTree
const Display = preload("res://scripts/chip_display.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")
const Timing = preload("res://scripts/presentation_timing.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FIDGET_TIMING: " + label)
func run() -> void:
	Engine.max_fps = 120
	var display := Display.new()
	display.size = Vector2(318, 218)
	root.add_child(display)
	display.set_amount(10000, false)
	for rate in [0.25, 2.0]:
		Timing.rate = rate
		check(is_equal_approx(Timing.duration(1), 1.0 / rate), "gameplay durations still follow selected speed")
		for style in [Gestures.NORMAL.SHUFFLE, Gestures.RARE]:
			var expected := 2.0 if style == Gestures.RARE else 1.0
			var start := Time.get_ticks_msec()
			display.flourish(style)
			await display.animation_finished
			var elapsed := (Time.get_ticks_msec() - start) / 1000.0
			check(absf(elapsed - expected) < 0.22, "real flourish duration is independent of gameplay speed")
			check(display._animation == null, "flourish completes without lingering tween")
			print("FIDGET_TIMING rate=%.2f style=%d elapsed=%.3f" % [rate, style, elapsed])
	Timing.rate = 1.0
	display.queue_free()
	await process_frame
	await process_frame
	print("FIDGET_TIMING_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
