extends RefCounted
## Fixed-orientation MIX Flip outer-display geometry from the R90 device trace.

const DEVICE_WIDTH := 1392.0
const DEVICE_HEIGHT := 1208.0
const BASIC_HEIGHT := 810.0
const CAMERA_BOUNDS_NATIVE := Rect2(664, 0, 728, 398)
# Estimated physical lens centers inside HyperOS' combined camera bounding box.
# Keep these calibration points centralized for later photographic adjustment.
const DECK_LENS_CENTER_NATIVE := Vector2(836, 199)
const POT_LENS_CENTER_NATIVE := Vector2(1220, 199)
const POT_NOTCH_NATIVE := Rect2(948, 292, 160, 100)
const POT_TITLE_NATIVE := Rect2(948, 12, 160, 92)
const LOGICAL_WIDTH := 1440.0

static func profile(window_native: Vector2i, screen_native: Vector2i, _cutouts: Array = [], force: bool = false) -> Dictionary:
	if window_native.x <= 0 or window_native.y <= 0:
		return {}
	var reference := screen_native if screen_native.x > 0 and screen_native.y > 0 else window_native
	var rotated := window_native.x < window_native.y
	var basic_window := _matches_basic_region(window_native) or _matches_rotated_basic_region(window_native)
	if not force and not _matches_full(reference) and not _matches_rotated_full(reference) and not basic_window:
		return {}
	var layout_window := Vector2i(window_native.y, window_native.x) if rotated else window_native
	var logical_size := Vector2(LOGICAL_WIDTH, LOGICAL_WIDTH * float(layout_window.y) / float(layout_window.x))
	var fills_display := not basic_window and absf(float(window_native.x) / float(reference.x) - 1.0) < 0.08 and absf(float(window_native.y) / float(reference.y) - 1.0) < 0.08
	var result := {
		"active": true,
		"full": fills_display,
		"landscape": true,
		"rotation_locked": rotated,
		"logical_size": logical_size,
		"camera_edge": "top" if fills_display else "none",
		"camera_zone": Rect2(),
		"camera_bounds": Rect2(),
		"camera_deck_center": Vector2.ZERO,
		"camera_pot_center": Vector2.ZERO,
		"pot_notch_rect": Rect2(),
		"pot_title_rect": Rect2(),
		"interactive_rect": Rect2(Vector2.ZERO, logical_size),
		"primary_rect": Rect2(Vector2.ZERO, logical_size),
		"aux_rect": Rect2(),
		"cutouts": [],
	}
	if not fills_display:
		result.mode = "basic_landscape"
		return result
	var factor := logical_size / Vector2(DEVICE_WIDTH, DEVICE_HEIGHT)
	var camera_bounds := Rect2(CAMERA_BOUNDS_NATIVE.position * factor, CAMERA_BOUNDS_NATIVE.size * factor)
	var band_height := CAMERA_BOUNDS_NATIVE.size.y * factor.y
	result.mode = "full_top"
	result.camera_zone = Rect2(0, 0, logical_size.x, band_height)
	result.camera_bounds = camera_bounds
	result.cutouts = [camera_bounds]
	result.camera_deck_center = DECK_LENS_CENTER_NATIVE * factor
	result.camera_pot_center = POT_LENS_CENTER_NATIVE * factor
	result.pot_notch_rect = Rect2(POT_NOTCH_NATIVE.position * factor, POT_NOTCH_NATIVE.size * factor)
	result.pot_title_rect = Rect2(POT_TITLE_NATIVE.position * factor, POT_TITLE_NATIVE.size * factor)
	result.interactive_rect = Rect2(0, band_height, logical_size.x, logical_size.y - band_height)
	result.primary_rect = result.interactive_rect
	result.aux_rect = Rect2(12, 12, camera_bounds.position.x - 24, band_height - 24)
	return result

static func _matches_full(dimensions: Vector2i) -> bool:
	return absi(dimensions.x - int(DEVICE_WIDTH)) <= 72 and absi(dimensions.y - int(DEVICE_HEIGHT)) <= 72

static func _matches_rotated_full(dimensions: Vector2i) -> bool:
	return absi(dimensions.x - int(DEVICE_HEIGHT)) <= 72 and absi(dimensions.y - int(DEVICE_WIDTH)) <= 72

static func _matches_basic_region(dimensions: Vector2i) -> bool:
	return absi(dimensions.x - int(DEVICE_WIDTH)) <= 48 and absi(dimensions.y - int(BASIC_HEIGHT)) <= 48

static func _matches_rotated_basic_region(dimensions: Vector2i) -> bool:
	return absi(dimensions.x - int(BASIC_HEIGHT)) <= 48 and absi(dimensions.y - int(DEVICE_WIDTH)) <= 48
