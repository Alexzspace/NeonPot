extends Control

@export var animate_on_start := false
var defer_home_entrance := false
var _entrance: Tween
var _entrance_poses: Array = []
var _entrance_pending := false
const TABLE_ENTRY_SECONDS := 1.85
var _table_entry: Tween
var _table_entry_poses: Array = []
var _table_entering := false
var _entered_room := ""
var _entry_latest: Dictionary = {}
var _deal_after_entry := false
var _modal_fade: Tween
var _prop_tweens: Dictionary = {}
var _deck_rest: Array = []
var home_cards: Array = []
var pot_touch: Control
var deck_touch: Control

const Card = preload("res://scripts/card_view.gd")
const Timing = preload("res://scripts/presentation_timing.gd")
const PropTouch = preload("res://scripts/table_prop_touch.gd")
const Wheel = preload("res://scripts/inertia_wheel.gd")
const ExactRaisePanel = preload("res://scripts/exact_raise_panel.gd")
const WinningHand = preload("res://scripts/winning_hand.gd")
var frame_limit := 60
var _home_title_label: Label
var _home_company_label: Label
var _home_return_queued := false
const DeckThemes = preload("res://scripts/card_themes.gd")
const DeckGallery = preload("res://scripts/deck_gallery.gd")
const DeckWorkshop = preload("res://scripts/deck_workshop.gd")
const MusicLibrary = preload("res://scripts/music_library_view.gd")
const AboutView = preload("res://scripts/about_view.gd")
var preferred_deck_theme := 3
var settings_path := "user://settings.cfg"
var deck_gallery: Control
const PublicCard = preload("res://scripts/public_card.gd")
const Session = preload("res://scripts/table_session.gd")
const Chips = preload("res://scripts/chip_display.gd")
const Feedback = preload("res://scripts/feedback.gd")
const ChipHoldButton = preload("res://scripts/chip_hold_button.gd")
const ManualChipPanel = preload("res://scripts/manual_chip_panel.gd")
const BetSizing = preload("res://scripts/bet_sizing.gd")
const ChipInventory = preload("res://scripts/chip_inventory.gd")
var manual_panel: Control
var _manual_context := ""
var _manual_exchange_pending := false
var _manual_window_size := Vector2.ZERO
var _manual_flight_origin := Vector2.ZERO
var _manual_flight_context := ""
var _hold_haptic_step := -1
var _displayed_pot_chips: Dictionary = {}
var _runout_pending := false
var _stable_layout_frames := 0
const TouchSlider = preload("res://scripts/touch_slider.gd")
const MarqueeLabel = preload("res://scripts/marquee_label.gd")
const Music = preload("res://scripts/music_player.gd")
const PixelPlayer = preload("res://scripts/pixel_player.gd")
const NightLines = preload("res://scripts/night_lines.gd")
const Responsive = preload("res://scripts/responsive_layout.gd")
const MixFlipOuterLayout = preload("res://scripts/mixflip_outer_layout.gd")
const MixFlipOuterDecor = preload("res://scripts/mixflip_outer_decor.gd")
const SeatBadge = preload("res://scripts/seat_badge.gd")
const Discovery = preload("res://scripts/lan_discovery.gd")
const LanLobby = preload("res://scripts/lan_lobby.gd")
const ShowdownBoard = preload("res://scripts/showdown_board.gd")
const Tutorial = preload("res://scripts/tutorial_view.gd")
const ChipGestures = preload("res://scripts/chip_gestures.gd")
const AiChipIdle = preload("res://scripts/ai_chip_idle.gd")
var ai_chip_idle = AiChipIdle.new()
const INK := Color("f4e9e1")
const MUTED := Color("a3a5bd")
const GOLD := Color("d9aad5")
const PANEL := Color("202036")
const CORAL := Color("965273")

var language := "en"
var _night_lines = NightLines.new()
var _home_line := -1
var _turn_line := -1
var _turn_line_key := ""
var _layout_pending := false
var ai_slider: Range
var session: Node
var feedback: Node
var canvas: Control
var home: Control
var table: Control
var modal: Control
var toast_label: Label
var own_cards: Array = []
var board_cards: Array = []
var _board_contact_offsets: Dictionary = {}
var _board_contact_times: Dictionary = {}
var deck_cards: Array = []
var seats: Array = []
var chip_display: Control
var pot_label: Label
var phase_label: Label
var title_label: Label
var hands_button: Button
var settings_button: Button
var mixflip_decor: Control
var mixflip_pot_title: Label
var _mixflip_previous_orientation := -1
var home_form_panel: Panel
var home_name_label: Label
var home_stack_label: Label
var home_wifi_label: Label
var home_host_button: Button
var home_search_button: Button
var home_solo_button: Button
var table_back_panel: Panel
var table_inner_panel: Panel
var own_panel: Panel
var pot_panel: Panel
var hand_label: Label
var balance_label: Label
var manual_bet_hint: Label
var action_label: Label
var fold_button: Button
var call_button: Button
var raise_button: Button
var allin_button: Button
var deal_button: Button
var showdown_button: Button
var amount_label: Label
var amount_input: Range
var music: Node
var music_title: Control
var music_pause_button: Button
var _background_material: ShaderMaterial
var sfx_slider: Range
var music_slider: Range
var haptic_slider: Range
var chip_touch: Button
var _fidget_nodes: Dictionary = {}
var _last_raise_tick := -1000
var room_info: Label
var name_edit: LineEdit
var discovery: Node
var lobby: Control
var room_list: VBoxContainer
var room_search_status: Label
var _search_modal: Control
var _joining := false
var _join_message: Label
var _join_title: Label
var _join_return: Button
var stack_input: Range
var player_count: Range
var home_chip_display: Control
var home_chip_touch: Button
var _home_gesture_rng := RandomNumberGenerator.new()
var _home_gesture_at := -3000
var _home_last_style := -1
var _solo_delay := 0.0
var _solo_turn_key := ""
var _application_active := true
var _exit_pending := false
var shown_state: Dictionary = {}
var previous_hand := -1
var previous_board := 0
var previous_phase := ""
var transition_id := 0
var input_locked := false
var pot_display: Control
var flight_layer: Control
var preview_profile := ""
var safe_rect := Rect2()
var mixflip_outer_profile: Dictionary = {}
var _mixflip_test_window := Vector2i.ZERO
var _mixflip_test_screen := Vector2i.ZERO
var _mixflip_test_cutouts: Array = []
var _stable_layout_serial := 0
var presentation_busy := false
var presentation_events: Array = []
var _presentation_queue: Array = []
var _presentation_token := 0
var _presented_revision := -1
var _displayed_pot := 0
var _settlement_key := ""
var _settling_key := ""
var _unlanded_refunds: Dictionary = {}
var _paid_awards: Dictionary = {}
var _deferred_rebuild := false
var _settings_after_rebuild := false
var _flight_tweens: Array[Tween] = []
const BASE_SIZE := Vector2(1440, 660)
const PHONE_SIZES := {"iphone": Vector2i(2622, 1206), "android": Vector2i(2400, 1080), "android195": Vector2i(2340, 1080), "kpad": Vector2i(2560, 1600), "sqrt2": Vector2i(2160, 1527)}
var _font: FontFile

func _ready() -> void:
	add_child(ai_chip_idle)
	get_tree().quit_on_go_back = false
	get_window().go_back_requested.connect(_handle_back)
	_font = load("res://assets/fonts/fusion-pixel.ttf")
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font.multichannel_signed_distance_field = false
	var palette := Theme.new()
	palette.default_font = _font
	palette.default_font_size = 24
	theme = palette
	feedback = Feedback.new()
	feedback.name = "Feedback"
	add_child(feedback)
	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.chip_gesture.connect(_on_chip_gesture)
	session.board_gesture.connect(_on_board_gesture)
	session.table_prop_gesture.connect(_on_table_prop_gesture)
	discovery = Discovery.new()
	add_child(discovery)
	discovery.rooms_changed.connect(_rooms_changed)
	discovery.status_changed.connect(_status)
	music = Music.new()
	music.name = "Music"
	_load_settings()
	Engine.max_fps = frame_limit
	_set_visible_deck(preferred_deck_theme)
	music.language = language
	add_child(music)
	music.changed.connect(_refresh_music_controls)
	session.state_changed.connect(_on_state)
	session.status_changed.connect(_status)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/felt.gdshader")
	_background_material = material
	bg.material = material
	add_child(bg)
	canvas = Control.new()
	canvas.size = BASE_SIZE
	add_child(canvas)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phone="):
			_set_preview_profile(arg.trim_prefix("--phone="), true)
	_build_ui()
	resized.connect(_queue_stable_layout)
	_layout()
	if animate_on_start and not "--demo" in OS.get_cmdline_user_args():
		_prepare_home_entrance()
		if not defer_home_entrance: play_home_entrance.call_deferred()
	if "--demo" in OS.get_cmdline_user_args():
		_start_solo()
		session.begin_hand()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func words(zh: String, en: String) -> String:
	return zh if language == "zh" else en

func _home_wheel(initial: int, low: int, high: int, increment: int, rect: Rect2, strong: bool) -> Range:
	var wheel := Wheel.new()
	wheel.position = rect.position
	wheel.size = rect.size
	wheel.min_value = low
	wheel.max_value = high
	wheel.step = increment
	wheel.value = initial
	wheel.strong_snap = strong
	home.add_child(wheel)
	wheel.user_changed.connect(func(_value: float): feedback.play("touch"))
	return wheel

func _return_home_if_uncovered() -> void:
	_home_return_queued = false
	if not is_instance_valid(home) or not home.is_visible_in_tree() or is_instance_valid(modal) or not shown_state.is_empty(): return
	_home_line = _night_lines.next_index("home")
	_home_title_label.text = _night_lines.line("home", _home_line, language)
	_home_company_label.text = _night_lines.line("company", _night_lines.next_index("company"), language)
	_prepare_home_entrance()
	play_home_entrance()

func _prepare_home_entrance() -> void:
	_cancel_home_entrance()
	_entrance_pending = true
	var nodes: Array = home.get_children()
	nodes.append(title_label)
	for node in nodes:
		if not node is Control or node == home_chip_touch: continue
		var rest: Vector2 = node.position
		_entrance_poses.append({"node": node, "position": rest, "rotation": node.rotation, "modulate": node.modulate})
		node.modulate.a = 0.0
		if node in home_cards:
			node.position = Vector2(179, 340)
			node.rotation = 0.0
		elif node == title_label:
			node.position.y -= 22
		elif rest.y > 470:
			node.position.y += 30
		else:
			node.position.x += -58 if rest.x < 720 else 58
	home_chip_touch.disabled = true

func play_home_entrance() -> void:
	if not _entrance_pending: return
	_entrance_pending = false
	_entrance = create_tween().set_parallel(true)
	for item in _entrance_poses:
		var node: Control = item.node
		var delay := 0.08 + clampf(item.position.y / 1800.0, 0.0, 0.30)
		_entrance.tween_property(node, "position", item.position, 0.72).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_entrance.tween_property(node, "rotation", item.rotation, 0.72).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_entrance.tween_property(node, "modulate", item.modulate, 0.48).set_delay(delay)
	_entrance.tween_callback(func(): home_chip_display.intro_stack(0.76)).set_delay(0.27)
	_entrance.chain().tween_callback(_cancel_home_entrance)

func _cancel_home_entrance() -> void:
	if _entrance and _entrance.is_valid(): _entrance.kill()
	_entrance = null
	_entrance_pending = false
	for item in _entrance_poses:
		if is_instance_valid(item.node):
			item.node.position = item.position
			item.node.rotation = item.rotation
			item.node.modulate = item.modulate
	_entrance_poses.clear()
	if is_instance_valid(home_chip_display): home_chip_display.cancel_intro()
	if is_instance_valid(home_chip_touch): home_chip_touch.disabled = false

func _play_table_entry() -> void:
	# Real-time seating ceremony stays longer than home even at 2x dealing speed.
	_table_entry = create_tween().set_parallel(true)
	for node in table.get_children():
		if not node is Control or not node.visible or node in [flight_layer, chip_touch, deck_touch, pot_touch]: continue
		var rest: Vector2 = node.position
		_table_entry_poses.append({"node": node, "position": rest, "rotation": node.rotation, "modulate": node.modulate})
		if node in own_cards:
			node.modulate.a = 0.0
			continue # Private cards are dealt only after the table has settled.
		var delay := 0.05
		if rest.y < 185: delay = 0.12 + clampf(rest.x / canvas.size.x, 0.0, 1.0) * 0.20
		elif rest.y > 405: delay = 0.32
		node.modulate.a = 0.0
		_table_entry.tween_property(node, "modulate:a", _table_entry_poses.back().modulate.a, 0.65).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if node in deck_cards:
			var index: int = deck_cards.find(node)
			var offset := Vector2(-1.0 if index < 2 else 1.0, -0.20) * (24.0 + index * 4.0)
			_table_entry.tween_property(node, "position", rest + offset, 0.28).set_delay(0.60).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_table_entry.tween_property(node, "rotation", (-0.07 if index < 2 else 0.07), 0.28).set_delay(0.60)
			_table_entry.tween_property(node, "position", rest, 0.48).set_delay(0.91 + index * 0.035).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_table_entry.tween_property(node, "rotation", node.rotation, 0.48).set_delay(0.91 + index * 0.035)
		elif node != chip_display:
			node.position.y += -14.0 if rest.y < 185 else 26.0
			_table_entry.tween_property(node, "position", rest, 1.02).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	for card in own_cards: card.interactive = false
	chip_display.table_entry_stack(1.35)
	_table_entry.tween_callback(func():
		if _application_active and not is_instance_valid(modal): feedback.play("fold", true)).set_delay(0.60)
	_table_entry.tween_callback(func():
		if _application_active and not is_instance_valid(modal): feedback.play("release", true)).set_delay(1.05)
	_table_entry.tween_callback(_finish_table_entry).set_delay(TABLE_ENTRY_SECONDS)
	_update_presentation_controls()

func _cancel_table_entry() -> void:
	if _table_entry and _table_entry.is_valid(): _table_entry.kill()
	_table_entry = null
	for item in _table_entry_poses:
		if is_instance_valid(item.node):
			item.node.position = item.position
			item.node.rotation = item.rotation
			item.node.modulate = item.modulate
	_table_entry_poses.clear()
	if is_instance_valid(chip_display): chip_display.cancel_intro()
	_table_entering = false
	_entry_latest = {}
	_deal_after_entry = false
	input_locked = false

func _finish_table_entry() -> void:
	var latest := _entry_latest if not _entry_latest.is_empty() else shown_state
	var deal_after := _deal_after_entry
	_cancel_table_entry()
	_render_state(latest, true)
	if shown_state.get("phase", "lobby") != "lobby":
		for i in range(own_cards.size()):
			if own_cards[i].visible: own_cards[i].deal(i * 0.12)
	if _deferred_rebuild: _finish_deferred_rebuild.call_deferred()
	_deal_after_entry = deal_after
	if not _application_active or is_instance_valid(modal): _hide_private_cards()

func _prop_button(at: Vector2, extent: Vector2, kind: String) -> Control:
	var button := PropTouch.new()
	button.position = at
	button.size = extent
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_request_table_prop.bind(kind))
	table.add_child(button)
	return button

func _request_table_prop(kind: String) -> void:
	if not _application_active or modal != null or input_locked or presentation_busy: return
	if not table.visible: return
	session.request_table_prop_gesture(kind)

func _on_table_prop_gesture(seat: int, _sequence: int, kind: String) -> void:
	if not _application_active or modal != null or input_locked or presentation_busy or not table.visible: return
	_cancel_table_prop(kind)
	var shared := seat != int(shown_state.get("you", -1))
	feedback.play_table_prop_contact(kind, shared)
	var tween := create_tween()
	_prop_tweens[kind] = tween
	if kind == "pot":
		pot_display.nudge()
		tween.tween_interval(0.10)
	elif kind == "deck":
		_deck_rest.clear()
		for card in deck_cards:
			_deck_rest.append({"node": card, "position": card.position, "rotation": card.rotation})
		tween.set_parallel(true)
		for i in range(_deck_rest.size()):
			var item: Dictionary = _deck_rest[i]
			var lift := Vector2((i - 1.5) * 7, -10 - i * 2)
			tween.tween_property(item.node, "position", item.position + lift, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(item.node, "rotation", (i - 1.5) * 0.025, 0.16)
		tween.chain()
		for item in _deck_rest:
			tween.tween_property(item.node, "position", item.position, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(item.node, "rotation", item.rotation, 0.32)

func _cancel_table_props() -> void:
	_cancel_table_prop("pot")
	_cancel_table_prop("deck")

func _cancel_table_prop(kind: String) -> void:
	var tween: Tween = _prop_tweens.get(kind)
	if tween and tween.is_valid(): tween.kill()
	_prop_tweens.erase(kind)
	if kind == "deck":
		for item in _deck_rest:
			if is_instance_valid(item.node):
				item.node.position = item.position
				item.node.rotation = item.rotation
		_deck_rest.clear()
	elif kind == "pot" and is_instance_valid(pot_display):
		pot_display.cancel_nudge()

func _layout() -> void:
	if is_instance_valid(manual_panel) and _manual_window_size != get_viewport_rect().size: _close_manual_chips()
	if _table_entering and _table_entry: _finish_table_entry()
	_cancel_table_props()
	if _entrance and _entrance.is_valid(): _cancel_home_entrance()
	if not is_instance_valid(canvas):
		return
	var screen := _mixflip_test_screen if _mixflip_test_screen != Vector2i.ZERO else DisplayServer.screen_get_size()
	var window_native := _mixflip_test_window if _mixflip_test_window != Vector2i.ZERO else DisplayServer.window_get_size()
	var cutouts: Array = _mixflip_test_cutouts if _mixflip_test_window != Vector2i.ZERO else DisplayServer.get_display_cutouts()
	var next_mixflip_profile := MixFlipOuterLayout.profile(window_native, screen, cutouts, _mixflip_test_window != Vector2i.ZERO)
	if OS.has_feature("android") and _mixflip_test_window == Vector2i.ZERO:
		if not next_mixflip_profile.is_empty():
			if _mixflip_previous_orientation < 0:
				_mixflip_previous_orientation = DisplayServer.screen_get_orientation()
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
			# HyperOS rewrites LANDSCAPE to USER_LANDSCAPE when auto-rotate is on.
			# LOCKED preserves the calibrated outer-display rotation instead.
			if Engine.has_singleton("AndroidRuntime"):
				var activity = Engine.get_singleton("AndroidRuntime").getActivity()
				if activity != null:
					activity.setRequestedOrientation(14) # ActivityInfo.SCREEN_ORIENTATION_LOCKED
		elif _mixflip_previous_orientation >= 0:
			DisplayServer.screen_set_orientation(_mixflip_previous_orientation)
			_mixflip_previous_orientation = -1
	if presentation_busy or input_locked:
		# A fold/resize may arrive while cards or chips are moving. Keep the
		# current coordinate system until _process observes an idle queue.
		_layout_pending = true
		var held_factor := minf(size.x / canvas.size.x, size.y / canvas.size.y)
		canvas.scale = Vector2.ONE * held_factor
		canvas.position = (size - canvas.size * held_factor) * 0.5
		_layout_active_modal()
		return
	_restore_mixflip_layout()
	mixflip_outer_profile = next_mixflip_profile
	if not mixflip_outer_profile.is_empty():
		safe_rect = Rect2(Vector2.ZERO, size)
		var logical_size: Vector2 = mixflip_outer_profile.logical_size
		canvas.size = logical_size
		if is_instance_valid(table): Responsive.apply(self, logical_size.y)
		if is_instance_valid(lobby): lobby.layout_height(logical_size.y)
		_layout_pending = false
		var outer_factor := minf(size.x / canvas.size.x, size.y / canvas.size.y)
		canvas.scale = Vector2.ONE * outer_factor
		canvas.position = (size - canvas.size * outer_factor) * 0.5
		_apply_mixflip_layout(mixflip_outer_profile)
		_layout_active_modal()
		return
	safe_rect = Rect2(Vector2.ZERO, size)
	if PHONE_SIZES.has(preview_profile) and not OS.has_feature("mobile"):
		var native: Vector2 = PHONE_SIZES[preview_profile]
		var side := 72.0
		var bottom := 36.0
		var inset := Vector2(side / native.x * size.x, bottom / native.y * size.y)
		safe_rect = Rect2(Vector2(inset.x, 0), Vector2(size.x - inset.x * 2, size.y - inset.y))
	elif OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		safe_rect = preload("res://scripts/safe_area.gd").content_rect(size, screen, safe, cutouts)
	var available_height := maxf(660.0, 1440.0 * safe_rect.size.y / maxf(1.0, safe_rect.size.x))
	if presentation_busy or input_locked:
		_layout_pending = true
	else:
		canvas.size = Vector2(1440, available_height)
		if is_instance_valid(table): Responsive.apply(self, available_height)
		if is_instance_valid(lobby): lobby.layout_height(available_height)
		_layout_pending = false
	var factor := minf(safe_rect.size.x / canvas.size.x, safe_rect.size.y / canvas.size.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = safe_rect.position + (safe_rect.size - canvas.size * factor) * 0.5
	if is_instance_valid(hand_label) and is_instance_valid(room_info):
		_layout_table_heading()
	if is_instance_valid(pot_label):
		var hand_total: bool = shown_state.get("phase", "") == "showdown" and not presentation_busy
		pot_label.text = _pot_caption(int(shown_state.get("pot", 0)) if hand_total else _displayed_pot, hand_total)
	_layout_pot_inventory()
	_layout_active_modal()

func _layout_pot_inventory() -> void:
	if not is_instance_valid(pot_display) or not is_instance_valid(pot_panel): return
	if mixflip_outer_profile.get("full", false): return
	pot_display.position = pot_panel.position + Vector2(8, 8)
	pot_display.size = (pot_panel.size - Vector2(16, 16)).max(Vector2.ONE)
	if is_instance_valid(pot_touch):
		pot_touch.position = pot_display.position
		pot_touch.size = pot_display.size

func _queue_stable_layout() -> void:
	_stable_layout_serial += 1
	_stable_layout_frames = 2

func _set_mixflip_test_geometry(window_native: Vector2i, screen_native: Vector2i, cutouts: Array = []) -> void:
	_mixflip_test_window = window_native
	_mixflip_test_screen = screen_native
	_mixflip_test_cutouts = cutouts.duplicate()
	_layout()

func _clear_mixflip_test_geometry() -> void:
	_mixflip_test_window = Vector2i.ZERO
	_mixflip_test_screen = Vector2i.ZERO
	_mixflip_test_cutouts.clear()
	_layout()

func _mixflip_track(control: Control, prefer_layout_base: bool = true) -> void:
	if not is_instance_valid(control) or control.has_meta("mixflip_base_rect"):
		return
	control.set_meta("mixflip_base_rect", control.get_meta("layout_base") if prefer_layout_base and control.has_meta("layout_base") else Rect2(control.position, control.size))
	control.set_meta("mixflip_base_rotation", control.rotation)
	control.set_meta("mixflip_base_mouse_filter", control.mouse_filter)
	control.set_meta("mixflip_base_self_modulate", control.self_modulate)
	control.set_meta("mixflip_base_modulate", control.modulate)
	if control is Label or control is Button or control is LineEdit:
		control.set_meta("mixflip_base_font", control.get_theme_font_size("font_size"))
	if control is Label:
		control.set_meta("mixflip_base_alignment", control.horizontal_alignment)
		control.set_meta("mixflip_base_vertical_alignment", control.vertical_alignment)
	if control is Card:
		control.set_meta("mixflip_base_card_scale", control.get("card_scale"))

func _mixflip_rect(control: Control, rect: Rect2) -> void:
	if not is_instance_valid(control): return
	_mixflip_track(control)
	control.position = rect.position
	control.size = rect.size

func _mixflip_font(control: Control, font_size: int) -> void:
	if not is_instance_valid(control): return
	_mixflip_track(control)
	control.add_theme_font_size_override("font_size", font_size)

func _mixflip_card(control: Control, rect: Rect2) -> void:
	_mixflip_track(control)
	control.card_scale = rect.size.x / 132.0
	_mixflip_rect(control, rect)

func _restore_mixflip_layout() -> void:
	if is_instance_valid(amount_input): amount_input.set("outer_layout", false)
	if not is_instance_valid(canvas): return
	var nodes: Array[Node] = [canvas]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		nodes.append_array(node.get_children())
		if not node is Control or not node.has_meta("mixflip_base_rect"):
			continue
		var control := node as Control
		var base: Rect2 = control.get_meta("mixflip_base_rect")
		# Lower the card minimum before restoring its smaller inner-screen rect.
		if control.has_meta("mixflip_base_card_scale"):
			control.set("card_scale", float(control.get_meta("mixflip_base_card_scale")))
		control.position = base.position
		control.size = base.size
		control.rotation = float(control.get_meta("mixflip_base_rotation"))
		control.mouse_filter = int(control.get_meta("mixflip_base_mouse_filter"))
		control.self_modulate = control.get_meta("mixflip_base_self_modulate")
		control.modulate = control.get_meta("mixflip_base_modulate")
		if control.has_meta("mixflip_base_font"):
			control.add_theme_font_size_override("font_size", int(control.get_meta("mixflip_base_font")))
		if control is Label and control.has_meta("mixflip_base_alignment"):
			control.horizontal_alignment = int(control.get_meta("mixflip_base_alignment")) as HorizontalAlignment
			control.vertical_alignment = int(control.get_meta("mixflip_base_vertical_alignment")) as VerticalAlignment
	if is_instance_valid(mixflip_decor):
		mixflip_decor.hide()
	if is_instance_valid(mixflip_pot_title):
		mixflip_pot_title.hide()

func _apply_mixflip_layout(profile: Dictionary) -> void:
	if profile.is_empty() or not is_instance_valid(table): return
	var logical_size: Vector2 = profile.logical_size
	var play: Rect2 = profile.interactive_rect
	_mixflip_rect(mixflip_decor, Rect2(Vector2.ZERO, logical_size))
	mixflip_decor.configure(profile.camera_zone, profile.camera_bounds, profile.camera_deck_center, profile.camera_pot_center)
	if profile.full:
		profile.pot_notch_rect = mixflip_decor.notch_rect(true)
		profile.pot_title_rect = mixflip_decor.notch_rect(false)
	mixflip_decor.show_notches = table.visible
	mixflip_decor.queue_redraw()
	_layout_mixflip_header(profile, play)
	_layout_mixflip_home(play)
	_layout_mixflip_table_landscape(profile, play, logical_size)
	_layout_pot_inventory()
	if profile.full:
		var hand_total: bool = shown_state.get("phase", "") == "showdown" and not presentation_busy
		pot_label.text = _pot_caption(int(shown_state.get("pot", 0)) if hand_total else _displayed_pot, hand_total)
	_mixflip_rect(flight_layer, Rect2(Vector2.ZERO, logical_size))
	_mixflip_rect(toast_label, Rect2(24, logical_size.y - 50, logical_size.x - 48, 44))
	_mixflip_font(toast_label, 36)

func _layout_mixflip_header(profile: Dictionary, play: Rect2) -> void:
	_mixflip_track(title_label)
	var title_rect := Rect2(play.position + Vector2(18, 4), Vector2(350, 82))
	if profile.full and profile.landscape:
		title_label.self_modulate.a = 0.0
		_mixflip_rect(hands_button, Rect2(1232, play.position.y + 12, 184, 174))
		_mixflip_rect(settings_button, Rect2(1232, play.position.y + 202, 184, 174))
		if not table.visible:
			var aux: Rect2 = profile.aux_rect
			title_label.self_modulate.a = 1.0
			title_rect = Rect2(aux.position.x + 12, aux.position.y + 12, aux.size.x - 24, 114)
			title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_mixflip_rect(hands_button, Rect2(aux.position.x + 12, aux.position.y + 158, 300, 170))
			_mixflip_rect(settings_button, Rect2(aux.position.x + 328, aux.position.y + 158, aux.size.x - 340, 170))
	_mixflip_rect(title_label, title_rect)
	_mixflip_font(title_label, 52 if profile.full else 46)
	if profile.landscape and not profile.full:
		_mixflip_rect(hands_button, Rect2(play.end.x - 410, play.position.y + 4, 182, 82))
		_mixflip_rect(settings_button, Rect2(play.end.x - 214, play.position.y + 4, 196, 82))
	_mixflip_font(hands_button, 40)
	_mixflip_font(settings_button, 40)

func _layout_mixflip_home(play: Rect2) -> void:
	var vertical_shift := play.position.y
	var horizontal_shift := play.position.x
	for child in home.get_children():
		if not child is Control: continue
		var control := child as Control
		_mixflip_track(control)
		var base: Rect2 = control.get_meta("mixflip_base_rect")
		control.position = base.position + Vector2(horizontal_shift, vertical_shift)
	if mixflip_outer_profile.get("full", false):
		_mixflip_rect(home_form_panel, Rect2(735, play.position.y + 12, 677, play.size.y - 24))
		_mixflip_rect(home_name_label, Rect2(764, play.position.y + 28, 310, 40))
		_mixflip_rect(home_stack_label, Rect2(1126, play.position.y + 28, 264, 40))
		_mixflip_rect(name_edit, Rect2(764, play.position.y + 74, 335, 162))
		_mixflip_rect(stack_input, Rect2(1125, play.position.y + 74, 256, 162))
		_mixflip_rect(home_host_button, Rect2(764, play.position.y + 246, 617, 162))
		_mixflip_rect(home_search_button, Rect2(764, play.position.y + 418, 617, 162))
		_mixflip_rect(home_wifi_label, Rect2(765, play.position.y + 582, 620, 46))
		_mixflip_rect(home_solo_button, Rect2(764, play.position.y + 642, 440, 170))
		_mixflip_rect(player_count, Rect2(1218, play.position.y + 642, 162, 170))
		_mixflip_font(home_name_label, 36)
		_mixflip_font(home_stack_label, 36)
		_mixflip_font(home_wifi_label, 36)
		_mixflip_font(name_edit, 40)
		for button in [home_host_button, home_search_button, home_solo_button]: _mixflip_font(button, 42)
	if play.size.x < 1000.0:
		# The narrow fallback is intentionally scroll-free: stack setup and the
		# three entry actions remain in the camera-clear application column.
		var sx := play.size.x / 1440.0
		for child in home.get_children():
			if not child is Control: continue
			var control := child as Control
			var base: Rect2 = control.get_meta("mixflip_base_rect")
			control.position.x = play.position.x + base.position.x * sx
			control.size.x = base.size.x * sx

func _layout_mixflip_table_landscape(profile: Dictionary, play: Rect2, logical_size: Vector2) -> void:
	var y := play.position.y
	var h := play.size.y
	_mixflip_rect(table, Rect2(Vector2.ZERO, logical_size))
	_mixflip_rect(table_back_panel, Rect2(20, y + 188, 1400, 286))
	_mixflip_rect(table_inner_panel, Rect2(31, y + 199, 1378, 264))
	_mixflip_rect(phase_label, Rect2(42, y + 198, 250, 48))
	_mixflip_font(phase_label, 36)
	_mixflip_rect(pot_panel, Rect2(1092, y + 204, 308, 252))
	_mixflip_rect(pot_label, Rect2(14, 4, 280, 54))
	_mixflip_font(pot_label, 34)
	_mixflip_rect(pot_display, Rect2(1094, y + 270, 304, 180))
	_mixflip_rect(pot_touch, Rect2(1094, y + 270, 304, 180))
	for i in range(board_cards.size()):
		_mixflip_card(board_cards[i], Rect2(300 + i * 162, y + 232, 146, 204))
	for i in range(deck_cards.size()):
		_mixflip_card(deck_cards[i], Rect2(76 + i * 4, y + 300 - i * 4, 88, 123))
	_mixflip_rect(deck_touch, Rect2(58, y + 278, 132, 162))
	if profile.full:
		# Spend the space reclaimed by the upper-left seats on larger board cards.
		_mixflip_rect(table_back_panel, Rect2(20, y + 12, 1194, 364))
		_mixflip_rect(table_inner_panel, Rect2(31, y + 23, 1172, 342))
		_mixflip_rect(phase_label, Rect2(42, y + 24, 360, 46))
		for i in range(board_cards.size()):
			_mixflip_card(board_cards[i], Rect2(62 + i * 226, y + 76, 204, 285))
		var deck_center: Vector2 = profile.camera_deck_center
		var pot_center: Vector2 = profile.camera_pot_center
		for i in range(deck_cards.size()):
			_mixflip_card(deck_cards[i], Rect2(deck_center + Vector2(-80 + i * 7, -72 - i * 6), Vector2(104, 145)))
			deck_cards[i].self_modulate.a = 0.0
		_mixflip_rect(pot_display, Rect2(pot_center - Vector2(158, 118), Vector2(316, 236)))
		pot_display.self_modulate.a = 0.0
		pot_display.modulate.a = 0.0
		_mixflip_rect(pot_panel, profile.pot_notch_rect)
		pot_panel.self_modulate.a = 0.0
		_mixflip_rect(pot_label, Rect2(Vector2.ZERO, profile.pot_notch_rect.size))
		pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_mixflip_font(pot_label, 40)
		if not is_instance_valid(mixflip_pot_title):
			mixflip_pot_title = _label(table, "", Rect2(), 36, GOLD)
			mixflip_pot_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mixflip_pot_title.text = words("底池", "POT")
		mixflip_pot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mixflip_pot_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_mixflip_rect(mixflip_pot_title, profile.pot_title_rect)
		mixflip_pot_title.show()
		pot_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var players: Array = shown_state.get("players", [])
	var count := clampi(players.size() if not players.is_empty() else 6, 2, 6)
	var seat_width := (1400.0 - 10.0 * (count - 1)) / count
	if profile.full:
		seat_width = (profile.aux_rect.size.x - 12.0) * 0.5
	for i in range(seats.size()):
		var slot: Dictionary = seats[i]
		_mixflip_rect(slot.panel, Rect2(20 + i * (seat_width + 10), y + 96, seat_width, 82))
		if profile.full:
			_mixflip_rect(slot.panel, Rect2(profile.aux_rect.position + Vector2((i % 2) * (seat_width + 12), 72 + (i / 2) * 100), Vector2(seat_width, 94)))
		_mixflip_rect(slot.name, Rect2(12, 1, seat_width - (132 if slot.badge.visible else 24), 41))
		_mixflip_rect(slot.stack, Rect2(12, 40, seat_width - 24, 38))
		_mixflip_font(slot.name, 36)
		_mixflip_font(slot.stack, 36)
		_mixflip_track(slot.badge)
		slot.badge.position.x = seat_width - 116
	_mixflip_card(own_cards[0], Rect2(24, y + h - 298, 160, 223))
	_mixflip_card(own_cards[1], Rect2(202, y + h - 298, 160, 223))
	var peek: Label = own_cards[0].get_parent().get_child(own_cards[1].get_index() + 1) as Label
	if is_instance_valid(peek):
		_mixflip_rect(peek, Rect2(24, y + h - 73, 340, 44))
		_mixflip_font(peek, 36)
	_mixflip_rect(own_panel, Rect2(386, y + h - 288, 300, 258))
	_mixflip_rect(balance_label, Rect2(402, y + h - 280, 270, 48))
	_mixflip_font(balance_label, 36)
	_mixflip_rect(manual_bet_hint, Rect2(386, y + h - 29, 300, 23))
	_mixflip_font(manual_bet_hint, 18)
	_mixflip_rect(chip_display, Rect2(386, y + h - 230, 300, 196))
	_mixflip_rect(chip_touch, Rect2(386, y + h - 230, 300, 196))
	_mixflip_rect(action_label, Rect2(716, y + h - 398, 700, 52))
	_mixflip_font(action_label, 36)
	_mixflip_rect(amount_input, Rect2(716, y + h - 340, 700, 104))
	var button_y := y + h - 232
	_mixflip_rect(fold_button, Rect2(716, button_y, 162, 170))
	_mixflip_rect(call_button, Rect2(890, button_y, 176, 170))
	_mixflip_rect(raise_button, Rect2(1078, button_y, 162, 170))
	_mixflip_rect(allin_button, Rect2(1252, button_y, 162, 170))
	for button in [fold_button, call_button, raise_button, allin_button]: _mixflip_font(button, 46)
	_mixflip_rect(deal_button, Rect2(716, button_y, 700, 170))
	_mixflip_rect(showdown_button, Rect2(716, y + h - 340, 700, 104))
	_mixflip_font(deal_button, 50)
	_mixflip_font(showdown_button, 46)
	if profile.full:
		_mixflip_rect(action_label, Rect2(24, y + h - 398, 660, 80))
		amount_input.set("outer_layout", true)
		_mixflip_rect(amount_input, Rect2(716, y + h - 430, 700, 164))
		for button in [fold_button, call_button, raise_button, allin_button, deal_button]:
			_mixflip_rect(button, Rect2(button.position.x, y + h - 256, button.size.x, 220))
		_mixflip_rect(showdown_button, Rect2(716, y + h - 430, 700, 164))
	_layout_table_heading()

func _set_preview_profile(profile: String, change_window: bool = true) -> void:
	preview_profile = profile if PHONE_SIZES.has(profile) else ""
	if change_window and PHONE_SIZES.has(profile) and not OS.has_feature("mobile"):
		get_window().size = PHONE_SIZES[profile] / 2
		get_window().title = words("霓虹夜河 · Neon Pot", "Neon Pot") + " · " + (profile if not profile.is_empty() else "Free resize")
	_layout()

func _box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	if border.a > 0:
		style.shadow_color = Color(border, 0.12)
		style.shadow_size = 6
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style

func _panel(parent: Node, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 8) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("panel", _box(color, border, radius))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 24, color: Color = INK, center: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, rect: Rect2, callback: Callable, color: Color = PANEL) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 30)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("73738e"))
	var normal := _box(color, color.lightened(0.2))
	normal.shadow_color = Color(0.02, 0.025, 0.025, 0.65)
	normal.shadow_size = 2
	normal.shadow_offset = Vector2(0, 5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.09), GOLD))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.2), GOLD))
	button.add_theme_stylebox_override("disabled", _box(Color("1b1a2a"), Color("373349")))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD))
	button.pressed.connect(func():
		feedback.play("touch")
		callback.call())
	parent.add_child(button)
	return button

func _edit(parent: Node, initial: String, rect: Rect2) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = initial
	edit.position = rect.position
	edit.size = rect.size
	edit.max_length = 48
	edit.add_theme_stylebox_override("normal", _box(Color("141421"), Color("56516d")))
	edit.add_theme_stylebox_override("focus", _box(Color("141421"), GOLD))
	edit.add_theme_color_override("font_color", INK)
	parent.add_child(edit)
	return edit

func _spin(parent: Node, value: int, low: int, high: int, rect: Rect2) -> SpinBox:
	var spin := SpinBox.new()
	spin.position = rect.position
	spin.size = rect.size
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	spin.add_theme_font_size_override("font_size", 30)
	spin.get_line_edit().add_theme_stylebox_override("normal", _box(Color("141421"), Color("56516d")))
	parent.add_child(spin)
	return spin

func _build_ui() -> void:
	_close_manual_chips()
	_cancel_home_entrance()
	if shown_state.is_empty(): _set_visible_deck(preferred_deck_theme)
	music.language = language
	get_window().title = words("霓虹夜河 · Neon Pot", "Neon Pot")
	if presentation_busy or _table_entering:
		_deferred_rebuild = true
		return
	_deferred_rebuild = false
	transition_id += 1
	_cancel_presentation()
	_presented_revision = int(shown_state.get("revision", -1))
	if shown_state.get("phase", "") == "showdown":
		_settlement_key = _hand_key(shown_state)
		_displayed_pot = 0
	else:
		_displayed_pot = int(shown_state.get("pot", 0))
	input_locked = false
	for child in canvas.get_children():
		child.hide()
		child.queue_free()
	modal = null
	mixflip_decor = MixFlipOuterDecor.new()
	mixflip_decor.size = canvas.size
	canvas.add_child(mixflip_decor)
	mixflip_decor.calibration_changed.connect(_queue_stable_layout)
	mixflip_decor.hide()
	title_label = _label(canvas, words("霓虹夜河", "NEON POT"), Rect2(28, 0, 330, 88), 42, GOLD)
	hands_button = _button(canvas, words("牌型表", "HANDS"), Rect2(1002, 0, 184, 88), _show_reference)
	settings_button = _button(canvas, words("设置", "SETTINGS"), Rect2(1200, 0, 212, 88), _show_settings)
	home = Control.new()
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(home)
	_build_home()
	table = Control.new()
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(table)
	_build_table()
	table.hide()
	lobby = LanLobby.new()
	lobby.app = self
	canvas.add_child(lobby)
	lobby.hide()
	toast_label = _label(canvas, "", Rect2(34, 638, 1372, 22), 20, GOLD, true)
	toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_layout()
	if not shown_state.is_empty():
		_on_state(shown_state)

func _build_home() -> void:
	home_cards.clear()
	_panel(home, Rect2(28, 108, 680, 513), Color("1a192f", 0.82), Color("715175"), 20)
	_home_line = _night_lines.next_index("home")
	# Configure wrapping before text establishes the Label's minimum width.
	var home_title := _label(home, "", Rect2(65, 118, 620, 104), 44)
	_home_title_label = home_title
	home_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Trim this font's extra leading so two 44px lines fit the existing panel.
	home_title.add_theme_constant_override("line_spacing", -16)
	home_title.size = Vector2(620, 104)
	home_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	home_title.text = _night_lines.line("home", _home_line, language)
	_home_company_label = _label(home, _night_lines.line("company", _night_lines.next_index("company"), language), Rect2(67, 226, 608, 48), 30, GOLD)
	var back := Card.new()
	back.position = Vector2(97, 320)
	back.size = Vector2(164, 229)
	back.rotation = -0.12
	home.add_child(back)
	back.set_card(50, false)
	back.interactive = true
	back.touched.connect(func(kind: String): feedback.play(kind))
	var ace := Card.new()
	ace.position = Vector2(250, 297)
	ace.size = Vector2(164, 229)
	ace.rotation = 0.12
	home.add_child(ace)
	ace.set_card(38, true)
	ace.interactive = true
	ace.touched.connect(func(kind: String): feedback.play(kind))
	home_cards.assign([back, ace])
	home_chip_display = Chips.new()
	home_chip_display.position = Vector2(384, 343)
	home_chip_display.size = Vector2(318, 218)
	home_chip_display.visual_scale = 1.5
	home.add_child(home_chip_display)
	home_chip_display.set_inventory(ChipInventory.balanced(1000), false)
	home_chip_display.contact.connect(func(kind: String):
		if _application_active and not is_instance_valid(modal): feedback.play_chip_contact(kind))
	home_chip_touch = Button.new()
	home_chip_touch.position = home_chip_display.position
	home_chip_touch.size = home_chip_display.size
	home_chip_touch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "disabled"]:
		home_chip_touch.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	home_chip_touch.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	home_chip_touch.pressed.connect(_play_home_chips)
	home_chip_touch.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			_play_home_chips()
			home_chip_touch.accept_event())
	home.add_child(home_chip_touch)
	_label(home, words("按住牌背 · 轻点筹码", "HOLD A CARD · TAP THE CHIPS"), Rect2(62, 562, 620, 44), 24, MUTED)
	home_form_panel = _panel(home, Rect2(735, 108, 677, 513), Color("191a2a", 0.82), Color("5b6288"), 20)
	home_name_label = _label(home, words("你的名字", "YOUR NAME"), Rect2(764, 123, 310, 40), 26, MUTED)
	home_stack_label = _label(home, words("初始筹码 / 每人", "CHIPS / PLAYER"), Rect2(1126, 123, 264, 40), 24, MUTED)
	name_edit = _edit(home, words("玩家", "Player"), Rect2(764, 170, 335, 88))
	name_edit.max_length = 24
	name_edit.add_theme_font_size_override("font_size", 30)
	stack_input = _home_wheel(1000, 500, 10000, 500, Rect2(1125, 170, 256, 88), false)
	home_host_button = _button(home, words("创建牌桌", "HOST TABLE"), Rect2(764, 276, 617, 88), _host, Color("664561"))
	home_search_button = _button(home, words("搜索本地牌桌", "FIND LOCAL TABLES"), Rect2(764, 382, 617, 88), _show_room_search, Color("353e60"))
	home_wifi_label = _label(home, words("连接同一 Wi-Fi，找到朋友的牌桌", "SAME WI-FI. FIND YOUR FRIENDS."), Rect2(765, 478, 620, 30), 24, MUTED)
	home_solo_button = _button(home, words("单人模式", "SOLO TABLE"), Rect2(764, 522, 440, 88), _start_solo)
	player_count = _home_wheel(5, 2, 6, 1, Rect2(1220, 522, 160, 88), true)
	player_count.tooltip_text = words("单人桌总人数（包括你）", "TOTAL SOLO SEATS, INCLUDING YOU")
	stack_input.value_changed.connect(func(value: float): home_chip_display.set_inventory(ChipInventory.balanced(int(value)), false))

func _build_table() -> void:
	table_back_panel = _panel(table, Rect2(28, 185, 1384, 221), Color("141625", 0.72), Color("755b83"), 28)
	table_inner_panel = _panel(table, Rect2(39, 196, 1362, 199), Color.TRANSPARENT, Color(0.42, 0.36, 0.58, 0.20), 22)
	# Dedicated, softly lit receiving area; the accumulated pot is always tangible.
	pot_panel = _panel(table, Rect2(1040, 208, 350, 190), Color("201d32", 0.72), Color("716280"), 22)
	phase_label = _label(table, "", Rect2(60, 214, 250, 36), 26, GOLD)
	pot_label = _label(pot_panel, "", Rect2(18, 6, 316, 42), 28, GOLD)
	pot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pot_display = Chips.new()
	pot_display.display_mode = "pot"
	pot_display.visual_scale = 1.2
	pot_display.position = Vector2(1048, 216)
	pot_display.size = Vector2(334, 174)
	table.add_child(pot_display)
	pot_display.set_bounded_pot_enabled(true)
	pot_display.set_amount(0, false)
	board_cards.clear()
	for i in range(5):
		var card := PublicCard.new()
		card.card_scale = 116.0 / 132.0
		card.position = Vector2(343 + i * 134, 220)
		card.size = Vector2(116, 162)
		table.add_child(card)
		card.set_card(-1, false)
		card.gesture_requested.connect(func(kind: String, offset: Vector2): _request_board_gesture(i, kind, offset))
		board_cards.append(card)
	deck_cards.clear()
	for i in range(4):
		var card := Card.new()
		card.card_scale = 72.0 / 132.0
		card.size = Vector2(72, 101)
		card.position = Vector2(107 + i * 3, 275 - i * 3)
		table.add_child(card)
		card.set_card(-1, false)
		deck_cards.append(card)
	pot_touch = _prop_button(pot_display.position, pot_display.size, "pot")
	deck_touch = _prop_button(Vector2(89, 260), Vector2(118, 130), "deck")
	seats.clear()
	for i in range(6):
		var panel := _panel(table, Rect2(28 + i * 232, 98, 224, 70), PANEL, Color("3f3a54"))
		var player_name := _label(panel, "", Rect2(12, 2, 200, 33), 26)
		var badge := SeatBadge.new()
		badge.language = language
		badge.position = Vector2(124, 0)
		badge.size = Vector2(112, 44)
		panel.add_child(badge)
		var stack := _label(panel, "", Rect2(12, 33, 200, 34), 24, MUTED)
		stack.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		seats.append({"panel": panel, "name": player_name, "stack": stack, "badge": badge})
	hand_label = _label(table, "", Rect2(350, 0, 170, 88), 24, MUTED)
	room_info = _label(table, "", Rect2(540, 0, 380, 88), 22, MUTED)
	room_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	deal_button = _button(table, "", Rect2(740, 540, 648, 96), _begin_hand, Color("684664"))
	showdown_button = _button(table, words("查看摊牌", "SHOWDOWN"), Rect2(740, 443, 648, 88), func(): _show_showdown(shown_state))
	showdown_button.hide()
	own_cards.clear()
	for i in range(2):
		var card := Card.new()
		card.position = Vector2(37 + i * 149, 428)
		card.size = Vector2(132, 184)
		card.interactive = true
		table.add_child(card)
		card.touched.connect(func(kind: String): feedback.play_private_peek(kind))
		own_cards.append(card)
	_label(table, words("按住看牌 · 松手盖住", "HOLD TO PEEK"), Rect2(38, 609, 320, 30), 24, MUTED)
	own_panel = _panel(table, Rect2(351, 425, 358, 208), Color("1c1b2d", 0.74), Color("725579"), 18)
	balance_label = _label(table, "", Rect2(370, 437, 328, 41), 28, GOLD)
	balance_label.z_index = 10
	pot_label.z_index = 10
	for total in [pot_label, balance_label]:
		total.add_theme_color_override("font_outline_color", Color("100c1b"))
		total.add_theme_constant_override("outline_size", 3)
	manual_bet_hint = _label(table, words("长按手动加注", "Hold to bet manually"), Rect2(351, 635, 358, 20), 15, MUTED)
	manual_bet_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual_bet_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_display = Chips.new()
	chip_display.position = Vector2(351, 455)
	chip_display.size = Vector2(358, 174)
	chip_display.visual_scale = 1.35
	table.add_child(chip_display)
	chip_display.set_render_overflow_enabled(true)
	chip_display.contact.connect(func(kind: String):
		if _application_active and not is_instance_valid(modal): feedback.play_chip_contact(kind))
	action_label = _label(table, "", Rect2(742, 408, 650, 36), 26, MUTED)
	action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	amount_label = _label(table, "", Rect2(0, 0, 0, 0))
	amount_label.hide()
	amount_input = TouchSlider.new()
	amount_input.position = Vector2(740, 443)
	amount_input.size = Vector2(648, 88)
	amount_input.caption = words("加注至", "RAISE TO")
	amount_input.allow_value_edit = true
	amount_input.min_value = 20
	amount_input.max_value = 1000
	amount_input.step = 1
	amount_input.value = 20
	table.add_child(amount_input)
	amount_input.value_edit_requested.connect(_show_exact_raise)
	amount_input.magnet_entered.connect(func(): feedback.play_chip_contact("chip_fidget", false, 0.22))
	amount_input.user_changed.connect(func(_value: float):
		if Time.get_ticks_msec() - _last_raise_tick >= 80:
			_last_raise_tick = Time.get_ticks_msec()
			feedback.play("touch"))
	fold_button = _button(table, words("弃牌", "FOLD"), Rect2(740, 540, 136, 96), func(): _act("fold"))
	call_button = _button(table, "", Rect2(890, 540, 192, 96), _call_or_check, Color("384f6e"))
	raise_button = _button(table, words("加注", "RAISE"), Rect2(1096, 540, 146, 96), func(): _act("raise", int(amount_input.value)), Color("84506f"))
	allin_button = _button(table, "ALL\nIN", Rect2(1256, 540, 132, 96), _confirm_allin, Color("51334e"))
	for small_button in [fold_button, call_button, raise_button, allin_button]:
		small_button.add_theme_font_size_override("font_size", 26)
	chip_touch = ChipHoldButton.new()
	chip_touch.position = Vector2(351, 455)
	chip_touch.size = Vector2(358, 174)
	chip_touch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "disabled"]:
		chip_touch.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	chip_touch.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, GOLD))
	chip_touch.short_tapped.connect(_request_chip_gesture)
	chip_touch.hold_completed.connect(_open_manual_chips)
	chip_touch.hold_progress.connect(_chip_hold_progress)
	table.add_child(chip_touch)
	flight_layer = Control.new()
	flight_layer.size = BASE_SIZE
	flight_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(flight_layer)

func _room_metadata() -> Dictionary:
	return {"room_id": shown_state.get("room_id", ""), "host_name": shown_state.get("room_name", name_edit.text), "port": shown_state.get("host_port", 27846), "player_count": shown_state.get("players", []).size(), "max_players": 6, "started": shown_state.get("phase", "lobby") != "lobby"}

func _host() -> void:
	_close_modal()
	_cancel_presentation()
	discovery.stop_search()
	_presented_revision = -1
	shown_state = {}
	session.set_deck_theme(preferred_deck_theme)
	if session.host_game(name_edit.text, int(stack_input.value)) == OK:
		feedback.public_audio = true
		if discovery.start_host(_room_metadata()) != OK:
			_status(words("牌桌已创建，但本地广播未能启动。请重新创建牌桌。", "TABLE OPEN, BUT DISCOVERY COULD NOT START. RECREATE THE TABLE."))

func _show_room_search() -> void:
	var box := _open_modal(words("本地牌桌", "LOCAL TABLES"), 616)
	_search_modal = modal
	room_search_status = _label(box, words("正在寻找同一 Wi-Fi 下的牌桌……", "LOOKING FOR TABLES ON YOUR WI-FI…"), Rect2(36, 104, 1200, 48), 26, MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 168)
	scroll.size = Vector2(1230, 328)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	room_list = VBoxContainer.new()
	room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_list.add_theme_constant_override("separation", 12)
	scroll.add_child(room_list)
	_button(box, words("重新搜索", "SEARCH AGAIN"), Rect2(36, 514, 1230, 88), func(): discovery.refresh())
	if discovery.start_search() != OK:
		room_search_status.text = words("搜索暂不可用，请检查 Wi-Fi 后重试。", "SEARCH UNAVAILABLE. CHECK WI-FI AND RETRY.")

func _rooms_changed(rooms: Array) -> void:
	if not is_instance_valid(room_list) or not is_instance_valid(_search_modal) or _search_modal != modal: return
	for child in room_list.get_children():
		child.hide()
		child.queue_free()
	room_search_status.text = words("尚未发现牌桌 · 请让朋友创建牌桌并保持前台", "NO TABLES YET · ASK YOUR FRIEND TO HOST AND KEEP THE APP OPEN") if rooms.is_empty() else words("找到 %d 张牌桌 · 轻点入座", "%d TABLES FOUND · TAP TO JOIN") % rooms.size()
	for room in rooms:
		var title := words("%s的牌桌", "%s's table") % str(room.host_name)
		var button := _button(room_list, title + "    %d / %d" % [int(room.player_count), int(room.max_players)], Rect2(0, 0, 1200, 96), func(): _join_room(room))
		button.custom_minimum_size = Vector2(0, 96)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.disabled = not room.get("joinable", true)

func _join_room(room: Dictionary) -> void:
	_close_modal()
	_cancel_presentation()
	_presented_revision = -1
	shown_state = {}
	feedback.public_audio = false
	var box := _open_modal(words("正在入座", "JOINING TABLE"), 444)
	_joining = true
	_join_title = box.get_child(0) as Label
	_join_message = _label(box, words("正在连接朋友的牌桌……", "CONNECTING TO YOUR FRIEND'S TABLE…"), Rect2(40, 130, 1228, 128), 30)
	_join_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_return = _button(box, words("取消", "CANCEL"), Rect2(40, 320, 1228, 88), func():
		_joining = false
		session.leave_game()
		_show_room_search())
	if session.join_game(str(room.address), name_edit.text, int(room.port)) != OK:
		_fail_join()

func _fail_join() -> void:
	_joining = false
	session.leave_game()
	if is_instance_valid(_join_title): _join_title.text = words("暂时无法入座", "COULD NOT JOIN")
	if is_instance_valid(_join_return): _join_return.text = words("返回牌桌列表", "BACK TO TABLES")

func _start_solo() -> void:
	discovery.stop_host()
	discovery.stop_search()
	_close_modal()
	_cancel_presentation()
	_presented_revision = -1
	shown_state = {}
	session.set_deck_theme(preferred_deck_theme)
	feedback.public_audio = true
	session.start_solo(name_edit.text, int(stack_input.value), int(player_count.value))

func _play_home_chips() -> void:
	_cancel_home_entrance()
	if not is_instance_valid(home) or not home.is_visible_in_tree() or is_instance_valid(modal): return
	var now := Time.get_ticks_msec()
	var duration := int(ChipGestures.duration(_home_last_style) * 1000) if _home_last_style >= 0 else 350
	if now - _home_gesture_at < maxi(350, duration): return
	_home_gesture_at = now
	var choices: Array = ChipGestures.NORMAL.values()
	choices.erase(_home_last_style)
	var style: int = ChipGestures.RARE if _home_gesture_rng.randi_range(0, 99) == 0 else choices[_home_gesture_rng.randi_range(0, choices.size() - 1)]
	_home_last_style = style
	home_chip_display.flourish(style)
	feedback.play("touch")

func _process(delta: float) -> void:
	if _stable_layout_frames > 0:
		_stable_layout_frames -= 1
		if _stable_layout_frames == 0: _layout()
	ai_chip_idle.tick(delta, session, _application_active and not is_instance_valid(modal) and not presentation_busy and not input_locked and not _table_entering and _presentation_queue.is_empty())
	if _deal_after_entry and _application_active and not is_instance_valid(modal) and not _table_entering and not presentation_busy and not input_locked:
		_deal_after_entry = false
		_begin_hand()
	if _layout_pending and not presentation_busy and not input_locked: _layout()
	if not is_instance_valid(session) or not session.is_host or not _application_active or is_instance_valid(modal) or presentation_busy or input_locked or not _presentation_queue.is_empty():
		_solo_delay = 0.0
		return
	var actor: int = shown_state.get("actor", -1)
	if not session.is_bot_turn() or shown_state.get("phase", "lobby") in ["lobby", "showdown"] or shown_state.get("paused", false):
		_solo_delay = 0.0
		return
	var key := "%s:%s:%s" % [shown_state.get("room_id", ""), shown_state.get("hand_id", 0), shown_state.get("revision", 0)]
	if key != _solo_turn_key:
		_solo_turn_key = key
		_solo_delay = 0.0
	_solo_delay += delta
	if _solo_delay >= 0.75:
		_solo_delay = 0.0
		session.advance_bots()

func _solo_finished() -> bool:
	if not session.is_solo or shown_state.get("phase", "") != "showdown": return false
	var players: Array = shown_state.get("players", [])
	var funded := 0
	for player in players:
		if int(player.stack) > 0: funded += 1
	return players.is_empty() or int(players[0].stack) <= 0 or funded < 2

func _begin_hand() -> void:
	_cancel_table_props()
	if _solo_finished():
		_start_solo()
		_deal_after_entry = _table_entering
		if _table_entering: return
	if input_locked or presentation_busy:
		return
	if is_instance_valid(lobby) and lobby.visible:
		feedback.play("deal", true)
		session.begin_hand()
		return
	input_locked = true
	deal_button.disabled = true
	var current_transition := transition_id
	feedback.play("fold", true)
	var tween := create_tween().set_parallel(true).set_speed_scale(Timing.rate)
	var cut_rest: Dictionary = {}
	for i in range(2, 4):
		cut_rest[i] = {"position": deck_cards[i].position, "rotation": deck_cards[i].rotation}
		tween.tween_property(deck_cards[i], "position", deck_cards[i].position + Vector2(84, 0), 0.23).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(deck_cards[i], "rotation", deck_cards[i].rotation + 0.10, 0.23)
	await tween.finished
	if current_transition != transition_id:
		return
	feedback.play("release", true)
	tween = create_tween().set_parallel(true).set_speed_scale(Timing.rate)
	for i in range(2, 4):
		var rest: Dictionary = cut_rest[i]
		tween.tween_property(deck_cards[i], "position", rest.position, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(deck_cards[i], "rotation", rest.rotation, 0.28)
	await tween.finished
	if current_transition != transition_id:
		return
	input_locked = false
	feedback.play("deal", true)
	session.begin_hand()

func _on_state(state: Dictionary) -> void:
	if is_instance_valid(manual_panel):
		if _manual_exchange_pending and state.get("room_id", "") == shown_state.get("room_id", "") and state.get("hand_id", -1) == shown_state.get("hand_id", -2) and state.get("actor", -1) == state.get("you", -2) and state.get("current_bet", -1) == shown_state.get("current_bet", -2):
			_manual_context = _chip_context(state)
			_manual_exchange_pending = false
		if _chip_context(state) != _manual_context or state.get("paused", false):
			_close_manual_chips()
		else:
			var you := int(state.get("you", -1))
			if you >= 0 and you < state.get("players", []).size(): manual_panel.update_inventory(state.players[you].get("chips", {}))
	if _table_entering:
		if state.is_empty() or state.get("paused", false) or state.get("room_id", "") != shown_state.get("room_id", ""):
			_cancel_table_entry()
		else:
			_entry_latest = state
			return
	var room := str(state.get("room_id", ""))
	var entering: bool = not state.is_empty() and room != _entered_room and (session.is_solo or (not session.is_local and state.get("phase", "lobby") != "lobby"))
	if entering:
		_entered_room = room
		_table_entering = true
		input_locked = true
	_render_state(state)
	if entering: _play_table_entry()

func _render_state(state: Dictionary, reconcile: bool = false) -> void:
	_set_visible_deck(int(state.get("deck_theme", preferred_deck_theme)))
	if is_instance_valid(deck_gallery):
		deck_gallery.selected_theme = DeckThemes.active_id
	if not reconcile and not shown_state.is_empty() and state.get("room_id", "") == shown_state.get("room_id", "") and state.get("revision", -1) == shown_state.get("revision", -1) and int(state.get("deck_theme_revision", 0)) > int(shown_state.get("deck_theme_revision", 0)):
		shown_state = state
		return # A cosmetic host update must not interrupt a held card or an action.
	_cancel_table_props()
	_cancel_home_entrance()
	if _joining and state.is_empty():
		_fail_join()
	if is_instance_valid(modal) and modal.has_meta("settlement_hand") and not state.is_empty():
		if state.get("phase", "") != "showdown" or str(modal.get_meta("settlement_hand")) != _hand_key(state):
			_close_modal()
	var old_state := shown_state
	if old_state.get("room_id", "") != state.get("room_id", "") or old_state.get("hand_id", -1) != state.get("hand_id", -1) or old_state.get("board", []) != state.get("board", []) or state.get("paused", false):
		_reset_board_gestures()
	if old_state.is_empty() or old_state.get("hand_id", -1) != state.get("hand_id", -1):
		_unlanded_refunds.clear()
		_paid_awards.clear()
	elif not state.get("paused", false) and int(state.get("revision", -1)) > _presented_revision:
		if state.has("chip_transfers"):
			for transfer in (state.chip_transfers if state.get("chip_revision", -1) != old_state.get("chip_revision", -1) else []):
				if transfer.get("kind", "") == "refund":
					var seat := int(transfer.seat)
					_unlanded_refunds[seat] = int(_unlanded_refunds.get(seat, 0)) + ChipInventory.value(transfer.chips)
		else:
			var old_players: Array = old_state.get("players", [])
			var new_players: Array = state.get("players", [])
			for seat in range(mini(old_players.size(), new_players.size())):
				var refund := int(old_players[seat].get("committed", 0)) - int(new_players[seat].get("committed", 0))
				if refund > 0: _unlanded_refunds[seat] = int(_unlanded_refunds.get(seat, 0)) + refund
	shown_state = state
	if is_instance_valid(deck_gallery): deck_gallery.can_apply = _can_choose_deck()
	if _joining and not state.is_empty():
		_joining = false
		_close_modal()
		toast_label.text = ""
	if session.is_host and not session.is_local: discovery.update_host(_room_metadata())
	if not is_instance_valid(table) or state.is_empty():
		return
	home.hide()
	var in_lan_lobby: bool = state.get("phase", "") == "lobby" and not session.is_local
	lobby.visible = in_lan_lobby
	table.visible = not in_lan_lobby
	if in_lan_lobby: lobby.update_state(state)
	var players: Array = state.get("players", [])
	var phase: String = state.get("phase", "lobby")
	var actor: int = state.get("actor", -1)
	var you: int = state.get("you", session.local_seat)
	var paused: bool = state.get("paused", false)
	var legal: Dictionary = state.get("legal", {})
	var active := actor == you and not paused and phase not in ["lobby", "showdown"] and not input_locked
	var is_new_hand: bool = int(state.get("hand_id", 0)) != previous_hand
	if is_new_hand and phase != "lobby": toast_label.text = ""
	for i in range(seats.size()):
		var slot: Dictionary = seats[i]
		slot.panel.visible = i < players.size()
		if i >= players.size():
			continue
		var seat_width := (1384.0 - 8.0 * (players.size() - 1)) / players.size()
		slot.panel.position.x = 28 + i * (seat_width + 8)
		slot.panel.size.x = seat_width
		slot.name.size.x = seat_width - 24
		slot.stack.size.x = seat_width - 24
		var player: Dictionary = players[i]
		var roles: Array[String] = []
		if state.get("dealer", -1) == i: roles.append("D")
		if state.get("small_blind_seat", -1) == i: roles.append("SB")
		if state.get("big_blind_seat", -1) == i: roles.append("BB")
		slot.badge.roles = roles
		slot.badge.position.x = seat_width - 116
		slot.badge.visible = not roles.is_empty()
		slot.name.size.x = seat_width - (132 if not roles.is_empty() else 24)
		slot.name.text = str(player.get("name", "")) + (words("·你", "·YOU") if i == you else "")
		slot.name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var player_status := ""
		var live_hand := phase not in ["lobby", "showdown"]
		var folded: bool = phase != "lobby" and player.get("folded", false)
		# A live all-in still contests the pot; payout animation is not seat eligibility.
		var all_in: bool = live_hand and not folded and player.get("all_in", false)
		var out: bool = int(player.get("stack", 0)) <= 0 and not all_in
		var dimmed := folded or out
		var acting := actor == i and live_hand and not dimmed
		if out:
			player_status = words("筹码耗尽", "OUT")
		elif folded:
			player_status = words("弃牌", "FOLDED")
		elif all_in:
			player_status = "ALL IN"
		else:
			player_status = words("出 ", "BET ") + str(player.get("bet", 0))
		slot.stack.text = str(_visual_stack(state, i)) + " / " + player_status
		slot.panel.add_theme_stylebox_override("panel", _box(Color("11121e") if dimmed else (Color("42344f") if acting else PANEL), Color("292a3a") if dimmed else (GOLD if acting else Color("423a55"))))
		slot.name.add_theme_color_override("font_color", Color("9394a5") if dimmed else INK)
		slot.stack.add_theme_color_override("font_color", Color("85879b") if dimmed else (GOLD if all_in else MUTED))
		slot.badge.self_modulate = Color("777889") if dimmed else Color.WHITE
	var phase_names := {"lobby": words("牌桌已就绪", "THE TABLE IS OPEN"), "preflop": words("翻牌前", "PREFLOP"), "flop": words("翻牌", "FLOP"), "turn": words("转牌", "TURN"), "river": words("河牌", "RIVER"), "showdown": words("本手结束", "HAND COMPLETE")}
	phase_label.text = phase_names.get(phase, phase)
	pot_label.text = _pot_caption(_displayed_pot)
	hand_label.text = words("第 %02d 手", "HAND %02d") % int(state.get("hand_id", 0))
	room_info.text = words("单人牌桌", "SOLO TABLE") if session.is_solo else words("局域网牌桌", "LOCAL TABLE")
	_layout_table_heading()
	var board: Array = state.get("board", [])
	_runout_pending = phase == "showdown" and board.size() > old_state.get("board", []).size() and not old_state.is_empty() and old_state.get("hand_id", -1) == state.get("hand_id", -2) and players.filter(func(p): return not p.get("folded", false)).size() > 1
	var visible_board_count: int = old_state.get("board", []).size() if _runout_pending else board.size()
	for i in range(5):
		board_cards[i].visible = phase != "lobby"
		board_cards[i].modulate.a = 1.0 if i < visible_board_count else 0.17
		if i < visible_board_count:
			board_cards[i].set_card(int(board[i]), true)
			if i >= previous_board or is_new_hand:
				board_cards[i].deal((i - previous_board) * 0.11 if not is_new_hand else i * 0.06)
		else:
			board_cards[i].set_card(-1, false)
	if board.size() > previous_board:
		feedback.play("reveal", true)
	previous_board = board.size()
	previous_hand = state.get("hand_id", 0)
	var own: Dictionary = players[you] if you >= 0 and you < players.size() else {}
	var cards: Array = own.get("cards", [])
	for i in range(2):
		own_cards[i].visible = phase != "lobby" and cards.size() > i
		if cards.size() > i:
			own_cards[i].set_card(int(cards[i]), phase == "showdown" and not own.get("folded", false))
			own_cards[i].interactive = phase != "showdown" and not paused and not own.get("folded", false)
			if is_new_hand and not _table_entering:
				own_cards[i].deal(i * 0.12)
	balance_label.text = words("筹码  ", "STACK  ") + str(_visual_stack(state, you))
	_set_player_chips(chip_display, state, you, false)
	deal_button.visible = session.is_host and phase in ["lobby", "showdown"]
	showdown_button.visible = phase == "showdown"
	deal_button.text = words("开始发牌", "DEAL HAND") if phase == "lobby" else words("下一手", "NEXT HAND")
	deal_button.disabled = not state.get("can_start", players.size() >= 2) or paused
	if _solo_finished():
		deal_button.text = words("重新开局", "NEW SOLO TABLE")
		deal_button.disabled = paused
	if paused:
		action_label.text = words("连接中断，牌局已暂停", "DISCONNECTED · TABLE PAUSED")
	elif phase == "lobby":
		action_label.text = words("你与 %d 位 AI · 点击开始发牌", "YOU + %d BOTS · DEAL TO BEGIN") % (players.size() - 1) if session.is_solo else words("等朋友入座，由房主发牌", "JOIN YOUR FRIENDS. HOST DEALS.")
	elif phase == "showdown":
		action_label.text = _result_text(state)
	elif active:
		var prompt_key := "%s:%s:%s" % [state.get("room_id", ""), state.get("hand_id", 0), state.get("revision", 0)]
		if prompt_key != _turn_line_key or _turn_line < 0:
			_turn_line_key = prompt_key
			_turn_line = _night_lines.next_index("turn")
		action_label.text = _night_lines.line("turn", _turn_line, language)
	else:
		var actor_name: String = str(players[actor].get("name", "")) if actor >= 0 and actor < players.size() else ""
		action_label.text = words("等待 ", "WAITING FOR ") + actor_name
	fold_button.disabled = not active or not legal.get("fold", false)
	call_button.text = words("过牌", "CHECK") if legal.get("check", false) else words("跟注 ", "CALL ") + str(legal.get("call_amount", 0))
	if not legal.get("check", false):
		call_button.text = words("跟注", "CALL") + "\n" + str(legal.get("call_amount", 0))
	call_button.disabled = not active or not (legal.get("call", false) or legal.get("check", false))
	raise_button.disabled = not active or not legal.get("raise", false)
	allin_button.disabled = not active or not legal.get("all_in", false)
	amount_input.set_block_signals(true)
	amount_input.min_value = 0
	amount_input.max_value = maxi(legal.get("max_raise_to", 1000), legal.get("min_raise_to", 20))
	amount_input.min_value = legal.get("min_raise_to", 20)
	amount_input.value = amount_input.min_value
	amount_input.editable = active and legal.get("raise", false)
	amount_input.set_block_signals(false)
	_update_bet_magnets(state)
	for control in [amount_input, allin_button, fold_button, call_button, raise_button]:
		control.visible = phase not in ["lobby", "showdown"]
	chip_display.show()
	chip_touch.visible = chip_display.visible
	chip_touch.disabled = paused or presentation_busy or input_locked or int(own.get("stack", 0)) <= 0
	if not mixflip_outer_profile.is_empty() and not presentation_busy and (not input_locked or (_table_entering and _table_entry == null)):
		_apply_mixflip_layout(mixflip_outer_profile)
	_accept_presentation(old_state, state)
	_update_presentation_controls()
	previous_phase = phase
	if not presentation_busy and _deferred_rebuild:
		_finish_deferred_rebuild.call_deferred()

func _finish_deferred_rebuild() -> void:
	if not _deferred_rebuild or presentation_busy:
		return
	_build_ui()
	if _settings_after_rebuild:
		_settings_after_rebuild = false
		_show_settings()
	elif shown_state.get("phase", "") == "showdown" and not shown_state.get("paused", false):
		_show_showdown(shown_state)

func _hand_key(state: Dictionary) -> String:
	return str(state.get("hand_id", -1))

func _layout_table_heading() -> void:
	if not mixflip_outer_profile.is_empty():
		var play: Rect2 = mixflip_outer_profile.interactive_rect
		_mixflip_track(hand_label, false)
		_mixflip_track(room_info, false)
		_mixflip_rect(hand_label, Rect2(382, play.position.y + 4, 190, 82))
		_mixflip_rect(room_info, Rect2(584, play.position.y + 4, 430, 82))
		if mixflip_outer_profile.get("full", false):
			var aux: Rect2 = mixflip_outer_profile.aux_rect
			_mixflip_rect(hand_label, Rect2(aux.position + Vector2(8, 0), Vector2(208, 60)))
			_mixflip_rect(room_info, Rect2(aux.position + Vector2(224, 0), Vector2(aux.size.x - 232, 60)))
		_mixflip_font(hand_label, 36)
		_mixflip_font(room_info, 36)
		return
	var title_width := _font.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
	hand_label.position.x = title_label.position.x + title_width + 28.0
	hand_label.size.x = _font.get_string_size(hand_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 12.0
	room_info.position.x = hand_label.position.x + hand_label.size.x + 20.0
	room_info.size.x = maxf(0.0, 976.0 - room_info.position.x)

func _visual_stack(state: Dictionary, seat: int) -> int:
	var players: Array = state.get("players", [])
	if seat < 0 or seat >= players.size():
		return 0
	var amount: int = players[seat].get("stack", 0)
	if state.get("paused", false):
		return amount
	amount -= int(_unlanded_refunds.get(seat, 0))
	if state.get("phase", "") == "showdown" and _settlement_key != _hand_key(state) and not _paid_awards.has(seat):
		for award in state.get("result", []):
			if int(award.seat) == seat:
				amount -= int(award.amount)
	return maxi(0, amount)

func _cancel_presentation() -> void:
	_manual_flight_context = ""
	_close_manual_chips()
	_cancel_table_props()
	if is_instance_valid(feedback): feedback.cancel_chip_haptics()
	_presentation_token += 1
	_unlanded_refunds.clear()
	_presentation_queue.clear()
	if is_instance_valid(home_chip_display): home_chip_display.cancel_flourish()
	if is_instance_valid(chip_display): chip_display.cancel_flourish()
	_clear_fidgets()
	presentation_busy = false
	_settling_key = ""
	for tween in _flight_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_flight_tweens.clear()
	if is_instance_valid(flight_layer):
		for child in flight_layer.get_children():
			flight_layer.remove_child(child)
			child.queue_free()

func _record_event(kind: String, seat: int = -1, amount: int = 0) -> void:
	presentation_events.append({"kind": kind, "seat": seat, "amount": amount})
	if presentation_events.size() > 100:
		presentation_events.pop_front()

func _accept_presentation(old: Dictionary, state: Dictionary) -> void:
	var phase: String = state.get("phase", "lobby")
	var revision: int = state.get("revision", -1)
	var changed_hand: bool = old.is_empty() or old.get("hand_id", -1) != state.get("hand_id", -1)
	if changed_hand:
		_cancel_presentation()
		_displayed_pot = 0
		_displayed_pot_chips.clear()
		_settlement_key = ""
		_paid_awards.clear()
		_presented_revision = -1
	if state.get("paused", false):
		_cancel_presentation()
		_displayed_pot = 0 if phase == "showdown" else int(state.get("pot", 0))
		_displayed_pot_chips = {} if phase == "showdown" else state.get("pot_chips", {}).duplicate(true)
		_presented_revision = revision
		if phase == "showdown":
			_settlement_key = _hand_key(state)
	elif revision > _presented_revision:
		_presented_revision = revision
		if state.has("chip_transfers"):
			for transfer in (state.chip_transfers if changed_hand or state.get("chip_revision", -1) != old.get("chip_revision", -1) else []):
				if transfer.get("kind", "") in ["bet", "refund"]:
					_presentation_queue.append({"kind": transfer.kind, "seat": int(transfer.seat), "amount": ChipInventory.value(transfer.chips), "chips": transfer.chips.duplicate(true)})
		else:
			var players: Array = state.get("players", [])
			var old_players: Array = old.get("players", [])
			for seat in range(players.size()):
				var before := 0 if changed_hand or seat >= old_players.size() else int(old_players[seat].get("committed", 0))
				var difference := int(players[seat].get("committed", 0)) - before
				if difference > 0: _presentation_queue.append({"kind": "bet", "seat": seat, "amount": difference})
				elif difference < 0: _presentation_queue.append({"kind": "refund", "seat": seat, "amount": -difference})
		_presentation_queue.append({"kind": "sync", "amount": int(state.get("pot", 0)), "chips": _pot_before_payout(state)})
	if phase == "showdown" and _settlement_key != _hand_key(state) and _settling_key != _hand_key(state) and not state.get("paused", false):
		_settling_key = _hand_key(state)
		if _runout_pending: _presentation_queue.append({"kind": "runout", "state": state.duplicate(true), "start": old.get("board", []).size()})
		_presentation_queue.append({"kind": "settle", "state": state.duplicate(true)})
	if not presentation_busy and not _table_entering and not _presentation_queue.is_empty():
		_run_presentation()
	_render_pot_chips(false)
	pot_label.text = _pot_caption(_displayed_pot)

func _update_presentation_controls() -> void:
	if not is_instance_valid(deal_button):
		return
	var phase: String = shown_state.get("phase", "lobby")
	var paused: bool = shown_state.get("paused", false)
	var active: bool = shown_state.get("actor", -1) == shown_state.get("you", -2) and not paused and not presentation_busy and not input_locked and not is_instance_valid(manual_panel)
	var legal: Dictionary = shown_state.get("legal", {})
	fold_button.disabled = not active or not legal.get("fold", false)
	call_button.disabled = not active or not (legal.get("check", false) or legal.get("call", false))
	raise_button.disabled = not active or not legal.get("raise", false)
	allin_button.disabled = not active or not legal.get("all_in", false)
	amount_input.editable = active and legal.get("raise", false)
	chip_touch.disabled = paused or presentation_busy or input_locked or _visual_stack(shown_state, int(shown_state.get("you", -1))) <= 0
	chip_touch.hold_enabled = active and (legal.get("raise", false) or legal.get("all_in", false))
	manual_bet_hint.visible = chip_display.visible and not is_instance_valid(manual_panel)
	manual_bet_hint.modulate.a = 0.85 if chip_touch.hold_enabled else 0.5
	deal_button.disabled = presentation_busy or input_locked or paused or (not shown_state.get("can_start", false) and not _solo_finished())
	showdown_button.disabled = presentation_busy
	for card in board_cards:
		card.public_interactive = phase in ["preflop", "flop", "turn", "river", "showdown"] and not paused and not input_locked and not is_instance_valid(modal) and _application_active
	if presentation_busy and phase == "showdown":
		action_label.text = words("筹码归位中…", "SETTLING THE CHIPS…")
	pot_label.text = _pot_caption(int(shown_state.get("pot", 0)), true) if phase == "showdown" and not presentation_busy else _pot_caption(_displayed_pot)

func _pot_caption(amount: int, hand_total: bool = false) -> String:
	if mixflip_outer_profile.get("full", false):
		if is_instance_valid(mixflip_pot_title):
			mixflip_pot_title.text = words("总池", "TOTAL") if hand_total else words("底池", "POT")
		var digits := str(amount)
		var digit_size := 40
		var digit_font := pot_label.get_theme_font("font")
		while digit_size > 12 and digit_font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, digit_size).x > pot_label.size.x - 12.0:
			digit_size -= 1
		_mixflip_font(pot_label, digit_size)
		return digits
	return (words("本手总池  ", "HAND POT  ") if hand_total else words("底池  ", "POT  ")) + str(amount)

func _seat_position(seat: int) -> Vector2:
	if seat == int(shown_state.get("you", -1)):
		return chip_display.position + chip_display.size * 0.5
	if seat >= 0 and seat < seats.size():
		var panel: Control = seats[seat].panel
		return panel.position + Vector2(panel.size.x * 0.5, panel.size.y * 0.8)
	return Vector2(710, 140)

func _pot_position() -> Vector2:
	return pot_display.position + pot_display.size * Vector2(0.5, 0.52)

func _chip_packet_size(inventory: Dictionary) -> Vector2:
	var columns := 0
	for value in Chips.VALUES:
		columns += ceili(mini(100, int(inventory.get(str(value), 0))) / 10.0)
	var pitch: float = Chips.CHIP_PIXELS * Chips.COLUMN_SPACING / 1.14
	var width := clampf(columns * pitch + 32.0, 188.0, minf(720.0, table.size.x - 32.0))
	var across := maxi(1, floori((width - 8.0) / pitch))
	return Vector2(width, 220.0 + maxi(0, ceili(float(columns) / across) - 1) * 52.0)

func _fly_chips(origin: Vector2, destination: Vector2, amount: int, duration: float, token: int, inventory: Dictionary = {}) -> void:
	duration = Timing.duration(duration)
	var packet := Chips.new()
	packet.display_mode = "flight"
	packet.size = _chip_packet_size(inventory)
	packet.position = (origin - packet.size * 0.5).clamp(Vector2.ZERO, (table.size - packet.size).max(Vector2.ZERO))
	flight_layer.add_child(packet)
	if not inventory.is_empty(): packet.set_inventory(inventory, false)
	else: packet.set_amount(amount, false)
	packet.toss(duration)
	var tween := create_tween()
	_flight_tweens = _flight_tweens.filter(func(active_tween: Tween): return active_tween.is_valid())
	_flight_tweens.append(tween)
	tween.tween_method(func(progress: float):
		if is_instance_valid(packet):
			var center := origin.lerp(destination, progress) - Vector2(0, sin(progress * PI) * 78.0)
			packet.position = (center - packet.size * 0.5).clamp(Vector2.ZERO, (table.size - packet.size).max(Vector2.ZERO))
		, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		if token == _presentation_token:
			if is_instance_valid(packet):
				packet.queue_free())

func _presentation_delay(seconds: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(timer.queue_free)
	timer.start(Timing.duration(seconds))
	return timer

func _run_presentation() -> void:
	presentation_busy = true
	var token := _presentation_token
	_update_presentation_controls()
	while not _presentation_queue.is_empty() and token == _presentation_token:
		var item: Dictionary = _presentation_queue.pop_front()
		match item.kind:
			"bet":
				_record_event("throw", item.seat, item.amount)
				feedback.play_chip_contact("chip_throw", true, 1.0 if int(item.get("seat", -1)) == int(shown_state.get("you", -2)) else 0.45)
				var source := _seat_position(item.seat)
				if int(item.seat) == int(shown_state.get("you", -1)) and not _manual_flight_context.is_empty():
					source = _manual_flight_origin
					_manual_flight_context = ""
				_fly_chips(source, _pot_position() - Vector2(0, pot_display.size.y * 0.45), item.amount, 0.46, token, item.get("chips", {}))
				await _presentation_delay(0.46).timeout
				if token != _presentation_token: return
				_displayed_pot += int(item.amount)
				_displayed_pot_chips = ChipInventory.add(_displayed_pot_chips, item.get("chips", {}))
				_render_pot_chips(true)
				feedback.play_chip_contact("chip_land", true, 1.0 if int(item.get("seat", -1)) == int(shown_state.get("you", -2)) else 0.45)
				_record_event("land", item.seat, item.amount)
			"refund":
				feedback.play_chip_contact("chip_collect", true, 1.0 if int(item.get("seat", -1)) == int(shown_state.get("you", -2)) else 0.45)
				_fly_chips(_pot_position(), _seat_position(item.seat), item.amount, 0.42, token, item.get("chips", {}))
				await _presentation_delay(0.42).timeout
				if token != _presentation_token: return
				_displayed_pot = maxi(0, _displayed_pot - int(item.amount))
				_displayed_pot_chips = ChipInventory.take(_displayed_pot_chips, int(item.amount)).get("remaining", {}) if not _displayed_pot_chips.is_empty() else {}
				_unlanded_refunds[item.seat] = maxi(0, int(_unlanded_refunds.get(item.seat, 0)) - int(item.amount))
				feedback.play_chip_contact("chip_land", true, 1.0 if int(item.seat) == int(shown_state.get("you", -1)) else 0.45)
				var returned_stack := _visual_stack(shown_state, item.seat)
				seats[item.seat].stack.text = str(returned_stack) + " / +" + str(item.amount)
				if int(item.seat) == int(shown_state.get("you", -1)):
					balance_label.text = words("筹码  ", "STACK  ") + str(returned_stack)
					_set_player_chips(chip_display, shown_state, item.seat, true)
					chip_display.organize(Timing.duration(0.38))
					feedback.play_chip_contact("chip_stack", true)
					await _presentation_delay(0.38).timeout
					if token != _presentation_token: return
				_record_event("refund", item.seat, item.amount)
				_render_pot_chips(true)
			"sync":
				_displayed_pot = int(item.amount)
				_displayed_pot_chips = item.get("chips", {}).duplicate(true)
				_render_pot_chips(false)
			"runout":
				await _presentation_delay(0.55).timeout
				if token != _presentation_token: return
				var cards: Array = item.state.get("board", [])
				for index in range(int(item.start), cards.size()):
					if index >= 3:
						await _presentation_delay(0.7).timeout
						if token != _presentation_token: return
					board_cards[index].modulate.a = 1.0
					board_cards[index].set_card(int(cards[index]), true)
					board_cards[index].deal(0.08 * index if index < 3 else 0.0)
					feedback.play("reveal", true)
				await _presentation_delay(0.65).timeout
				if token != _presentation_token: return
				_runout_pending = false
			"settle":
				var snapshot: Dictionary = item.state
				_displayed_pot = int(snapshot.get("pot", 0))
				_displayed_pot_chips = _pot_before_payout(snapshot)
				_render_pot_chips(false)
				_record_event("collect", -1, _displayed_pot)
				feedback.play_chip_contact("chip_collect", true, 1.0 if int(item.get("seat", -1)) == int(shown_state.get("you", -2)) else 0.45)
				pot_display.collect(Timing.duration(0.44))
				await _presentation_delay(0.46).timeout
				if token != _presentation_token: return
				var awards: Dictionary = {}
				for award in snapshot.get("result", []):
					awards[award.seat] = int(awards.get(award.seat, 0)) + int(award.amount)
				for seat in awards:
					var amount: int = awards[seat]
					feedback.play_chip_contact("chip_throw", true, 0.7 if seat == int(shown_state.get("you", -1)) else 0.3)
					_fly_chips(_pot_position(), _seat_position(seat), amount, 0.6, token, _transfer_chips(snapshot, seat, "payout"))
					await _presentation_delay(0.6).timeout
					if token != _presentation_token: return
					_displayed_pot = maxi(0, _displayed_pot - amount)
					_displayed_pot_chips = ChipInventory.take(_displayed_pot_chips, amount).get("remaining", {})
					_render_pot_chips(false)
					_record_event("award", seat, amount)
					_paid_awards[seat] = amount
					seats[seat].stack.text = str(snapshot.players[seat].stack) + " / +" + str(amount)
					feedback.play_chip_contact("payout", true, 1.0 if seat == int(shown_state.get("you", -1)) else 0.45)
					var received_chips: Control = null
					if seat == int(shown_state.get("you", -1)):
						_set_player_chips(chip_display, snapshot, seat, true)
						balance_label.text = words("筹码  ", "STACK  ") + str(shown_state.players[seat].stack)
						chip_display.organize(Timing.duration(0.38))
					else:
						received_chips = Chips.new()
						received_chips.display_mode = "pot"
						received_chips.size = _chip_packet_size(_transfer_chips(snapshot, seat, "payout"))
						received_chips.position = (_seat_position(seat) - received_chips.size * 0.5).clamp(Vector2.ZERO, (table.size - received_chips.size).max(Vector2.ZERO))
						flight_layer.add_child(received_chips)
						if snapshot.has("chip_transfers"): received_chips.set_inventory(_transfer_chips(snapshot, seat, "payout"), false)
						else: received_chips.set_amount(amount, false)
						received_chips.organize(Timing.duration(0.38))
						var panel: Control = seats[seat].panel
						panel.modulate = Color("e9c9ed")
						create_tween().tween_property(panel, "modulate", Color.WHITE, 0.38)
					feedback.play_chip_contact("chip_stack", true, 1.0 if seat == int(shown_state.get("you", -1)) else 0.45)
					await _presentation_delay(0.4).timeout
					if token != _presentation_token: return
					if is_instance_valid(received_chips):
						received_chips.queue_free()
					_record_event("organized", seat, amount)
				_displayed_pot = 0
				_displayed_pot_chips.clear()
				_render_pot_chips(false)
				_settlement_key = _hand_key(snapshot)
				_settling_key = ""
				if not is_instance_valid(modal):
					_show_showdown(shown_state)
		_update_presentation_controls()
	if token == _presentation_token:
		presentation_busy = false
		_update_presentation_controls()
		if shown_state.get("phase", "") == "showdown":
			action_label.text = _result_text(shown_state)
		if _deferred_rebuild:
			_finish_deferred_rebuild()

func _call_or_check() -> void:
	_act("check" if shown_state.get("legal", {}).get("check", false) else "call")

func _act(action: String, amount: int = 0) -> void:
	_close_modal()
	if input_locked or presentation_busy:
		return
	if action == "fold":
		feedback.play("fold")
	elif action == "check":
		feedback.play("touch")
	session.submit_action(action, amount)

func _show_showdown(state: Dictionary) -> void:
	var players: Array = state.get("players", [])
	var height := mini(int(canvas.size.y) - 16, 850 if players.size() > 3 else 640)
	var box := _open_modal(words("摊牌 · 本手结算", "SHOWDOWN · SETTLEMENT"), height)
	modal.set_meta("settlement_hand", _hand_key(state))
	modal.set_meta("settlement_max_height", 850 if players.size() > 3 else 640)
	box.name = "SettlementPanel"
	var board: Array = state.get("board", [])
	var winners := WinningHand.winners(state, language)
	var winner_info: Dictionary = {}
	var highlights: Dictionary = {}
	var groups: Dictionary = {}
	var colors := [Color("ffdc45"), Color("39cfff"), Color("ff9238"), Color("b394ff"), Color("ffffff"), Color("ff526d")]
	for winner in winners:
		var sorted_cards: Array = winner.cards.duplicate()
		sorted_cards.sort()
		var key := str(sorted_cards)
		if not groups.has(key): groups[key] = colors[groups.size() % colors.size()]
		winner["color"] = groups[key]
		winner_info[winner.seat] = winner
		for id in winner.cards:
			if not board.has(id): continue
			if not highlights.has(id): highlights[id] = []
			if not highlights[id].has(winner.color): highlights[id].append(winner.color)
	_panel(box, Rect2(32, 92, 1248, 206), Color("141322"), Color("49415b"), 12)
	_label(box, words("公共牌", "BOARD") if not board.is_empty() else words("未发公共牌", "NO BOARD"), Rect2(50, 98, 620, 32), 24, MUTED)
	if not board.is_empty():
		var public_cards := ShowdownBoard.new()
		public_cards.name = "ShowdownBoard"
		public_cards.cards = board.duplicate()
		public_cards.highlight_colors = highlights
		public_cards.position = Vector2(52, 136)
		box.add_child(public_cards)
	_label(box, words("本手总池", "HAND POT"), Rect2(740, 111, 510, 36), 26, MUTED)
	_label(box, str(state.get("pot", 0)), Rect2(740, 151, 510, 64), 48, INK)
	_label(box, words("亮色描边 · 获胜五张", "BRIGHT FRAMES · WINNING FIVE") if not highlights.is_empty() else words("本手已结算", "HAND SETTLED"), Rect2(740, 244, 510, 36), 22 if language == "zh" else 18, colors[0])
	var winnings: Dictionary = {}
	for award in state.get("result", []):
		winnings[award.seat] = int(winnings.get(award.seat, 0)) + int(award.amount)
	var scroll := ScrollContainer.new()
	scroll.name = "SettlementScroll"
	scroll.position = Vector2(32, 314)
	scroll.size = Vector2(1248, height - 418)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(1232, ceilf(players.size() / 3.0) * 212.0)
	scroll.add_child(content)
	for seat in range(players.size()):
		var player: Dictionary = players[seat]
		var x := (seat % 3) * 416.0
		var y := (seat / 3) * 212.0
		var winner: Dictionary = winner_info.get(seat, {})
		var accent: Color = winner.get("color", GOLD)
		var player_box := _panel(content, Rect2(x, y, 400, 204), Color("242037"), accent if winnings.has(seat) else Color("49415b"), 12)
		player_box.name = "ShowdownPlayer%d" % seat
		var name_label := _label(content, str(player.get("name", "")), Rect2(x + 14, y + 5, 371, 32), 28, accent if winnings.has(seat) else INK)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var cards: Array = player.get("cards", [])
		for i in range(mini(2, cards.size())):
			var card := Card.new()
			card.name = "ShowdownHole%d_%d" % [seat, i]
			card.card_scale = ShowdownBoard.CARD_SIZE.x / 132.0
			card.position = Vector2(x + 16 + i * 124, y + 44)
			card.size = ShowdownBoard.CARD_SIZE
			content.add_child(card)
			card.set_card(int(cards[i]), not player.get("folded", false) and int(cards[i]) >= 0)
			if winner.get("cards", []).has(int(cards[i])): card.winning_colors = [accent]
		var reward := words("弃牌", "FOLDED") if player.get("folded", false) else ("+" + str(winnings[seat]) if winnings.has(seat) else "—")
		if not winner.is_empty():
			reward = "+%d\n%s\n%s" % [winnings[seat], words("筹码 · 获胜", "CHIPS · WIN"), winner.category]
		var result_label := _label(content, reward, Rect2(x + 252, y + 38, 138, 144), 22 if language == "zh" else 18, accent if winnings.has(seat) else MUTED, true)
		result_label.name = "ShowdownResult%d" % seat
		result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result_label.size = Vector2(138, 144)
	var footer: Control
	if session.is_host:
		footer = _button(box, words("重新开局", "NEW TABLE") if _solo_finished() else words("下一手  →", "NEXT HAND  →"), Rect2(36, height - 96, 1230, 88), func():
			_close_modal()
			_begin_hand(), Color("684664"))
	else:
		footer = _label(box, words("筹码已归位，等待房主开始下一手。", "CHIPS SETTLED. WAITING FOR THE HOST."), Rect2(36, height - 96, 1230, 88), 24, MUTED)
	footer.name = "SettlementFooter"
	_layout_active_modal()

func _modal_available_rect() -> Rect2:
	return mixflip_outer_profile.interactive_rect if mixflip_outer_profile.get("full", false) else Rect2(Vector2.ZERO, canvas.size)

func _layout_active_modal() -> void:
	if not is_instance_valid(modal): return
	var available := _modal_available_rect()
	if modal.has_meta("fullscreen_modal"):
		modal.position = available.position
		modal.size = available.size
		if modal.has_method("set_available_height"):
			modal.set_available_height(available.size.y)
		return
	modal.position = Vector2.ZERO
	modal.size = canvas.size
	if modal.get_child_count() > 0 and modal.get_child(0) is ColorRect:
		modal.get_child(0).size = canvas.size
	var box: Control
	for child in modal.get_children():
		if child is Panel and child.has_meta("main_modal_panel"):
			box = child
			break
	if box == null: return
	var requested := float(modal.get_meta("modal_requested_height", box.size.y))
	var height := minf(requested, available.size.y - 16.0)
	box.position = Vector2(64, available.position.y + maxf(8.0, (available.size.y - height) * 0.5))
	box.size.y = height
	if modal.has_meta("modal_requested_width"):
		box.size.x = minf(float(modal.get_meta("modal_requested_width")), available.size.x - 16.0)
		box.position.x = available.position.x + (available.size.x - box.size.x) * 0.5
	if modal.has_meta("settlement_hand"):
		_layout_settlement(available, box, height)

func _layout_settlement(available: Rect2, box: Control, height: float) -> void:
	height = minf(height, float(modal.get_meta("settlement_max_height")))
	box.size.y = height
	box.position.y = available.position.y + maxf(8.0, (available.size.y - height) * 0.5)
	var scroll := box.get_node("SettlementScroll") as ScrollContainer
	scroll.size.y = maxf(1.0, height - 418)
	box.get_node("SettlementFooter").position.y = height - 96

func _confirm_allin() -> void:
	var box := _open_modal(words("全下", "ALL IN"))
	_label(box, words("把剩余筹码全部推入底池？", "PUT YOUR REMAINING STACK IN?"), Rect2(40, 125, 1228, 64), 30)
	_label(box, words("确认后不能撤回。", "THIS ACTION CANNOT BE UNDONE."), Rect2(40, 200, 730, 50), 24, MUTED)
	_button(box, words("确认 ALL IN", "CONFIRM ALL IN"), Rect2(40, 340, 1228, 96), func(): _act("all_in"), CORAL)

func _confirm_leave() -> void:
	var box := _open_modal(words("离开牌桌", "LEAVE TABLE"))
	_label(box, words("离桌会中断当前牌局。", "LEAVING INTERRUPTS THIS TABLE."), Rect2(40, 130, 1228, 60), 30)
	_button(box, words("确认离开", "LEAVE TABLE"), Rect2(40, 340, 1228, 96), _leave_to_home, CORAL)

func _leave_to_home() -> void:
	transition_id += 1
	_cancel_table_entry()
	_entered_room = ""
	_cancel_presentation()
	_presented_revision = -1
	input_locked = false
	discovery.stop_host()
	discovery.stop_search()
	_joining = false
	session.leave_game()
	lobby.hide()
	shown_state = {}
	_set_visible_deck(preferred_deck_theme)
	previous_hand = -1
	previous_board = 0
	previous_phase = ""
	_close_modal()
	table.hide()
	home.show()
	toast_label.text = ""
	_layout()

func _handle_back() -> void:
	if is_instance_valid(manual_panel):
		manual_panel.cancel()
		return
	if not is_instance_valid(home): return
	if is_instance_valid(modal):
		_close_modal()
	elif is_instance_valid(lobby) and lobby.visible:
		_leave_to_home()
	elif is_instance_valid(table) and table.visible:
		_show_settings()
	else:
		_confirm_exit()

func _confirm_exit() -> void:
	var box := _open_modal(words("暂别夜河？", "LEAVE THE NIGHT?"))
	modal.name = "ExitConfirmation"
	_label(box, words("是否退出游戏？", "EXIT NEON POT?"), Rect2(40, 138, 1228, 64), 32)
	_button(box, words("继续夜色", "STAY A WHILE"), Rect2(40, 340, 596, 96), _close_modal)
	_button(box, words("退出游戏", "EXIT GAME"), Rect2(672, 340, 596, 96), _exit_game, CORAL)

func _exit_game() -> void:
	if _exit_pending: return
	_exit_pending = true
	_cancel_table_entry()
	_cancel_home_entrance()
	_cancel_presentation()
	music.shutdown()
	feedback.haptics.stop()
	# Let the audio mixer release its streaming playback before engine teardown.
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_back()
		get_viewport().set_input_as_handled()
func _open_modal(title: String, height: float = 500, width: float = 1312) -> Panel:
	_close_manual_chips()
	_clear_fidgets()
	chip_display.cancel_flourish()
	_cancel_home_entrance()
	_cancel_table_props()
	_close_modal()
	_reset_board_gestures()
	_hide_private_cards()
	modal = Control.new()
	modal.z_index = 40
	modal.size = canvas.size
	modal.set_meta("modal_requested_height", height)
	if width != 1312: modal.set_meta("modal_requested_width", width)
	canvas.add_child(modal)
	modal.focus_mode = Control.FOCUS_ALL
	modal.grab_focus()
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.018, 0.048, 0.90)
	shade.size = canvas.size
	modal.add_child(shade)
	var box_y := (canvas.size.y - height) * 0.5
	if mixflip_outer_profile.get("full", false):
		var play: Rect2 = mixflip_outer_profile.interactive_rect
		box_y = play.position.y + maxf(0.0, (play.size.y - height) * 0.5)
	var box := _panel(modal, Rect2((canvas.size.x - width) * 0.5, box_y, width, height), Color("1c1b2e"), Color("725474"), 18)
	box.set_meta("main_modal_panel", true)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(box, title, Rect2(34, 4, width - 182, 70 if width < 800 else 86), 28 if width < 800 else 36)
	_button(box, "×", Rect2(width - 96, 8, 72, 60) if width < 800 else Rect2(width - 122, 0, 96, 88), _close_modal)
	_layout_active_modal()
	modal.modulate.a = 0.0
	_modal_fade = modal.create_tween()
	_modal_fade.tween_property(modal, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return box

func _close_modal() -> void:
	if _modal_fade and _modal_fade.is_valid(): _modal_fade.kill()
	_modal_fade = null
	var had_modal := is_instance_valid(modal)
	if _joining:
		_joining = false
		session.leave_game()
	if is_instance_valid(_search_modal) and _search_modal == modal:
		discovery.stop_search()
		_search_modal = null
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null
	if had_modal and not _home_return_queued:
		_home_return_queued = true
		_return_home_if_uncovered.call_deferred()
	if is_instance_valid(deal_button): _update_presentation_controls()

func _show_settings() -> void:
	var box := _open_modal(words("设置", "SETTINGS"), 616)
	_button(box, words("纸牌展廊", "CARD GALLERY"), Rect2(374, 0, 252, 88), _show_deck_gallery)
	_button(box, words("关于", "ABOUT"), Rect2(640, 0, 172, 88), _show_about)
	_button(box, words("游戏", "GAME"), Rect2(826, 0, 198, 88), _show_play_settings)
	sfx_slider = _setting_slider(box, words("音效", "SOUND EFFECTS"), feedback.volume, Vector2(36, 110), func(value: float):
		feedback.volume = value / 10.0
		_preview_setting()
		_save_settings())
	music_slider = _setting_slider(box, words("背景音乐", "MUSIC"), music.level / 10.0, Vector2(36, 254), func(value: float):
		music.set_level(int(value))
		_preview_setting()
		_save_settings())
	haptic_slider = _setting_slider(box, words("震动", "HAPTICS"), feedback.haptic_strength, Vector2(666, 110), func(value: float):
		feedback.haptic_strength = value / 10.0
		_preview_setting()
		_save_settings())
	_label(box, "LANGUAGE / 语言", Rect2(666, 254, 600, 44), 28, MUTED)
	_button(box, "简体中文", Rect2(666, 310, 290, 88), func(): _change_language("zh"), Color("61445f") if language == "zh" else PANEL)
	_button(box, "ENGLISH", Rect2(972, 310, 290, 88), func(): _change_language("en"), Color("61445f") if language == "en" else PANEL)
	var deck := PixelPlayer.new()
	deck.music = music
	deck.position = Vector2(36, 390)
	deck.size = Vector2(596, 200)
	box.add_child(deck)
	deck.operated.connect(func(): feedback.play("touch"); _save_settings())
	music_title = deck.title_label
	music_pause_button = deck.pause_button
	var shared := CheckButton.new()
	shared.text = words("发牌与下注公共音效", "DEAL & BET TABLE SOUNDS")
	shared.position = Vector2(666, 420)
	shared.size = Vector2(600, 96)
	shared.add_theme_font_size_override("font_size", 26)
	shared.button_pressed = feedback.public_audio
	shared.toggled.connect(func(value: bool): feedback.public_audio = value; _save_settings())
	box.add_child(shared)
	_button(box, words("牌面工坊", "DECK WORKSHOP"), Rect2(666, 526, 290, 64), _show_deck_workshop)
	_button(box, words("导入音乐", "IMPORT MUSIC"), Rect2(972, 526, 290, 64), _show_music_library)
	_button(box, words("离桌", "LEAVE"), Rect2(1038, 0, 138, 88), _confirm_leave).visible = not shown_state.is_empty()
	_refresh_music_controls()

func _set_visible_deck(value: int) -> void:
	var clean := DeckThemes.valid_id(value)
	if DeckThemes.active_id == clean: return
	DeckThemes.active_id = clean
	if is_inside_tree(): get_tree().call_group("poker_cards", "queue_redraw")

func _can_choose_deck() -> bool:
	return not _joining and not shown_state.get("paused", false) and (shown_state.is_empty() or session.is_host or session.is_local)

func _show_deck_gallery() -> void:
	_clear_fidgets()
	_close_modal()
	_reset_board_gestures()
	_hide_private_cards()
	_cancel_home_entrance()
	_cancel_table_props()
	deck_gallery = DeckGallery.new()
	deck_gallery.language = language
	deck_gallery.selected_theme = DeckThemes.active_id
	deck_gallery.can_apply = _can_choose_deck()
	deck_gallery.size = canvas.size
	modal = deck_gallery
	modal.set_meta("fullscreen_modal", true)
	canvas.add_child(modal)
	modal.focus_mode = Control.FOCUS_ALL
	modal.grab_focus()
	deck_gallery.closed.connect(_show_settings)
	deck_gallery.contact.connect(func(): feedback.play("touch"))
	deck_gallery.theme_selected.connect(_choose_deck)
	_layout_active_modal()

func _choose_deck(value: int) -> void:
	if not _can_choose_deck() or value < 0 or value >= DeckThemes.COUNT: return
	if not session.set_deck_theme(value): return
	DeckThemes.custom_recipe = {}
	get_tree().call_group("poker_cards", "queue_redraw")
	preferred_deck_theme = value
	_set_visible_deck(value)
	if is_instance_valid(deck_gallery): deck_gallery.selected_theme = value
	_save_settings()

func _open_personal_panel(panel: Control) -> void:
	_clear_fidgets()
	_close_modal()
	_reset_board_gestures()
	_hide_private_cards()
	_cancel_home_entrance()
	_cancel_table_props()
	panel.language = language
	panel.size = canvas.size
	modal = panel
	modal.set_meta("fullscreen_modal", true)
	canvas.add_child(panel)
	panel.focus_mode = Control.FOCUS_ALL
	panel.grab_focus()
	panel.closed.connect(_show_settings)
	_layout_active_modal()

func _show_deck_workshop() -> void:
	var workshop := DeckWorkshop.new()
	workshop.recipe = DeckThemes.custom_recipe.duplicate(true)
	workshop.recipe_applied.connect(_apply_custom_deck)
	_open_personal_panel(workshop)

func _apply_custom_deck(recipe: Dictionary) -> void:
	DeckThemes.custom_recipe = DeckThemes.sanitize_recipe(recipe)
	get_tree().call_group("poker_cards", "queue_redraw")
	_save_settings()
	if is_instance_valid(modal) and modal is DeckWorkshop:
		_show_settings()

func _show_music_library() -> void:
	var library := MusicLibrary.new()
	library.music = music
	library.operated.connect(_save_settings)
	_open_personal_panel(library)

func _show_about() -> void:
	_close_modal()
	_reset_board_gestures()
	_hide_private_cards()
	_cancel_home_entrance()
	_cancel_table_props()
	var about := AboutView.new()
	about.language = language
	about.size = canvas.size
	modal = about
	modal.set_meta("fullscreen_modal", true)
	canvas.add_child(about)
	about.closed.connect(_show_settings)
	_layout_active_modal()

func _show_play_settings() -> void:
	var box := _open_modal(words("游戏体验", "GAME EXPERIENCE"), 616)
	ai_slider = _setting_slider(box, words("AI 激进度 · 保守 → 激进", "AI AGGRESSION · CALM → BOLD"), session.ai_aggression / 10.0, Vector2(36, 108), func(value: float):
		session.set_ai_aggression(int(value))
		feedback.play("touch")
		_save_settings())
	ai_slider.size.x = 1228
	_label(box, words("AI 不会偷看底牌；联机 AI 在大厅单独调整。", "AI CANNOT SEE YOUR CARDS. CONFIGURE LAN BOTS IN THE LOBBY."), Rect2(38, 220, 1230, 44), 24, MUTED)
	_label(box, words("游戏速度 · 发牌与筹码动效", "PACE · DEALING & CHIP ANIMATIONS"), Rect2(38, 274, 1230, 44), 28, GOLD)
	var speeds := [0.25, 0.5, 1.0, 1.5, 2.0]
	for i in speeds.size():
		var rate: float = speeds[i]
		_button(box, ["0.25×", "0.5×", "1×", "1.5×", "2×"][i], Rect2(38 + i * 250, 326, 230, 76), func():
			Timing.rate = rate
			feedback.play("touch")
			_save_settings()
			_show_play_settings(), Color("61445f") if is_equal_approx(Timing.rate, rate) else PANEL)
	_label(box, words("帧率上限 · 默认 60", "FRAME LIMIT · DEFAULT 60"), Rect2(38, 430, 1230, 44), 28, GOLD)
	for i in 3:
		var limit: int = [30, 60, 120][i]
		_button(box, str(limit) + " FPS", Rect2(38 + i * 416, 486, 396, 88), func():
			frame_limit = limit
			Engine.max_fps = limit
			feedback.play("touch")
			_save_settings()
			_show_play_settings(), Color("61445f") if frame_limit == limit else PANEL)

func _setting_slider(parent: Node, title: String, value: float, at: Vector2, callback: Callable) -> Range:
	var slider := TouchSlider.new()
	slider.position = at
	slider.size = Vector2(596, 112)
	slider.caption = title
	slider.notches = true
	slider.min_value = 0
	slider.max_value = 10
	slider.step = 1
	slider.value = roundi(value * 10)
	slider.user_changed.connect(callback)
	parent.add_child(slider)
	return slider

func _preview_setting() -> void:
	feedback.preview_sound()
	feedback.preview_haptics()

func _refresh_music_controls() -> void:
	if is_instance_valid(music_title):
		music_title.text = music.title() if not music.tracks.is_empty() else words("BGM 目录暂无音乐", "NO TRACKS IN BGM")
	if is_instance_valid(music_pause_button):
		music_pause_button.glyph = "play" if music.paused else "pause"
		music_pause_button.queue_redraw()
		music_pause_button.disabled = music.tracks.is_empty()

func _show_exact_raise() -> void:
	if not amount_input.editable: return
	var context := _chip_context(shown_state)
	var box := _open_modal(words("精确加注至", "EXACT RAISE TO"), 408, 584)
	var edit := ExactRaisePanel.new()
	edit.name = "ExactRaiseEditor"
	edit.configure(int(amount_input.value), int(amount_input.min_value), int(amount_input.max_value), language)
	edit.position = Vector2(32, 80)
	edit.size = Vector2(520, 300)
	box.add_child(edit)
	edit.cancel_requested.connect(_close_modal)
	edit.accepted.connect(func(amount: int):
		if context == _chip_context(shown_state) and amount_input.editable:
			amount_input.value = clampi(amount, int(amount_input.min_value), int(amount_input.max_value))
		_close_modal())

func _request_chip_gesture() -> void:
	if not presentation_busy and not input_locked and not is_instance_valid(modal):
		session.request_chip_gesture()

func _request_board_gesture(index: int, kind: String, offset: Vector2) -> void:
	if kind == "release" or (not input_locked and not is_instance_valid(modal) and _application_active):
		session.request_board_gesture(index, kind, offset)

func _reset_board_gestures() -> void:
	for card in board_cards:
		if is_instance_valid(card): card.reset_public_gesture()
	_board_contact_offsets.clear()
	_board_contact_times.clear()

func _on_board_gesture(seat: int, _sequence: int, index: int, kind: String, offset: Vector2) -> void:
	if index < 0 or index >= board_cards.size() or not is_instance_valid(board_cards[index]): return
	if not _application_active or is_instance_valid(modal) or shown_state.get("paused", false) or shown_state.get("phase", "lobby") == "lobby":
		board_cards[index].reset_public_gesture()
		_board_contact_offsets.erase(index)
		_board_contact_times.erase(index)
		return
	board_cards[index].apply_public_gesture(kind, offset)
	var now := Time.get_ticks_msec()
	var contact := kind != "drag"
	if kind == "drag":
		var previous: Vector2 = _board_contact_offsets.get(index, offset)
		contact = offset.distance_to(previous) >= 0.18 and now - int(_board_contact_times.get(index, 0)) >= 90
	if contact:
		_board_contact_offsets[index] = offset
		_board_contact_times[index] = now
		if _application_active and not is_instance_valid(modal) and not shown_state.get("paused", false):
			feedback.play_card_contact({"press": "touch", "drag": "swipe", "release": "release"}.get(kind, "touch"), seat != int(shown_state.get("you", -1)))
	if kind == "release":
		_board_contact_offsets.erase(index)
		_board_contact_times.erase(index)

func _on_chip_gesture(seat: int, _sequence: int, style: int = 0) -> void:
	if not _application_active or is_instance_valid(modal) or input_locked or _table_entering: return
	if not _application_active or shown_state.is_empty() or shown_state.get("paused", false) or not ChipGestures.is_valid_style(style): return
	var players: Array = shown_state.get("players", [])
	if seat < 0 or seat >= players.size() or int(players[seat].stack) <= 0: return
	if seat == int(shown_state.get("you", -1)):
		chip_display.flourish(style)
		feedback.play("touch")
	else:
		if _fidget_nodes.has(seat) and is_instance_valid(_fidget_nodes[seat]):
			_fidget_nodes[seat].queue_free()
		var pile := Chips.new()
		pile.size = Vector2(246, 174)
		pile.position = _seat_position(seat) - Vector2(123, 30)
		flight_layer.add_child(pile)
		if players[seat].has("chips"): pile.set_inventory(players[seat].chips, false)
		else: pile.set_amount(int(players[seat].stack), false)
		pile.contact.connect(func(kind: String):
			if _application_active and not is_instance_valid(modal): feedback.play_chip_contact(kind, false, 0.3))
		pile.flourish(style)
		_fidget_nodes[seat] = pile
		var tween := pile.create_tween()
		tween.tween_interval(ChipGestures.duration(style) + 0.03)
		tween.tween_property(pile, "modulate:a", 0.0, 0.18)
		tween.tween_callback(pile.queue_free)
	_record_event("fidget", seat)

func _clear_fidgets() -> void:
	for pile in _fidget_nodes.values():
		if is_instance_valid(pile): pile.queue_free()
	_fidget_nodes.clear()

func _change_language(value: String) -> void:
	language = value
	_save_settings()
	_settings_after_rebuild = presentation_busy or _table_entering
	_build_ui()
	_show_settings()

func _show_reference() -> void:
	var box := _open_modal(words("牌型大小 · 从大到小", "HAND RANKINGS · HIGH TO LOW"), 616)
	var rows := [
		["皇家同花顺", "ROYAL FLUSH", "A K Q J 10", "♠ ♠ ♠ ♠ ♠"],
		["同花顺", "STRAIGHT FLUSH", "9 8 7 6 5", "♥ ♥ ♥ ♥ ♥"],
		["四条", "FOUR OF A KIND", "K K K K 3", "♠ ♥ ♦ ♣ ♠"],
		["葫芦", "FULL HOUSE", "Q Q Q 8 8", "♠ ♥ ♦ ♣ ♥"],
		["同花", "FLUSH", "A J 8 6 2", "♣ ♣ ♣ ♣ ♣"],
		["顺子", "STRAIGHT", "8 7 6 5 4", "♠ ♥ ♣ ♦ ♠"],
		["三条", "THREE OF A KIND", "7 7 7 K 2", "♠ ♥ ♦ ♣ ♠"],
		["两对", "TWO PAIR", "J J 4 4 A", "♠ ♥ ♣ ♦ ♠"],
		["一对", "ONE PAIR", "10 10 K 8 3", "♠ ♥ ♣ ♦ ♠"],
		["高牌", "HIGH CARD", "A J 8 5 2", "♠ ♥ ♣ ♦ ♠"]]
	for i in range(rows.size()):
		var x := 30.0 + (i / 5) * 634
		var y := 103.0 + (i % 5) * 78
		_panel(box, Rect2(x, y, 616, 72), Color("242238") if i % 2 == 0 else Color("1c1b2e"), Color.TRANSPARENT, 8)
		_label(box, "%02d" % (i + 1), Rect2(x + 10, y, 56, 72), 26, GOLD)
		_label(box, words(rows[i][0], rows[i][1]), Rect2(x + 74, y, 305, 72), 26)
		_label(box, rows[i][2], Rect2(x + 390, y + 1, 220, 38), 26, INK)
		_label(box, rows[i][3], Rect2(x + 390, y + 36, 220, 32), 24, GOLD)
	_label(box, words("同类比点数，再比踢脚牌；花色不分大小。\nA2345 是最小顺子，最终选最佳五张。", "RANKS, THEN KICKERS. SUITS ARE EQUAL.\nA2345 IS LOW. BEST FIVE CARDS PLAY."), Rect2(38, 505, 636, 100), 22, MUTED)
	_button(box, words("新手教学  →", "HOW TO PLAY  →"), Rect2(712, 511, 560, 88), _show_tutorial, Color("394963"))

func _show_tutorial() -> void:
	_close_modal()
	_hide_private_cards()
	modal = Tutorial.new()
	modal.language = language
	modal.size = canvas.size
	modal.set_meta("fullscreen_modal", true)
	canvas.add_child(modal)
	modal.closed.connect(_show_reference)
	_layout_active_modal()

func _result_text(state: Dictionary) -> String:
	var parts: Array[String] = []
	var players: Array = state.get("players", [])
	for award in state.get("result", []):
		var seat: int = award.get("seat", -1)
		if seat >= 0 and seat < players.size():
			parts.append(str(players[seat].get("name", "")) + " +" + str(award.get("amount", 0)))
	return "  /  ".join(parts)

func _status(message: String) -> void:
	_manual_exchange_pending = false
	_manual_flight_context = ""
	if is_instance_valid(manual_panel) and manual_panel.has_method("unlock_submission"): manual_panel.unlock_submission()
	if not is_instance_valid(toast_label):
		return
	var translations := {
		"Room discovery port is unavailable. Please retry.": "搜索服务端口暂不可用，请重试。",
		"Could not open room search. Check Wi-Fi and retry.": "无法搜索牌桌，请检查 Wi-Fi 后重试。",
		"Search could not send. Check Wi-Fi and retry.": "搜索未能发出，请检查 Wi-Fi 后重试。",
		"Could not initialize room search.": "搜索初始化失败，请重试。",
		"Invalid room discovery metadata.": "牌桌信息暂不可用，请重新创建。",
		"Invalid name, starting chips, or port.": "请检查名字、初始筹码或端口。",
		"Invalid solo name, chips, or player count.": "请检查名字、筹码和单人桌人数。",
		"Invalid address, name, or port.": "请检查地址、名字或端口。",
		"Use 2–6 players and 100–1,000,000 chips.": "请设置 2–6 人，每人 100–1,000,000 筹码。",
		"Names must contain 1–24 printable characters.": "名字需为 1–24 个可显示字符。",
		"Table paused. Create a new room to continue.": "牌局已暂停，请重新创建牌桌。",
		"Connection failed. Check LAN IP, Wi-Fi, and host firewall.": "连接失败，请检查局域网 IP、Wi-Fi 与房主防火墙。",
		"Host disconnected. Table paused; create a new room to continue.": "房主已断线，牌局暂停；请重新创建牌桌。",
		"A player disconnected. Table paused; create a new room to continue.": "有玩家断线，牌局暂停；请重新创建牌桌。",
		"This table has already started. Ask the host to create a new room.": "本桌已开始，请让房主重新建桌后加入。",
		"Room full or invalid player name.": "牌桌已满或玩家名字无效。",
		"Action expired; use the current table state.": "该操作已过期，请按最新牌桌状态操作。",
		"Invalid action.": "无效操作。",
		"A hand is already in progress.": "当前正在进行一手牌。",
		"Use 2 to 6 seats.": "请设置 2–6 个座位。",
		"Starting stack is out of range.": "初始筹码超出范围。",
		"Invalid blinds.": "盲注设置无效。",
		"Every seat needs a name.": "每个座位都需要名字。",
		"Finish the current hand first.": "请先完成当前这手牌。",
		"At least two players need chips. Start a new session to reset stacks.": "至少两人需要有筹码；请新开一场，重新均分筹码。",
		"Secure random source is unavailable.": "安全随机源不可用，未发牌。",
		"It is not this seat's turn.": "还没轮到这个座位。",
		"This action is not legal now.": "现在不能进行该操作。",
		"Raise-to amount is outside the legal range.": "加注金额不在允许的范围内。",
		"Room open. Friends can find it in Local Tables.": "牌桌已创建，朋友可在本地牌桌列表找到你。",
		"Connecting to room...": "正在连接牌桌……",
		"Solo table ready. You play against computer opponents.": "单人牌桌已就绪，点击开始发牌。",
		"Could not host: check the port and firewall.": "创建失败：请检查端口和防火墙。",
		"Could not connect to this address.": "无法连接该地址。",
		"Only the host can deal, with at least two connected players.": "至少两人入座后，由房主发牌。"}
	toast_label.text = translations.get(message, message) if language == "zh" else message
	if _joining and is_instance_valid(_join_message):
		_join_message.text = toast_label.text
		if message != "Connecting to room...": _fail_join()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("preferences", "language", language)
	config.set_value("preferences", "deck_theme", preferred_deck_theme)
	config.set_value("preferences", "custom_deck", DeckThemes.custom_recipe)
	config.set_value("preferences", "frame_limit", frame_limit)
	config.set_value("preferences", "animation_rate", Timing.rate)
	config.set_value("preferences", "volume", feedback.volume)
	config.set_value("preferences", "haptics", feedback.haptic_strength)
	config.set_value("preferences", "public_audio", feedback.public_audio)
	config.set_value("music", "level", music.level)
	config.set_value("music", "paused", music.paused)
	config.set_value("music", "index", music.index)
	config.set_value("music", "neon_defaults", true)
	config.set_value("solo", "aggression", session.ai_aggression)
	config.save(settings_path)

func _load_settings() -> void:
	Timing.rate = 1.0
	DeckThemes.custom_recipe = {}
	frame_limit = 60
	language = "en"
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var saved_limit := int(config.get_value("preferences", "frame_limit", 60))
		frame_limit = saved_limit if saved_limit in [30, 60, 120] else 60
		var saved_rate := float(config.get_value("preferences", "animation_rate", 1.0))
		Timing.rate = saved_rate if saved_rate in [0.25, 0.5, 1.0, 1.5, 2.0] else 1.0
		preferred_deck_theme = DeckThemes.valid_id(int(config.get_value("preferences", "deck_theme", 3)))
		DeckThemes.custom_recipe = DeckThemes.sanitize_recipe(config.get_value("preferences", "custom_deck", {}))
		var saved_language := str(config.get_value("preferences", "language", "en"))
		language = saved_language if saved_language in ["zh", "en"] else "en"
		feedback.volume = roundf(clampf(float(config.get_value("preferences", "volume", 0.7)), 0, 1) * 10) / 10.0
		feedback.haptic_strength = roundf(clampf(float(config.get_value("preferences", "haptics", 0.7)), 0, 1) * 10) / 10.0
		feedback.public_audio = bool(config.get_value("preferences", "public_audio", true))
		music.set_level(int(config.get_value("music", "level", 3)))
		music.set_paused(bool(config.get_value("music", "paused", false)))
		music.select_track(int(config.get_value("music", "index", Music.DEFAULT_TRACK)) if bool(config.get_value("music", "neon_defaults", false)) else Music.DEFAULT_TRACK)
		session.set_ai_aggression(int(config.get_value("solo", "aggression", 6)))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_application_active = false
		_close_manual_chips()
		if is_instance_valid(chip_touch): chip_touch.cancel_hold()
		_clear_fidgets()
		_cancel_home_entrance()
		_cancel_table_props()
		_solo_delay = 0.0
		_reset_board_gestures()
		_hide_private_cards()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_application_active = true
		if is_instance_valid(deal_button): _update_presentation_controls()
		_queue_stable_layout()

func _hide_private_cards() -> void:
	if shown_state.get("phase", "") == "showdown":
		return
	for card in own_cards:
		if is_instance_valid(card):
			card.flip(false)

func _capture() -> void:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	get_viewport().get_texture().get_image().save_png("res://artifacts/table.png" if "--demo" in OS.get_cmdline_user_args() else "res://artifacts/home.png")
	print("CAPTURE_OK")
	get_tree().quit()

func _chip_context(state: Dictionary) -> String:
	return "%s:%s:%s:%s" % [state.get("room_id", ""), state.get("hand_id", -1), state.get("revision", -1), state.get("you", -1)]

func _chip_hold_progress(progress: float) -> void:
	if not is_instance_valid(chip_display): return
	chip_display.pivot_offset = chip_display.size * 0.5
	chip_display.scale = Vector2.ONE * (1.0 + sin(progress * PI * 0.72) * 0.12)
	if progress <= 0:
		_hold_haptic_step = -1
		return
	var step_index := int(progress * 5)
	if step_index > _hold_haptic_step:
		_hold_haptic_step = step_index
		if feedback.haptic_strength > 0 and _application_active:
			feedback.haptics.pulse("touch", feedback.haptic_strength * lerpf(0.12, 0.65, progress))

func _open_manual_chips() -> void:
	if is_instance_valid(manual_panel) or not _application_active or presentation_busy or input_locked or is_instance_valid(modal): return
	var state: Dictionary = shown_state
	var you := int(state.get("you", -1))
	if you < 0 or you != int(state.get("actor", -2)) or state.get("paused", false): return
	var legal: Dictionary = state.get("legal", {})
	if not legal.get("raise", false) and not legal.get("all_in", false): return
	var own: Dictionary = state.players[you]
	chip_display.cancel_flourish()
	chip_display.scale = Vector2.ONE
	_reset_board_gestures()
	_hide_private_cards()
	feedback.play_chip_contact("confirm", false, 0.75)
	_manual_context = _chip_context(state)
	_manual_window_size = get_viewport_rect().size
	manual_panel = ManualChipPanel.new()
	manual_panel.z_index = 20
	manual_panel.configure({"controls_top": minf(amount_input.position.y, own_panel.position.y), "inventory": own.get("chips", {}), "street_bet": int(own.get("bet", 0)), "min_raise_to": int(legal.get("min_raise_to", 0)), "max_raise_to": int(own.get("bet", 0)) + int(own.get("stack", 0)), "current_bet": int(state.get("current_bet", 0)), "can_raise": legal.get("raise", false), "can_all_in": legal.get("all_in", false), "language": language, "feedback": feedback})
	table.add_child(manual_panel)
	manual_panel.confirmed.connect(func(_action: String, _total: int, counts: Dictionary):
		if _manual_context != _chip_context(shown_state):
			_close_manual_chips()
			return
		_manual_flight_origin = manual_panel.get_staging_position() if manual_panel.has_method("get_staging_position") else _pot_position() + Vector2(-150, 90)
		_manual_flight_context = _manual_context
		session.submit_chip_action(counts))
	manual_panel.cancelled.connect(func():
		manual_panel = null
		_update_presentation_controls())
	manual_panel.exchange_requested.connect(func(reserved: Dictionary):
		_manual_exchange_pending = true
		session.exchange_chips(reserved))
	manual_panel.open(Rect2(chip_display.position, chip_display.size), _pot_position())
	_update_presentation_controls()

func _close_manual_chips() -> void:
	_manual_exchange_pending = false
	if is_instance_valid(manual_panel):
		manual_panel.close()
		manual_panel = null
	if is_instance_valid(chip_display): chip_display.scale = Vector2.ONE

func _update_bet_magnets(state: Dictionary) -> void:
	var data: Dictionary = state.get("legal", {}).duplicate()
	data["street"] = state.get("phase", "preflop")
	data["pot"] = int(state.get("pot", 0))
	data["current_bet"] = int(state.get("current_bet", 0))
	data["big_blind"] = int(state.get("big_blind", 10))
	var you := int(state.get("you", -1))
	data["street_bet"] = int(state.players[you].get("bet", 0)) if you >= 0 and you < state.get("players", []).size() else 0
	amount_input.set_magnets(BetSizing.magnets(data))

func _transfer_chips(state: Dictionary, seat: int, kind: String) -> Dictionary:
	var result := {}
	for transfer in state.get("chip_transfers", []):
		if int(transfer.get("seat", -1)) == seat and transfer.get("kind", "") == kind:
			result = ChipInventory.add(result, transfer.get("chips", {}))
	return result

func _pot_before_payout(state: Dictionary) -> Dictionary:
	if state.get("phase", "") == "showdown":
		if state.has("settlement_pot_chips"): return state.settlement_pot_chips.duplicate(true)
		var result := {}
		for transfer in state.get("chip_transfers", []):
			if transfer.get("kind", "") == "payout": result = ChipInventory.add(result, transfer.get("chips", {}))
		return result
	return state.get("pot_chips", {}).duplicate(true)

func _render_pot_chips(animate: bool = false) -> void:
	if shown_state.has("pot_chips") or ChipInventory.value(_displayed_pot_chips) == _displayed_pot:
		pot_display.set_inventory(_displayed_pot_chips, animate)
	else:
		pot_display.set_amount(_displayed_pot, animate) # Legacy fixture snapshots lack inventories.

func _set_player_chips(view: Control, state: Dictionary, seat: int, animate: bool = false) -> void:
	var players: Array = state.get("players", [])
	if seat < 0 or seat >= players.size():
		view.set_inventory({}, false)
		return
	var own: Dictionary = players[seat]
	var chips: Dictionary = own.get("chips", {}).duplicate(true)
	if state.get("phase", "") == "showdown" and _settlement_key != _hand_key(state) and not _paid_awards.has(seat) and not state.get("paused", false):
		var award := _transfer_chips(state, seat, "payout")
		if ChipInventory.contains(chips, award): chips = ChipInventory.subtract(chips, award)
	if int(_unlanded_refunds.get(seat, 0)) > 0:
		var refund := _transfer_chips(state, seat, "refund")
		if ChipInventory.contains(chips, refund): chips = ChipInventory.subtract(chips, refund)
	if own.has("chips"): view.set_inventory(chips, animate)
	else: view.set_amount(_visual_stack(state, seat), animate)
