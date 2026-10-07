extends Control
## One-shot video cover. The main scene is loaded off-thread, then instantiated
## only after video audio has stopped. This scene never writes preferences.

signal intro_finished(reason: String)
signal main_ready(main: Control)

const BACKGROUND := Color("#0f0d17")
const VIDEO_SIZE := Vector2(1280, 720)
const VIDEO_WATCHDOG := 8.0
const LOAD_WATCHDOG := 20.0
const FADE_SECONDS := 0.35

## Optional startup movie; a missing file falls through to the main scene.
@export_file("*.ogv") var video_path := "res://assets/startup/intro.ogv"
## The scene loaded concurrently but instantiated only when the movie ends.
@export_file("*.tscn") var main_scene_path := "res://scenes/main.tscn"

var player: VideoStreamPlayer
var cover: ColorRect
var completion_reason := ""
var _main_scene: PackedScene
var _main: Control
var _load_requested := false
var _load_ready := false
var _video_done := false
var _transition_started := false
var _revealing := false
var _failed := false
var _active := true
var _elapsed := 0.0
var _fade_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	cover = ColorRect.new()
	cover.color = BACKGROUND
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cover)
	player = VideoStreamPlayer.new()
	player.expand = true
	player.loop = false
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.volume = _saved_volume()
	cover.add_child(player)
	resized.connect(_fit_video)
	_fit_video()
	_request_main_load()
	if _failed: return
	if "--skip-intro" in OS.get_cmdline_user_args():
		_finish_intro("skipped")
	elif ResourceLoader.exists(video_path, "VideoStream"):
		player.stream = load(video_path) as VideoStream
		if player.stream != null:
			player.finished.connect(_finish_intro.bind("finished"))
			player.play()
			player.paused = not _active
		else:
			_finish_intro("unavailable")
	else:
		_finish_intro("unavailable")

static func fitted_rect(area: Vector2) -> Rect2:
	var factor := maxf(0.0, minf(area.x / VIDEO_SIZE.x, area.y / VIDEO_SIZE.y))
	var fitted := VIDEO_SIZE * factor
	return Rect2((area - fitted) * 0.5, fitted)

func _fit_video() -> void:
	if not is_instance_valid(player): return
	var rect := fitted_rect(size)
	player.position = rect.position
	player.size = rect.size

static func volume_from_config(config: ConfigFile) -> float:
	var value: Variant = config.get_value("preferences", "volume", 0.7)
	if not value is float and not value is int: return 0.7
	var level := float(value)
	return clampf(level, 0.0, 1.0) if is_finite(level) else 0.0

func _saved_volume() -> float:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	return volume_from_config(config)

func _request_main_load() -> void:
	if not ResourceLoader.exists(main_scene_path, "PackedScene"):
		_show_failure()
		return
	_load_requested = ResourceLoader.load_threaded_request(main_scene_path, "PackedScene") == OK
	if not _load_requested: _show_failure()

func _process(delta: float) -> void:
	if not _active or _failed: return
	_elapsed += delta
	if _revealing:
		_fade_elapsed += delta
		cover.modulate.a = 1.0 - smoothstep(0.0, FADE_SECONDS, _fade_elapsed)
		if _fade_elapsed >= FADE_SECONDS:
			_release_video()
			main_ready.emit(_main)
			queue_free()
		return
	if not _video_done and _elapsed >= VIDEO_WATCHDOG:
		_finish_intro("watchdog")
	if _load_requested and not _load_ready:
		var status := ResourceLoader.load_threaded_get_status(main_scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_main_scene = ResourceLoader.load_threaded_get(main_scene_path) as PackedScene
			_load_ready = _main_scene != null
			if not _load_ready: _show_failure()
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_show_failure()
	if _elapsed >= LOAD_WATCHDOG and not _load_ready:
		_show_failure()
	elif _video_done and _load_ready and not _transition_started:
		_begin_reveal()

func _finish_intro(reason: String) -> void:
	if _video_done: return
	_video_done = true
	completion_reason = reason
	if is_instance_valid(player):
		player.stop()
		player.volume = 0.0
	intro_finished.emit(reason)

func _create_main() -> Control:
	return _main_scene.instantiate() as Control

func _begin_reveal() -> void:
	_transition_started = true
	_main = _create_main()
	if _main == null:
		_show_failure()
		return
	_main.set("defer_home_entrance", true)
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if not is_inside_tree() or not is_instance_valid(_main): return
	_revealing = true
	_main.call("play_home_entrance")

func _release_video() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
	_main_scene = null

func _show_failure() -> void:
	if _failed: return
	_failed = true
	_release_video()
	# Loading errors have a finite, visible endpoint instead of an eternal cover.
	var label := Label.new()
	label.text = "无法启动，请重启应用。\nUnable to start. Please restart the app."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("#e2ddeb"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(label)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_active = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_active = true
	else:
		return
	if is_instance_valid(player): player.paused = not _active

func _exit_tree() -> void:
	_release_video()
