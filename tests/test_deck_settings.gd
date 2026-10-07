extends SceneTree
const Main = preload("res://scripts/main.gd")
const Themes = preload("res://scripts/card_themes.gd")
var checks := 0
var failures := 0
class Probe extends Main:
	var saves := 0
	func _load_settings() -> void:
		feedback.volume = 0
		feedback.haptic_strength = 0
		music.paused = true
	func _save_settings() -> void: saves += 1
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var app := Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app._choose_deck(2)
	check(app.preferred_deck_theme == 2 and Themes.active_id == 2 and app.saves == 1, "personal choice applies and saves")
	app._show_deck_gallery()
	await process_frame
	check(app.modal == app.deck_gallery and app.deck_gallery.can_apply, "settings opens full gallery")
	app._show_about()
	await process_frame
	check(app.modal.has_method("set_available_height"), "about supports responsive modal contract")
	if DisplayServer.get_name() != "headless":
		for lang in ["zh", "en"]:
			app.language = lang
			app._show_about()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/about-" + lang + ".png")
			app.modal.scroll.scroll_vertical = 9999
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/about-" + lang + "-credits.png")
		app.language = "zh"
	for height in [660, 900, 1018]:
		app.modal.set_available_height(height)
		await process_frame
		check(app.modal.scroll.size.y > 500 and app.modal.scroll.size.y <= height, "about has bounded readable scroll viewport")
	app._close_modal()
	app._start_solo()
	while app._table_entering: await process_frame
	check(int(app.shown_state.get("deck_theme", -1)) == 2, "solo inherits preference")
	var original: Dictionary = app.shown_state.duplicate(true)
	var presentation_token: int = app._presentation_token
	app.input_locked = true
	app._choose_deck(1)
	check(app.input_locked and app._presentation_token == presentation_token, "theme-only host publication preserves ongoing presentation and input state")
	app.input_locked = false
	check(app.preferred_deck_theme == 1 and Themes.active_id == 1, "solo theme can change")
	check(app.shown_state.players == original.players and app.shown_state.board == original.board, "theme selection does not change poker state")
	# Exercise a recipient state using the real root hook without creating fake cards.
	app.session.is_host = false
	app.session.is_local = false
	var received: Dictionary = app.shown_state.duplicate(true)
	received.deck_theme = 3
	app._on_state(received)
	check(Themes.active_id == 3 and app.preferred_deck_theme == 1, "host display does not overwrite local preference")
	var prior_saves: int = app.saves
	app._choose_deck(0)
	check(Themes.active_id == 3 and app.saves == prior_saves, "client cannot apply or save a table override")
	app._show_deck_gallery()
	await process_frame
	check(not app.deck_gallery.can_apply and app.deck_gallery.selected_theme == 3, "client gallery shows room choice and disables apply")
	app.session.is_host = true
	app.shown_state.paused = true
	check(not app._can_choose_deck(), "paused host cannot offer a nonfunctional Apply")
	app.shown_state.paused = false
	app.session.is_host = false
	app._confirm_leave()
	var box := app.modal.get_child(1)
	for child in box.get_children():
		if child is Button and child.position.y == 340: child.pressed.emit()
	check(Themes.active_id == 1 and app.preferred_deck_theme == 1, "leaving room restores personal theme")
	app._close_modal()
	app.queue_free()
	await process_frame
	await process_frame
	print("DECK_SETTINGS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
