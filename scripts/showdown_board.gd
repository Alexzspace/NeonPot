extends Control
## Passive public cards use the same dimensions as settlement hole cards.
const Card = preload("res://scripts/card_view.gd")
const CARD_SIZE := Vector2(108, 151)
const CARD_STEP := 124.0
var cards: Array = []
var highlight_colors: Dictionary = {}

func _ready() -> void:
	size = Vector2(maxf(0, cards.size() * CARD_STEP - 16), CARD_SIZE.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in cards.size():
		var card := Card.new()
		card.card_scale = CARD_SIZE.x / 132.0
		card.size = CARD_SIZE
		card.position = Vector2(i * CARD_STEP, 0)
		add_child(card)
		card.set_card(int(cards[i]), true)
		card.winning_colors = highlight_colors.get(int(cards[i]), [])
