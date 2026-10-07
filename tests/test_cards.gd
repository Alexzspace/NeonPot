extends SceneTree

const Card = preload("res://scripts/card_view.gd")
var checks := 0
var failures := 0
var events: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	if "--gallery" in OS.get_cmdline_user_args():
		await _gallery()
		return
	var card := Card.new()
	card.set_card(51, false)
	card.deal(0.01)
	card.interactive = true
	card.size = Vector2(132, 184)
	card.position = Vector2(20, 20)
	card.touched.connect(func(kind: String) -> void: events.append(kind))
	root.add_child(card)
	await process_frame
	check(card.card_id == 51 and not card.face_up, "Pre-ready set_card preserves private state")
	check(Card.CORNER_PIP_PIXEL * 7.0 >= 22.4 and Card.NUMBER_PIP_PIXEL > 3.0 and Card.ACE_PIP_PIXEL > 7.2,
		"corner, ordinary number, and ace suit marks are enlarged")
	var corner_extent := Vector2.ONE * Card.CORNER_PIP_PIXEL * 7.0
	var corner_rects := [Rect2(Vector2(-49, -43) - corner_extent * 0.5, corner_extent), Rect2(Vector2(49, 43) - corner_extent * 0.5, corner_extent)]
	for rank in range(2, 11):
		var positions := card._number_pip_positions(rank)
		check(positions.size() == rank, "number card %d retains exact pip count" % rank)
		var pixel: float = Card.DENSE_PIP_PIXEL if rank >= 9 else Card.NUMBER_PIP_PIXEL
		var extent := Vector2.ONE * pixel * 7.0
		var bounds: Array[Rect2] = []
		for position in positions:
			var pip_rect := Rect2(position - extent * 0.5, extent)
			check(Rect2(-62, -88, 124, 176).encloses(pip_rect), "pip fits printed face")
			for corner in corner_rects:
				check(not corner.intersects(pip_rect), "number pips do not overlap either corner suit")
			for previous in bounds:
				check(not previous.intersects(pip_rect), "enlarged number pips have disjoint bounds, including ten")
			bounds.append(pip_rect)
	for corner in corner_rects:
		check(Rect2(-62, -88, 124, 176).encloses(corner), "larger corner suit stays inside paper border")
		check(not corner.intersects(Rect2(-61, -86, 28, 25)) and not corner.intersects(Rect2(33, 61, 28, 25)), "corner suit avoids both rank numbers")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(50, 80)
	card._gui_input(press)
	check(card._peeking and not card.face_up, "Touch reveals temporarily without mutating face_up")
	check(events == ["touch"], "One touch signal")
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.pressed = true
	card._gui_input(second)
	check(events.size() == 1, "Second finger does not duplicate or steal touch")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.relative = Vector2(12, 2)
	card._input(drag)
	card._input(drag)
	check(events.count("swipe") == 1, "Swipe feedback emits once per gesture")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(2000, 2000)
	card._input(release)
	check(not card._peeking and events.back() == "release", "Release outside card hides private card")
	card._gui_input(press)
	card.set_card(0, false)
	check(not card._peeking and card._pointer == -2, "Changing private card clears previous peek")
	card.interactive = false
	card.set_card(12, true)
	var count_before := events.size()
	card._gui_input(press)
	check(card.face_up and not card._peeking and events.size() == count_before, "Public cards ignore touches")
	card.interactive = true
	card.set_card(2, false)
	card._gui_input(press)
	card._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not card._peeking, "Focus loss hides private card")
	var old_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	card._gui_input(mouse)
	check(not card._peeking, "Mouse ignored when touch emulation owns mouse input")
	Input.emulate_touch_from_mouse = false
	mouse.position = Vector2(40, 50)
	card._gui_input(mouse)
	check(card._peeking, "Direct mouse press supported when emulation off")
	mouse.pressed = false
	card._input(mouse)
	check(not card._peeking, "Direct mouse release hides private card")
	Input.emulate_touch_from_mouse = old_emulation
	card.flip(true)
	await create_timer(0.65).timeout
	check(card.face_up and is_equal_approx(card._flip_width, 1.0), "Flip animation completes")
	check(is_equal_approx(card._deal_alpha, 1.0) and card._deal_offset.is_zero_approx(), "Deal animation completes")
	card.set_card(30, false)
	root.push_input(press, true)
	await process_frame
	check(card._peeking, "Real viewport touch dispatch reaches private card")
	root.push_input(release, true)
	await process_frame
	check(not card._peeking, "Real viewport dispatch releases outside bounds")
	for id in range(52):
		card.set_card(id, true)
		await process_frame
	check(card.card_id == 51, "All 52 front faces render without errors")
	card.set_card(52, true)
	check(card.card_id == -1, "Invalid card id safely becomes a back")
	card.queue_free()
	await process_frame
	print("CARDS_TEST_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _gallery() -> void:
	root.size = Vector2i(1000, 620)
	root.content_scale_size = Vector2i(1000, 620)
	var background := ColorRect.new()
	background.color = Color("12383c")
	background.size = Vector2(1000, 620)
	root.add_child(background)
	var ids := [51, 24, 36, 9, 8, -1, 38, 11, 23, 48, 6, -1]
	for i in range(ids.size()):
		var card := Card.new()
		card.size = Vector2(132, 184)
		card.position = Vector2(40 + (i % 6) * 155, 90 + (i / 6) * 240)
		card.set_card(ids[i], ids[i] >= 0)
		root.add_child(card)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var path := "user://cards_preview.png"
	var error := root.get_texture().get_image().save_png(path)
	print("CARD_GALLERY path=%s error=%s" % [ProjectSettings.globalize_path(path), error])
	quit(error)
