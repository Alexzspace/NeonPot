extends SceneTree
const Themes = preload("res://scripts/card_themes.gd")
const Art = preload("res://scripts/kaleidoscope_art.gd")
const Card = preload("res://scripts/card_view.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("KALEIDOSCOPE: " + message)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var recipe := Themes.default_recipe()
	check(Themes.PALETTE.size() == 16 and recipe.paper in Themes.PALETTE and recipe.primary in Themes.PALETTE and recipe.accent in Themes.PALETTE, "sixteen preset colors and palette defaults")
	var geometry := Art.geometry(recipe)
	check(geometry == Art.geometry(recipe), "deterministic cached motif")
	check(geometry.size() == 4, "two colors and two bounded depth layers")
	for tap in [[0.0, 0.0], [1.0, 0.0]]:
		var tapped := recipe.duplicate(true)
		tapped.depth = 0.0
		tapped.strokes = [{"points": [tap], "color": 0}]
		var tap_lines: PackedVector2Array = Art.geometry(tapped)[0].points
		check(tap_lines[-2].distance_to(tap_lines[-1]) > 0.0001, "center and boundary taps produce visible nonzero ink")
		check(tap_lines[-2].length() <= 1.001 and tap_lines[-1].length() <= 1.001, "tap dash stays inside art boundary")
	seed(614)
	var expected := randi()
	seed(614)
	var alternate := recipe.duplicate(true)
	alternate.seed += 1
	check(Art.geometry(alternate) != geometry, "cosmetic seed changes structured curves")
	check(randi() == expected, "art never consumes gameplay random stream")
	var migrated := Themes.sanitize_recipe({"version": 1, "seed": 86, "paper": "112233", "density": 0.2})
	check(migrated.version == 3 and migrated.segments == 6 and migrated.strokes.is_empty(), "legacy recipe migrates to structured defaults")
	check(migrated.seed == 86 and migrated.paper == "112233" and migrated.density == 0.2, "migration retains original palette and seed")
	var unsafe := Themes.sanitize_recipe({"segments": INF, "depth": NAN, "rotation": -900, "line_width": 999, "motif": -2, "strokes": [{"points": [[INF, 0], ["x", 2], [3, 4], [0.1, 0.2]], "color": {}}]})
	check(unsafe.segments == 6 and unsafe.depth == 0.35 and unsafe.rotation == 0 and unsafe.line_width == 5 and unsafe.motif == 0, "invalid parameters bounded")
	check(unsafe.strokes.size() == 1 and unsafe.strokes[0].points.size() == 2 and unsafe.strokes[0].color == 0, "invalid brush points removed")
	check(Themes.sanitize_recipe(JSON.parse_string(JSON.stringify(unsafe))) == unsafe, "JSON roundtrip keeps sanitized drawing")
	var many: Array = []
	for i in 500: many.append([cos(i * 0.02) * 0.7, sin(i * 0.02) * 0.7])
	var strokes: Array = []
	for i in 40: strokes.append({"points": many, "color": i % 2})
	var bounded := Themes.sanitize_recipe({"strokes": strokes, "segments": 12, "depth": 1.0})
	var total := 0
	for stroke in bounded.strokes:
		total += stroke.points.size()
		check(stroke.points.size() <= 64, "each stroke decimated")
	check(total == 512 and bounded.strokes.size() <= 16, "global saved drawing bound")
	var point_count := 0
	for group in Art.geometry(bounded):
		point_count += group.points.size()
		check(group.points.size() % 2 == 0, "geometry uses paired independent lines")
		var inside := true
		for p in group.points:
			if not p.is_finite() or maxf(absf(p.x), absf(p.y)) > 1.001: inside = false
		check(inside, "all generated ink stays within safe unit rectangle")
	check(point_count <= 65536, "worst-case draw geometry bounded")
	for n in [2, 3, 6, 8, 12]:
		var symmetric := Themes.default_recipe()
		symmetric.segments = n
		symmetric.depth = 0
		symmetric.strokes = [{"points": [[0.21, 0.12], [0.63, 0.29]], "color": 1}]
		var points: PackedVector2Array = Art.geometry(symmetric)[1].points
		var rotated := Vector2(0.21, 0.12).rotated(TAU / n)
		var reflected := Vector2(0.21, -0.12)
		check(_contains_near(points, rotated) and _contains_near(points, reflected), "%d-fold drawing rotation and reflection" % n)
	for i in 24:
		var variant := recipe.duplicate(true)
		variant.seed = i
		Art.geometry(variant)
	check(Art._cache.size() <= 16 and Art._order.size() <= 16, "cache remains bounded after many slider changes")
	for motif in 3:
		var variant := recipe.duplicate(true)
		variant.motif = motif
		check(not Art.geometry(variant).is_empty(), "each motif generates art")
	var card := Card.new()
	root.add_child(card)
	card.custom_recipe = recipe
	card.set_card(0, false)
	await process_frame
	card.custom_recipe = {}
	card.theme_id = 2
	check(card.effective_recipe().is_empty() and Themes.COUNT == 4, "preset identity and protocol unchanged")
	card.queue_free()
	await process_frame
	print("KALEIDOSCOPE_ART checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _contains_near(points: PackedVector2Array, target: Vector2) -> bool:
	for p in points:
		if p.distance_to(target) < 0.0001: return true
	return false
