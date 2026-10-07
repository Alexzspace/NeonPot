extends Control
## Compact role chips. A heads-up dealer can also hold the small blind.
const BASE := Vector2(96, 38)
const COLORS := {"D": Color("ffd78a"), "SB": Color("76f0e3"), "BB": Color("ff8eba")}
const PIXEL_FONT = preload("res://assets/fonts/fusion-pixel.ttf")
var language := "zh":
	set(value):
		language = value
		queue_redraw()
const GLYPHS := {
	"D": ["110", "101", "101", "101", "110"],
	"S": ["111", "100", "111", "001", "111"],
	"B": ["110", "101", "110", "101", "110"]
}
var roles: Array[String] = []:
	set(value):
		roles = []
		for role in ["D", "SB", "BB"]:
			if value.has(role):
				roles.append(role)
		if roles.has("SB") and roles.has("BB"):
			roles.erase("SB")
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BASE
	resized.connect(queue_redraw)

func _shape(rect: Rect2, corner: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([a + Vector2(corner, 0), Vector2(b.x - corner, a.y), Vector2(b.x, a.y + corner),
		b - Vector2(0, corner), b - Vector2(corner, 0), Vector2(a.x + corner, b.y), Vector2(a.x, b.y - corner), a + Vector2(0, corner)])

func role_text(role: String) -> String:
	return {"D": "庄", "SB": "小盲", "BB": "大盲"}.get(role, "") if language == "zh" else role

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / BASE)
	for index in roles.size():
		var role := roles[index]
		var color: Color = COLORS[role]
		var at := Vector2(index * 48, 2)
		draw_colored_polygon(_shape(Rect2(at + Vector2(0, 2), Vector2(44, 32)), 5), Color("090d20"))
		draw_colored_polygon(_shape(Rect2(at, Vector2(44, 32)), 5), color)
		draw_colored_polygon(_shape(Rect2(at + Vector2(2, 2), Vector2(40, 28)), 4), Color("19243d"))
		if language == "zh":
			# Two Chinese characters fit the same 44px chip, including heads-up D+SB.
			var label := role_text(role)
			var font_size := 20
			draw_string(PIXEL_FONT, at + Vector2(2, 24), label, HORIZONTAL_ALIGNMENT_CENTER, 40, font_size, color)
			continue
		var text_width := role.length() * 12 - 3
		var origin := at + Vector2((44 - text_width) * 0.5, 9)
		for letter in role.length():
			var grid: Array = GLYPHS[role[letter]]
			for row in grid.size():
				for column in 3:
					if grid[row][column] == "1":
						draw_rect(Rect2(origin + Vector2(letter * 12 + column * 3, row * 3), Vector2(3, 3)), color)
		if role == "D":
			for x in [17, 21, 25]:
				draw_rect(Rect2(at + Vector2(x, 4), Vector2(2, 3)), color)
		else:
			draw_rect(Rect2(at + Vector2(17, 4), Vector2(10, 2)), color)
			if role == "BB":
				draw_rect(Rect2(at + Vector2(17, 27), Vector2(10, 2)), color)
	draw_set_transform(Vector2.ZERO)
