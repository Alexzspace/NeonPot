extends SceneTree
const Boot = preload("res://scripts/boot.gd")
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures := 0

class FixtureMain extends Control:
	var defer_home_entrance := false
	var deferred_before_ready := false
	var entrances := 0
	func _ready() -> void: deferred_before_ready = defer_home_entrance
	func play_home_entrance() -> void: entrances += 1

class FastBoot extends Boot:
	var creates := 0
	func _request_main_load() -> void: _load_ready = true
	func _create_main() -> Control:
		creates += 1
		return FixtureMain.new()
	func _saved_volume() -> float: return 0.0

class FailedBoot extends FastBoot:
	func _request_main_load() -> void: pass

class MainProbe extends Main:
	func _load_settings() -> void:
		feedback.volume = 0.0
		feedback.haptic_strength = 0.0
		music.level = 0.0
		music.paused = true
	func _save_settings() -> void: pass

class FullBoot extends Boot:
	var creates := 0
	func _create_main() -> Control:
		creates += 1
		var main := MainProbe.new()
		main.animate_on_start = true
		main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return main
	func _saved_volume() -> float: return 0.0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOOT: " + label)

func _add(boot: Control) -> void:
	boot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(boot)

func _wait_until(predicate: Callable, label: String, timeout: float = 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	check(predicate.call(), label)

func _run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var previous_settings := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	for area in [Vector2(2622, 1206), Vector2(2912, 1224), Vector2(3008, 1880), Vector2(2160, 1527), Vector2(600, 1000)]:
		var rect := Boot.fitted_rect(area)
		check(Rect2(Vector2.ZERO, area).grow(0.01).encloses(rect), "full video is contained at %s" % area)
		check(is_equal_approx(rect.size.x / rect.size.y, 16.0 / 9.0), "video aspect never stretches at %s" % area)
		check(rect.get_center().is_equal_approx(area * 0.5), "letterboxing stays symmetrical at %s" % area)
	var config := ConfigFile.new()
	check(is_equal_approx(Boot.volume_from_config(config), 0.7), "missing preference keeps existing SFX default")
	for pair in [[0.0, 0.0], [0.4, 0.4], [1.0, 1.0], [-4.0, 0.0], [8.0, 1.0], [NAN, 0.0], [INF, 0.0], ["invalid", 0.7]]:
		config.set_value("preferences", "volume", pair[0])
		check(is_equal_approx(Boot.volume_from_config(config), pair[1]), "saved volume clamps safely: %s" % pair[0])
	var boot := FastBoot.new()
	boot.video_path = "res://assets/startup/missing-fixture.ogv"
	_add(boot)
	check(boot.completion_reason == "unavailable", "missing optional video immediately falls through")
	var boot_ref: WeakRef = weakref(boot)
	await _wait_until(func(): return boot_ref.get_ref() == null, "fallback transitions to main without hanging")
	var next := current_scene as FixtureMain
	check(next != null and next.deferred_before_ready and next.entrances == 1, "entrance deferred before ready and invoked exactly once")
	next.queue_free()
	await process_frame
	boot = FastBoot.new()
	_add(boot)
	boot.set_process(false)
	check(boot.player.stream != null and boot.player.volume == 0.0 and not boot.player.loop, "Theora opens with saved mute and no loop")
	boot._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	boot._process(30.0)
	check(boot._elapsed == 0.0 and boot.player.paused and boot.creates == 0, "background pause freezes video and active-time watchdog")
	boot._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not boot.player.paused, "resume unpauses existing playback")
	boot._process(Boot.VIDEO_WATCHDOG + 0.1)
	check(boot.completion_reason == "watchdog" and boot.creates == 1 and not boot.player.is_playing(), "stalled video reaches finite fallback before instantiating main")
	await _wait_until(func(): return boot._revealing, "watchdog waits for main's first rendered frame")
	boot._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	boot._process(1.0)
	await process_frame
	check(not is_instance_valid(boot), "watchdog transition releases boot node")
	if is_instance_valid(boot): boot.queue_free()
	if is_instance_valid(current_scene): current_scene.queue_free()
	await process_frame
	var failed := FailedBoot.new()
	_add(failed)
	failed.set_process(false)
	failed._process(Boot.LOAD_WATCHDOG + 0.1)
	check(failed._failed and failed.player.stream == null and failed.cover.get_child_count() >= 2, "stalled main load has visible finite failure and releases video")
	failed.queue_free()
	await process_frame
	var absent := Boot.new()
	absent.main_scene_path = "res://scenes/missing-main-fixture.tscn"
	_add(absent)
	check(absent._failed and not absent.player.is_playing(), "missing main resource stops before starting movie")
	absent.queue_free()
	await process_frame
	await _real_playback()
	check(FileAccess.file_exists("user://settings.cfg") == had_settings and (not had_settings or FileAccess.get_file_as_bytes("user://settings.cfg") == previous_settings), "all boot paths preserve user settings bytes")
	print("BOOT_SUMMARY checks=%d failures=%d renderer=%s" % [checks, failures, DisplayServer.get_name()])
	quit(0 if failures == 0 else 1)

func _real_playback() -> void:
	var capture := DisplayServer.get_name() != "headless"
	var ratio := "phone"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): ratio = arg.trim_prefix("--profile=")
	var area := Vector2i(2622, 1206) if ratio == "phone" else Vector2i(3008, 1880)
	root.content_scale_size = area
	root.size = Vector2i(Vector2(area) * (0.5 if ratio == "phone" else 0.35))
	var boot := FullBoot.new()
	var reasons: Array = []
	var released: Array = []
	boot.intro_finished.connect(func(reason): reasons.append(reason))
	boot.main_ready.connect(func(main): released.append(boot.player.stream == null and not boot.player.is_playing() and main._entrance != null))
	_add(boot)
	var begin := Time.get_ticks_msec()
	await create_timer(0.45).timeout
	check(is_instance_valid(boot) and boot.creates == 0 and boot.player.stream_position > 0.1, "real decoder advances with no instantiated Main or background music")
	boot._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var paused_position: float = boot.player.stream_position
	await create_timer(0.2).timeout
	check(absf(boot.player.stream_position - paused_position) < 0.06 and boot.creates == 0, "actual decoder pauses without skipping ahead or loading Main")
	boot._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	var first: Image
	if capture:
		await RenderingServer.frame_post_draw
		first = boot.player.get_video_texture().get_image()
		check(first != null and first.get_size() == Vector2i(1280, 720), "actual decoded frame has encoded dimensions")
	await create_timer(1.35).timeout
	if capture:
		await RenderingServer.frame_post_draw
		var second := boot.player.get_video_texture().get_image()
		check(first.get_data() != second.get_data(), "actual moving video pixels change during playback")
		var path := "user://intro_%s_playing.png" % ratio
		check(root.get_texture().get_image().save_png(path) == OK, "capture real video within letterbox")
		print("BOOT_CAPTURE " + ProjectSettings.globalize_path(path))
	var boot_ref: WeakRef = weakref(boot)
	await _wait_until(func(): return boot_ref.get_ref() == null, "natural video finish enters fully rendered home", 12.0)
	check(reasons == ["finished"], "decoder finished naturally once, without fake completion or watchdog")
	check(released == [true], "video resources are released while the actual home entrance is running")
	check(Time.get_ticks_msec() - begin >= 3000, "full original three-second intro plays before transition")
	check(current_scene is MainProbe and current_scene.has_method("play_home_entrance"), "actual Main lifecycle reached after video")
	if capture:
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var path := "user://intro_%s_home.png" % ratio
		check(root.get_texture().get_image().save_png(path) == OK, "capture home after cover is freed")
		print("BOOT_CAPTURE " + ProjectSettings.globalize_path(path))
	if is_instance_valid(current_scene): current_scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
