extends RefCounted
## Original bilingual lines, drawn from independent no-repeat shuffle bags.
const HOME = [["夜色入席。", "Let the night take a seat."], ["霓虹未眠。", "Neon never quite sleeps."], ["把今夜留给相逢。", "Leave tonight for good company."], ["灯火有岸，夜色有河。", "City lights, a midnight river."], ["落座，让喧嚣走远。", "Take a seat. Let the noise drift."], ["一桌微光，几位故人。", "A little light. Familiar faces."], ["借一盏灯，慢慢相聚。", "Gather softly under the lights."], ["今晚，月色不催人。", "Tonight, the moon keeps no time."], ["好久不见，夜还很长。", "Good to see you. The night is young."], ["在光影里，碰个面。", "Meet me where the colors fall."], ["此刻，城市轻了下来。", "For a moment, the city grows quiet."], ["风过窗边，故事开场。", "A breeze at the window. A story begins."], ["星光很远，你们很近。", "Distant stars. Good company close."], ["让灯火替今晚署名。", "Let the lights sign this evening."], ["留一点清醒，给夜色。", "Keep a little clarity for the night."], ["不赶路，只赴这一席。", "No rush. Just this table."], ["把疲惫放在门外。", "Leave the long day at the door."], ["相逢，就是今晚的好牌。", "Good company is tonight’s best hand."], ["灯下有你，夜便有温度。", "Your company warms the neon."], ["城市流光，心事靠岸。", "The city glows. Let your thoughts rest."], ["今夜不远，就在桌边。", "Tonight is right here at the table."], ["河面起光，故事未央。", "Light on the river. More stories to tell."], ["借夜色，见一面。", "A little midnight. A little company."], ["让快乐，轻轻发生。", "Let a little joy arrive quietly."]]
const TURN = [["想清楚，再让筹码开口。", "Think first. Let the chips speak later."], ["留一拍，听听自己的判断。", "Take a beat. Trust a considered choice."], ["夜还长，不必急着证明。", "The night is long. Nothing to prove."], ["一手输赢，不定义今夜。", "One hand does not define the night."], ["心静一点，牌看清一点。", "A quieter mind sees a clearer table."], ["可以收手，也可以从容。", "Folding can be a calm decision."], ["先呼吸，再决定。", "Breathe first. Decide after."], ["只是一场游戏，别丢了好心情。", "It is a game. Keep the good feeling."], ["让情绪经过，别替你下注。", "Let feelings pass before chips move."], ["享受夜色，不追逐上一手。", "Enjoy the night. Leave the last hand behind."], ["输赢会散，朋友还在。", "Hands come and go. Friends stay."], ["筹码有起落，心不必跟着走。", "Chips rise and fall. Stay steady."], ["把目光留在这一手。", "Give this hand a fresh look."], ["谨慎，也是一种漂亮。", "There is grace in a careful choice."], ["不必每一次都争到最后。", "You need not see every hand through."], ["让判断，比心跳慢半拍。", "Let your judgment settle before you act."], ["好运不必追，分寸要握住。", "Do not chase luck. Keep your balance."], ["牌可以放下，夜色不会走。", "You can fold. The night will stay."], ["先看清，再靠近。", "Look carefully before stepping in."], ["小小停顿，也有力量。", "A small pause has its own strength."], ["把上一手，留给上一刻。", "Leave the last hand in the last moment."], ["今晚值得记住的不只输赢。", "Tonight has more to remember than a score."], ["有把握再走，没把握也能停。", "Move with purpose. Pausing is allowed."], ["轻一点玩，长一点开心。", "Play lightly. Let the good mood last."]]
const COMPANY = [
	["一桌好友 · 一夜好牌", "GOOD FRIENDS. GREAT HANDS."],
	["灯火正好 · 故友入席", "WARM LIGHTS. OLD FRIENDS."],
	["今夜有约 · 桌边见面", "TONIGHT. AROUND THE TABLE."],
	["好牌随缘 · 好友在座", "LUCK COMES. FRIENDS STAY."],
	["霓虹作伴 · 笑语成局", "NEON LIGHTS. EASY LAUGHTER."],
	["一席微光 · 满桌故事", "SOFT LIGHT. SHARED STORIES."],
	["落座相逢 · 尽兴而归", "SIT TOGETHER. LEAVE HAPPY."],
	["牌有起落 · 情谊常在", "HANDS CHANGE. FRIENDS REMAIN."],
	["夜色温柔 · 好友慢聚", "A SOFT NIGHT. NO NEED TO RUSH."],
	["此刻同桌 · 今夜同频", "ONE TABLE. THE SAME GOOD MOOD."]
]
var rng := RandomNumberGenerator.new()
var _bags: Dictionary = {}
var _last: Dictionary = {}
func next_index(kind: String) -> int:
	var lines: Array = COMPANY if kind == "company" else (HOME if kind == "home" else TURN)
	var bag: Array = _bags.get(kind, [])
	if bag.is_empty():
		bag = range(lines.size())
		for index in range(bag.size() - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var swap: int = bag[index]
			bag[index] = bag[other]
			bag[other] = swap
		if bag.back() == _last.get(kind, -1):
			var swap: int = bag[0]
			bag[0] = bag[-1]
			bag[-1] = swap
	var selected: int = bag.pop_back()
	_bags[kind] = bag
	_last[kind] = selected
	return selected
func line(kind: String, index: int, language: String) -> String:
	var lines: Array = COMPANY if kind == "company" else (HOME if kind == "home" else TURN)
	return lines[posmod(index, lines.size())][0 if language == "zh" else 1]
