class_name CardThemes
extends RefCounted
## Four original static print treatments; switching never changes card identity.
const COUNT := 4
const PALETTE: Array[String] = ["080c18", "161b2e", "29273f", "49465e", "747085", "aaa5b5", "d6ccd0", "f3ead8", "143f46", "287c87", "65d8ca", "86bdf0", "7773cf", "bc8ee1", "eb7aa8", "e4b66d"]
static var active_id: int = 0

static func collection_name(value: int, language: String = "zh") -> String:
	var names := ["鎏金夜幕", "霓光拼诗", "赤线构想", "纯白牌序"] if language == "zh" else ["MIDNIGHT GILT", "NEON COLLAGE", "REDLINE", "PURE FORM"]
	return names[valid_id(value)]

static func valid_id(value: int) -> int:
	return value if value >= 0 and value < COUNT else 0

static func paper(value: int) -> Color:
	return [Color("08090b"), Color("ece4dc"), Color("e7dfc9"), Color("fffdf8")][valid_id(value)]

static func ink(value: int, suit: int) -> Color:
	var red := suit == 1 or suit == 2
	match valid_id(value):
		0: return Color("ffda7a") if red else Color("a18a60")
		1: return Color("b72453") if red else Color("262948")
		2: return Color("bc3029") if red else Color("171d27")
		_: return Color("bd233c") if red else Color("142132")

static func edge(value: int) -> Color:
	return [Color("715a33"), Color("a6a0b4"), Color("342e26"), Color("d7d8db")][valid_id(value)]

static var custom_recipe: Dictionary = {}
const RECIPE_VERSION := 3
const SLIDER_KEYS := ["geometry", "density", "symmetry", "pixel_size", "color_balance"]

static func default_recipe() -> Dictionary:
	return {"version": RECIPE_VERSION, "mode": "kaleidoscope", "segments": 6, "mirror": true, "rotation": 0.0, "depth": 0.35, "line_width": 1.4, "motif": 0, "motif_enabled": true, "strokes": [], "seed": 1400, "geometry": 0.65, "density": 0.45, "symmetry": 1.0, "pixel_size": 0.4, "color_balance": 0.5, "paper": "161b2e", "primary": "bc8ee1", "accent": "65d8ca"}

static func sanitize_recipe(value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty(): return {}
	var result := default_recipe()
	var seed_value: Variant = value.get("seed", 1400)
	if seed_value is int or seed_value is float:
		if is_finite(float(seed_value)): result.seed = int(clampf(float(seed_value), 0, 2147483647))
	for key in SLIDER_KEYS:
		var number: Variant = value.get(key, result[key])
		if (number is int or number is float) and is_finite(float(number)):
			result[key] = clampf(float(number), 0.0, 1.0)
	for key in ["paper", "primary", "accent"]:
		var raw: Variant = value.get(key, result[key])
		if raw is String and raw.length() <= 9 and Color.html_is_valid(raw):
			result[key] = Color.html(raw).to_html(false)
	for key in ["segments", "rotation", "depth", "line_width", "motif"]:
		var number: Variant = value.get(key, result[key])
		if not (number is int or number is float) or not is_finite(float(number)): continue
		match key:
			"segments": result[key] = clampi(int(clampf(float(number), 1, 12)), 1, 12)
			"rotation": result[key] = clampf(float(number), 0, 360)
			"depth": result[key] = clampf(float(number), 0, 1)
			"line_width": result[key] = clampf(float(number), 1, 5)
			"motif": result[key] = clampi(int(clampf(float(number), 0, 2)), 0, 2)
	if value.get("mirror") is bool: result.mirror = value.mirror
	if value.get("motif_enabled") is bool: result.motif_enabled = value.motif_enabled
	var raw_strokes: Variant = value.get("strokes", [])
	var total := 0
	if raw_strokes is Array:
		for stroke in raw_strokes.slice(0, 16):
			if not stroke is Dictionary or not stroke.get("points") is Array: continue
			var raw_points: Array = stroke.points
			var points: Array = []
			var count := mini(64, mini(raw_points.size(), 512 - total))
			for i in count:
				var index := int(round(float(i) * (raw_points.size() - 1) / maxf(count - 1, 1)))
				var point: Variant = raw_points[index]
				if not point is Array or point.size() != 2: continue
				if not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float): continue
				if not is_finite(float(point[0])) or not is_finite(float(point[1])): continue
				# v2 saved disk coordinates remain valid rectangular coordinates; never
				# project old strokes again or discard their corners on later saves.
				var p := Vector2(clampf(float(point[0]), -1, 1), clampf(float(point[1]), -1, 1))
				points.append([p.x, p.y])
			if points.is_empty(): continue
			total += points.size()
			var stroke_color: Variant = stroke.get("color", 0)
			var use_accent: bool = (stroke_color is int or stroke_color is float) and stroke_color == 1
			result.strokes.append({"points": points, "color": 1 if use_accent else 0})
	return result

static func recipe_ink(recipe: Dictionary, suit: int) -> Color:
	var paper_color := Color.html(recipe.paper)
	# Fixed contrasting index inks prevent arbitrary DIY colors hiding identity.
	if paper_color.get_luminance() > 0.38:
		return Color("9e153a") if suit in [1, 2] else Color("11182b")
	return Color("ffafbc") if suit in [1, 2] else Color("f6f2df")

static func recipe_marks(value: Dictionary) -> Array[Dictionary]:
	var recipe := sanitize_recipe(value)
	var marks: Array[Dictionary] = []
	if recipe.is_empty(): return marks
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed
	var pixel := lerpf(2.0, 8.0, recipe.pixel_size)
	for i in range(int(lerpf(10.0, 70.0, recipe.density))):
		var p := Vector2(snappedf(rng.randf_range(-45, 45), pixel), snappedf(rng.randf_range(-69, 69), pixel))
		var mark := {"position": p, "radius": pixel * rng.randi_range(1, 2), "square": rng.randf() < recipe.geometry, "accent": rng.randf() < recipe.color_balance}
		marks.append(mark)
		if rng.randf() < recipe.symmetry:
			var mirror := mark.duplicate()
			mirror.position = -p
			marks.append(mirror)
	return marks
