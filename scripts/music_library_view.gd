extends Control
## Device-local playlist management; audio never enters a room snapshot.
signal closed()
signal operated()

var music: Node
var language := "zh"
var _list: VBoxContainer
var _status: Label
var _dialog: FileDialog
var _heading: Label
var _import_button: Button

func _ready() -> void:
	size = Vector2(1440, maxf(660, size.y))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("11131f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_heading = Label.new()
	_heading.text = _t("本地音乐库", "Local music library")
	_heading.add_theme_font_size_override("font_size", 32)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	header.add_child(_button(_t("返回", "Back"), func(): closed.emit()))
	var description := Label.new()
	description.text = _t("从设备导入 MP3 / Ogg Vorbis / WAV · 单首最多 64 MB / 30 分钟\n复制到游戏内保存，只在本机播放。移除不会删除原文件。", "Import MP3 / Ogg Vorbis / WAV · Up to 64 MB / 30 minutes per track\nSaved inside the game and played on this device. Removing a track keeps your original file.")
	if is_instance_valid(music) and music.flac_available():
		description.text += _t("\nFLAC：本机转换为高质量 Ogg 有损播放副本，原文件保留不变。", "\nFLAC: converted locally to a high-quality lossy Ogg playback copy. Original files stay unchanged.")
	else:
		description.text += _t("\n此设备未配置 FLAC 转换器。", "\nFLAC converter is not configured on this device.")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 20)
	column.add_child(description)
	_import_button = _button(_t("＋ 导入音乐", "+ Import music"), _open_import)
	column.add_child(_import_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 20)
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_dialog = FileDialog.new()
	_dialog.use_native_dialog = true
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dialog.filters = PackedStringArray(["*.mp3,*.ogg,*.wav ; Audio / 音乐"])
	if is_instance_valid(music) and music.flac_available():
		_dialog.filters = PackedStringArray(["*.mp3,*.ogg,*.wav,*.flac ; Audio / 音乐"])
	_dialog.title = _t("导入音乐", "Import music")
	_dialog.files_selected.connect(_import_files)
	add_child(_dialog)
	if is_instance_valid(music):
		music.changed.connect(_refresh)
		music.import_busy_changed.connect(_refresh)
		music.import_finished.connect(_import_finished)
	_refresh()

func set_available_height(value: float) -> void:
	size.y = maxf(660, value)

func _t(zh: String, en: String) -> String:
	return en if language == "en" else zh

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(140, 52)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(callback)
	return button

func _open_import() -> void:
	if not is_instance_valid(music) or music.import_busy or music._batch_busy: return
	_dialog.popup_centered_ratio(0.8)

func _import_files(paths: PackedStringArray) -> void:
	if not is_instance_valid(music): return
	music.import_files(paths)

func _import_finished(imported: int, errors: Array[String]) -> void:
	_refresh()
	_status.text = _t("已导入 %d 首。", "Imported %d tracks.") % imported
	if not errors.is_empty():
		_status.text += " " + " / ".join(errors.slice(0, 3))
	if imported > 0:
		operated.emit()

func _play(track_index: int) -> void:
	music.select_track(track_index)
	music.set_paused(false)
	operated.emit()

func _remove(track_index: int) -> void:
	if music.remove_imported_track(track_index):
		operated.emit()

func _refresh() -> void:
	if not is_instance_valid(_list): return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not is_instance_valid(music): return
	_import_button.disabled = music.import_busy or music._batch_busy
	_status.text = music.error_text() if not music.last_error.is_empty() else _t("正在选择：", "Selected: ") + music.title()
	if music.import_busy:
		_status.text = _t("正在本地转换 FLAC… 可以返回，音乐导入会继续。", "Converting FLAC locally… You can go back; the import will continue.")
	var count := 0
	for track_index in music.tracks.size():
		var track: Dictionary = music.tracks[track_index]
		if not track.get("imported", false): continue
		count += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_list.add_child(row)
		var label := Label.new()
		label.text = str(track.title)
		label.tooltip_text = label.text
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 22)
		row.add_child(label)
		row.add_child(_button(_t("播放", "Play"), _play.bind(track_index)))
		row.add_child(_button(_t("移除", "Remove"), _remove.bind(track_index)))
	if count == 0:
		var empty := Label.new()
		empty.text = _t("还没有导入音乐。原有曲目仍可在播放器中播放。", "No imported tracks yet. Built-in tracks remain in the player.")
		empty.add_theme_font_size_override("font_size", 22)
		_list.add_child(empty)
