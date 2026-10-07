extends RefCounted
## Local cinematic pace. Never changes engine, network or direct-touch timing.
static var rate := 1.0

static func duration(seconds: float) -> float:
	return seconds / clampf(rate, 0.25, 2.0)
