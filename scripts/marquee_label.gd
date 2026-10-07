extends Control
## Clip a long track title, hold each end briefly, then scroll at reading speed.
var text := "":
	set(next):
		if text != next:
			text = next
			_elapsed = 0
		queue_redraw()
var _elapsed := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var overflow := maxf(0, width - size.x)
	var offset := 0.0
	if overflow > 0:
		var travel := overflow / 36.0
		var cycle := fmod(_elapsed, travel * 2 + 4.0)
		if cycle > 2.0 and cycle < travel + 2.0: offset = (cycle - 2.0) * 36.0
		elif cycle >= travel + 2.0 and cycle <= travel + 4.0: offset = overflow
		elif cycle > travel + 4.0: offset = overflow - (cycle - travel - 4.0) * 36.0
	draw_string(font, Vector2(-offset, (size.y + font.get_ascent(28) - font.get_descent(28)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("f4e9e1"))
