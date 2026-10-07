extends Node

const HapticDriver = preload("res://scripts/haptic_driver.gd")
const SOUND_KINDS := ["touch", "release", "swipe", "deal", "chip", "confirm", "fold", "reveal",
	"chip_throw", "chip_land", "chip_collect", "chip_stack", "payout", "chip_fidget", "pot_touch", "shuffle"]
const CHIP_KINDS := ["chip", "confirm", "chip_throw", "chip_land", "chip_collect", "chip_stack", "payout", "chip_fidget", "pot_touch"]
const VARIANT_COUNT := 8
const GENERATED_DIRECTORY := "res://assets/audio/generated"
const SAMPLE_PEAK := 0.36
const VOICE_GAIN_DB := -5.0 # Louder ceramic transients with a bounded active mix.
const MAX_ACTIVE_VOICES := 4
var haptics = HapticDriver.new()

var volume: float = 0.7
var haptic_strength: float = 0.7
var public_audio: bool = true
var _voices: Array[AudioStreamPlayer] = []
var _samples: Dictionary = {}
var _voice := 0
var _last_swipe := 0
var _last_shared_sound: Dictionary = {}
var _variant_bags: Dictionary = {}
var _last_variant: Dictionary = {}
var _audio_rng := RandomNumberGenerator.new() # Audio variation never touches deck RNG.
var _focused := true
var _backgrounded := false

func _ready() -> void:
	haptics.setup()
	_audio_rng.randomize()
	for i in range(8):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_voices.append(player)
	for kind in SOUND_KINDS:
		var variants: Array = []
		for variation in range(VARIANT_COUNT):
			variants.append(_load_sample(kind, variation))
		_samples[kind] = variants

func _load_sample(kind: String, variant: int) -> AudioStreamWAV:
	# Offline-baked PCM is identical to _make_sample; avoid synthesizing 128 sounds
	# on the main thread at startup. Missing development assets retain the fallback.
	var path := "%s/%s_%d.res" % [GENERATED_DIRECTORY, kind, variant]
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		var sample := ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
		if sample != null: return sample
	return _make_sample(kind, variant)

func play(kind: String, shared: bool = false) -> void:
	if shared and not public_audio:
		return
	if kind == "swipe":
		var now := Time.get_ticks_msec()
		if now - _last_swipe < 90:
			return
		_last_swipe = now
	_play_sound(kind, shared)
	if not shared and haptic_strength > 0.0:
		haptics.pulse(_haptic_kind(kind), haptic_strength)

func play_audio_only(kind: String) -> void:
	# Explicit sound-only preview/tool path; production chip contacts use
	# play_chip_contact so their independently configured haptics remain active.
	_play_sound(kind, false)

func play_card_contact(kind: String, shared: bool = false) -> void:
	if kind not in ["touch", "swipe", "release"] or not _focused or _backgrounded: return
	if not shared or public_audio: _play_sound(kind, shared)
	var strength := clampf(haptic_strength, 0.0, 1.0) if is_finite(haptic_strength) else 0.0
	if strength > 0.0: haptics.pulse(_haptic_kind(kind), strength * (0.75 if shared else 1.0))

func play_private_peek(kind: String) -> void:
	if kind not in ["touch", "swipe", "release"] or not _focused or _backgrounded: return
	_play_sound(kind, false)
	if not is_finite(haptic_strength) or haptic_strength <= 0.0: return
	# Explicit user preference: private peek press/release uses full hardware amplitude
	# for every nonzero setting. Zero stays off; ordinary touch/swipe keep their scale.
	# This local-only API has no shared argument or session/network side effects.
	if kind == "swipe": haptics.pulse("swipe", clampf(haptic_strength, 0.0, 1.0))
	else: haptics.pulse("peek_open" if kind == "touch" else "peek_close", 1.0)

func play_table_prop_contact(kind: String, shared: bool = false) -> void:
	if kind not in ["pot", "deck"] or not _focused or _backgrounded: return
	var sound := "pot_touch" if kind == "pot" else "shuffle"
	var playing: Dictionary = {}
	if not shared or public_audio: playing = _play_sound(sound, shared)
	var strength := clampf(haptic_strength, 0.0, 1.0) if is_finite(haptic_strength) else 0.0
	if strength <= 0.0: return
	strength *= 0.75 if shared else 1.0
	var impacts := _chip_impacts(sound, int(playing.get("variant", 0))) if kind == "pot" else _shuffle_impacts()
	if haptics.has_method("play_contacts"):
		haptics.play_contacts(sound, strength, impacts, float(playing.get("pitch", 1.0)))
	else: haptics.pulse(sound, strength)

func _shuffle_impacts() -> Array:
	return [[0.0, 0.65], [0.10, 0.45]]

func play_chip_contact(kind: String, shared: bool = false, intensity: float = 1.0) -> void:
	if not CHIP_KINDS.has(kind) or not _focused or _backgrounded:
		return
	var playing: Dictionary = {}
	if not shared or public_audio:
		playing = _play_sound(kind, shared)
	var strength := clampf(haptic_strength, 0.0, 1.0) if is_finite(haptic_strength) else 0.0
	strength *= clampf(intensity, 0.0, 1.0) if is_finite(intensity) else 0.0
	if strength <= 0: return
	# Use the same contact offsets and playback pitch as the chosen audible variant.
	# Muting shared audio never disables physical contact feedback.
	if haptics.has_method("play_contacts"):
		haptics.play_contacts(kind, strength, _chip_impacts(kind, int(playing.get("variant", 0))), float(playing.get("pitch", 1.0)))
	else:
		haptics.pulse(kind, strength)

func cancel_chip_haptics() -> void:
	haptics.stop()

func _process(_delta: float) -> void:
	if haptics.has_method("process_pending"):
		if not is_finite(haptic_strength) or haptic_strength <= 0:
			# Clear queued future contacts without repeated native cancel calls.
			if haptics.has_method("has_pending") and haptics.has_pending(): haptics.stop()
		elif _focused and not _backgrounded:
			haptics.process_pending()

func preview_sound() -> void:
	play_audio_only("chip_fidget")

func preview_haptics() -> void:
	if not is_finite(haptic_strength) or haptic_strength <= 0.0:
		haptics.stop()
		return
	haptics.pulse("chip", clampf(haptic_strength, 0.0, 1.0))

func _play_sound(kind: String, shared: bool) -> Dictionary:
	var level: float = clampf(volume, 0.0, 1.0) if is_finite(volume) else 0.0
	var audio_allowed := true
	if shared:
		# A landing batch can contain many visual chips. Coalesce its same-key sounds
		# without scheduling timers or suppressing a different stage of the gesture.
		audio_allowed = Time.get_ticks_msec() - int(_last_shared_sound.get(kind, -1000)) >= 45
	if level > 0.001 and _samples.has(kind) and not _voices.is_empty() and audio_allowed:
		if _voice >= MAX_ACTIVE_VOICES:
			_voices[(_voice - MAX_ACTIVE_VOICES) % _voices.size()].stop()
		var voice: AudioStreamPlayer = _voices[_voice % _voices.size()]
		var variation := _next_variant(kind)
		voice.stream = _samples[kind][variation]
		voice.volume_db = linear_to_db(level) + VOICE_GAIN_DB - (5.0 if kind in ["swipe", "chip_throw", "shuffle"] else 0.0)
		voice.pitch_scale = _audio_rng.randf_range(0.982, 1.022)
		voice.play()
		_voice += 1
		if shared:
			_last_shared_sound[kind] = Time.get_ticks_msec()
		return {"variant": variation, "pitch": voice.pitch_scale}
	return {}

func _next_variant(kind: String) -> int:
	var bag: Array = _variant_bags.get(kind, [])
	if bag.is_empty():
		bag = range(_samples[kind].size())
		for index in range(bag.size() - 1, 0, -1):
			var other := _audio_rng.randi_range(0, index)
			var value: int = bag[index]
			bag[index] = bag[other]
			bag[other] = value
		# The first item popped from a new bag must differ from the previous bag's
		# final item, even if other kinds of sounds were played in between.
		if bag.size() > 1 and bag.back() == _last_variant.get(kind, -1):
			var value: int = bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = value
	var chosen: int = bag.pop_back()
	_variant_bags[kind] = bag
	_last_variant[kind] = chosen
	return chosen

func _haptic_kind(kind: String) -> String:
	match kind:
		"chip_throw", "chip_collect":
			return "swipe"
		"chip_land", "chip_stack", "chip_fidget":
			return "chip"
		"payout":
			return "confirm"
	return kind

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _focused = false
	if what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true
	if what == NOTIFICATION_APPLICATION_PAUSED: _backgrounded = true
	if what == NOTIFICATION_APPLICATION_RESUMED: _backgrounded = false
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		haptics.stop()
		for voice in _voices:
			if is_instance_valid(voice):
				voice.stop()

func _make_sample(kind: String, variant: int) -> AudioStreamWAV:
	# Original dry micro-foley: filtered friction, damped ceramic resonances, no music.
	var rate := 44100
	var duration := 0.16
	if kind in ["reveal", "confirm"]:
		duration = 0.28
	if kind == "shuffle": duration = 0.22
	if CHIP_KINDS.has(kind):
		duration = {"chip": 0.19, "confirm": 0.22, "chip_throw": 0.12, "chip_land": 0.18,
			"chip_collect": 0.29, "chip_stack": 0.22, "payout": 0.41, "chip_fidget": 0.19, "pot_touch": 0.14}[kind]
	var data := PackedByteArray()
	data.resize(int(rate * duration) * 2)
	var waveform := PackedFloat32Array()
	waveform.resize(data.size() / 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + variant * 731 + kind.hash()
	var low := 0.0
	var medium := 0.0
	var previous := 0.0
	var peak := 0.0
	var impacts := _shuffle_impacts() if kind == "shuffle" else _chip_impacts(kind, variant)
	for i in range(data.size() / 2):
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.16)
		medium = lerpf(medium, noise, 0.42)
		var high := noise - low
		var sample := 0.0
		if CHIP_KINDS.has(kind):
			sample = _chip_foley(kind, t, variant, low, medium - low, noise - medium, impacts)
		elif kind == "shuffle":
			# Two short paper releases: noise/grain only, without ceramic resonances.
			for tap in impacts:
				var dt := t - float(tap[0])
				if dt < 0.0 or dt > 0.10: continue
				var envelope := minf(dt * 2400.0, 1.0) * exp(-dt * (48.0 + variant))
				var flutter := 0.70 + 0.20 * sin(TAU * (110.0 + variant * 13.0) * dt)
				sample += ((medium - low) * 0.56 + high * 0.12) * envelope * flutter * float(tap[1])
		elif kind in ["deal", "reveal", "fold"]:
			var envelope := sin(PI * clampf(t / 0.12, 0, 1)) * exp(-t * 21.0)
			sample = (high * 0.17 + low * 0.35) * envelope
			var dt := t - 0.085
			if dt > 0:
				sample += (sin(TAU * 240.0 * dt) * 0.25 + low * 0.2) * exp(-dt * 100.0)
		else:
			sample = (low * 0.5 + high * 0.035) * exp(-t * 65.0) * minf(t * 1400, 1)
			sample += sin(TAU * 430 * t) * 0.06 * exp(-t * 100)
		previous = lerpf(previous, sample, 0.8)
		# Short fades remove truncation clicks without rounding off the body impact.
		var fade: float = minf(t / 0.0007, 1.0) * clampf((duration - t) / 0.015, 0.0, 1.0)
		var value: float = previous * 0.85 * fade
		waveform[i] = value
		peak = maxf(peak, absf(value))
	var gain: float = minf(1.0, SAMPLE_PEAK / peak) if peak > 0.0 else 1.0
	for i in range(waveform.size()):
		data.encode_s16(i * 2, int(waveform[i] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func _chip_impacts(kind: String, variation: int) -> Array:
	# [start seconds, impact strength, table-body contribution]. Irregular timing
	# avoids a musical pattern; each variant is a slightly different physical gesture.
	var layout: Array = []
	match kind:
		"pot_touch":
			layout = [[0.0, 0.65, 0.04]]
			if variation % 2 == 1: layout.append([0.034, 0.32, 0.02])
		"chip", "chip_fidget":
			var gestures: Array = [
				[[0.0, 0.80, 0.03], [0.033, 0.48, 0.01]],
				[[0.0, 0.65, 0.02], [0.019, 0.38, 0.01], [0.054, 0.61, 0.02]],
				[[0.0, 0.78, 0.03], [0.044, 0.55, 0.01]],
				[[0.0, 0.63, 0.02], [0.028, 0.36, 0.01], [0.063, 0.28, 0.01], [0.106, 0.52, 0.02]],
				[[0.0, 0.91, 0.03], [0.022, 0.48, 0.01], [0.079, 0.34, 0.01]],
				[[0.0, 0.74, 0.03], [0.047, 0.45, 0.01], [0.074, 0.62, 0.02]],
				[[0.0, 0.66, 0.02], [0.016, 0.34, 0.01], [0.041, 0.46, 0.01], [0.089, 0.53, 0.02]],
				[[0.0, 0.83, 0.03], [0.058, 0.54, 0.01]],
			]
			layout = gestures[variation % gestures.size()].duplicate(true)
		"chip_throw":
			layout = [[0.057, 0.21, 0.01]]
		"chip_land":
			layout = [[0.0, 0.96, 0.34], [0.018, 0.36, 0.06], [0.049, 0.19, 0.03]]
		"chip_collect":
			layout = [[0.008, 0.24, 0.06], [0.046, 0.29, 0.07], [0.092, 0.18, 0.05],
				[0.137, 0.31, 0.08], [0.193, 0.22, 0.07], [0.242, 0.36, 0.16]]
		"chip_stack", "confirm":
			layout = [[0.0, 0.24, 0.05], [0.037, 0.32, 0.09], [0.076, 0.21, 0.05], [0.126, 0.69, 0.35]]
		"payout":
			layout = [[0.012, 0.34, 0.12], [0.059, 0.25, 0.08], [0.109, 0.37, 0.09],
				[0.168, 0.26, 0.07], [0.224, 0.31, 0.11], [0.279, 0.28, 0.08], [0.335, 0.73, 0.46]]
	var rhythm := RandomNumberGenerator.new()
	rhythm.seed = 40213 + kind.hash() + variation * 1907
	for index in range(layout.size()):
		var tap: Array = layout[index]
		if float(tap[0]) > 0.0:
			tap[0] += rhythm.randf_range(-0.0045, 0.0055)
		tap[1] *= rhythm.randf_range(0.83, 1.08)
		tap.append(rhythm.randf_range(0.93, 1.07)) # Contact-specific material detune.
	return layout

func _chip_foley(kind: String, t: float, variant: int, low: float, grain: float, high: float, impacts: Array) -> float:
	var sample := 0.0
	var friction_end := 0.0
	var friction_gain := 0.0
	match kind:
		"chip_throw":
			friction_end = 0.095
			friction_gain = 0.29
		"chip_collect":
			friction_end = 0.255
			friction_gain = 0.24
		"chip_stack":
			friction_end = 0.125
			friction_gain = 0.15
		"payout":
			friction_end = 0.35
			friction_gain = 0.23
	if friction_end > 0.0 and t < friction_end:
		var envelope: float = sin(PI * t / friction_end)
		var texture: float = 0.66 + 0.22 * sin(TAU * (39.0 + variant * 3.0) * t) + 0.12 * sin(TAU * 73.0 * t)
		sample += (grain * 0.8 + low * 0.08 + high * 0.11) * envelope * texture * friction_gain
	for index in range(impacts.size()):
		var tap: Array = impacts[index]
		var dt: float = t - float(tap[0])
		if dt < 0.0 or dt > 0.072:
			continue
		var attack: float = minf(dt * 6000.0, 1.0)
		var weight: float = tap[1]
		var detune: float = float(tap[3]) * (0.97 + float(variant % 4) * 0.018)
		# Fixed, inharmonic, rapidly damped modes model ceramic/composite contact.
		# The low component is the felt-covered tabletop, not a pitched UI cue.
		var ceramic: float = sin(TAU * 1650.0 * detune * dt) * 0.18 * exp(-dt * 170.0)
		ceramic += sin(TAU * 2987.0 * detune * dt) * 0.14 * exp(-dt * 255.0)
		ceramic += sin(TAU * 4721.0 * detune * dt) * 0.07 * exp(-dt * 345.0)
		var contact: float = (grain * 0.80 + high * 0.17) * exp(-dt * 620.0)
		var table_body: float = (sin(TAU * 267.0 * dt) * 0.13 + low * 0.10) * exp(-dt * 160.0)
		sample += attack * (weight * (ceramic + contact) + float(tap[2]) * table_body)
	return sample
