extends SceneTree

const Driver = preload("res://scripts/haptic_driver.gd")
var checks := 0
var failures := 0

class MotorSpy extends RefCounted:
	var cancels := 0
	func cancel() -> void: cancels += 1

class TimedDriver extends Driver:
	var clock_ms := 1000
	var emitted: Array = []
	func _now() -> int: return clock_ms
	func _dispatch(profile: Dictionary) -> void:
		emitted.append({"at": clock_ms, "profile": profile.duplicate(true)})

class CoreSpy extends RefCounted:
	var calls: Array = []
	var stops := 0
	func play_transients(times: PackedFloat32Array, intensities: PackedFloat32Array, sharpness: float) -> bool:
		calls.append([times, intensities, sharpness])
		return true
	func stop() -> void: stops += 1


func _initialize() -> void:
	var driver = Driver.new()
	_check(driver.backend == "uninitialized", "new driver does not touch native APIs")
	for kind in Driver.PROFILES:
		var full: Dictionary = driver._profile(kind, 1.0)
		var half: Dictionary = driver._profile(kind, 0.5)
		_check(full.duration > 0 and full.duration <= 30, "bounded brief duration: " + kind)
		_check(full.steps.size() >= 1 and full.steps.size() <= 2, "at most two primitives: " + kind)
		_check(half.amplitude < full.amplitude and half.amplitude > 0, "strength changes amplitude: " + kind)
		_check(driver._profile(kind, -1.0).strength == 0.0, "negative strength muted: " + kind)
		_check(driver._profile(kind, 10.0).strength == 1.0, "strength upper clamp: " + kind)
		for step in full.steps:
			_check(step[1] > 0.0 and step[1] <= 1.0 and step[2] >= 0 and step[2] <= 22, "safe primitive scale/delay: " + kind)
	_check(driver._profile("unknown", 1.0).is_empty(), "unknown event has no effect")
	_check(driver._profile("touch", NAN).strength == 0.0, "NaN input muted")
	_check(driver._profile("touch", INF).strength == 0.0, "infinite input muted")
	_check(driver._profile("chip", 1.0).steps.size() == 2, "chips have a double impact")
	_check(driver._profile("confirm", 1.0).steps[0][0] == Driver.THUD, "confirmation begins with weight")
	_check(driver._profile("swipe", 1.0).amplitude < driver._profile("touch", 1.0).amplitude, "swiping is lighter than pressing")
	for kind in ["peek_open", "peek_close"]:
		var peek: Dictionary = driver._profile(kind, 1.0)
		_check(peek.gain == 1.0 and peek.amplitude == 1.0, "private peek requests full hardware amplitude: " + kind)
		_check(peek.steps.size() == 1 and peek.steps[0][1] == 1.0 and peek.steps[0][2] == 0, "private peek uses one full primitive: " + kind)
		_check(peek.duration == (18 if kind == "peek_open" else 14), "private peek stays short: " + kind)
	_check(driver._profile("touch", 1.0).gain == 0.42 and driver._profile("release", 1.0).gain == 0.28, "ordinary touch and release intensity unchanged")
	var modified: Dictionary = driver._profile("chip", 0.5)
	modified.steps[0][1] = 99.0
	_check(driver._profile("chip", 1.0).steps[0][1] < 1.0, "profiles do not mutate shared constants")
	driver._supported = {Driver.CLICK: true, Driver.TICK: true}
	_check(driver._select_primitive(Driver.LOW_TICK) == Driver.TICK, "API30 low tick degrades to tick")
	_check(driver._select_primitive(Driver.THUD) == Driver.CLICK, "unsupported thud degrades to click")
	driver._supported = {}
	_check(driver._select_primitive(Driver.CLICK) == -1, "no primitives requests oneshot fallback")
	driver.setup()
	var selected: String = driver.backend
	driver.setup()
	_check(driver.backend == selected, "setup is idempotent")
	# Headless Windows proves parse/load and no-op behavior only, never hardware feel.
	if OS.get_name() not in ["Android", "iOS"]:
		_check(driver.backend == "desktop_none", "desktop selects silent no-op")
		for kind in Driver.PROFILES:
			driver.pulse(kind, 1.0)
			driver.pulse(kind, 0.0)
		driver.stop()
		_check(driver.backend == "desktop_none" and driver._vibrator == null, "desktop never instantiates Android objects")
	var timed := TimedDriver.new()
	timed._initialized = true
	timed.backend = "test"
	timed._platform = "Android"
	var motor := MotorSpy.new()
	timed._vibrator = motor
	timed.play_contacts("chip_land", 1.0, [[0.0, 1.0], [0.05, 0.5]])
	_check(timed.emitted.size() == 1 and timed.emitted[0].at == 1000, "first contact dispatches at the supplied audio onset")
	timed.pulse("chip_throw", 1.0)
	timed.pulse("chip_stack", 1.0)
	_check(timed.emitted.size() == 1 and motor.cancels == 0, "overlapping impacts never cancel or truncate the active motor pulse")
	timed.clock_ms = 1010
	timed.process_pending()
	_check(timed.emitted.size() == 1, "motor's active duration prevents a premature second pulse")
	timed.clock_ms = 1020
	timed.process_pending()
	_check(timed.emitted.size() == 2 and timed.emitted[1].profile.kind == "chip_stack", "simultaneous collisions retain the stronger dedicated profile")
	timed.clock_ms = 1050
	timed.process_pending()
	_check(timed.emitted.size() == 3 and timed.emitted[2].at == 1050, "later contact keeps the exact audio offset")
	_check(is_equal_approx(timed.emitted[2].profile.amplitude, timed.emitted[0].profile.amplitude * 0.5), "contact weight scales impact strength")
	timed.play_contacts("payout", 1.0, [[0.05, 0.5], [0.10, 0.8]])
	timed.clock_ms = 1300
	timed.process_pending()
	_check(timed.emitted.size() == 3 and not timed.has_pending(), "stalled frames discard stale contacts instead of delayed vibration bursts")
	timed.play_contacts("chip_fidget", 1.0, [[0.11, 1.0]], 1.1)
	_check(timed._events[0].due == 1400, "haptics follows the audio voice pitch-adjusted contact time")
	for burst in 80:
		timed._enqueue(timed._profile("chip_collect", 0.5), 1500 + burst * 20)
	_check(timed._events.size() <= Driver.MAX_PENDING, "queued overlapping activities remain bounded")
	timed.stop()
	_check(not timed.has_pending() and motor.cancels == 1, "one explicit stop clears all future impacts and cancels hardware once")
	timed.play_contacts("chip_land", 0.0, [[0.0, 1.0]])
	timed.play_contacts("chip_land", NAN, [[0.0, 1.0]])
	timed.play_contacts("chip_land", 1.0, [[NAN, 1.0], [0.0, INF], [-1.0, 1.0]])
	_check(not timed.has_pending() and timed.emitted.size() == 3, "invalid and zero-strength contacts are silent")
	timed.backend = "android_composition"
	timed._supported = {Driver.CLICK: true, Driver.TICK: true}
	timed._primitive_durations = {Driver.CLICK: 11, Driver.TICK: 8}
	_check(timed._effect_duration(timed._profile("chip", 1.0)) == 35, "Android busy time includes hardware primitive durations and relative delays")
	var fingerprints: Dictionary = {}
	for kind in ["chip_throw", "chip_land", "chip_collect", "chip_stack", "payout", "chip_fidget"]:
		var profile: Dictionary = timed._profile(kind, 1.0)
		fingerprints[str([profile.duration, profile.gain, profile.sharpness, profile.steps])] = true
	_check(fingerprints.size() == 6, "all six chip activity types have distinct tactile profiles")
	var native_driver = Driver.new()
	native_driver._initialized = true
	native_driver._platform = "iOS"
	native_driver.backend = "ios_core_haptics"
	var core := CoreSpy.new()
	native_driver._ios = core
	native_driver.pulse("chip_fidget", 0.5)
	_check(core.calls.size() == 1 and core.calls[0][0] == PackedFloat32Array([0.0]), "optional iOS singleton receives a transient at collision onset")
	_check(is_equal_approx(core.calls[0][1][0], 0.24) and is_equal_approx(core.calls[0][2], 0.94), "iOS transient receives scaled material intensity and sharpness")
	native_driver.stop()
	_check(core.stops == 1 and not native_driver.has_pending(), "native iOS stop cancels playback and clears scheduled contacts")
	var paper := TimedDriver.new()
	paper._initialized = true
	paper.backend = "test"
	paper.play_contacts("shuffle", 0.5, [[0.0, 0.65], [0.1, 0.45]], 1.0)
	_check(paper.emitted.size() == 1 and paper._events.size() == 1, "paper contact begins now and queues one return contact")
	paper.clock_ms = 1099
	paper.process_pending()
	_check(paper.emitted.size() == 1, "paper return does not fire early")
	paper.clock_ms = 1100
	paper.process_pending()
	_check(paper.emitted.size() == 2 and paper.emitted[1].at == 1100, "paper return follows the 100ms sound offset")
	paper.play_contacts("shuffle", 0.5, [[0.1, 0.45]])
	paper.stop()
	paper.clock_ms = 1300
	paper.process_pending()
	_check(paper.emitted.size() == 2 and not paper.has_pending(), "cancel discards future paper contacts")
	print("HAPTICS_TEST checks=%d failures=%d hardware_validated=false" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HAPTICS FAILED: " + label)
