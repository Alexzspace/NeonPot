extends SceneTree
## Run with --headless --script res://tools/bake_feedback.gd.
## --benchmark-only measures ready without baking. --verify checks existing PCM.
const Feedback = preload("res://scripts/feedback.gd")
const OUTPUT := "res://assets/audio/generated"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var feedback := Feedback.new()
	feedback.haptic_strength = 0
	feedback.volume = 0
	if "--benchmark-only" in OS.get_cmdline_user_args():
		var started := Time.get_ticks_usec()
		root.add_child(feedback)
		print("FEEDBACK_READY_USEC=%d samples=%d" % [Time.get_ticks_usec() - started, feedback._samples.size() * Feedback.VARIANT_COUNT])
		feedback.queue_free()
		await process_frame
		await create_timer(0.25).timeout
		quit()
		return
	var verify := "--verify" in OS.get_cmdline_user_args()
	if not verify and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("Could not create generated feedback directory")
		feedback.free()
		quit(1)
		return
	var count := 0
	var failures := 0
	var pcm_bytes := 0
	for kind in Feedback.SOUND_KINDS:
		for variant in Feedback.VARIANT_COUNT:
			var expected: AudioStreamWAV = feedback._make_sample(kind, variant)
			var path := "%s/%s_%d.res" % [OUTPUT, kind, variant]
			if not verify and ResourceSaver.save(expected, path) != OK:
				push_error("Could not save " + path)
				failures += 1
				continue
			var actual := ResourceLoader.load(path, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
			if actual == null or actual.data != expected.data or actual.mix_rate != expected.mix_rate or actual.format != expected.format or actual.stereo != expected.stereo or actual.loop_mode != expected.loop_mode:
				push_error("Baked PCM mismatch: " + path)
				failures += 1
			count += 1
			pcm_bytes += expected.data.size()
	feedback.free()
	print("FEEDBACK_BAKE samples=%d pcm_bytes=%d failures=%d verify_only=%s" % [count, pcm_bytes, failures, verify])
	quit(1 if failures else 0)
