extends SubViewportContainer
## Physical denomination inventory; set_amount is a legacy decorative fallback.
signal animation_finished(kind: String)
signal contact(kind: String)

const Timing = preload("res://scripts/presentation_timing.gd")
const Gestures = preload("res://scripts/chip_gestures.gd")

var display_mode: String = "stack"
var visual_scale: float = 1.0:
	set(value):
		visual_scale = clampf(value, 0.5, 2.0) if is_finite(value) else 1.0
		if is_instance_valid(_camera):
			_frame_camera()
			_request_redraw()
var _camera: Camera3D
var _rest_camera_size := 3.4
var _rest_camera_focus := Vector3.ZERO
var _flourish_style := 0
var _flourish_columns: Array[int] = []
var _flourish_center := Vector3.ZERO
var _moving_indices: Array[int] = []
var _flourish_levels: Array[int] = []
var _pairs: Array = []
var _alternate_pairs: Array = []
var _max_flourish_level := 0
var _motion_canvas_expanded := false
var _motion_canvas_changing := false
var _base_display_size := Vector2.ZERO
var _base_display_position := Vector2.ZERO
var _motion_canvas_factor := 1.0
var _contacts: Array = []
var _contact_cursor := 0
var viewport_3d: SubViewport
var stage: Node3D
var chips: Node3D
var _amount := 0
var _built_mode := ""
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _chip_nodes: Array[Node3D] = []
var _denominations: Array[int] = []
var _rest_positions: Array[Vector3] = []
var _rest_rotations: Array[Vector3] = []
var _animation: Tween
var _animation_kind := ""
var _intro_order: Array[int] = []
var _pending_intro := -1.0
var _pending_table_entry := -1.0
var _layout_center := Vector3.ZERO
var _collect_alpha := 1.0
var _inventory: Dictionary = {}
var _physical_inventory := false
const CHIP_PIXELS := 64.0
const COLUMN_SPACING := 1.18
var _fixed_chip_pixels := CHIP_PIXELS
var _render_overflow_enabled := false
var _bounded_pot_enabled := false
var _overflow_surface: SubViewportContainer
var _rest_render_size := Vector2.ZERO
var _arriving: Array[int] = []
var _overflow_counts: Dictionary = {}
const VALUES := [500, 100, 50, 10, 5, 1]
const COLORS := [Color("6a5587"), Color("282a38"), Color("397c65"), Color("467ba3"), Color("b94e50"), Color("d9d2b9")]
const MAX_CHIPS := 160
const COLUMN_CAP := 10
# Faces and denomination labels extend to +/-0.098: the old0.146 pitch cut through them.
const CHIP_PITCH := 0.21
const POT_CENTERS := [Vector3(-1.24, 0, 0), Vector3(-0.62, 0, -1.074), Vector3(0.62, 0, -1.074), Vector3(1.24, 0, 0), Vector3(0.62, 0, 1.074), Vector3(-0.62, 0, 1.074), Vector3.ZERO]

func _ready() -> void:
	if display_mode not in ["stack", "pot", "flight", "expanded", "manual", "pending"]:
		display_mode = "stack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(440, 240)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	if _render_overflow_enabled: _attach_overflow_surface()
	stage = Node3D.new()
	viewport_3d.add_child(stage)
	chips = Node3D.new()
	stage.add_child(chips)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(_camera)
	_aim_camera(Vector3(0, 0.3, 0), 3.4)
	var key := DirectionalLight3D.new()
	key.light_color = Color("e4def0")
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-55, -25, 0)
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("8389bd")
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-30, 145, 0)
	stage.add_child(fill)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CANVAS
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("77749c")
	environment.environment.ambient_light_energy = 0.3
	stage.add_child(environment)
	resized.connect(_on_resized)
	visibility_changed.connect(_request_redraw)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			cancel_intro()
			cancel_flourish())
	_build_chips()
	if _pending_intro >= 0.0: intro_stack(_pending_intro)
	if _pending_table_entry >= 0.0: table_entry_stack(_pending_table_entry)

func _exit_tree() -> void:
	_stop_animation()

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.78
		_materials[key] = material
	return _materials[key]

func _append_cylinder(surface: SurfaceTool, radius: float, height: float, y: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 32
	surface.append_from(cylinder, 0, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)))

func _chip_mesh(index: int) -> ArrayMesh:
	if _meshes.has(index):
		return _meshes[index]
	# Three cached surfaces replace ten separate MeshInstance nodes per chip.
	var result := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	body.set_material(_mat(COLORS[index]))
	_append_cylinder(body, 0.57, 0.135, 0)
	_append_cylinder(body, 0.505, 0.012, 0.077)
	_append_cylinder(body, 0.505, 0.012, -0.077)
	body.commit(result)
	var cream := SurfaceTool.new()
	cream.begin(Mesh.PRIMITIVE_TRIANGLES)
	cream.set_material(_mat(Color("ddd3b9")))
	_append_cylinder(cream, 0.32, 0.01, 0.088)
	_append_cylinder(cream, 0.32, 0.01, -0.088)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.13, 0.138, 0.13)
	for slot in 6:
		var angle := slot * TAU / 6
		cream.append_from(stripe, 0, Transform3D(Basis(Vector3.UP, angle), Vector3(sin(angle) * 0.505, 0, cos(angle) * 0.505)))
	cream.commit(result)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	rim.set_material(_mat(Color("9d8c68")))
	_append_cylinder(rim, 0.55, 0.008, 0.07)
	_append_cylinder(rim, 0.55, 0.008, -0.07)
	rim.commit(result)
	_meshes[index] = result
	return result

func set_amount(amount: int, animated: bool = true) -> void:
	amount = maxi(amount, 0)
	var was_physical := _physical_inventory
	_physical_inventory = false
	_inventory.clear()
	if not is_instance_valid(chips):
		_amount = amount
		return
	if not was_physical and amount == _amount and _built_mode == display_mode:
		_request_redraw()
		return
	_amount = amount
	_stop_animation()
	_build_chips()
	if animated and not _chip_nodes.is_empty():
		_begin_layout("amount", Timing.duration(0.34))

## Pot presentation stays inside its caller-owned full panel interior. Fixed
## chip diameter remains unchanged; only safe grid capacity and motion differ.
func set_bounded_pot_enabled(enabled: bool) -> void:
	if _bounded_pot_enabled == enabled: return
	_bounded_pot_enabled = enabled
	if enabled: set_render_overflow_enabled(false)
	if is_instance_valid(chips): _build_chips()

## Grows only the transparent output canvas. Public layout bounds and anchors
## remain unchanged, and the camera expands at the same world units per pixel.
func set_render_overflow_enabled(enabled: bool) -> void:
	if enabled == _render_overflow_enabled: return
	cancel_flourish()
	_render_overflow_enabled = enabled
	if not is_instance_valid(viewport_3d): return
	if enabled:
		_attach_overflow_surface()
	elif is_instance_valid(_overflow_surface):
		viewport_3d.reparent(self)
		remove_child(_overflow_surface)
		_overflow_surface.queue_free()
		_overflow_surface = null
	_frame_camera()
	_request_redraw()

func _attach_overflow_surface() -> void:
	if is_instance_valid(_overflow_surface): return
	_overflow_surface = SubViewportContainer.new()
	_overflow_surface.name = "UnclippedChipCanvas"
	_overflow_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overflow_surface.stretch = true
	_overflow_surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_overflow_surface)
	_set_render_size(size)
	viewport_3d.reparent(_overflow_surface)

func _set_render_size(output_size: Vector2) -> void:
	if not is_instance_valid(_overflow_surface): return
	_overflow_surface.size = output_size.ceil().max(Vector2.ONE)
	_overflow_surface.position = (size - _overflow_surface.size) * 0.5

func get_render_rect() -> Rect2:
	if is_instance_valid(_overflow_surface): return Rect2(_overflow_surface.position, _overflow_surface.size)
	return Rect2(Vector2.ZERO, size)

func _project_to_local(at: Vector3) -> Vector2:
	var output := get_render_rect()
	return output.position + _camera.unproject_position(at) * output.size / Vector2(viewport_3d.size)

func set_fixed_chip_pixels(pixels: float) -> void:
	_fixed_chip_pixels = clampf(pixels, 12.0, 96.0) if is_finite(pixels) else CHIP_PIXELS
	if is_instance_valid(_camera):
		_frame_camera()
		_request_redraw()

static func measure_inventory_size(counts: Dictionary, pixels: float = CHIP_PIXELS) -> Vector2:
	var columns := 0
	for value in VALUES:
		columns += ceili(float(maxi(0, int(counts.get(str(value), counts.get(value, 0))))) / COLUMN_CAP)
	return Vector2(maxi(1, columns) * pixels * COLUMN_SPACING / 1.14 + 8.0, pixels * 2.55 + 8.0)

func get_inventory() -> Dictionary:
	return _inventory.duplicate()

func set_inventory(counts: Dictionary, animate: bool = false) -> void:
	var clean: Dictionary = {}
	var total := 0
	for value in VALUES:
		var count := maxi(0, int(counts.get(str(value), counts.get(value, 0))))
		if count > 0: clean[str(value)] = count
		total += value * count
	if _physical_inventory and clean == _inventory and _built_mode == display_mode: return
	var previous := _inventory.duplicate() if _physical_inventory else {}
	_inventory = clean
	_physical_inventory = true
	_amount = total
	if not is_instance_valid(chips): return
	_build_chips()
	_arriving.clear()
	var seen: Dictionary = {}
	for index in _denominations.size():
		var key := str(VALUES[_denominations[index]])
		seen[key] = int(seen.get(key, 0)) + 1
		if int(seen[key]) > int(previous.get(key, 0)): _arriving.append(index)
	if animate and not _arriving.is_empty():
		_begin_animation("inventory", Timing.duration(0.42), _pose_inventory)
		_pose_inventory(0.0)

func _pose_inventory(t: float) -> void:
	if _bounded_pot_enabled:
		var heights: Array[float] = []
		heights.resize(_chip_nodes.size())
		heights.fill(0.0)
		for index in _arriving: heights[index] = 0.48 * pow(1.0 - t, 2)
		_apply_packet(_fit_packet(_intro_packet.bind(heights), true))
		return
	# Each column descends as a separated packet: upper discs never overtake lower ones.
	for index in _arriving:
		_chip_nodes[index].position = _rest_positions[index] + Vector3.UP * (0.48 * pow(1.0 - t, 2))
		_chip_nodes[index].rotation = _rest_rotations[index]

func denomination_position(value: int) -> Vector2:
	if not is_instance_valid(_camera): return Vector2(-1, -1)
	var denomination: int = VALUES.find(value)
	for index in range(_denominations.size() - 1, -1, -1):
		if _denominations[index] == denomination:
			return _project_to_local(_chip_nodes[index].global_position)
	return Vector2(-1, -1)

func denomination_at(local_point: Vector2) -> int:
	if not is_instance_valid(_camera) or not get_render_rect().has_point(local_point): return 0
	var nearest := 0
	var distance := _fixed_chip_pixels * 0.55
	# Every visible disc is selectable, including earlier stacks of the same
	# denomination. Hit radius follows chip size, never the containing panel.
	for index in range(_chip_nodes.size() - 1, -1, -1):
		if not _chip_nodes[index].visible: continue
		var at := _project_to_local(_chip_nodes[index].global_position)
		if not get_render_rect().has_point(at): continue
		var delta := local_point.distance_to(at)
		if delta < distance:
			distance = delta
			nearest = VALUES[_denominations[index]]
	return nearest

func _build_chips() -> void:
	_stop_animation()
	for child in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	_chip_nodes.clear()
	_denominations.clear()
	_rest_positions.clear()
	_rest_rotations.clear()
	_built_mode = display_mode
	var counts: Array[int] = []
	counts.resize(VALUES.size())
	counts.fill(0)
	var remaining := _amount
	if _physical_inventory:
		for index in VALUES.size(): counts[index] = int(_inventory.get(str(VALUES[index]), 0))
	else:
		if display_mode != "flight":
			for reserve in [[4, 6], [3, 5], [2, 4], [1, 3]]:
				var index: int = reserve[0]
				var count := mini(reserve[1], remaining / int(VALUES[index]))
				counts[index] += count
				remaining -= count * int(VALUES[index])
		for index in VALUES.size():
			counts[index] += remaining / int(VALUES[index])
			remaining %= int(VALUES[index])
	var limit := 600 if _physical_inventory else (MAX_CHIPS if display_mode != "flight" else 8)
	var active_columns := 0
	var bounded_columns: Array[int] = []
	if _bounded_pot_enabled:
		bounded_columns.resize(counts.size())
		bounded_columns.fill(0)
		var available := _bounded_pot_column_capacity()
		while available > 0:
			var allocated := false
			for index in counts.size():
				if available > 0 and bounded_columns[index] * COLUMN_CAP < counts[index]:
					bounded_columns[index] += 1
					available -= 1
					allocated = true
			if not allocated: break
	_overflow_counts.clear()
	for index in counts.size():
		var budget := 100 if _physical_inventory else (MAX_CHIPS - 24 if index == 0 else MAX_CHIPS)
		if _bounded_pot_enabled: budget = mini(budget, bounded_columns[index] * COLUMN_CAP)
		var shown := mini(counts[index], budget)
		if counts[index] > shown: _overflow_counts[str(VALUES[index])] = counts[index] - shown
		counts[index] = shown
		active_columns += ceili(float(shown) / COLUMN_CAP)
	var column := 0
	for denomination in VALUES.size():
		var count := int(counts[denomination])
		if count == 0:
			continue
		for level in count:
			if _chip_nodes.size() >= limit:
				break
			var chip := MeshInstance3D.new()
			chip.mesh = _chip_mesh(denomination)
			chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chips.add_child(chip)
			var at := _stack_position(column + level / COLUMN_CAP, active_columns, level % COLUMN_CAP, 1.22)
			var turn := Vector3(0, level * 0.14, 0)
			if _physical_inventory:
				var slot := column + level / COLUMN_CAP
				if display_mode == "manual":
					at = Vector3((column + level / COLUMN_CAP) * COLUMN_SPACING, (level % COLUMN_CAP) * CHIP_PITCH, 0)
				elif display_mode == "expanded":
					at = Vector3((VALUES.size() - 1 - denomination) * COLUMN_SPACING, (level % COLUMN_CAP) * CHIP_PITCH, (level / COLUMN_CAP) * COLUMN_SPACING)
				else:
					var across := _physical_columns()
					at = Vector3((slot % across) * COLUMN_SPACING, (level % COLUMN_CAP) * CHIP_PITCH, (slot / across) * COLUMN_SPACING)
			elif display_mode == "flight":
				at = Vector3((_chip_nodes.size() % 3 - 1) * 1.20, (_chip_nodes.size() / 3) * CHIP_PITCH, 0)
				turn.y = level * 0.5
			chip.position = at
			chip.rotation = turn
			_chip_nodes.append(chip)
			_denominations.append(denomination)
			_rest_positions.append(at)
			_rest_rotations.append(turn)
			for face in [-1, 1]:
				var value := Label3D.new()
				value.name = "DenominationTop" if face == 1 else "DenominationBottom"
				value.text = str(VALUES[denomination])
				value.font_size = 48
				value.pixel_size = 0.005
				value.modulate = Color("363342")
				value.outline_size = 0
				value.position.y = 0.098 * face
				value.rotation_degrees.x = -90 * face
				value.double_sided = false
				chip.add_child(value)
		column += ceili(float(count) / COLUMN_CAP)
	# Extreme inventories retain exact counts and explicitly label off-screen reserves.
	for key in _overflow_counts:
		var marker := Label3D.new()
		marker.name = "Reserve" + str(key)
		marker.text = "+%d × %s" % [_overflow_counts[key], key]
		marker.font_size = 40
		marker.pixel_size = 0.009
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		var denomination: int = VALUES.find(int(key))
		for index in _denominations.size():
			if _denominations[index] == denomination: marker.position = _rest_positions[index] + Vector3.UP * 0.45
		chips.add_child(marker)
	if display_mode == "flight" and not _chip_nodes.is_empty():
		var left := _rest_positions[0].x
		var right := left
		for at in _rest_positions:
			left = minf(left, at.x)
			right = maxf(right, at.x)
		for index in _chip_nodes.size():
			_rest_positions[index].x -= (left + right) * 0.5
			_chip_nodes[index].position = _rest_positions[index]
	_frame_camera()
	_request_redraw()

func _stack_position(column: int, columns: int, level: int, spacing: float) -> Vector3:
	if columns > 3 and size.x / maxf(1.0, size.y) < 2.3:
		var row: int = column / 3
		var in_row := mini(3, columns - row * 3)
		return Vector3((column % 3 - (in_row - 1) * 0.5) * spacing, level * CHIP_PITCH, (row - (ceili(float(columns) / 3.0) - 1) * 0.5) * 1.28)
	return Vector3((column - (columns - 1) * 0.5) * spacing, level * CHIP_PITCH, 0)

func toss(duration: float = 0.55) -> void:
	if not _chip_nodes.is_empty():
		_begin_animation("toss", duration, _pose_toss)

func collect(duration: float = 0.45) -> void:
	if _chip_nodes.is_empty(): return
	_begin_animation("collect", duration, _pose_collect)
	_collect_alpha = modulate.a

func organize(duration: float = 0.4) -> void:
	_begin_layout("organize", duration)

func nudge() -> void:
	if not _chip_nodes.is_empty():
		_begin_animation("nudge", 0.4, _pose_nudge)

func intro_stack(duration: float = 0.8) -> void:
	var seconds := clampf(duration, 0.15, 3.0) if is_finite(duration) else 0.8
	if not is_inside_tree() or not is_instance_valid(chips):
		_pending_intro = seconds
		return
	_pending_intro = -1.0
	if _chip_nodes.is_empty(): return
	_begin_animation("intro", seconds, _pose_intro)
	_intro_order.assign(range(_chip_nodes.size()))
	_intro_order.sort_custom(func(a: int, b: int):
		if not is_equal_approx(_rest_positions[a].y, _rest_positions[b].y): return _rest_positions[a].y < _rest_positions[b].y
		return a < b)
	_pose_intro(0.0)

func _pose_intro(t: float) -> void:
	# Higher discs start later and never fall below the disc underneath.
	var heights: Array[float] = []
	heights.resize(_chip_nodes.size())
	for rank in _intro_order.size():
		var index := _intro_order[rank]
		var start := 0.65 * float(rank) / maxf(1.0, _intro_order.size() - 1)
		var fall := clampf((t - start) / 0.25, 0.0, 1.0)
		heights[index] = 0.30 * (1.0 - fall * fall)
	var packet := _fit_packet(_intro_packet.bind(heights), true)
	for index in _chip_nodes.size():
		_chip_nodes[index].position = packet[0][index]
		_chip_nodes[index].rotation = _rest_rotations[index]

func table_entry_stack(duration: float = 1.2) -> void:
	var seconds := clampf(duration, 0.3, 3.0) if is_finite(duration) else 1.2
	if not is_inside_tree() or not is_instance_valid(chips):
		_pending_table_entry = seconds
		return
	_pending_table_entry = -1.0
	if _chip_nodes.is_empty(): return
	_begin_animation("table_entry", seconds, _pose_table_entry)
	_intro_order.assign(range(_chip_nodes.size()))
	_intro_order.sort_custom(func(a: int, b: int):
		if not is_equal_approx(_rest_positions[a].y, _rest_positions[b].y): return _rest_positions[a].y < _rest_positions[b].y
		return a < b)
	# Every disc lands in order; audible contacts are spaced to keep a large
	# balance from producing a burst of dozens of simultaneous voices.
	var last_contact := -1.0
	for rank in _intro_order.size():
		var impact := 0.22 + 0.68 * float(rank) / maxf(1.0, _intro_order.size() - 1)
		if (impact - last_contact) * seconds >= 0.065 or rank == _intro_order.size() - 1:
			_contacts.append([impact, "chip_land" if rank == _intro_order.size() - 1 else "chip_fidget"])
			last_contact = impact
	_pose_table_entry(0.0)

func _pose_table_entry(t: float) -> void:
	var heights: Array[float] = []
	heights.resize(_chip_nodes.size())
	for rank in _intro_order.size():
		var index := _intro_order[rank]
		var start := 0.68 * float(rank) / maxf(1.0, _intro_order.size() - 1)
		var fall := clampf((t - start) / 0.22, 0.0, 1.0)
		# Constant orientation preserves the narrow physical gaps. A tiny upward
		# settling rebound never compresses the ceramic faces into each other.
		var settle := clampf((t - start - 0.22) / 0.09, 0.0, 1.0)
		heights[index] = 0.48 * (1.0 - fall * fall) + 0.008 * sin(settle * PI)
		_chip_nodes[index].visible = t >= start
	var packet := _fit_packet(_intro_packet.bind(heights), true)
	for index in _chip_nodes.size():
		_chip_nodes[index].position = packet[0][index]
		_chip_nodes[index].rotation = _rest_rotations[index]
	while _contact_cursor < _contacts.size() and t >= float(_contacts[_contact_cursor][0]):
		var kind: String = _contacts[_contact_cursor][1]
		_contact_cursor += 1
		contact.emit(kind)

func _intro_packet(weight: float, heights: Array[float]) -> Array:
	var positions: Array[Vector3] = []
	for index in _chip_nodes.size(): positions.append(_rest_positions[index] + Vector3.UP * heights[index] * weight)
	return [positions, _rest_rotations]

func cancel_intro() -> void:
	_pending_intro = -1.0
	_pending_table_entry = -1.0
	if _animation_kind not in ["intro", "table_entry"]: return
	_stop_animation()
	_request_redraw()

func cancel_nudge() -> void:
	if _animation_kind != "nudge": return
	_stop_animation()
	_restore_rest_pose()
	_request_redraw()

func _restore_rest_pose() -> void:
	for index in _chip_nodes.size():
		if not is_instance_valid(_chip_nodes[index]): continue
		_chip_nodes[index].visible = true
		_chip_nodes[index].position = _rest_positions[index]
		_chip_nodes[index].rotation = _rest_rotations[index]

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		cancel_intro()
		cancel_flourish()

func flourish(style: int) -> void:
	if _chip_nodes.is_empty() or not Gestures.is_valid_style(style):
		return
	_stop_animation()
	_flourish_style = style
	_flourish_columns.clear()
	_flourish_center = _rest_center()
	var columns: Array[Vector2] = []
	for at in _rest_positions:
		var footprint := Vector2(at.x, at.z).snapped(Vector2.ONE * 0.01)
		if not columns.has(footprint): columns.append(footprint)
		_flourish_columns.append(columns.find(footprint))
	_moving_indices.assign(range(_chip_nodes.size()))
	_flourish_levels.clear()
	_max_flourish_level = 0
	for at in _rest_positions:
		var level := roundi(at.y / CHIP_PITCH)
		_flourish_levels.append(level)
		_max_flourish_level = maxi(_max_flourish_level, level)
	_pairs = _column_pairs(columns, false)
	_alternate_pairs = _column_pairs(columns, true)
	_begin_animation("flourish", Gestures.duration(style), _pose_flourish)
	_expand_motion_canvas()
	_contacts = _contact_schedule(style)
	_contact_cursor = 0

func _begin_layout(kind: String, duration: float) -> void:
	if _chip_nodes.is_empty(): return
	_layout_center = _rest_center()
	_begin_animation(kind, duration, _pose_layout)
	_pose_layout(0.0)

func _rest_center() -> Vector3:
	var center := Vector3.ZERO
	for at in _rest_positions: center += at
	return center / maxf(1.0, _rest_positions.size())

func _begin_animation(kind: String, duration: float, pose: Callable) -> void:
	_stop_animation()
	_animation_kind = kind
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_animation = create_tween()
	_animation.tween_method(pose, 0.0, 1.0, clampf(duration, 0.02, 5.0))
	_animation.tween_callback(_finish_animation.bind(kind))

func _pose_toss(t: float) -> void:
	# One rigid packet: spinning separate tightly stacked chips cuts through neighbours.
	var flight := minf(t / 0.76, 1.0)
	var settle := clampf((t - 0.76) / 0.24, 0, 1)
	var damping := sin(settle * PI * 3.0) * pow(1.0 - settle, 2)
	var turn := Basis.from_euler(Vector3(TAU * flight + damping * 0.13, 0, 0))
	var center := _rest_center()
	var lift := Vector3(0, sin(flight * PI) * 0.40 + absf(damping) * 0.04, 0)
	for index in _chip_nodes.size():
		_chip_nodes[index].position = center + turn * (_rest_positions[index] - center) + lift
		_chip_nodes[index].basis = turn * Basis.from_euler(_rest_rotations[index])

func _apply_packet(packet: Array) -> void:
	for index in _chip_nodes.size():
		_chip_nodes[index].position = packet[0][index]
		_chip_nodes[index].rotation = packet[1][index]

func _translation_packet(weight: float, shift: Vector3) -> Array:
	var positions: Array[Vector3] = []
	for at in _rest_positions: positions.append(at + shift * weight)
	return [positions, _rest_rotations]

func _layout_packet(weight: float, t: float) -> Array:
	var positions: Array[Vector3] = []
	var remaining := pow(1.0 - t, 3)
	var spread := 1.0 + remaining * 0.16 * weight
	var lift := Vector3(0, remaining * 0.16 + sin(t * PI) * 0.05, 0) * weight
	for at in _rest_positions: positions.append(_layout_center + (at - _layout_center) * spread + lift)
	return [positions, _rest_rotations]

func _pose_layout(t: float) -> void:
	if _bounded_pot_enabled:
		_apply_packet(_fit_packet(_layout_packet.bind(t), true))
		return
	# Only distances expand. Fixed orientations and a shared return preserve every
	# resting gap, including tall piles; no crossing denomination-sort trajectories.
	var remaining := pow(1.0 - t, 3)
	var spread := 1.0 + remaining * 0.16
	var lift := Vector3(0, remaining * 0.16 + sin(t * PI) * 0.05, 0)
	for index in _chip_nodes.size():
		_chip_nodes[index].position = _layout_center + (_rest_positions[index] - _layout_center) * spread + lift
		_chip_nodes[index].rotation = _rest_rotations[index]

func _pose_collect(t: float) -> void:
	# Main owns the winner's travel packet. This whole-pile gathering cue never
	# pulls individual cylinders through neighbouring stacks.
	var envelope := sin(t * PI)
	var shift := Vector3(0, envelope * 0.09, -envelope * 0.14)
	if _bounded_pot_enabled:
		_apply_packet(_fit_packet(_translation_packet.bind(shift), true))
		modulate.a = _collect_alpha * (1.0 - envelope * 0.32)
		return
	for index in _chip_nodes.size():
		_chip_nodes[index].position = _rest_positions[index] + shift
		_chip_nodes[index].rotation = _rest_rotations[index]
	modulate.a = _collect_alpha * (1.0 - envelope * 0.32)

func _pose_nudge(t: float) -> void:
	var rock := sin(t * PI * 2.0) * (1.0 - t)
	var shift := Vector3(rock * 0.13, sin(t * PI) * (1.0 - t) * 0.055, rock * 0.025)
	if _bounded_pot_enabled:
		_apply_packet(_fit_packet(_translation_packet.bind(shift), true))
		# A full panel can exhaust translation clearance. Upright disc twists
		# still give a tactile response without enlarging the cylinder footprint.
		for index in _chip_nodes.size():
			var level := roundi(_rest_positions[index].y / CHIP_PITCH)
			var twist := sin(t * TAU - level * 0.32) * sin(t * PI) * 0.22
			_chip_nodes[index].rotation = _rest_rotations[index] + Vector3(0, twist, 0)
		return
	for index in _chip_nodes.size():
		_chip_nodes[index].position = _rest_positions[index] + shift
		_chip_nodes[index].rotation = _rest_rotations[index]

func _c2(value: float) -> float:
	# Quintic Bezier control ordinates [0, 0, 0, 1, 1, 1]: C2 at both ends.
	var u := clampf(value, 0.0, 1.0)
	return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))

func _plateau(t: float, rise: float, hold: float, finish: float = 1.0) -> float:
	if t <= 0.0 or t >= finish: return 0.0
	if t < rise: return _c2(t / rise)
	if t > hold: return 1.0 - _c2((t - hold) / (finish - hold))
	return 1.0

func _bell(t: float) -> float:
	if t <= 0.0 or t >= 1.0: return 0.0
	var curved := t * (1.0 - t)
	return 64.0 * curved * curved * curved

func _column_pairs(columns: Array[Vector2], alternate: bool) -> Array:
	var centers: Array[Vector2] = columns.duplicate()
	var sides: Array[int] = []
	sides.resize(columns.size())
	sides.fill(-1)
	var visited: Dictionary = {}
	for index in columns.size():
		if visited.has(index): continue
		var row: Array[int] = []
		for candidate in columns.size():
			if is_equal_approx(columns[candidate].y, columns[index].y):
				row.append(candidate)
				visited[candidate] = true
		row.sort_custom(func(a: int, b: int): return columns[a].x < columns[b].x)
		var start := 1 if alternate and row.size() > 2 else 0
		for pair_index in range(start, row.size() - 1, 2):
			var left := row[pair_index]
			var right := row[pair_index + 1]
			var middle := (columns[left] + columns[right]) * 0.5
			centers[left] = middle
			centers[right] = middle
			sides[left] = 0
			sides[right] = 1
	return [centers, sides]

func _flourish_packet(t: float) -> Array:
	if _flourish_style != Gestures.RARE: return _mass_packet(_flourish_style, t, false)
	# Two opposing real stack shuffles, followed by a progressive compression.
	# Every section ends at the same rest pose with zero velocity and acceleration.
	if t < 0.36: return _mass_packet(1, t / 0.36, false)
	if t < 0.72: return _mass_packet(1, (t - 0.36) / 0.36, true)
	return _mass_packet(0, (t - 0.72) / 0.28, false)

func _mass_packet(style: int, t: float, alternate: bool) -> Array:
	var positions: Array[Vector3] = _rest_positions.duplicate()
	var rotations: Array[Vector3] = _rest_rotations.duplicate()
	if t <= 0.0 or t >= 1.0: return [positions, rotations]
	var open := _plateau(t, 0.24, 0.52)
	var center := Vector2(_flourish_center.x, _flourish_center.z)
	var pairing: Array = _alternate_pairs if alternate else _pairs
	for index in _chip_nodes.size():
		var rest := _rest_positions[index]
		var level := _flourish_levels[index]
		var column := _flourish_columns[index]
		var flat := Vector2(rest.x, rest.z)
		var height := rest.y
		var yaw := 0.0
		match style:
			0: # Whole-stack accordion: open individual seams, then close bottom-up.
				var breathe := _plateau(t, 0.25, 0.36, 0.98)
				flat = center + (flat - center) * (1.0 + 0.25 * breathe)
				for seam in range(1, level + 1):
					var close_at := minf(0.96, 0.66 + seam * 0.024)
					height += 0.115 * _plateau(t, 0.20 + seam * 0.008, 0.36, close_at)
				# One soft compression rebound, shared by each horizontal layer.
				height += level * 0.014 * _bell((t - 0.84) / 0.16)
				yaw = sin(level * 0.55) * breathe * 0.13
			1: # Open alternating slots before crossing neighbouring columns.
				var slots := _plateau(t, 0.22, 0.78)
				var weave := _plateau((t - 0.22) / 0.56, 0.36, 0.64)
				var side: int = pairing[1][column]
				if side >= 0:
					flat = flat.lerp(pairing[0][column], weave)
					height = lerpf(rest.y, (level * 2 + side) * CHIP_PITCH, slots)
				else:
					height = rest.y * (1.0 + slots * 0.55)
				flat = center + (flat - center) * (1.0 + slots * 0.20)
				yaw = sin(level * 0.8) * weave * 0.24
			2: # Every horizontal layer fans around the table at its existing height.
				var fan := _plateau(t, 0.34, 0.58)
				var angle := sin(level * 0.62 + 0.8) * fan * 0.38
				flat = center + (flat - center).rotated(angle) * (1.0 + fan * 0.38)
				height += level * 0.035 * fan
				yaw = angle
			3: # Alternating layers make two low, continuous push-cuts across the pile.
				var cut := _bell(t / 0.54) - 0.80 * _bell((t - 0.46) / 0.54)
				var side := -1.0 if level % 2 else 1.0
				flat = center + (flat - center) * (1.0 + open * 0.12)
				flat += Vector2(side * 0.68 * cut, side * 0.22 * cut)
				height += level * 0.030 * open
				yaw = side * 0.12 * cut
			5: # A two-pass finger-rake wave, with strictly positive seam widths.
				var sweep := _bell(t)
				flat = center + (flat - center) * (1.0 + sweep * 0.14)
				flat += Vector2(sin(t * TAU * 2.0 - level * 0.65) * 0.80, cos(t * TAU * 2.0 - level * 0.65) * 0.36) * sweep
				for seam in range(1, level + 1):
					height += 0.075 * sweep * (0.5 + 0.5 * sin(t * TAU * 2.0 - seam * 0.65))
				yaw = sin(t * TAU * 2.0 - level * 0.65) * sweep * 0.18
		# Each disc twists around its own vertical axis: no tilt enlarges the
		# cylinder footprint. Layer phases break the old rigid packet return.
		var flutter := _bell(t) * sin(t * TAU * 3.0 - level * 0.72)
		var settle_time := (t - 0.68) / 0.32
		var rebound := _bell(settle_time) * sin(settle_time * TAU * 1.5)
		var disc_phase := level * 0.72 + column * 0.91
		yaw += _bell(t) * sin(t * TAU * 3.0 - disc_phase) * 0.25 + rebound * sin(disc_phase + 0.4) * 0.22
		if style != 1:
			# Equal-height discs share translation; distinct layers keep their
			# existing safe vertical separation. The final sway crosses rest twice.
			flat += Vector2(flutter * 0.13, flutter * 0.055)
			flat += Vector2(cos(level * 0.7), sin(level * 0.7)) * rebound * 0.18
		else:
			# During paired slot closure different original levels may share a
			# height: retain a common translation until the columns are separated.
			flat += Vector2(rebound * 0.13, rebound * 0.04)
		positions[index] = Vector3(flat.x, height, flat.y)
		rotations[index] += Vector3(0, yaw, 0)
	return [positions, rotations]

func _expand_motion_canvas() -> void:
	_base_display_size = size
	_base_display_position = position
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	var factor := 1.0
	# Budget the canvas once from full-amplitude choreography; never reduce its motion.
	for sample in 33:
		var packet := _flourish_packet(float(sample) / 32.0)
		var bounds := _project_bounds(packet[0], packet[1])
		factor = maxf(factor, maxf(absf(bounds.position.y), absf(bounds.end.y)) * 2.0 / _rest_camera_size)
		factor = maxf(factor, maxf(absf(bounds.position.x), absf(bounds.end.x)) * 2.0 / (_rest_camera_size * aspect))
	_motion_canvas_factor = maxf(1.0, factor * 1.08)
	_motion_canvas_expanded = true
	if is_instance_valid(_overflow_surface):
		_set_render_size((_base_display_size * _motion_canvas_factor).max(_rest_render_size))
		_aim_camera(_rest_camera_focus, _rest_camera_size)
		return
	_motion_canvas_changing = true
	size = _base_display_size * _motion_canvas_factor
	position = _base_display_position - (size - _base_display_size) * 0.5
	_camera.size = _rest_camera_size * _motion_canvas_factor
	_motion_canvas_changing = false

func _restore_motion_canvas() -> void:
	if not _motion_canvas_expanded: return
	if is_instance_valid(_overflow_surface):
		_set_render_size(_rest_render_size)
		_motion_canvas_expanded = false
		_motion_canvas_factor = 1.0
		_aim_camera(_rest_camera_focus, _rest_camera_size)
		return
	_motion_canvas_changing = true
	size = _base_display_size
	position = _base_display_position
	_camera.size = _rest_camera_size
	_motion_canvas_expanded = false
	_motion_canvas_factor = 1.0
	_motion_canvas_changing = false

func _fit_packet(producer: Callable, anchored: bool = false) -> Array:
	# Fit the complete packet, never clamp individual discs back into neighbours.
	# Only a shared choreography amplitude is reduced; geometry and camera stay fixed.
	var half := get_render_rect().size * (_rest_camera_size / maxf(1.0, size.y)) * 0.5 - Vector2.ONE * 0.035
	var packet: Array = producer.call(1.0)
	var bounds := _project_bounds(packet[0], packet[1])
	if not _packet_fits(bounds, half, anchored):
		var low := 0.0
		var high := 1.0
		for iteration in 7:
			var middle := (low + high) * 0.5
			var trial: Array = producer.call(middle)
			var trial_bounds := _project_bounds(trial[0], trial[1])
			if _packet_fits(trial_bounds, half, anchored): low = middle
			else: high = middle
		packet = producer.call(low)
		bounds = _project_bounds(packet[0], packet[1])
	if anchored: return packet
	var correction := Vector2.ZERO
	if bounds.position.x < -half.x: correction.x = -half.x - bounds.position.x
	elif bounds.end.x > half.x: correction.x = half.x - bounds.end.x
	if bounds.position.y < -half.y: correction.y = -half.y - bounds.position.y
	elif bounds.end.y > half.y: correction.y = half.y - bounds.end.y
	var displacement := _camera.basis.x * correction.x + _camera.basis.y * correction.y
	for index in _chip_nodes.size(): packet[0][index] += displacement
	return packet

func _packet_fits(bounds: Rect2, half: Vector2, anchored: bool) -> bool:
	if anchored:
		return bounds.position.x >= -half.x and bounds.position.y >= -half.y and bounds.end.x <= half.x and bounds.end.y <= half.y
	return bounds.size.x <= half.x * 2.0 and bounds.size.y <= half.y * 2.0

func _contact_schedule(style: int) -> Array:
	match style:
		0:
			var contacts: Array = []
			var seams := mini(_max_flourish_level, 11)
			for seam in range(1, seams + 1, 3): contacts.append([0.66 + seam * 0.024, "chip_fidget"])
			contacts.append([0.893333, "chip_fidget"])
			contacts.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
			contacts.append([1.0, "chip_land"])
			return contacts
		1: return [[0.422, "chip_fidget"], [0.578, "chip_fidget"], [0.893333, "chip_fidget"], [1.0, "chip_land"]]
		2: return [[0.22, "chip_collect"], [0.42, "chip_fidget"], [0.78, "chip_collect"], [0.893333, "chip_fidget"], [1.0, "chip_land"]]
		3: return [[0.27, "chip_fidget"], [0.54, "chip_land"], [0.73, "chip_fidget"], [0.893333, "chip_fidget"], [1.0, "chip_land"]]
		4:
			var contacts: Array = [[0.152, "chip_fidget"], [0.36, "chip_land"], [0.512, "chip_fidget"], [0.72, "chip_land"]]
			for impact in _contact_schedule(0): contacts.append([0.72 + float(impact[0]) * 0.28, impact[1]])
			return contacts
		5: return [[0.20, "chip_fidget"], [0.40, "chip_collect"], [0.63, "chip_fidget"], [0.82, "chip_collect"], [0.893333, "chip_fidget"], [1.0, "chip_land"]]
	return []

func _pose_flourish(t: float) -> void:
	var motion := clampf(t, 0.0, 1.0)
	if motion <= 0.0 or motion >= 1.0:
		_restore_rest_pose()
	else:
		var packet := _flourish_packet(motion)
		for index in _chip_nodes.size():
			_chip_nodes[index].position = packet[0][index]
			_chip_nodes[index].rotation = packet[1][index]
	while _contact_cursor < _contacts.size() and motion >= float(_contacts[_contact_cursor][0]):
		var kind: String = _contacts[_contact_cursor][1]
		_contact_cursor += 1
		contact.emit(kind)

func _aim_camera(focus: Vector3, height: float) -> void:
	if not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return
	_camera.position = focus + Vector3(0.0 if _bounded_pot_enabled else 1.0, 7.8, 10.0)
	_camera.look_at(focus)
	_camera.size = height * maxf(1.0, get_render_rect().size.y) / maxf(1.0, size.y)

func _project_bounds(positions: Array[Vector3], rotations: Array[Vector3]) -> Rect2:
	if _bounded_pot_enabled: return _project_solid_bounds(positions, rotations)
	var first := true
	var result := Rect2()
	var inverse := _camera.basis.inverse()
	for index in range(positions.size()):
		var basis := Basis.from_euler(rotations[index])
		# Conservative solid-chip bounds also enclose both thin face labels.
		for x in [-0.61, 0.61]:
			for y in [-0.12, 0.12]:
				for z in [-0.61, 0.61]:
					var point: Vector3 = inverse * (positions[index] + basis * Vector3(x, y, z) - _rest_camera_focus)
					var flat := Vector2(point.x, point.y)
					if first:
						result = Rect2(flat, Vector2.ZERO)
						first = false
					else:
						result = result.expand(flat)
	return result

func _project_solid_bounds(positions: Array[Vector3], rotations: Array[Vector3]) -> Rect2:
	var bounds := Rect2()
	var inverse := _camera.basis.inverse()
	for index in positions.size():
		var basis := inverse * Basis.from_euler(rotations[index])
		var at: Vector3 = inverse * (positions[index] - _rest_camera_focus)
		# Cylinder bounds include the radial stripe corners and both face labels.
		var radial := Vector2(Vector2(basis.x.x, basis.z.x).length(), Vector2(basis.x.y, basis.z.y).length())
		var upright := Vector2(absf(basis.y.x), absf(basis.y.y))
		var radius := (radial * 0.575 + upright * 0.07).max(radial * 0.505 + upright * 0.083).max(radial * 0.36 + upright * 0.10)
		var rect := Rect2(Vector2(at.x, at.y) - radius, radius * 2.0)
		bounds = rect if index == 0 else bounds.merge(rect)
	return bounds

func _bounded_pot_column_capacity() -> int:
	var pixels_per_unit := _fixed_chip_pixels / 1.14
	var camera_distance := Vector2(7.8, 10.0).length()
	var upright := 10.0 / camera_distance
	var depth := 7.8 / camera_distance
	var tallest := ((9 * CHIP_PITCH + 0.14) * upright + 1.15 * depth) * pixels_per_unit
	var row_pitch := COLUMN_SPACING * depth * pixels_per_unit
	var rows := maxi(1, 1 + floori((size.y - 2.0 - tallest) / row_pitch))
	return _physical_columns() * rows

func _physical_columns() -> int:
	if _bounded_pot_enabled:
		var pitch := _fixed_chip_pixels * COLUMN_SPACING / 1.14
		return maxi(1, 1 + floori((size.x - 4.0 - _fixed_chip_pixels * 1.15 / 1.14) / pitch))
	return maxi(1, floori((size.x - 8.0) / (_fixed_chip_pixels * COLUMN_SPACING / 1.14)))

func _frame_camera() -> void:
	if not is_instance_valid(_camera) or _rest_positions.is_empty():
		return
	if _physical_inventory:
		# All physical displays use the same world-units-per-pixel, including
		# transfers. Recentring content never changes the ceramic disc diameter.
		_rest_camera_size = maxf(1.0, size.y) * 1.14 / _fixed_chip_pixels
		_rest_camera_focus = Vector3.ZERO
		_aim_camera(_rest_camera_focus, _rest_camera_size)
		var physical_bounds := _project_bounds(_rest_positions, _rest_rotations)
		_rest_camera_focus += _camera.basis.x * physical_bounds.get_center().x + _camera.basis.y * physical_bounds.get_center().y
		if is_instance_valid(_overflow_surface):
			_rest_render_size = size.max(physical_bounds.size * _fixed_chip_pixels / 1.14 + Vector2.ONE * 32.0).ceil()
			_set_render_size(_rest_render_size)
		_aim_camera(_rest_camera_focus, _rest_camera_size)
		return
	if is_instance_valid(_overflow_surface):
		_rest_render_size = size
		_set_render_size(size)
	var bounds := AABB(_rest_positions[0], Vector3.ZERO)
	for at in _rest_positions:
		bounds = bounds.expand(at)
	_rest_camera_focus = bounds.get_center()
	_aim_camera(_rest_camera_focus, 3.4)
	var projected := _project_bounds(_rest_positions, _rest_rotations)
	_rest_camera_focus += _camera.basis.x * projected.get_center().x + _camera.basis.y * projected.get_center().y
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	var fitted := maxf(projected.size.y + 0.20, (projected.size.x + 0.22) / aspect)
	var preferred := 2.9 if display_mode == "pot" else (2.4 if display_mode == "flight" else 3.4)
	_rest_camera_size = maxf(preferred / visual_scale, fitted)
	_aim_camera(_rest_camera_focus, _rest_camera_size)

func _on_resized() -> void:
	if _motion_canvas_changing: return
	if _motion_canvas_expanded and is_instance_valid(_overflow_surface):
		cancel_flourish()
	elif _motion_canvas_expanded:
		var requested_size := size
		var expanded_position := _base_display_position - _base_display_size * (_motion_canvas_factor - 1.0) * 0.5
		var requested_position := _base_display_position if position.is_equal_approx(expanded_position) else position
		cancel_flourish()
		_motion_canvas_changing = true
		size = requested_size
		position = requested_position
		_motion_canvas_changing = false
	cancel_intro()
	if is_instance_valid(chips) and _animation == null:
		if _physical_inventory: _build_chips()
		else: _frame_camera()
	_request_redraw()

func _finish_animation(kind: String) -> void:
	_restore_motion_canvas()
	if kind == "collect": modulate.a = _collect_alpha
	for index in _chip_nodes.size():
		_chip_nodes[index].visible = true
		_chip_nodes[index].position = _rest_positions[index]
		_chip_nodes[index].rotation = _rest_rotations[index]
	_animation = null
	_animation_kind = ""
	_contacts.clear()
	_contact_cursor = 0
	_aim_camera(_rest_camera_focus, _rest_camera_size)
	_request_redraw()
	animation_finished.emit(kind)

func _stop_animation() -> void:
	_restore_motion_canvas()
	if _animation_kind == "collect":
		modulate.a = _collect_alpha
		_restore_rest_pose()
	if _animation != null and _animation.is_valid():
		_animation.kill()
	if _animation_kind in ["intro", "table_entry"]: _restore_rest_pose()
	_animation = null
	_animation_kind = ""
	_contacts.clear()
	_contact_cursor = 0
	_aim_camera(_rest_camera_focus, _rest_camera_size)

func cancel_flourish() -> void:
	# Pause/disconnect cancels recreational motion, without interfering with
	# the table's separate authoritative transfer / payout animation.
	if _animation_kind != "flourish":
		return
	_stop_animation()
	for index in _chip_nodes.size():
		_chip_nodes[index].position = _rest_positions[index]
		_chip_nodes[index].rotation = _rest_rotations[index]
	_request_redraw()

func _request_redraw() -> void:
	if is_instance_valid(viewport_3d):
		# ONCE renders the final pose (also after resize), then sleeps itself.
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _animation != null else SubViewport.UPDATE_ONCE
