extends SceneTree

const Card = preload("res://scripts/public_card.gd")
var checks := 0
var failures := 0
var requests: Array = []
var touched: Array = []

class DrawingProbe extends Card:
	var faces := 0
	var backs := 0
	func _draw_face() -> void:
		faces += 1
		super._draw_face()
	func _draw_back() -> void:
		backs += 1
		super._draw_back()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PUBLIC_CARD: " + message)

func _initialize() -> void: _run.call_deferred()

func _press(card: Control, pointer: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer
	event.pressed = true
	event.position = Vector2(42, 65)
	card._gui_input(event)

func _release(card: Control, pointer: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = pointer
	event.pressed = false
	event.position = Vector2(-500, -500)
	card._input(event)

func _drag(card: Control, position: Vector2, pointer: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = pointer
	event.position = card.get_global_transform_with_canvas() * position
	card._input(event)

func _step(card: Control, count: int = 90) -> void:
	for frame in range(count): card._process(1.0 / 60.0)

func _paper_pixel(pixel: Color) -> bool:
	return pixel.a > 0.5 and pixel.r > 0.65 and pixel.g > 0.60 and pixel.b > 0.50

func _render_rigid_transform() -> void:
	# A rigidly moved ordinary card is an independent oracle for its public twin.
	# Compare paper/outline pixels, excluding the intentionally stronger lift shadow.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var public := Card.new()
	public.theme_id = 3 # This geometry oracle compares the white competition stock.
	public.position = Vector2(64, 48)
	public.size = Card.BASE
	viewport.add_child(public)
	var reference := preload("res://scripts/card_view.gd").new()
	reference.theme_id = 3
	reference.size = Card.BASE
	reference.pivot_offset = Card.BASE * 0.5
	viewport.add_child(reference)
	public.set_process(false)
	reference.set_process(false)
	await process_frame
	for identity in [8, 51]:
		public.show()
		reference.hide()
		public.set_card(identity, true)
		public.apply_public_gesture("press", Vector2(1, -0.5))
		_step(public)
		var center: Vector2 = public.position + public._draw_center()
		var angle: float = public._draw_angle()
		await process_frame
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		public.hide()
		reference.set_card(identity, true)
		reference.position = center - reference.size * 0.5
		reference.rotation = angle
		reference.show()
		await process_frame
		await RenderingServer.frame_post_draw
		var expected := viewport.get_texture().get_image()
		var errors := 0
		var union := 0
		for y in range(300):
			for x in range(280):
				var a := _paper_pixel(actual.get_pixel(x, y))
				var b := _paper_pixel(expected.get_pixel(x, y))
				if a or b: union += 1
				if a != b: errors += 1
		check(union > 15000 and float(errors) / maxi(1, union) < 0.01, "GPU face and border match one rigid transform")
		for sign_x in [-1, 1]:
			for sign_y in [-1, 1]:
				var corner := Vector2i(center + (Card.BASE * 0.5 * Vector2(sign_x, sign_y)).rotated(angle))
				var corner_errors := 0
				for y in range(corner.y - 14, corner.y + 15):
					for x in range(corner.x - 14, corner.x + 15):
						if _paper_pixel(actual.get_pixel(x, y)) != _paper_pixel(expected.get_pixel(x, y)): corner_errors += 1
				check(corner_errors < 10, "all four rendered corners follow public offset and tilt")
		print("PUBLIC_CARD_GPU identity=%d mismatched_paper_pixels=%d/%d" % [identity, errors, union])
	viewport.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	root.size = Vector2i(760, 420)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var surface := Control.new()
	surface.position = Vector2(60, 40)
	surface.scale = Vector2(1.25, 1.25)
	root.add_child(surface)
	var card := DrawingProbe.new()
	card.position = Vector2(20, 20)
	card.size = Vector2(132, 184)
	card.set_card(51, false)
	card.public_interactive = true
	card.gesture_requested.connect(func(kind: String, offset: Vector2): requests.append({"kind": kind, "offset": offset}))
	card.touched.connect(func(kind: String): touched.append(kind))
	surface.add_child(card)
	await process_frame
	await process_frame
	var original_rect := card.get_global_rect()
	_press(card)
	check(requests.size() == 1 and requests[0].kind == "press", "local press sends one request")
	check(card._public_offset == Vector2.ZERO and not card._public_down, "press has no local prediction")
	check(not card._peeking and not card.face_up and card.card_id == 51, "hidden public face is never peeked")
	_press(card, 1)
	_release(card, 1)
	check(requests.size() == 1 and card._public_pointer == 0, "second finger cannot steal or release")
	card.apply_public_gesture("press", Vector2.ZERO)
	_step(card)
	check(card._public_down and card._public_offset.y < -3.9, "accepted press lifts")
	card.set_card(51, false)
	check(card._public_pointer == 0 and card._public_down, "same snapshot preserves capture and accepted gesture")
	for drag in range(30): _drag(card, Vector2(58, 49))
	check(requests.size() == 1, "rapid drag events coalesce below 50ms")
	card._last_request_usec = Time.get_ticks_usec() - 51000
	card._process(0)
	check(requests.size() == 2 and requests.back().kind == "drag", "coalesced drag sent at rate limit")
	check(requests.back().offset.is_equal_approx(Vector2(1, -1)), "scaled canvas pointer maps to 16 local pixels")
	card._last_request_usec = Time.get_ticks_usec() - 200000
	card._process(0)
	check(requests.size() == 2, "idle hold waits for heartbeat interval")
	card._last_request_usec = Time.get_ticks_usec() - 251000
	card._process(0)
	check(requests.size() == 3 and requests.back().kind == "drag", "idle hold heartbeats at 250ms")
	card.apply_public_gesture("drag", Vector2(100, -100))
	_step(card)
	check(card._public_offset.length() <= 16.001 and absf(card._public_angle) <= 0.1, "motion stays within displacement and tilt limits")
	check(card.get_global_rect() == original_rect, "drawing movement leaves hit rectangle unchanged")
	var offset_before: Vector2 = card._public_offset
	_release(card)
	check(requests.back().kind == "release" and card._public_pointer == -2, "outside release ends local capture")
	check(card._public_offset == offset_before and card._public_down, "local release waits for server acknowledgement")
	card.apply_public_gesture("release", Vector2.ZERO)
	_step(card)
	check(card._public_offset.length() < 0.02 and absf(card._public_angle) < 0.001, "accepted release springs home")
	check(touched.is_empty(), "component does not produce unapproved base feedback")

	# A rejected local press/cancel must not erase another player's accepted gesture.
	card.apply_public_gesture("press", Vector2(0.7, 0.2))
	_step(card)
	_press(card)
	offset_before = card._public_offset
	card.cancel_public_gesture()
	check(card._public_down and card._public_offset == offset_before, "cancel preserves another owner's visual")
	card.public_interactive = false
	card.public_interactive = false
	check(card._public_down and card._public_offset == offset_before, "repeated disable preserves remote visual")
	card.reset_public_gesture()
	check(card._public_offset == Vector2.ZERO and not card._public_down, "explicit lifecycle reset clears remote visual")
	card.public_interactive = true
	card.set_card(-1, true)
	_press(card)
	card.apply_public_gesture("press", Vector2.ONE)
	_step(card)
	check(card.card_id == -1 and not card._peeking and card._public_down, "unknown back supports motion without disclosure")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(card.faces == 0 and card.backs > 0, "hidden and unknown cards use only back renderer")
	card.set_card(12, true)
	check(card._public_pointer == -2 and not card._public_down and card._public_offset == Vector2.ZERO, "revealing a new card cancels old hold")
	check(requests.back().kind == "release", "new card requests release for local owner")
	card.apply_public_gesture("drag", Vector2.ONE)
	check(not card._public_down, "orphan drag cannot create an owner")
	card.apply_public_gesture("press", Vector2(NAN, 0))
	card.apply_public_gesture("invalid", Vector2.ZERO)
	check(not card._public_down, "invalid events ignored safely")

	for reason in [Control.NOTIFICATION_APPLICATION_FOCUS_OUT, Control.NOTIFICATION_APPLICATION_PAUSED]:
		_press(card)
		card.apply_public_gesture("press", Vector2.ONE)
		card._notification(reason)
		check(card._public_pointer == -2 and not card._public_down, "focus/background cancellation")
	_press(card)
	card.apply_public_gesture("press", Vector2.ONE)
	card.hide()
	check(card._public_pointer == -2 and not card._public_down, "hiding cancels local and remote hold")
	card.apply_public_gesture("press", Vector2.ONE)
	check(not card._public_down, "hidden view ignores incoming motion")
	card.show()
	await process_frame
	_press(card)
	card.apply_public_gesture("press", Vector2.ONE)
	card.size += Vector2(1, 0)
	check(card._public_pointer == -2 and not card._public_down, "resize clears interaction")
	_press(card)
	card.apply_public_gesture("press", Vector2.ONE)
	surface.position += Vector2(5, 0)
	await process_frame
	check(card._public_pointer == -2 and not card._public_down, "ancestor layout move clears interaction")

	var prior_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(30, 30)
	var before := requests.size()
	card._gui_input(mouse)
	_press(card)
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	card._gui_input(mouse)
	check(requests.size() == before + 1, "touch and emulated mouse produce one press")
	card.cancel_public_gesture()
	Input.emulate_touch_from_mouse = false
	mouse.device = 0
	card._gui_input(mouse)
	check(card._public_pointer == -1, "physical mouse works without emulation")
	mouse.pressed = false
	card._input(mouse)
	check(card._public_pointer == -2, "physical mouse release")
	Input.emulate_touch_from_mouse = prior_emulation

	card.deal(0.02)
	card.apply_public_gesture("press", Vector2.ONE)
	check(card._deal_offset != Vector2.ZERO and card._public_down, "deal and gesture have independent state")
	await create_timer(0.75).timeout
	check(card._deal_offset.length() < 0.01 and card._deal_alpha == 1 and card._public_down, "deal finishes while public hold persists")
	card.apply_public_gesture("release", Vector2.ZERO)
	_step(card)
	check(card.face_up and card.card_id == 12 and not card._peeking, "all motion preserves authoritative face")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(card.faces > 0, "known revealed public card renders its face")
	var routed := InputEventScreenTouch.new()
	routed.index = 4
	routed.position = card.get_global_transform_with_canvas() * Vector2(42, 65)
	routed.pressed = true
	before = requests.size()
	root.push_input(routed, true)
	check(card._public_pointer == 4 and requests.size() == before + 1, "viewport touch dispatch captures original hit rectangle")
	card.apply_public_gesture("press", Vector2.ONE)
	_step(card)
	routed.position = Vector2(-100, -100)
	routed.pressed = false
	root.push_input(routed, true)
	check(card._public_pointer == -2 and requests.back().kind == "release", "viewport release outside moving artwork reaches captured card")
	card.apply_public_gesture("release", Vector2.ZERO)
	_press(card)
	card.apply_public_gesture("press", Vector2.ONE)
	before = requests.filter(func(item: Dictionary): return item.kind == "release").size()
	surface.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(surface), "queued ancestor and public card finish deletion")
	check(requests.filter(func(item: Dictionary): return item.kind == "release").size() == before + 1 and requests.back().kind == "release", "queue_free releases a captured pointer once")
	await process_frame
	if DisplayServer.get_name() != "headless": await _render_rigid_transform()
	print("PUBLIC_CARD checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
