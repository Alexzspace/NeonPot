extends SceneTree
const Main = preload("res://scripts/main.gd")
const Themes = preload("res://scripts/card_themes.gd")
const Workshop = preload("res://scripts/deck_workshop.gd")
const Library = preload("res://scripts/music_library_view.gd")
var checks := 0
var failures := 0
class Probe extends Main:
	var saves := 0
	func _load_settings() -> void:
		Themes.custom_recipe = {}
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.set_level(0)
		music.set_paused(true)
	func _save_settings() -> void:
		saves += 1
		super._save_settings()
	func reload_preferences() -> void: super._load_settings()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := find_button(child, text)
		if found != null: return found
	return null
func tap(control: Control) -> void:
	check(control != null, "touch target exists")
	if control == null: return
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://test-results/v140-" + name + ".png") == OK, "capture " + name)
func run() -> void:
	root.size = Vector2i(1440, 660)
	var app := Probe.new()
	app.settings_path = "user://test_personal_tools_" + str(Time.get_ticks_usec()) + ".cfg"
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	await process_frame
	for lang in ["zh", "en"]:
		app.language = lang
		app._show_settings()
		await create_timer(0.3).timeout
		await tap(find_button(app.modal, "牌面工坊" if lang == "zh" else "DECK WORKSHOP"))
		check(app.modal is Workshop, "native touch opens workshop")
		var original: Dictionary = Themes.custom_recipe.duplicate(true)
		await process_frame
		await capture("workshop-" + lang)
		check(Themes.custom_recipe == original, "opening and rendering workshop cannot apply draft")
		if DisplayServer.get_name() != "headless":
			app.modal.reveal_palette()
			await process_frame
			await tap(app.modal.color_buttons[0])
			check(app.modal.palette_buttons.size() == 16, "exactly sixteen preset color choices")
			await tap(app.modal.palette_buttons[7])
			check(app.modal.recipe.paper == Themes.PALETTE[7], "native color swatch applies paper color")
			await process_frame
		await tap(app.modal.random_button)
		var draft: Dictionary = app.modal.recipe.duplicate(true)
		check(Themes.custom_recipe == original, "native randomize remains draft only")
		await tap(app.modal.apply_button)
		check(Themes.custom_recipe == draft and not app.modal is Workshop, "native Apply saves and returns to settings")
		await process_frame
		await tap(find_button(app.modal, "导入音乐" if lang == "zh" else "IMPORT MUSIC"))
		check(app.modal is Library, "native touch opens music library")
		check(app.modal.music == app.music, "library uses live persistent player")
		await process_frame
		await capture("music-" + lang)
		root.go_back_requested.emit()
		await process_frame
		check(app.modal == null, "system back closes personal panel")
	app._apply_custom_deck({"seed": 140})
	check(not Themes.custom_recipe.is_empty() and app.saves > 0, "Apply saves personal recipe")
	var saved_recipe: Dictionary = Themes.custom_recipe.duplicate(true)
	Themes.custom_recipe = {}
	app.reload_preferences()
	check(Themes.custom_recipe == saved_recipe, "real ConfigFile save and reload restores exact recipe")
	var state_before: Dictionary = app.session.state.duplicate(true)
	app._apply_custom_deck({"seed": 141})
	check(app.session.state == state_before, "customization does not mutate session")
	app._choose_deck(1)
	check(Themes.custom_recipe.is_empty(), "preset Apply disables custom override")
	for viewport in [Vector2i(2560, 1600), Vector2i(2160, 1527)]:
		root.size = viewport
		await process_frame
		app._show_deck_workshop()
		await process_frame
		check(app.modal.position.y >= 0 and app.modal.size.y >= 660, "workshop safe layout survives resize")
		app._show_music_library()
		await process_frame
		check(app.modal.size.y >= 660, "music safe layout survives resize")
	app._close_modal()
	DirAccess.remove_absolute(app.settings_path)
	app.queue_free()
	await process_frame
	await process_frame
	Themes.custom_recipe = {}
	print("PERSONAL_TOOLS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
