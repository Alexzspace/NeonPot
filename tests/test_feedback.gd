extends SceneTree

const FeedbackScript = preload("res://scripts/feedback.gd")
const Driver = preload("res://scripts/haptic_driver.gd")
var checks := 0
var failures := 0

class LoadingProbe extends FeedbackScript:
	var synthesized := 0
	func _make_sample(kind: String, variant: int = 0) -> AudioStreamWAV:
		synthesized += 1
		return super._make_sample(kind, variant)

class HapticSpy extends RefCounted:
	var pulses: Array = []
	var stops := 0
	func setup() -> void:
		pass
	func pulse(kind: String, strength: float) -> void:
		pulses.append([kind, strength])
	func stop() -> void:
		stops += 1

class ContactSpy extends HapticSpy:
	var contacts: Array = []
	func play_contacts(kind: String, strength: float, impacts: Array, pitch: float) -> void:
		contacts.append({"kind": kind, "strength": strength, "impacts": impacts.duplicate(true), "pitch": pitch})

class PendingDriver extends Driver:
	var dispatched := 0
	func _now() -> int: return 1000
	func _dispatch(_profile: Dictionary) -> void: dispatched += 1


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FEEDBACK FAILED: " + label)


func _run() -> void:
	var feedback = LoadingProbe.new()
	feedback.haptic_strength = 0.0
	root.add_child(feedback)
	_check(feedback.synthesized == 0, "startup loads all baked sounds without main-thread synthesis")
	for kind in FeedbackScript.SOUND_KINDS:
		for variant in FeedbackScript.VARIANT_COUNT:
			var original: AudioStreamWAV = feedback._make_sample(kind, variant)
			var baked: AudioStreamWAV = feedback._samples[kind][variant]
			_check(baked.data == original.data and baked.format == original.format and baked.mix_rate == original.mix_rate
				and baked.stereo == original.stereo and baked.loop_mode == original.loop_mode,
				"baked stream exactly preserves original PCM and playback metadata: %s/%d" % [kind, variant])
	var synthesized_before: int = feedback.synthesized
	var fallback: AudioStreamWAV = feedback._load_sample("touch", FeedbackScript.VARIANT_COUNT)
	_check(feedback.synthesized == synthesized_before + 1, "missing asset invokes original synthesizer once")
	_check(fallback.data == feedback._make_sample("touch", FeedbackScript.VARIANT_COUNT).data, "missing asset fallback preserves deterministic PCM")
	_check(feedback._voices.size() == 8, "fixed bounded voice pool")
	_check(feedback._samples.size() == FeedbackScript.SOUND_KINDS.size(), "all original and new sound keys loaded")
	for kind in FeedbackScript.SOUND_KINDS:
		var variants: Array = feedback._samples[kind]
		_check(variants.size() >= 8, "at least eight variants: " + kind)
		var fingerprints: Dictionary = {}
		for stream in variants:
			fingerprints[hash(stream.data)] = true
		_check(fingerprints.size() == variants.size(), "all variants are distinct: " + kind)
		for stream in variants:
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100 and not stream.stereo,
				"16-bit 44.1kHz mono stream: " + kind)
			_check(stream.data.size() >= 8820 and stream.data.size() <= 40000 and stream.data.size() % 2 == 0,
				"short complete PCM data: " + kind)
			_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot, no music/loops: " + kind)
			var peak := 0.0
			var square_sum := 0.0
			var dc_sum := 0.0
			for offset in range(0, stream.data.size(), 2):
				var value: float = float(stream.data.decode_s16(offset)) / 32767.0
				peak = maxf(peak, absf(value))
				square_sum += value * value
				dc_sum += value
			var count: int = stream.data.size() / 2
			var rms: float = sqrt(square_sum / count)
			_check(peak > 0.005 and peak <= FeedbackScript.SAMPLE_PEAK + 0.0001, "audible nonclipped peak: " + kind)
			_check(rms > 0.001 and rms < 0.12, "nonzero moderate energy: " + kind)
			_check(absf(dc_sum / count) < 0.004, "no sustained DC offset: " + kind)
			_check(abs(stream.data.decode_s16(0)) <= 2 and abs(stream.data.decode_s16(stream.data.size() - 2)) <= 64,
				"clean start and tail: " + kind)
	_check(FeedbackScript.MAX_ACTIVE_VOICES * FeedbackScript.SAMPLE_PEAK * db_to_linear(FeedbackScript.VOICE_GAIN_DB) < 0.95,
		"bounded active voices retain mix headroom at louder gain")
	for kind in FeedbackScript.CHIP_KINDS:
		_check(feedback.haptics.PROFILES.has(feedback._haptic_kind(kind)), "new key maps to existing haptic profile: " + kind)
	feedback._audio_rng.seed = 318761
	for kind in FeedbackScript.SOUND_KINDS:
		var previous := -1
		for _bag in range(5):
			var choices: Dictionary = {}
			for _entry in range(FeedbackScript.VARIANT_COUNT):
				var selected: int = feedback._next_variant(kind)
				_check(selected != previous, "never repeat consecutive variant, including bag boundary: " + kind)
				choices[selected] = true
				previous = selected
			_check(choices.size() == FeedbackScript.VARIANT_COUNT, "each bag explores every variation: " + kind)
	var rhythms: Dictionary = {}
	for variation in range(FeedbackScript.VARIANT_COUNT):
		var impacts: Array = feedback._chip_impacts("chip_fidget", variation)
		rhythms[str(impacts)] = true
		_check(impacts.size() >= 2 and impacts.size() <= 4, "fidget contains bounded irregular double/triple/quad contacts")
	_check(rhythms.size() == FeedbackScript.VARIANT_COUNT, "fidget variants use distinct timing and material profiles")
	var before: int = feedback._voice
	feedback.volume = 0.0
	feedback.play("chip_land")
	_check(feedback._voice == before, "volume zero does not start a voice")
	feedback.volume = 0.7
	feedback.public_audio = false
	feedback.play("chip_land", true)
	_check(feedback._voice == before, "public audio disabled does not start shared sound")
	feedback.play("chip_land", false)
	_check(feedback._voice == before + 1, "private audio still works when public audio disabled")
	_check(feedback._voices[before % 8].stream in feedback._samples.chip_land, "play chooses requested sample stream")
	_check(feedback._voices[before % 8].pitch_scale >= 0.982 and feedback._voices[before % 8].pitch_scale <= 1.022,
		"random playback detune remains subtle")
	feedback.public_audio = true
	feedback.play("chip_stack", true)
	var batch_voice: int = feedback._voice
	feedback.play("chip_stack", true)
	_check(feedback._voice == batch_voice, "same-frame shared batch cannot duplicate sound")
	feedback.play("payout", true)
	_check(feedback._voice == batch_voice + 1, "different animation stage is not coalesced")
	before = feedback._voice
	feedback.play("not_a_sound")
	_check(feedback._voice == before, "unknown sound is silent")
	feedback.volume = 1.0
	for burst in 12:
		feedback.play_audio_only("chip_fidget")
	var active_voices := 0
	for voice in feedback._voices:
		if voice.playing: active_voices += 1
	_check(active_voices <= FeedbackScript.MAX_ACTIVE_VOICES, "rapid ceramic contacts enforce active voice headroom")
	before = feedback._voice
	feedback.volume = 10.0
	feedback.play("chip_collect")
	_check(is_equal_approx(feedback._voices[before % 8].volume_db, FeedbackScript.VOICE_GAIN_DB), "volume above one safely clamps")
	feedback.volume = NAN
	before = feedback._voice
	feedback.play("chip_throw")
	_check(feedback._voice == before, "nonfinite volume safely mutes")
	var spy := HapticSpy.new()
	feedback.haptics = spy
	feedback.volume = 0.0
	feedback.haptic_strength = 0.0
	before = feedback._voice
	feedback.preview_sound()
	feedback.preview_haptics()
	_check(feedback._voice == before and spy.pulses.is_empty(), "previews never break zero sound or haptic settings")
	_check(spy.stops == 1, "zero haptic preview cancels any existing feedback")
	feedback.volume = 0.6
	feedback.haptic_strength = 0.5
	feedback.public_audio = false
	feedback.play_audio_only("chip_fidget")
	_check(feedback._voice == before + 1, "explicit audio-only preview bypasses public-audio preference")
	_check(spy.pulses.is_empty(), "explicit audio-only preview does not request haptics")
	feedback.preview_sound()
	_check(feedback._voice == before + 2 and spy.pulses.is_empty(), "sound preview is sound only")
	feedback.preview_haptics()
	_check(feedback._voice == before + 2 and spy.pulses == [["chip", 0.5]], "haptic preview is haptic only at selected intensity")
	feedback.play("chip_fidget")
	_check(spy.pulses.size() == 2 and spy.pulses[1] == ["chip", 0.5], "local fidget still receives local haptic")
	feedback.haptic_strength = 0.0
	feedback.play("chip_fidget")
	_check(spy.pulses.size() == 2, "local zero haptic intensity stays muted")
	feedback.volume = 0.0
	before = feedback._voice
	feedback.play_audio_only("chip_fidget")
	_check(feedback._voice == before, "explicit audio-only preview respects volume zero")
	var contacts := ContactSpy.new()
	feedback.haptics = contacts
	feedback.haptic_strength = 0.6
	feedback.public_audio = false
	feedback.play_chip_contact("chip_land", true, 0.5)
	_check(feedback._voice == before and contacts.contacts.size() == 1, "shared sound mute does not silence chip contact haptics")
	_check(contacts.contacts[0].kind == "chip_land" and is_equal_approx(contacts.contacts[0].strength, 0.3), "contact API preserves dedicated kind and event intensity")
	feedback.volume = 0.7
	feedback.play_chip_contact("chip_stack", false)
	var played: Dictionary = contacts.contacts.back()
	_check(played.impacts == feedback._chip_impacts("chip_stack", feedback._last_variant.chip_stack), "haptics uses the exact chosen sound variant's contact offsets")
	_check(played.pitch == feedback._voices[(feedback._voice - 1) % 8].pitch_scale, "contact scheduling follows actual sound playback pitch")
	feedback.haptic_strength = 0.0
	feedback.play_chip_contact("payout")
	_check(contacts.contacts.size() == 2, "zero haptic setting silences every chip activity")
	feedback.haptic_strength = 0.6
	feedback.play_chip_contact("payout", false, NAN)
	_check(contacts.contacts.size() == 2, "nonfinite event intensity cannot trigger haptics")
	feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	feedback.play_chip_contact("chip_fidget")
	_check(contacts.stops == 1 and contacts.contacts.size() == 2, "focus loss cancels and suppresses future chip haptics")
	feedback._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	feedback.play_chip_contact("chip_throw")
	_check(contacts.contacts.size() == 2, "focus return cannot trigger contacts while still backgrounded")
	feedback._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	feedback.play_chip_contact("chip_throw")
	_check(contacts.contacts.size() == 3, "foreground restores contact feedback without replaying canceled events")
	var stops_before := contacts.stops
	var pulses_before := contacts.pulses.size()
	feedback.public_audio = false
	before = feedback._voice
	feedback.play_card_contact("touch", true)
	_check(feedback._voice == before and contacts.pulses.size() == pulses_before + 1, "peer card touch vibrates even when peer audio is muted")
	_check(is_equal_approx(contacts.pulses.back()[1], 0.45), "peer card haptic follows selected strength")
	feedback.haptic_strength = 0
	feedback.play_card_contact("swipe", true)
	_check(contacts.pulses.size() == pulses_before + 1, "zero setting mutes synchronized card haptics")
	feedback.haptic_strength = 0.6
	feedback.play_card_contact("unknown", true)
	_check(contacts.pulses.size() == pulses_before + 1, "invalid card contact cannot pulse")
	feedback._focused = false
	feedback.play_card_contact("release", true)
	_check(contacts.pulses.size() == pulses_before + 1, "background peer card contact cannot pulse")
	feedback._focused = true
	for level in [0.1, 0.4, 1.0]:
		feedback.haptic_strength = level
		before = feedback._voice
		feedback.play_private_peek("touch")
		_check(contacts.pulses.back() == ["peek_open", 1.0], "every enabled setting opens private peek at full amplitude")
		feedback.play_private_peek("release")
		_check(contacts.pulses.back() == ["peek_close", 1.0], "every enabled setting closes private peek at full amplitude")
		_check(feedback._voice == before + 2, "private sounds remain local when shared audio is off")
	feedback.haptic_strength = 0.2
	feedback.play_private_peek("swipe")
	_check(contacts.pulses.back() == ["swipe", 0.2], "private dragging keeps normal gentle intensity")
	feedback.play_card_contact("touch")
	_check(contacts.pulses.back() == ["touch", 0.2], "ordinary public-card touch is not amplified")
	feedback.volume = 0
	before = feedback._voice
	pulses_before = contacts.pulses.size()
	for disabled in [0.0, -1.0, NAN, INF]:
		feedback.haptic_strength = disabled
		feedback.play_private_peek("touch")
		feedback.play_private_peek("release")
	_check(feedback._voice == before and contacts.pulses.size() == pulses_before, "private peek respects sound zero and disabled/invalid haptics")
	feedback.haptic_strength = 0.5
	feedback.play_private_peek("invalid")
	_check(contacts.pulses.size() == pulses_before, "unknown private event is silent")
	feedback.play_private_peek("touch")
	_check(feedback._voice == before and contacts.pulses.back() == ["peek_open", 1.0], "private haptic remains independent of sound mute")
	feedback.volume = 0.7
	feedback.public_audio = false
	before = feedback._voice
	feedback.play_table_prop_contact("deck", true)
	_check(feedback._voice == before and contacts.contacts.back().kind == "shuffle", "shared deck sound mute leaves haptics active")
	_check(is_equal_approx(contacts.contacts.back().strength, 0.375) and contacts.contacts.back().impacts == [[0.0, 0.65], [0.1, 0.45]], "deck carries two weighted contacts at intended offsets")
	feedback.play_table_prop_contact("deck")
	var deck: Dictionary = contacts.contacts.back()
	_check(feedback._voices[(feedback._voice - 1) % 8].stream in feedback._samples.shuffle, "deck uses original paper sample family")
	_check(deck.pitch == feedback._voices[(feedback._voice - 1) % 8].pitch_scale, "paper haptics follows actual audio playback pitch")
	feedback.play_table_prop_contact("pot")
	var pot: Dictionary = contacts.contacts.back()
	_check(pot.kind == "pot_touch" and pot.impacts == feedback._chip_impacts("pot_touch", feedback._last_variant.pot_touch), "pot uses exact selected ceramic contact variant")
	for variant in FeedbackScript.VARIANT_COUNT:
		var pot_impacts: Array = feedback._chip_impacts("pot_touch", variant)
		_check(pot_impacts.size() in [1, 2] and pot_impacts[0][0] == 0.0, "pot is a short single/double contact at onset")
		_check(not feedback._samples.shuffle[variant].data == feedback._samples.deal[variant].data, "shuffle is an independent paper waveform")
	var contact_count := contacts.contacts.size()
	feedback.volume = 0
	feedback.haptic_strength = 0
	before = feedback._voice
	feedback.play_table_prop_contact("pot")
	feedback.play_table_prop_contact("deck", true)
	_check(contacts.contacts.size() == contact_count and feedback._voice == before, "zero settings silence both prop materials")
	feedback.volume = 0.7
	feedback.haptic_strength = 0.5
	feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	before = feedback._voice
	pulses_before = contacts.pulses.size()
	feedback.play_private_peek("touch")
	feedback.play_table_prop_contact("pot")
	feedback.play_table_prop_contact("deck")
	_check(contacts.contacts.size() == contact_count and contacts.pulses.size() == pulses_before and feedback._voice == before, "background suppresses private and prop feedback")
	feedback._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	stops_before = contacts.stops
	feedback.cancel_chip_haptics()
	_check(contacts.stops == stops_before + 1, "presentation cancellation explicitly clears native and pending chip haptics")
	for voice in feedback._voices:
		voice.stop()
	feedback.queue_free()
	await process_frame
	# Audio mixing is a real thread even when headless frames run without wall-time pacing.
	var cleanup_deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < cleanup_deadline:
		await process_frame
	_check(contacts.stops >= 3, "scene exit cancels native feedback")
	var pending := PendingDriver.new()
	pending._initialized = true
	pending.backend = "test"
	var exiting = FeedbackScript.new()
	exiting.haptics = pending
	exiting.volume = 0
	exiting.haptic_strength = 0.6
	root.add_child(exiting)
	exiting.play_table_prop_contact("deck")
	_check(pending.dispatched == 1 and pending.has_pending(), "deck has a real future haptic before scene exit")
	exiting.queue_free()
	await process_frame
	await process_frame
	_check(not pending.has_pending(), "scene exit clears the scheduled deck return contact")
	await create_timer(0.25).timeout
	print("FEEDBACK_TEST checks=%d failures=%d listening_validated=false" % [checks, failures])
	quit(0 if failures == 0 else 1)
