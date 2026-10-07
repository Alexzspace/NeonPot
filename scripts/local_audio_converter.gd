extends Node
## Optional Windows helper. The child process and temporary output belong to this node.
signal completed(success: bool)

const MAX_OUTPUT_BYTES := 64 * 1024 * 1024
var executable_override := "" # Tests may supply an explicit unavailable path.
var timeout_ms := 120000
var pid := -1
var output_path := ""
var last_error := ""
var _started := 0

func executable() -> String:
	if OS.get_name() != "Windows": return ""
	if not executable_override.is_empty():
		return executable_override if FileAccess.file_exists(executable_override) else ""
	var configured := OS.get_environment("NEON_POT_FFMPEG")
	if not configured.is_empty():
		return configured if configured.is_absolute_path() and FileAccess.file_exists(configured) else ""
	for folder in OS.get_environment("PATH").split(";", false):
		var candidate := folder.trim_prefix('"').trim_suffix('"').path_join("ffmpeg.exe")
		if candidate.is_absolute_path() and FileAccess.file_exists(candidate): return candidate
	var local := OS.get_environment("LOCALAPPDATA").path_join("Temp/texas-holdem-music-transcode/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe")
	return local if FileAccess.file_exists(local) else ""

func start(source: String, destination: String) -> bool:
	if pid > 0: return false
	var program := executable()
	if program.is_empty():
		last_error = "flac_unavailable"
		return false
	output_path = ProjectSettings.globalize_path(destination)
	var input_path := ProjectSettings.globalize_path(source)
	if not input_path.is_absolute_path():
		last_error = "read"
		return false
	var arguments := PackedStringArray(["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-xerror", "-protocol_whitelist", "file", "-f", "flac", "-i", input_path, "-map", "0:a:0", "-vn", "-map_metadata", "-1", "-ac", "2", "-ar", "48000", "-c:a", "libvorbis", "-q:a", "6", output_path])
	pid = OS.create_process(program, arguments, false)
	if pid <= 0:
		last_error = "flac_convert"
		cleanup()
		return false
	_started = Time.get_ticks_msec()
	last_error = ""
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	return true

func _process(_delta: float) -> void:
	if pid <= 0: return
	if Time.get_ticks_msec() - _started > timeout_ms:
		cancel("flac_timeout")
		return
	if FileAccess.file_exists(output_path):
		var file := FileAccess.open(output_path, FileAccess.READ)
		if file != null and file.get_length() > MAX_OUTPUT_BYTES:
			file.close()
			cancel("size")
			return
	if OS.is_process_running(pid): return
	var exit_code := OS.get_process_exit_code(pid)
	pid = -1
	set_process(false)
	last_error = "" if exit_code == 0 else "flac_convert"
	completed.emit(exit_code == 0)

func cancel(reason: String = "flac_cancelled") -> void:
	var was_running := pid > 0
	if was_running and OS.is_process_running(pid): OS.kill(pid)
	# Windows may release the output handle shortly after TerminateProcess.
	# Only cancellation/shutdown uses this bounded cleanup grace period.
	if was_running:
		var deadline := Time.get_ticks_msec() + 200
		while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(2)
	pid = -1
	set_process(false)
	last_error = reason
	cleanup()
	if was_running: completed.emit(false)

func cleanup() -> void:
	if not output_path.is_empty() and FileAccess.file_exists(output_path):
		var deadline := Time.get_ticks_msec() + 200
		while DirAccess.remove_absolute(output_path) != OK and FileAccess.file_exists(output_path) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(2)
	output_path = ""

func _exit_tree() -> void:
	cancel()
