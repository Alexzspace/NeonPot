extends RefCounted
## Convert native display insets/cutouts to the game's logical control space.
static func content_rect(area: Vector2, screen: Vector2i, reported: Rect2i, cutouts: Array = []) -> Rect2:
	var fallback := Rect2(Vector2.ZERO, area)
	if screen.x <= 0 or screen.y <= 0: return fallback
	var bounds := Rect2(Vector2.ZERO, Vector2(screen))
	var safe := Rect2(reported).intersection(bounds)
	if not safe.has_area(): safe = bounds
	for cutout in cutouts:
		var hole := Rect2(cutout).intersection(bounds)
		if not hole.has_area() or not safe.intersects(hole): continue
		# Keep the largest rectangle clear of the hole, normally trimming the
		# nearest screen edge. Never reserve an entire strip on both sides.
		var candidates := [
			Rect2(safe.position, Vector2(maxf(0, hole.position.x - safe.position.x), safe.size.y)),
			Rect2(Vector2(hole.end.x, safe.position.y), Vector2(maxf(0, safe.end.x - hole.end.x), safe.size.y)),
			Rect2(safe.position, Vector2(safe.size.x, maxf(0, hole.position.y - safe.position.y))),
			Rect2(Vector2(safe.position.x, hole.end.y), Vector2(safe.size.x, maxf(0, safe.end.y - hole.end.y)))
		]
		var best := Rect2()
		for candidate in candidates:
			if candidate.get_area() > best.get_area(): best = candidate
		if best.has_area(): safe = best
	var factor := area / Vector2(screen)
	return Rect2(safe.position * factor, safe.size * factor)
