extends RefCounted

enum NORMAL { SHUFFLE = 0, TOSS = 1, ROCK = 2, SCATTER = 3, ROLL = 5 }
const RARE := 4 # Advanced paired shuffle; historic wire IDs remain stable.
const DURATIONS := [1.0, 1.0, 1.0, 1.0, 2.0, 1.0]

static func is_valid_style(style: int) -> bool:
	return style >= NORMAL.SHUFFLE and style < DURATIONS.size()

static func duration(style: int) -> float:
	return DURATIONS[style] if is_valid_style(style) else 0.0
