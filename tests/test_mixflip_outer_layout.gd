extends SceneTree
## Deterministic fixed-orientation MIX Flip outer-display UI coverage.

const Main = preload("res://scripts/main.gd")
const Layout = preload("res://scripts/mixflip_outer_layout.gd")
var checks := 0
var failures := 0
var app: Control

class Probe extends Main:
	func _load_settings() -> void:
		language = "zh"
		feedback.volume = 0.0
		feedback.haptic_strength = 0.0
		music.level = 0
		music.paused = true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIXFLIP_OUTER: " + label)

func _inside(rect: Rect2, control: Control) -> bool:
	return rect.grow(1.0).encloses(control.get_rect())

func _check_modal_below_camera(label: String, primary: Rect2) -> void:
	check(is_instance_valid(app.modal), label + " exists")
	if app.modal.has_meta("fullscreen_modal"):
		check(app.modal.position.y >= primary.position.y and app.modal.position.y + app.modal.size.y <= primary.end.y + 1.0, label + " fullscreen content stays in primary region")
	else:
		var panel: Control
		for child in app.modal.get_children():
			if child is Panel and child.has_meta("main_modal_panel"):
				panel = child
				break
		check(is_instance_valid(panel) and panel.position.y >= primary.position.y and panel.position.y + panel.size.y <= primary.end.y + 1.0, label + " panel stays below camera band")

func _showdown_state(count: int) -> Dictionary:
	var players: Array = []
	for i in range(count):
		players.append({"name": "Player %d Long Name" % i, "cards": [i, 13 + i], "folded": false})
	return {"phase": "showdown", "hand_id": 90 + count, "board": [8, 22, 36, 50, 12], "pot": 600, "players": players, "result": [{"seat": 0, "amount": 600}]}

func _profile_geometry() -> void:
	var full := Layout.profile(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)], true)
	check(full.mode == "full_top" and full.full and full.landscape, "single camera-top landscape profile detected")
	check(full.logical_size.x == 1440.0 and absf(full.logical_size.y - 1250.0) < 1.0, "full profile retains complete 1392x1208 aspect")
	check(full.camera_bounds.position.x > 686.0 and full.camera_bounds.end.x == full.logical_size.x, "R90 664..1392 camera bounds map to the right side")
	check(full.primary_rect.position.y >= 410.0 and full.primary_rect.end.is_equal_approx(full.logical_size), "all key interaction is reserved below the camera band")
	check(full.aux_rect.end.x < full.camera_bounds.position.x, "left auxiliary art/title region avoids camera bounds")
	check(full.camera_deck_center.x < full.camera_pot_center.x, "calibratable deck and pot lens centers remain distinct")
	check(full.camera_bounds.has_point(full.pot_notch_rect.get_center()), "pot amount notch sits between the estimated lenses")
	var basic := Layout.profile(Vector2i(1392, 810), Vector2i(1392, 1208), [], false)
	check(basic.mode == "basic_landscape" and not basic.full and basic.primary_rect.size == basic.logical_size, "existing 1392x810 HyperOS application region remains supported")
	var other := Layout.profile(Vector2i(2400, 1080), Vector2i(2400, 1080), [], false)
	check(other.is_empty(), "ordinary inner display does not trigger MIX Flip outer UI")

func _run() -> void:
	_profile_geometry()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1392, 1208)
	root.size = Vector2i(1392, 1208)
	app = Probe.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app.session.start_local(["你的超长玩家名字", "Long Opponent Alpha", "East Side Player", "South Seat", "West Side", "River Seat"], 1000)
	await process_frame
	var normal_hand_rect: Rect2 = app.hand_label.get_rect()
	var normal_room_rect: Rect2 = app.room_info.get_rect()
	app._set_mixflip_test_geometry(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)])
	await process_frame
	var profile: Dictionary = app.mixflip_outer_profile
	var primary: Rect2 = profile.primary_rect
	check(profile.mode == "full_top", "fixed full-screen profile applied to product UI")
	check(app.canvas.size.is_equal_approx(profile.logical_size), "canvas uses the complete outer display")
	check(app.mixflip_decor.show_notches, "table displays camera pot notch frames")
	check(app.action_label.position.x == app.own_cards[0].position.x and app.action_label.get_rect().end.y <= app.own_cards[0].position.y, "table quote sits above the left hand cards")
	check(app.amount_input.size.y == 164.0 and app.fold_button.size.y == 220.0 and app.amount_input.get_rect().end.y < app.fold_button.position.y, "taller slider and action buttons fill separate right-hand rows")
	check(app.amount_input.get("outer_layout") == true, "outer slider uses larger internal typography and touch geometry")
	check(app.mixflip_decor.visible and app.mixflip_decor.camera_bounds == profile.camera_bounds, "camera-specific deck/pot art uses R90 bounds")
	for control in [app.fold_button, app.call_button, app.raise_button, app.allin_button, app.amount_input, app.own_cards[0], app.own_cards[1]]:
		check(_inside(primary, control), "primary card/action stays below camera band")
	for button in [app.fold_button, app.call_button, app.raise_button, app.allin_button]:
		check(button.size.x >= 162.0 and button.size.y >= 169.0 and button.get_theme_font_size("font_size") >= 46, "key action meets 48dp width and 52dp height target")
	for button in [app.hands_button, app.settings_button]:
		check(primary.grow(1.0).encloses(button.get_rect()) and button.size.y >= 170.0 and button.position.x > app.table_back_panel.get_rect().end.x, "utility buttons sit beside the board at touch size")
	check(app.title_label.self_modulate.a == 0.0, "outer title is removed")
	check(_inside(profile.aux_rect, app.hand_label) and _inside(profile.aux_rect, app.room_info), "hand and room heading occupy upper-left area")
	for slot in app.seats:
		check(_inside(profile.aux_rect, slot.panel), "six seat grid fits upper-left area")
	for control in [app.name_edit, app.stack_input, app.home_host_button, app.home_search_button, app.home_solo_button, app.player_count]:
		check(minf(control.size.x, control.size.y) >= 162.0 and primary.grow(1.0).encloses(control.get_rect()), "home input or entry action meets the true 48dp touch floor")
	check(app.name_edit.get_theme_font_size("font_size") == 40, "outer name field uses readable type")
	for label in [app.phase_label, app.pot_label, app.hand_label, app.room_info, app.toast_label]:
		check(label.get_theme_font_size("font_size") >= 36, "outer-screen body copy is at least 36px")
	check(app.hands_button.get_theme_font_size("font_size") >= 40 and app.settings_button.get_theme_font_size("font_size") >= 40, "secondary header actions remain readable")
	check(app.board_cards[0].size == Vector2(204, 285), "community cards are enlarged into the taller compact board")
	for card in app.board_cards:
		check(app.table_back_panel.get_rect().encloses(card.get_rect()), "enlarged community card stays within board")
	check(app.deck_touch.mouse_filter == Control.MOUSE_FILTER_IGNORE and app.pot_touch.mouse_filter == Control.MOUSE_FILTER_IGNORE, "camera deck and pot never intercept outer-screen touch")
	check(app.deck_cards[0].get_rect().intersects(profile.camera_bounds) and app.deck_cards[0].self_modulate.a == 0.0, "deal source stays at lens without exposed card corners")
	check(app.pot_display.get_rect().intersects(profile.camera_bounds) and app.pot_display.self_modulate.a == 0.0, "pot destination stays at lens without chip art")
	check(app.pot_panel.position.distance_to(profile.pot_notch_rect.position) < 0.1 and app.pot_panel.size.distance_to(profile.pot_notch_rect.size) < 0.1 and app.pot_label.position == Vector2.ZERO and app.pot_label.size.distance_to(app.pot_panel.size) < 0.1, "numeric pot label fills the between-lens notch")
	check(app.pot_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER and app.mixflip_pot_title.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "pot title and amount are vertically centered in their frames")
	check(app.pot_label.text == "0" and app.mixflip_pot_title.text == "底池", "pot title and numeric amount are separate")
	var notch_before: Rect2 = app.pot_panel.get_rect()
	app.mixflip_decor.left_offset.x += 2
	app.mixflip_decor.right_offset.x += 2
	app._apply_mixflip_layout(profile)
	check(is_equal_approx(app.pot_panel.position.x, notch_before.position.x + 2) and is_equal_approx(app.mixflip_pot_title.get_rect().get_center().x, app.pot_panel.get_rect().get_center().x), "live camera adjustment moves both notch frames and their centered labels together")
	app.mixflip_decor.left_offset.x -= 2
	app.mixflip_decor.right_offset.x -= 2
	app._apply_mixflip_layout(profile)
	check(app.mixflip_pot_title.position.distance_to(profile.pot_title_rect.position) < 0.1 and app.mixflip_pot_title.size.distance_to(profile.pot_title_rect.size) < 0.1 and app.pot_panel.self_modulate.a == 0.0, "pot title uses upper notch and old rectangular frame is hidden")
	check(app.mixflip_decor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "camera decoration cannot intercept touch")
	for amount in [0, 10, 100, 1000, 10000, 100000, 6000000]:
		app.pot_label.text = app._pot_caption(amount)
		var font: Font = app.pot_label.get_theme_font("font")
		var digit_width := font.get_string_size(app.pot_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, app.pot_label.get_theme_font_size("font_size")).x
		check(app.pot_label.text == str(amount) and digit_width <= app.pot_label.size.x - 12.0, "one through seven digit pot amounts fit without ellipsis")
	app.table.hide()
	app._apply_mixflip_layout(profile)
	check(not app.mixflip_decor.show_notches, "home hides both empty pot notch frames")
	for button in [app.hands_button, app.settings_button]:
		check(_inside(profile.aux_rect, button) and not button.get_rect().intersects(app.name_edit.get_rect()), "home utilities stay upper-left and do not cover setup fields")
	app.table.show()
	app._apply_mixflip_layout(profile)
	check(app.mixflip_decor.show_notches, "returning to table restores notch frames")
	app._show_settings()
	await process_frame
	_check_modal_below_camera("settings modal", primary)
	app._close_modal()
	await process_frame
	app._show_deck_gallery()
	await process_frame
	_check_modal_below_camera("deck gallery", primary)
	app._close_modal()
	await process_frame
	app._show_about()
	await process_frame
	var migrating_modal: Control = app.modal
	_check_modal_below_camera("about view", primary)
	app._set_mixflip_test_geometry(Vector2i(1392, 810), Vector2i(1392, 1208))
	await process_frame
	check(app.modal == migrating_modal and app.modal.position.y == 0.0, "open fullscreen modal migrates into folded basic region")
	app._set_mixflip_test_geometry(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)])
	await process_frame
	check(app.modal == migrating_modal, "open fullscreen modal survives unfold resize")
	_check_modal_below_camera("about view after unfold", app.mixflip_outer_profile.primary_rect)
	app._close_modal()
	await process_frame
	app._show_tutorial()
	await process_frame
	_check_modal_below_camera("tutorial", app.mixflip_outer_profile.primary_rect)
	app._close_modal()
	await process_frame
	for count in [4, 6]:
		app._show_showdown(_showdown_state(count))
		await process_frame
		_check_modal_below_camera("%d-player settlement" % count, app.mixflip_outer_profile.primary_rect)
		var settlement_panel := app.modal.get_node("SettlementPanel") as Control
		check(settlement_panel.position.y >= app.mixflip_outer_profile.primary_rect.position.y and settlement_panel.get_node("SettlementFooter").position.y + settlement_panel.position.y < app.canvas.size.y, "%d-player settlement footer stays reachable" % count)
		app._close_modal()
		await process_frame
	var dealer_role: Array[String] = ["D"]
	app.seats[0].badge.roles = dealer_role
	app.seats[0].badge.show()
	app._apply_mixflip_layout(profile)
	var badged_names := 0
	for slot in app.seats:
		if slot.panel.visible and slot.badge.visible:
			badged_names += 1
			check(not slot.name.get_rect().intersects(slot.badge.get_rect()), "long seat name reserves the role-badge area")
			check(slot.name.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "long seat name trims instead of entering badge")
	check(badged_names > 0, "fixture includes at least one role badge")
	app._set_mixflip_test_geometry(Vector2i(1392, 810), Vector2i(1392, 1208))
	await process_frame
	check(app.mixflip_outer_profile.mode == "basic_landscape", "non-fullscreen outer window keeps the same fixed landscape composition")
	check(app.amount_input.size.y == 104.0 and app.fold_button.size.y == 170.0 and app.action_label.position.x == 716.0, "basic outer profile retains its existing action layout")
	check(app.amount_input.get("outer_layout") == false, "basic slider restores standard internals")
	check(app.deck_touch.mouse_filter != Control.MOUSE_FILTER_IGNORE and app.pot_touch.mouse_filter != Control.MOUSE_FILTER_IGNORE, "basic region restores existing table-prop touch")
	app._clear_mixflip_test_geometry()
	await process_frame
	check(app.hand_label.position.x < 350.0 and app.hand_label.position.y == normal_hand_rect.position.y and app.hand_label.size.y == normal_hand_rect.size.y, "normal hand geometry leaves outer-screen coordinates")
	check(app.room_info.position.x < 540.0 and app.room_info.size.x > 500.0 and app.room_info.position.y == normal_room_rect.position.y, "normal room geometry regains the standard header width")
	check(app.name_edit.get_theme_font_size("font_size") == 30, "name field restores its normal inner-screen font size")
	check(app.action_label.position.x == 742.0 and app.action_label.size.x == 650.0 and app.amount_input.position.x == 740.0 and app.amount_input.size == Vector2(648, 88), "inner-screen quote and slider return to original responsive geometry")
	app._set_mixflip_test_geometry(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)])
	var held_fold_rect: Rect2 = app.fold_button.get_rect()
	var deck_rest: Vector2 = app.deck_cards[2].position
	app._begin_hand()
	check(app.input_locked, "deal cut locks input before its first await")
	app._clear_mixflip_test_geometry()
	check(app.mixflip_outer_profile.mode == "full_top" and app.fold_button.get_rect() == held_fold_rect, "busy fold/resize retains outer geometry")
	await create_timer(0.14).timeout
	check(app.deck_cards[2].position.x > 600.0 and app.deck_cards[2].position != deck_rest, "camera deck cut animates relative to its outer rest position")
	var deadline := Time.get_ticks_msec() + 15000
	while (app.input_locked or app.presentation_busy or app._layout_pending) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	check(app.mixflip_outer_profile.is_empty() and app.canvas.size.x == 1440.0, "leaving outer display restores normal responsive profile")
	for card in app.board_cards:
		check(card.size.is_equal_approx(Vector2(116, 162)), "unfold restores actual public card size, not only card_scale")
		check(is_equal_approx(card.card_scale, 116.0 / 132.0), "unfold restores public card minimum scale")
	for index in range(4):
		check(not app.board_cards[index].get_rect().intersects(app.board_cards[index + 1].get_rect()), "unfolded public cards do not overlap")
	check(app.fold_button.size == Vector2(136, 96), "normal phone/tablet action geometry is restored")
	check(app.title_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "normal header alignment is restored")
	check(app.title_label.self_modulate.a == 1.0 and app.deck_cards[0].self_modulate.a == 1.0 and app.pot_display.self_modulate.a == 1.0 and app.pot_display.modulate.a == 1.0 and app.pot_panel.self_modulate.a == 1.0 and not app.mixflip_pot_title.visible, "normal title, deck, chips and pot frame are fully restored")
	check("\n" not in app.pot_label.text, "normal pot caption is refreshed out of compact outer format")
	app._set_mixflip_test_geometry(Vector2i(1392, 1208), Vector2i(1392, 1208), [Rect2i(664, 0, 728, 398)])
	app._leave_to_home()
	await process_frame
	check(app.home.visible and not app.table.visible, "real leave-table path returns home")
	check(not app.mixflip_decor.show_notches, "real leave-table path removes pot notch frames")
	check(app.title_label.self_modulate.a == 1.0 and _inside(app.mixflip_outer_profile.aux_rect, app.title_label), "outer homepage restores visible centered title above tools")
	for button in [app.hands_button, app.settings_button]:
		check(_inside(app.mixflip_outer_profile.aux_rect, button) and not button.get_rect().intersects(app.name_edit.get_rect()), "leave-table path restores upper-left home tools")
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("MIXFLIP_OUTER_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
