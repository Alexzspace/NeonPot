extends RefCounted
## Android's built-in JNI bridge; no Android-only types are referenced at parse time.
## Hardware feel/support must be verified on each device. Optional iOS singleton
## requires a separately built Core Haptics plugin; otherwise use Godot's fallback.

const CLICK := 1
const THUD := 2
const TICK := 7
const LOW_TICK := 8
const PROFILES := {
	"peek_open": {"duration": 18, "gain": 1.0, "sharpness": 0.90, "steps": [[THUD, 1.0, 0]]},
	"peek_close": {"duration": 14, "gain": 1.0, "sharpness": 1.0, "steps": [[CLICK, 1.0, 0]]},
	"pot_touch": {"duration": 11, "gain": 0.42, "sharpness": 0.72, "steps": [[CLICK, 0.42, 0]]},
	"shuffle": {"duration": 8, "gain": 0.26, "sharpness": 0.35, "steps": [[LOW_TICK, 0.26, 0]]},
	"touch": {"duration": 9, "gain": 0.42, "steps": [[TICK, 0.42, 0]]},
	"release": {"duration": 7, "gain": 0.28, "steps": [[LOW_TICK, 0.28, 0]]},
	"swipe": {"duration": 6, "gain": 0.20, "steps": [[LOW_TICK, 0.20, 0]]},
	"deal": {"duration": 12, "gain": 0.45, "steps": [[TICK, 0.45, 0]]},
	"fold": {"duration": 10, "gain": 0.30, "steps": [[LOW_TICK, 0.30, 0]]},
	"reveal": {"duration": 16, "gain": 0.56, "steps": [[CLICK, 0.56, 0]]},
	"chip": {"duration": 23, "gain": 0.68, "steps": [[CLICK, 0.68, 0], [TICK, 0.36, 16]]},
	"confirm": {"duration": 30, "gain": 0.85, "steps": [[THUD, 0.85, 0], [CLICK, 0.48, 22]]},
	"chip_throw": {"duration": 7, "gain": 0.24, "sharpness": 0.30, "steps": [[LOW_TICK, 0.24, 0]]},
	"chip_land": {"duration": 20, "gain": 0.88, "sharpness": 0.88, "steps": [[THUD, 0.88, 0]]},
	"chip_collect": {"duration": 9, "gain": 0.38, "sharpness": 0.36, "steps": [[LOW_TICK, 0.38, 0]]},
	"chip_stack": {"duration": 13, "gain": 0.66, "sharpness": 0.76, "steps": [[CLICK, 0.66, 0]]},
	"payout": {"duration": 18, "gain": 0.76, "sharpness": 0.56, "steps": [[THUD, 0.76, 0]]},
	"chip_fidget": {"duration": 10, "gain": 0.48, "sharpness": 0.94, "steps": [[TICK, 0.48, 0]]},
}
const MAX_PENDING := 32
const MERGE_WINDOW_MS := 12
const MAX_LATENESS_MS := 45

var backend: String = "uninitialized"
var _initialized := false
var _platform := ""
var _wrapper: Object
var _vibrator
var _effect_class
var _sdk := 0
var _supported: Dictionary = {}
var _amplitude_control := false
var _last_swipe_ms := -1000
var _primitive_durations: Dictionary = {}
var _ios: Object
var _apple: Object
var _apple_started := false
var _events: Array[Dictionary] = []
var _busy_until_ms := 0


func setup() -> void:
	if _initialized:
		return
	_initialized = true
	_platform = OS.get_name()
	backend = "desktop_none"
	if _platform == "iOS":
		backend = "godot_ios"
		if Engine.has_singleton("AppleEmbedded"):
			_apple = Engine.get_singleton("AppleEmbedded")
			if _apple.has_method("supports_haptic_engine") and not _apple.call("supports_haptic_engine"):
				backend = "ios_no_haptics"
		if Engine.has_singleton("NeonPotHaptics"):
			_ios = Engine.get_singleton("NeonPotHaptics")
			if _ios.has_method("is_supported") and _ios.has_method("play_transients") and _ios.has_method("stop") and _ios.call("is_supported"):
				backend = "ios_core_haptics"
		return
	if _platform != "Android":
		return
	backend = "godot_android"
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return
	_wrapper = Engine.get_singleton("JavaClassWrapper")
	var runtime = Engine.get_singleton("AndroidRuntime")
	var context = runtime.getApplicationContext()
	if not _java_ok() or context == null:
		return
	_vibrator = context.getSystemService("vibrator")
	if not _java_ok() or _vibrator == null:
		_vibrator = null
		return
	var has_motor = _vibrator.hasVibrator()
	if not _java_ok():
		_vibrator = null
		return
	if not bool(has_motor):
		backend = "android_no_vibrator"
		return
	var version = _wrapper.call("wrap", "android.os.Build$VERSION")
	if not _java_ok() or version == null:
		return
	_sdk = int(version.SDK_INT)
	if not _java_ok() or _sdk < 26:
		return
	_effect_class = _wrapper.call("wrap", "android.os.VibrationEffect")
	if not _java_ok() or _effect_class == null:
		_effect_class = null
		return
	var amplitude_support = _vibrator.hasAmplitudeControl()
	_amplitude_control = bool(amplitude_support) if _java_ok() else false
	backend = "android_oneshot"
	if _sdk >= 30:
		var primitives := PackedInt32Array([CLICK, TICK])
		if _sdk >= 31:
			primitives.append(LOW_TICK)
			primitives.append(THUD)
		var supported = _vibrator.arePrimitivesSupported(primitives)
		if _java_ok() and (supported is Array or supported is PackedByteArray) and supported.size() == primitives.size():
			for index in range(primitives.size()):
				_supported[primitives[index]] = bool(supported[index])
			if _supported.values().has(true):
				backend = "android_composition"
		if _sdk >= 31:
			var durations = _vibrator.getPrimitiveDurations(primitives)
			if _java_ok() and (durations is Array or durations is PackedInt32Array) and durations.size() == primitives.size():
				for index in primitives.size():
					_primitive_durations[primitives[index]] = maxi(0, int(durations[index]))


func pulse(kind: String, strength: float) -> void:
	if not _initialized:
		setup()
	var profile := _profile(kind, strength)
	if profile.is_empty() or float(profile.strength) <= 0.0:
		return
	if backend in ["desktop_none", "android_no_vibrator", "ios_no_haptics"]:
		return
	if kind == "swipe":
		var now := _now()
		if now - _last_swipe_ms < 45:
			return
		_last_swipe_ms = now
	_enqueue(profile, _now())
	process_pending()


func play_contacts(kind: String, strength: float, impacts: Array, pitch: float = 1.0) -> void:
	if not _initialized: setup()
	if backend in ["desktop_none", "android_no_vibrator", "ios_no_haptics"]: return
	var now := _now()
	var rate := clampf(pitch, 0.9, 1.1) if is_finite(pitch) else 1.0
	for impact in impacts.slice(0, 8):
		if not impact is Array or impact.size() < 2: continue
		var seconds := float(impact[0])
		var weight := float(impact[1])
		if not is_finite(seconds) or not is_finite(weight) or seconds < 0 or seconds > 0.45: continue
		var profile := _profile(kind, strength * clampf(weight, 0.0, 1.0))
		if profile.is_empty() or profile.strength <= 0: continue
		_enqueue(profile, now + int(roundf(seconds / rate * 1000.0)))
	process_pending()


func _now() -> int:
	return Time.get_ticks_msec()


func _enqueue(profile: Dictionary, due: int) -> void:
	for event in _events:
		if absi(int(event.due) - due) <= MERGE_WINDOW_MS:
			# One motor cannot render simultaneous independent impacts: retain the
			# stronger material profile rather than repeatedly cancelling the motor.
			if float(profile.amplitude) > float(event.profile.amplitude): event.profile = profile
			event.due = mini(int(event.due), due)
			return
	if _events.size() >= MAX_PENDING: return
	_events.append({"due": due, "profile": profile})
	_events.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.due) < int(b.due))


func process_pending() -> void:
	var now := _now()
	while not _events.is_empty() and now - int(_events[0].due) > MAX_LATENESS_MS:
		_events.pop_front() # Never replay a stale collision after a stalled frame.
	if _events.is_empty() or now < _busy_until_ms or int(_events[0].due) > now: return
	var event: Dictionary = _events.pop_front()
	_dispatch(event.profile)
	_busy_until_ms = now + _effect_duration(event.profile)

func has_pending() -> bool:
	return not _events.is_empty()


func _effect_duration(profile: Dictionary) -> int:
	if backend != "android_composition": return int(profile.duration)
	var duration := 0
	for step in profile.steps:
		var primitive := _select_primitive(int(step[0]))
		duration += int(step[2]) + int(_primitive_durations.get(primitive, 18))
	return maxi(int(profile.duration), duration)


func _dispatch(profile: Dictionary) -> void:
	if backend == "ios_core_haptics":
		var times := PackedFloat32Array()
		var intensities := PackedFloat32Array()
		var at := 0.0
		for step in profile.steps:
			at += float(step[2]) / 1000.0
			times.append(at)
			intensities.append(float(step[1]))
		if _ios.call("play_transients", times, intensities, float(profile.get("sharpness", 0.65))): return
		backend = "godot_ios"
	if backend == "android_composition":
		if _compose(profile):
			return
		# Unsupported primitives are replaced per profile. A JNI failure disables the
		# composition path for this driver lifetime instead of retrying on every touch.
		backend = "android_oneshot"
	if backend == "android_oneshot":
		if _one_shot(profile):
			return
		backend = "godot_android"
	if backend in ["godot_android", "godot_ios"]:
		if backend == "godot_ios" and is_instance_valid(_apple) and not _apple_started and _apple.has_method("start_haptic_engine"):
			_apple.call("start_haptic_engine")
			_apple_started = true
		Input.vibrate_handheld(int(profile.duration), float(profile.amplitude))


func stop() -> void:
	_events.clear()
	_busy_until_ms = 0
	if not _initialized:
		return
	if backend == "ios_core_haptics" and is_instance_valid(_ios):
		_ios.call("stop")
	elif _platform == "Android" and _vibrator != null:
		_vibrator.cancel()
		_java_ok()
	elif backend == "godot_ios":
		# A zero-duration Input call creates another iOS pattern; use the actual stop API.
		if is_instance_valid(_apple) and _apple_started and _apple.has_method("stop_haptic_engine"):
			_apple.call("stop_haptic_engine")
		_apple_started = false
	elif backend == "godot_android":
		Input.vibrate_handheld(0, 0.0)


func _profile(kind: String, strength: float) -> Dictionary:
	if not PROFILES.has(kind):
		return {}
	var amount: float = clampf(strength, 0.0, 1.0) if is_finite(strength) else 0.0
	var profile: Dictionary = PROFILES[kind].duplicate(true)
	profile.kind = kind
	profile.strength = amount
	profile.amplitude = amount * float(profile.gain)
	for step in profile.steps:
		step[1] = amount * float(step[1])
	return profile


func _select_primitive(preferred: int) -> int:
	if bool(_supported.get(preferred, false)):
		return preferred
	# Prefer another crisp primitive to turning a low tick into a long buzz.
	var alternatives: Array = [CLICK, TICK] if preferred == THUD else [TICK, CLICK]
	for primitive in alternatives:
		if bool(_supported.get(primitive, false)):
			return int(primitive)
	return -1


func _compose(profile: Dictionary) -> bool:
	var steps: Array = []
	for step in profile.steps:
		var primitive := _select_primitive(int(step[0]))
		if primitive < 0:
			return false
		steps.append([primitive, float(step[1]), int(step[2])])
	var composition = _effect_class.startComposition()
	if not _java_ok() or composition == null:
		return false
	for step in steps:
		composition.addPrimitive(int(step[0]), float(step[1]), int(step[2]))
		if not _java_ok():
			return false
	var effect = composition.compose()
	if not _java_ok() or effect == null:
		return false
	_vibrator.vibrate(effect)
	return _java_ok()


func _one_shot(profile: Dictionary) -> bool:
	if _effect_class == null or _vibrator == null:
		return false
	var amplitude := clampi(int(round(float(profile.amplitude) * 255.0)), 1, 255) if _amplitude_control else -1
	var effect = _effect_class.createOneShot(int(profile.duration), amplitude)
	if not _java_ok() or effect == null:
		return false
	_vibrator.vibrate(effect)
	return _java_ok()


func _java_ok() -> bool:
	return _wrapper == null or _wrapper.call("get_exception") == null
