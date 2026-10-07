extends SceneTree
const Safe = preload("res://scripts/safe_area.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var screen := Vector2i(2912, 1224)
	var full := Rect2i(Vector2i.ZERO, screen)
	var area := Vector2(1456, 612)
	check(Safe.content_rect(area, screen, full) == Rect2(Vector2.ZERO, area), "uncut screen uses all available space")
	for hole in [Rect2i(35, 550, 80, 100), Rect2i(2797, 550, 80, 100)]:
		var result := Safe.content_rect(area, screen, full, [hole])
		var scaled := Rect2(Vector2(hole.position) * 0.5, Vector2(hole.size) * 0.5)
		check(not result.intersects(scaled), "either landscape hole is outside content")
		check(result.size.x > area.x * 0.95, "only nearest edge inset avoids wasted space")
	var native_safe := Rect2i(120, 0, 2792, 1190)
	check(Safe.content_rect(area, screen, native_safe, [Rect2i(35, 550, 80, 100)]) == Rect2(60, 0, 1396, 595), "existing native inset is not double applied")
	check(Safe.content_rect(area, Vector2i.ZERO, full) == Rect2(Vector2.ZERO, area), "invalid screen falls back safely")
	check(Safe.content_rect(area, screen, Rect2i(-20, -20, 3000, 1300)) == Rect2(Vector2.ZERO, area), "reported safe area is clipped to screen")
	check(Safe.content_rect(area, screen, Rect2i()) == Rect2(Vector2.ZERO, area), "empty native safe area falls back")
	var opposing := [Rect2i(35, 550, 80, 100), Rect2i(2797, 550, 80, 100)]
	var dual := Safe.content_rect(area, screen, full, opposing)
	check(dual == Rect2(57.5, 0, 1341, 612), "two opposite cutouts reserve only their real edge strips")
	opposing.reverse()
	check(Safe.content_rect(area, screen, full, opposing) == dual, "opposite edge cutout order does not alter safe bounds")
	check(Safe.content_rect(area, screen, full, [Rect2i(-30, 500, 100, 100)]) == Rect2(35, 0, 1421, 612), "partially off-screen hole clips before insetting")
	check(Safe.content_rect(area, screen, full, [Rect2i(-100, 500, 20, 100), Rect2i()]) == Rect2(Vector2.ZERO, area), "outside and empty cutouts cannot waste screen space")
	var portrait := Vector2i(1224, 2912)
	var portrait_area := Vector2(612, 1456)
	check(Safe.content_rect(portrait_area, portrait, Rect2i(Vector2i.ZERO, portrait), [Rect2i(550, 35, 100, 80)]) == Rect2(0, 57.5, 612, 1398.5), "portrait top camera trims top rather than a side")
	var bottom := Safe.content_rect(area, screen, full, [Rect2i(1400, 1144, 100, 80)])
	check(bottom == Rect2(0, 0, 1456, 572), "bottom cutout trims the bottom edge")
	check(Safe.content_rect(Vector2(728, 612), screen, full, [Rect2i(35, 550, 80, 100)]) == Rect2(28.75, 0, 699.25, 612), "native cutout maps independently on each logical axis")
	print("SAFE_AREA_SUMMARY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
