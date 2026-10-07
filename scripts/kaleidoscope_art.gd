class_name KaleidoscopeArt
extends RefCounted
## Cached local ink geometry. No frame clock, card identity or gameplay RNG.
const Themes = preload("res://scripts/card_themes.gd")
const CACHE_LIMIT := 16
static var _cache: Dictionary = {}
static var _order: Array[String] = []

static func geometry(value: Dictionary) -> Array[Dictionary]:
	var recipe := Themes.sanitize_recipe(value)
	var empty: Array[Dictionary] = []
	if recipe.is_empty(): return empty
	var key := JSON.stringify(recipe)
	if _cache.has(key): return _cache[key]
	var groups: Array[Dictionary] = []
	var paths := _motif_paths(recipe)
	for stroke in recipe.strokes:
		var points := PackedVector2Array()
		for p in stroke.points: points.append(Vector2(p[0], p[1]))
		# A tap becomes a tiny radial dash, repeated like any other brush stroke.
		if points.size() == 1:
			points.append(points[0] * 0.985 if points[0].length() > 0.02 else points[0] + Vector2(0.01, 0))
		paths.append({"points": points, "color": stroke.color})
	var layers := 2 if recipe.depth > 0.01 else 1
	for layer in range(layers - 1, -1, -1):
		for ink in 2:
			var lines := PackedVector2Array()
			var scale_factor: float = 1.0 - layer * recipe.depth * 0.37
			var rotation: float = deg_to_rad(recipe.rotation) + layer * recipe.depth * PI / recipe.segments
			for path in paths:
				if path.color != ink: continue
				var points: PackedVector2Array = path.points
				for sector in recipe.segments:
					var angle: float = rotation + TAU * sector / recipe.segments
					for mirrored in (2 if recipe.mirror else 1):
						var previous := Vector2.ZERO
						for i in points.size():
							var p := points[i] * Vector2(1, -1 if mirrored else 1)
							p = p.rotated(angle) * scale_factor
							if i > 0:
								lines.append_array(clip_segment(previous, p))
							previous = p
			if not lines.is_empty(): groups.append({"points": lines, "color": ink, "alpha": 1.0 if layer == 0 else 0.28 + recipe.depth * 0.16})
	if _order.size() >= CACHE_LIMIT: _cache.erase(_order.pop_front())
	_order.append(key)
	_cache[key] = groups
	return groups

static func _motif_paths(recipe: Dictionary) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	if not recipe.motif_enabled: return paths
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed
	var wedge: float = PI / recipe.segments
	var fullness := rng.randf_range(0.62, 0.88)
	var inner := rng.randf_range(0.16, 0.24)
	# Every curve is designed inside a single wedge, then repeated exactly.
	for band in 3:
		var points := PackedVector2Array()
		for i in 33:
			var t := float(i) / 32.0
			var p := Vector2.ZERO
			match int(recipe.motif):
				0:
					var radius := inner + (0.75 - band * 0.14) * sin(PI * t)
					p = Vector2.from_angle(wedge * fullness * sin(TAU * t)) * radius
				1:
					var radius := lerpf(0.17 + band * 0.10, 0.94 - band * 0.06, t)
					p = Vector2.from_angle(wedge * (0.15 + 0.7 * sin(PI * t))) * radius
				2:
					var center := Vector2(0.48 + band * 0.09, 0)
					p = center + Vector2(cos(TAU * t) * (0.39 - band * 0.08), sin(TAU * t) * wedge * fullness * (0.37 - band * 0.055))
			points.append(p)
		paths.append({"points": points, "color": band % 2})
	# Outer scalloped tracery joins adjacent sectors into a continuous medallion.
	var rim := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		rim.append(Vector2.from_angle(wedge * t) * (0.91 + 0.025 * cos(PI * t)))
	paths.append({"points": rim, "color": 1})
	return paths

## Clip each transformed straight segment, without bending it along the border.
static func clip_segment(from: Vector2, to: Vector2) -> PackedVector2Array:
	var delta := to - from
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if absf(delta[axis]) < 0.000001:
			if absf(from[axis]) > 1.0: return PackedVector2Array()
			continue
		var a := (-1.0 - from[axis]) / delta[axis]
		var b := (1.0 - from[axis]) / delta[axis]
		enter = maxf(enter, minf(a, b))
		leave = minf(leave, maxf(a, b))
		if enter > leave: return PackedVector2Array()
	if leave - enter < 0.000001: return PackedVector2Array()
	return PackedVector2Array([from + delta * enter, from + delta * leave])
