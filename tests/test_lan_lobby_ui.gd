extends "res://tests/test_host_lobby.gd"

class LobbyProbe extends Probe:
	var selected_room: Dictionary = {}
	func _join_room(room: Dictionary) -> void:
		selected_room = room.duplicate(true)

func _slider_touch(slider: Control, level: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.position = slider.get_global_transform() * Vector2(30 + (slider.size.x - 60) * level / 10.0, slider.size.y * 0.5)
	touch.pressed = true
	root.push_input(touch, true)
	touch.pressed = false
	root.push_input(touch, true)

func _topbar() -> void:
	for captions in [["设置", "SETTINGS"], ["牌型表", "HANDS"]]:
		var button := _button_with_text(app.canvas, captions)
		check(is_instance_valid(button), "topbar button exists")
		if is_instance_valid(button): _tap(button)
		await process_frame
		check(is_instance_valid(app.modal), "topbar receives touch through full-screen surface")
		if is_instance_valid(app.modal):
			var close := _button_with_text(app.modal, ["×"])
			if is_instance_valid(close): _tap(close)
		await process_frame
		check(not is_instance_valid(app.modal), "modal touch close")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	for locale in ["zh", "en"]:
		app = LobbyProbe.new()
		app.language = locale
		root.add_child(app)
		app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app._set_preview_profile("kpad" if locale == "zh" else "iphone", true)
		await process_frame
		app.set_process(false) # Keep AI from advancing while checking the table controls.
		await _topbar()
		for button in app.find_children("*", "Button", true, false):
			check(not button.is_visible_in_tree() or "F8" not in button.text, "no debug preview entry")
		app.name_edit.text = "测试房主" if locale == "zh" else "Host test"
		app._host()
		await process_frame
		check(app.lobby.is_visible_in_tree(), "host enters dedicated lobby")
		await _topbar()
		for count in range(2):
			_tap(app.lobby.add_button)
			await process_frame
		check(app.shown_state.players.size() == 3, "touch adds two bots")
		check(app.lobby.rows.size() == 3, "bot rows follow state")
		_slider_touch(app.lobby.rows[1].slider, 0)
		_slider_touch(app.lobby.rows[2].slider, 10)
		await process_frame
		check(app.shown_state.players[1].ai_aggression == 0, "first bot passive endpoint")
		check(app.shown_state.players[2].ai_aggression == 10, "second bot aggressive endpoint")
		check(app.lobby.rows[1].slider._finger == -1 and app.lobby.rows[2].slider._finger == -1, "sliders release touch ownership")
		var remove := _button_with_text(app.lobby.rows[1].panel, ["移除", "REMOVE"])
		check(is_instance_valid(remove), "bot removal exposed")
		if is_instance_valid(remove): _tap(remove)
		await process_frame
		check(app.shown_state.players.size() == 2 and app.shown_state.players[1].ai_aggression == 10, "remove preserves remaining bot policy")
		for count in range(4):
			_tap(app.lobby.add_button)
			await process_frame
		check(app.shown_state.players.size() == 6 and app.lobby.add_button.disabled, "six-seat capacity disables add")
		check(not app.lobby.start_button.disabled, "bots satisfy minimum player count")
		for seat in app.lobby.rows.size():
			var row: Dictionary = app.lobby.rows[seat]
			var panel_rect: Rect2 = row.panel.get_global_rect()
			check(app.safe_rect.grow(0.5).encloses(panel_rect), "seat row remains in safe area")
			for other in range(seat + 1, app.lobby.rows.size()):
				check(not panel_rect.intersects(app.lobby.rows[other].panel.get_global_rect()), "seat rows do not overlap")
			if row.has("slider"):
				var remove_button := _button_with_text(row.panel, ["移除", "REMOVE"])
				check(row.slider.size.y >= 80 and remove_button.size.y >= 88, "large AI control targets")
				check(not row.slider.get_global_rect().intersects(remove_button.get_global_rect()), "AI slider and removal targets distinct")
				for control in [row.slider, remove_button]:
					check(panel_rect.grow(0.5).encloses(control.get_global_rect()), "AI control remains inside its row")
					if app.preview_profile == "iphone":
						var height_points: float = control.get_global_rect().size.y * 1206.0 / root.size.y / 3.0
						check(height_points >= 44.0, "AI target at least 44 iPhone points")
		for button in [app.lobby.add_button, app.lobby.leave_button, app.lobby.start_button]:
			var bounds: Rect2 = button.get_global_rect()
			check(app.safe_rect.grow(0.5).encloses(bounds), "lobby action within safe area")
			var status_gap: float = app.toast_label.get_global_rect().position.y - bounds.end.y
			check(status_gap + 0.1 >= 4.0 * app.canvas.scale.y, "footer leaves visible spacing before status text")
			for row in app.lobby.rows:
				check(not bounds.intersects(row.panel.get_global_rect()), "footer actions do not overlap seats")
		for node in app.lobby.find_children("*", "Label", true, false):
			check("UDP" not in node.text and "127.0.0.1" not in node.text, "lobby omits network plumbing")
		check("LAN IP" not in app.toast_label.text, "host status describes automatic discovery")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var screenshot := "res://test-results/lan_lobby_%s.png" % locale
			check(root.get_texture().get_image().save_png(screenshot) == OK, "capture six-seat lobby")
			print("LAN_LOBBY_CAPTURE " + ProjectSettings.globalize_path(screenshot))
		_tap(app.lobby.start_button)
		var deadline := Time.get_ticks_msec() + 20000
		while (app.input_locked or app.presentation_busy) and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not app.input_locked and not app.presentation_busy, "deal completes without lock")
		check(app.table.is_visible_in_tree() and not app.lobby.visible, "deal switches lobby to playing table")
		check(app.shown_state.get("phase", "") == "preflop", "host and bots enter real hand")
		await _topbar()
		app._confirm_leave()
		await process_frame
		_tap(_button_with_text(app.modal, ["确认离开", "LEAVE TABLE"]))
		await process_frame
		check(app.home.visible and not app.lobby.visible and not app.table.visible, "leave restores home")
		check(app.discovery._host_socket == null, "leave releases discovery host socket")
		app._show_room_search()
		app.discovery.stop_search() # Deterministic UI fixture; transport discovery has separate tests.
		app._rooms_changed([])
		check(app.room_list.get_child_count() == 0, "empty discovery has no stale rows")
		var rooms := [
			{"room_id": "one", "host_name": "小米朋友" if locale == "zh" else "A friend's table", "address": "127.0.0.1", "port": 27846, "player_count": 2, "max_players": 6, "joinable": true},
			{"room_id": "two", "host_name": "Full table", "address": "127.0.0.2", "port": 27848, "player_count": 6, "max_players": 6, "joinable": false}]
		app._rooms_changed(rooms)
		await process_frame
		check(app.room_list.get_child_count() == 2, "search renders local table rows")
		var first: Button = app.room_list.get_child(0)
		var full: Button = app.room_list.get_child(1)
		check(not first.disabled and full.disabled, "full room disabled")
		check("127.0.0.1" not in first.text and "27846" not in first.text, "room row shows friendly name")
		_tap(first)
		check(app.selected_room.get("room_id", "") == "one", "touch chooses correct room metadata")
		app._close_modal()
		app.queue_free()
		await process_frame
		await create_timer(0.3).timeout
	print("LAN_LOBBY_UI checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
