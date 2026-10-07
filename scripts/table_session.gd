extends Node
class_name TableSession

signal state_changed(state: Dictionary)
signal status_changed(message: String)
signal chip_gesture(seat: int, sequence: int, style: int)
signal board_gesture(seat: int, sequence: int, index: int, kind: String, offset: Vector2)
signal table_prop_gesture(seat: int, sequence: int, kind: String)

const Inventory = preload("res://scripts/chip_inventory.gd")
var _chip_players: Array = []
var _pot_chips: Dictionary = {}
var _settlement_pot_chips: Dictionary = {}
var _chip_transfers: Array = []
var _chip_revision := 0

const EngineScript = preload("res://scripts/poker_engine.gd")
const ChipGestures = preload("res://scripts/chip_gestures.gd")
const PokerAI = preload("res://scripts/poker_ai.gd")
const MAX_PLAYERS := 6
const MIN_STACK := 100
const MAX_STACK := 1000000
const ACTIONS := ["fold", "check", "call", "raise", "all_in"]
const CHIP_GESTURE_INTERVAL_MS := 350
const MAX_GESTURE_SEQUENCE := 2147483647
const BOARD_GESTURE_TICK_MS := 50
const BOARD_GESTURE_TTL_MS := 1500
const BOARD_PRESS_INTERVAL_MS := 100

var state: Dictionary = {}
var is_host := false
var is_local := false
var is_solo := false
var ai_aggression := 6
var deck_theme := 0
var _deck_theme_revision := 0
var host_name := ""
var host_port := 0
var local_seat := -1
var _engine = EngineScript.new()
var _peer: ENetMultiplayerPeer
var _names: Array = []
var _peer_seats: Dictionary = {}
var _connected: Array = []
var _stack := 1000
var _revision := 0
var _paused := false
var _connection_lost := false
var _started := false
var _joining_name := ""
var _room_id := ""
var _gesture_request_sequence := 0
var _gesture_server_sequence := 0
var _gesture_received_sequence := 0
var _gesture_last_sent: Dictionary = {}
var _gesture_last_request: Dictionary = {}
var _gesture_last_accepted: Dictionary = {}
var _gesture_last_received: Dictionary = {}
var _gesture_last_normal: Dictionary = {}
var _gesture_rare_until: Dictionary = {}
# Separate from all deck randomness; replaceable in deterministic test fixtures.
var _gesture_rng = RandomNumberGenerator.new()
var _solo_rng := RandomNumberGenerator.new()
var _lan_dealer_rng := RandomNumberGenerator.new()
var _solo_first_dealer := -1
var _solo_ai = PokerAI.new()
var _bot_levels: Dictionary = {}
var _bot_policies: Dictionary = {}
var _next_bot_name := 1
var _board_request_sequence := 0
var _board_server_sequence := 0
var _board_received_sequence := 0
var _board_last_request: Dictionary = {}
var _board_last_press: Dictionary = {}
var _board_owners: Dictionary = {}
var _board_activity: Dictionary = {}
var _board_visible_owners: Dictionary = {}
var _board_client_drags: Dictionary = {}
var _board_pending_drags: Dictionary = {}
var _board_edges: Array = []
var _board_next_tick := 0
var _prop_request_sequence := 0
var _prop_server_sequence := 0
var _prop_received_sequence := 0
var _prop_last_request: Dictionary = {}

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func set_deck_theme(value: int) -> bool:
	if value < 0 or value > 3 or _paused or _connection_lost: return false
	# An idle session can prepare its next local/host room. Joining peers may not
	# override the authoritative theme, including before registration completes.
	if not is_host and not is_local and (_peer != null or not state.is_empty()): return false
	if deck_theme == value: return true
	deck_theme = value
	_deck_theme_revision += 1
	if is_host and not state.is_empty(): _publish_snapshot()
	return true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _board_next_tick: return
	_board_next_tick = now + BOARD_GESTURE_TICK_MS
	var drags := _board_client_drags.duplicate()
	_board_client_drags.clear()
	for index in drags:
		_send_board_request(index, "drag", drags[index])
	if not is_host: return
	for index in _board_owners.keys():
		if now - int(_board_activity.get(index, 0)) >= BOARD_GESTURE_TTL_MS:
			_end_board_hold(index)
	_flush_board_events()

func _can_touch_board(seat: int) -> bool:
	if _paused or _connection_lost or state.is_empty() or state.get("paused", false) or int(state.get("hand_id", 0)) <= 0:
		return false
	var players: Array = state.get("players", [])
	return seat >= 0 and seat < players.size() and players[seat].get("connected", true) and not players[seat].get("is_bot", false)

func _valid_board_input(index: int, kind: String, offset: Vector2) -> bool:
	return index >= 0 and index < 5 and kind in ["press", "drag", "release"] and offset.is_finite() and absf(offset.x) <= 1.0 and absf(offset.y) <= 1.0

func request_board_gesture(index: int, kind: String, offset: Vector2) -> void:
	if not _valid_board_input(index, kind, offset) or not _can_touch_board(local_seat): return
	if kind == "drag":
		# One latest sample per card; no per-frame reliable RPC backlog.
		_board_client_drags[index] = offset
	else:
		_board_client_drags.erase(index)
		_send_board_request(index, kind, offset)

func _send_board_request(index: int, kind: String, offset: Vector2) -> void:
	if not _can_touch_board(local_seat) or _board_request_sequence >= MAX_GESTURE_SEQUENCE: return
	_board_request_sequence += 1
	var hand: int = state.get("hand_id", -1)
	var board_count: int = state.get("board", []).size()
	if is_host:
		_accept_board_gesture(local_seat, -local_seat - 1 if is_local else 1, hand, _board_request_sequence, _room_id, board_count, index, kind, offset)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_board_gesture.rpc_id(1, hand, _board_request_sequence, _room_id, board_count, index, kind, offset)

@rpc("any_peer", "call_remote", "reliable")
func _request_board_gesture(hand: int, sequence: int, room: String, board_count: int, index: int, kind: String, offset: Vector2) -> void:
	if not is_host or is_local: return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not _peer_seats.has(sender): return
	_accept_board_gesture(_peer_seats[sender], sender, hand, sequence, room, board_count, index, kind, offset)

func _accept_board_gesture(seat: int, sender: int, hand: int, sequence: int, room: String, board_count: int, index: int, kind: String, offset: Vector2) -> void:
	if not is_host or not _can_touch_board(seat) or not _valid_board_input(index, kind, offset): return
	if room != _room_id or hand != int(state.get("hand_id", -1)) or board_count != state.get("board", []).size(): return
	if (is_local and sender != -seat - 1) or (not is_local and int(_peer_seats.get(sender, -1)) != seat): return
	if sequence <= int(_board_last_request.get(sender, 0)) or sequence > MAX_GESTURE_SEQUENCE: return
	# Consume even losing presses, so a replay cannot acquire a subsequently released card.
	_board_last_request[sender] = sequence
	var now := Time.get_ticks_msec()
	if kind == "press":
		# Keep a hard queue bound even if a malicious peer floods between process ticks.
		# Reserve room for releases of all five currently held cards.
		if _board_edges.size() >= 24: return
		if _board_owners.has(index) or now - int(_board_last_press.get(index, -BOARD_PRESS_INTERVAL_MS)) < BOARD_PRESS_INTERVAL_MS: return
		_board_last_press[index] = now
		_board_owners[index] = seat
		_board_activity[index] = now
		_board_edges.append([seat, index, kind, offset])
	elif int(_board_owners.get(index, -1)) == seat:
		if kind == "release":
			_end_board_hold(index)
		else:
			_board_activity[index] = now
			_board_pending_drags[index] = [seat, index, kind, offset]

func _end_board_hold(index: int) -> void:
	if not _board_owners.has(index): return
	_board_edges.append([int(_board_owners[index]), index, "release", Vector2.ZERO])
	_board_owners.erase(index)
	_board_activity.erase(index)
	_board_pending_drags.erase(index)

func _flush_board_events() -> void:
	var hand: int = state.get("hand_id", -1)
	var room := _room_id
	var board_count: int = state.get("board", []).size()
	var outgoing := _board_edges.duplicate()
	_board_edges.clear()
	for event in _board_pending_drags.values(): outgoing.append(event)
	_board_pending_drags.clear()
	for event in outgoing:
		if room != _room_id or hand != int(state.get("hand_id", -1)) or board_count != state.get("board", []).size(): return
		if not _can_touch_board(event[0]) or _board_server_sequence >= MAX_GESTURE_SEQUENCE: continue
		_board_server_sequence += 1
		if not is_local and _peer != null:
			for peer_id in _peer_seats:
				if peer_id != 1:
					_receive_board_gesture.rpc_id(peer_id, event[0], _board_server_sequence, hand, room, board_count, event[1], event[2], event[3])
		_receive_board_gesture(event[0], _board_server_sequence, hand, room, board_count, event[1], event[2], event[3])

@rpc("authority", "call_remote", "reliable")
func _receive_board_gesture(seat: int, sequence: int, hand: int, room: String, board_count: int, index: int, kind: String, offset: Vector2) -> void:
	if not _can_touch_board(seat) or not _valid_board_input(index, kind, offset): return
	if room != _room_id or hand != int(state.get("hand_id", -1)) or board_count != state.get("board", []).size(): return
	if sequence <= _board_received_sequence or sequence > MAX_GESTURE_SEQUENCE: return
	_board_received_sequence = sequence
	if kind == "press":
		if _board_visible_owners.has(index): return
		_board_visible_owners[index] = seat
	else:
		if int(_board_visible_owners.get(index, -1)) != seat: return
		if kind == "release": _board_visible_owners.erase(index)
	board_gesture.emit(seat, sequence, index, kind, Vector2.ZERO if kind == "release" else offset)

func _reset_board_gestures(reset_sequences: bool = true) -> void:
	var visible := _board_visible_owners.duplicate()
	_board_visible_owners.clear()
	_board_owners.clear()
	_board_activity.clear()
	_board_client_drags.clear()
	_board_pending_drags.clear()
	_board_edges.clear()
	_board_last_press.clear()
	if reset_sequences:
		_board_request_sequence = 0
		_board_server_sequence = 0
		_board_received_sequence = 0
		_board_last_request.clear()
	for index in visible:
		# Local lifecycle cleanup also works after transport loss, without another RPC.
		board_gesture.emit(int(visible[index]), _board_received_sequence, index, "release", Vector2.ZERO)

func _can_touch_table_prop(seat: int, kind: String) -> bool:
	# Showdown's pot field is a settlement total, not chips still on the table.
	return kind in ["pot", "deck"] and _can_touch_board(seat) and (kind == "deck" or (int(state.get("pot", 0)) > 0 and state.get("phase", "") != "showdown"))

func request_table_prop_gesture(kind: String) -> void:
	if not _can_touch_table_prop(local_seat, kind) or _room_id.is_empty(): return
	if _prop_request_sequence >= MAX_GESTURE_SEQUENCE: return
	_prop_request_sequence += 1
	var hand: int = state.get("hand_id", -1)
	if is_host:
		_accept_table_prop_gesture(local_seat, -local_seat - 1 if is_local else 1, hand, _prop_request_sequence, _room_id, kind)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_table_prop_gesture.rpc_id(1, hand, _prop_request_sequence, _room_id, kind)

@rpc("any_peer", "call_remote", "reliable")
func _request_table_prop_gesture(hand: int, sequence: int, room: String, kind: String) -> void:
	if not is_host or is_local: return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not _peer_seats.has(sender): return
	_accept_table_prop_gesture(_peer_seats[sender], sender, hand, sequence, room, kind)

func _accept_table_prop_gesture(seat: int, sender: int, hand: int, sequence: int, room: String, kind: String) -> void:
	if not is_host or not _can_touch_table_prop(seat, kind) or room != _room_id or hand != int(state.get("hand_id", -1)): return
	if (is_local and sender != -seat - 1) or (not is_local and int(_peer_seats.get(sender, -1)) != seat): return
	if sequence <= int(_prop_last_request.get(sender, 0)) or sequence > MAX_GESTURE_SEQUENCE: return
	# Every fresh human tap is accepted immediately; sequence validation rejects replay.
	_prop_last_request[sender] = sequence
	if _prop_server_sequence >= MAX_GESTURE_SEQUENCE: return
	_prop_server_sequence += 1
	if not is_local and _peer != null:
		for peer_id in _peer_seats:
			if peer_id != 1: _receive_table_prop_gesture.rpc_id(peer_id, seat, _prop_server_sequence, hand, room, kind)
	_receive_table_prop_gesture(seat, _prop_server_sequence, hand, room, kind)

@rpc("authority", "call_remote", "reliable")
func _receive_table_prop_gesture(seat: int, sequence: int, hand: int, room: String, kind: String) -> void:
	if not _can_touch_table_prop(seat, kind) or room != _room_id or hand != int(state.get("hand_id", -1)): return
	if sequence <= _prop_received_sequence or sequence > MAX_GESTURE_SEQUENCE: return
	_prop_received_sequence = sequence
	table_prop_gesture.emit(seat, sequence, kind)

func _reset_table_prop_gestures() -> void:
	_prop_request_sequence = 0
	_prop_server_sequence = 0
	_prop_received_sequence = 0
	_prop_last_request.clear()

func host_game(player_name: String, stack: int = 1000, port: int = 27846) -> Error:
	if not _valid_name(player_name) or not _valid_stack(stack) or not _valid_port(port):
		status_changed.emit("Invalid name, starting chips, or port.")
		return ERR_INVALID_PARAMETER
	leave_game()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		_peer = null
		status_changed.emit("Could not host: check the port and firewall.")
		return error
	multiplayer.multiplayer_peer = _peer
	is_host = true
	host_name = player_name.strip_edges()
	host_port = port
	local_seat = 0
	_stack = stack
	_names = [player_name.strip_edges()]
	_connected = [true]
	_peer_seats = {1: 0}
	_room_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_publish()
	status_changed.emit("Room open. Friends can find it in Local Tables.")
	return OK

func join_game(address: String, player_name: String, port: int = 27846) -> Error:
	if not _valid_name(player_name) or address.strip_edges().is_empty() or not _valid_port(port):
		status_changed.emit("Invalid address, name, or port.")
		return ERR_INVALID_PARAMETER
	leave_game()
	_joining_name = player_name.strip_edges()
	host_port = port
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address.strip_edges(), port)
	if error != OK:
		_peer = null
		status_changed.emit("Could not connect to this address.")
		return error
	multiplayer.multiplayer_peer = _peer
	status_changed.emit("Connecting to room...")
	return OK

func start_local(names: Array, stack: int = 1000) -> void:
	if names.size() < 2 or names.size() > MAX_PLAYERS or not _valid_stack(stack):
		status_changed.emit("Use 2–6 players and 100–1,000,000 chips.")
		return
	for player_name in names:
		if not player_name is String or not _valid_name(player_name):
			status_changed.emit("Names must contain 1–24 printable characters.")
			return
	leave_game()
	is_local = true
	is_host = true
	local_seat = 0
	_stack = stack
	_room_id = Crypto.new().generate_random_bytes(16).hex_encode()
	for player_name in names:
		_names.append(player_name.strip_edges())
		_connected.append(true)
	host_name = str(_names[0])
	_engine.configure(_names, _stack)
	_publish()
	status_changed.emit("Local pass-and-play test. Switch seat before viewing private cards.")

func start_solo(player_name: String, stack: int = 1000, count: int = 5) -> void:
	if not _valid_name(player_name) or not _valid_stack(stack) or count < 2 or count > MAX_PLAYERS:
		status_changed.emit("Invalid solo name, chips, or player count.")
		return
	leave_game()
	is_local = true
	is_solo = true
	is_host = true
	local_seat = 0
	_stack = stack
	_room_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_names = [player_name.strip_edges()]
	host_name = player_name.strip_edges()
	_connected = [true]
	for seat in range(1, count):
		_names.append("AI %d" % seat)
		_connected.append(true)
		_bot_levels[seat] = ai_aggression
	_solo_first_dealer = _solo_rng.randi_range(0, count - 1)
	_publish()
	status_changed.emit("Solo table ready. You play against computer opponents.")

func advance_solo() -> bool:
	return advance_bots() if is_solo else false

func is_bot_turn() -> bool:
	if state.is_empty() or _paused or _connection_lost or state.get("paused", false):
		return false
	var actor: int = state.get("actor", -1)
	var players: Array = state.get("players", [])
	return actor >= 0 and actor < players.size() and players[actor].get("is_bot", false)

func advance_bots() -> bool:
	if not is_host or not _started or not is_bot_turn():
		return false
	var actor: int = state.get("actor", -1)
	if not _bot_levels.has(actor):
		return false
	# Only this bot's recipient-safe snapshot enters its policy. No live engine reference.
	var policy = _solo_ai if is_solo else _bot_policies.get(actor)
	if policy == null: return false
	var decision: Dictionary = policy.choose(_snapshot_for(actor))
	if decision.is_empty():
		return false
	var chip_before: Dictionary = _engine.snapshot(0)
	if not _engine.act(actor, str(decision.get("action", "")), int(decision.get("amount", 0))):
		return false
	_sync_chip_transition(chip_before)
	_publish()
	return true

func _can_manage_bots() -> bool:
	return is_host and not is_local and not _started and not _paused and not _connection_lost and not state.is_empty()

func add_bot(aggression: int = 6) -> bool:
	if not _can_manage_bots() or _names.size() >= MAX_PLAYERS or aggression < 0 or aggression > 10:
		return false
	var seat := _names.size()
	_names.append("AI %d" % _next_bot_name)
	_next_bot_name += 1
	_connected.append(true)
	_bot_levels[seat] = aggression
	var policy := PokerAI.new()
	policy.aggression = aggression
	_bot_policies[seat] = policy
	_publish()
	return true

func remove_bot(seat: int) -> bool:
	if not _can_manage_bots() or not _bot_levels.has(seat): return false
	_remove_lobby_seat(seat)
	_publish()
	return true

func set_bot_aggression(seat: int, level: int) -> bool:
	if not _can_manage_bots() or not _bot_levels.has(seat) or level < 0 or level > 10: return false
	if int(_bot_levels[seat]) == level: return true
	_bot_levels[seat] = level
	_bot_policies[seat].aggression = level
	_publish()
	return true

func _remove_lobby_seat(seat: int) -> void:
	_names.remove_at(seat)
	_connected.remove_at(seat)
	for peer_id in _peer_seats:
		if int(_peer_seats[peer_id]) > seat: _peer_seats[peer_id] -= 1
	for seat_map in [_bot_levels, _bot_policies, _gesture_last_sent, _gesture_last_received, _gesture_last_normal, _gesture_rare_until]:
		var shifted: Dictionary = {}
		for index in seat_map:
			if int(index) != seat: shifted[int(index) - (1 if int(index) > seat else 0)] = seat_map[index]
		seat_map.clear()
		seat_map.merge(shifted)

func set_ai_aggression(level: int) -> void:
	ai_aggression = clampi(level, 0, 10)
	_solo_ai.aggression = ai_aggression
	if is_solo:
		for seat in _bot_levels: _bot_levels[seat] = ai_aggression
		if not state.is_empty():
			for player in state.players:
				if player.get("is_bot", false): player["ai_aggression"] = ai_aggression

func begin_hand() -> void:
	if _paused:
		status_changed.emit("Table paused. Create a new room to continue.")
		return
	if not is_host or _names.size() < 2:
		status_changed.emit("Only the host can deal, with at least two connected players.")
		return
	if not _started:
		var first_dealer := _solo_first_dealer if is_solo else -1
		if not is_local:
			first_dealer = _lan_dealer_rng.randi_range(0, _names.size() - 1)
		if not _engine.configure(_names, _stack, 5, 10, first_dealer):
			status_changed.emit(_engine.last_error)
			return
	if not _started:
		_chip_players.clear()
		for _seat in _names.size(): _chip_players.append(Inventory.balanced(_stack))
	var chip_before: Dictionary = _engine.snapshot(0)
	for player in chip_before.players: player.committed = 0
	if not _engine.start_hand():
		status_changed.emit(_engine.last_error)
		return
	_settlement_pot_chips.clear()
	_pot_chips.clear()
	_sync_chip_transition(chip_before)
	_started = true
	_reset_chip_gestures()
	_reset_board_gestures()
	_reset_table_prop_gestures()
	_publish()

func submit_action(action: String, amount: int = 0) -> void:
	if state.is_empty() or _paused or local_seat < 0:
		return
	var hand_id: int = state.get("hand_id", 0)
	var revision: int = state.get("revision", -1)
	if is_host:
		_apply_action(local_seat, action, amount, hand_id, revision, 1)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_action.rpc_id(1, action, amount, hand_id, revision)

func set_local_seat(seat: int) -> void:
	if not is_local or is_solo or seat < 0 or seat >= _names.size():
		return
	_board_client_drags.clear()
	local_seat = seat
	# Changing viewpoint is not a server state change and must not invalidate actions.
	state = _snapshot_for(seat)
	state_changed.emit(state.duplicate(true))

func request_chip_gesture() -> void:
	if not _can_play_chips(local_seat) or _room_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_gesture_last_sent.get(local_seat, -CHIP_GESTURE_INTERVAL_MS)) < CHIP_GESTURE_INTERVAL_MS:
		return
	if _gesture_request_sequence >= MAX_GESTURE_SEQUENCE:
		return
	_gesture_last_sent[local_seat] = now
	_gesture_request_sequence += 1
	var hand_id: int = state.get("hand_id", -1)
	if is_host:
		var sender_key := -local_seat - 1 if is_local else 1
		_accept_chip_gesture(local_seat, sender_key, hand_id, _gesture_request_sequence, _room_id)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_chip_gesture.rpc_id(1, hand_id, _gesture_request_sequence, _room_id)

func _can_play_chips(seat: int) -> bool:
	if _paused or _connection_lost or state.is_empty() or state.get("paused", false):
		return false
	var players: Array = state.get("players", [])
	return seat >= 0 and seat < players.size() and players[seat].get("connected", true) and int(players[seat].get("stack", 0)) > 0

func play_bot_chip_gesture(seat: int) -> bool:
	# Host-local cosmetic entry point. Human RPCs never select a bot's seat.
	if not is_host or not _started or not _bot_levels.has(seat) or not _can_play_chips(seat) or _room_id.is_empty():
		return false
	if state.get("phase", "") not in ["preflop", "flop", "turn", "river"]:
		return false
	var now := Time.get_ticks_msec()
	if now < int(_gesture_rare_until.get(seat, 0)) or now - int(_gesture_last_sent.get(seat, -15000)) < 15000:
		return false
	if _gesture_server_sequence >= MAX_GESTURE_SEQUENCE: return false
	_gesture_last_sent[seat] = now
	_gesture_server_sequence += 1
	var style := _choose_chip_style(seat)
	if style == ChipGestures.RARE:
		_gesture_rare_until[seat] = now + int(ChipGestures.duration(style) * 1000.0)
	var hand_id: int = state.get("hand_id", -1)
	if not is_local and _peer != null:
		for peer_id in _peer_seats:
			if peer_id != 1:
				_receive_chip_gesture.rpc_id(peer_id, seat, _gesture_server_sequence, hand_id, _room_id, style)
	_receive_chip_gesture(seat, _gesture_server_sequence, hand_id, _room_id, style)
	return true

func _reset_chip_gestures() -> void:
	_gesture_request_sequence = 0
	_gesture_server_sequence = 0
	_gesture_received_sequence = 0
	_gesture_last_sent.clear()
	_gesture_last_request.clear()
	_gesture_last_accepted.clear()
	_gesture_last_received.clear()
	_gesture_last_normal.clear()
	_gesture_rare_until.clear()

func _choose_chip_style(seat: int) -> int:
	if _gesture_rng.randi_range(0, 99) == 0:
		return ChipGestures.RARE
	var previous: int = _gesture_last_normal.get(seat, -1)
	var choices: Array = ChipGestures.NORMAL.values()
	choices.erase(previous)
	var style: int = choices[_gesture_rng.randi_range(0, choices.size() - 1)]
	_gesture_last_normal[seat] = style
	return style

@rpc("any_peer", "call_remote", "reliable")
func _request_chip_gesture(hand_id: int, request_sequence: int, room_id: String) -> void:
	if not is_host or is_local:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not _peer_seats.has(sender):
		return
	_accept_chip_gesture(_peer_seats[sender], sender, hand_id, request_sequence, room_id)

func _accept_chip_gesture(seat: int, sender_key: int, hand_id: int, request_sequence: int, room_id: String) -> void:
	if not is_host or not _can_play_chips(seat) or room_id != _room_id or hand_id != int(state.get("hand_id", -1)):
		return
	if _bot_levels.has(seat): return
	if (is_local and sender_key != -seat - 1) or (not is_local and int(_peer_seats.get(sender_key, -1)) != seat):
		return
	if request_sequence <= 0 or request_sequence > MAX_GESTURE_SEQUENCE or request_sequence <= int(_gesture_last_request.get(sender_key, 0)):
		return
	# Even rate-limited requests are consumed: replay cannot turn a dropped tap into a queued one.
	_gesture_last_request[sender_key] = request_sequence
	var now := Time.get_ticks_msec()
	if now < int(_gesture_rare_until.get(seat, 0)):
		return
	if now - int(_gesture_last_accepted.get(sender_key, -CHIP_GESTURE_INTERVAL_MS)) < CHIP_GESTURE_INTERVAL_MS:
		return
	if _gesture_server_sequence >= MAX_GESTURE_SEQUENCE:
		return
	_gesture_last_accepted[sender_key] = now
	_gesture_server_sequence += 1
	var style := _choose_chip_style(seat)
	if style == ChipGestures.RARE:
		_gesture_rare_until[seat] = now + int(ChipGestures.duration(style) * 1000.0)
	if not is_local and _peer != null:
		for peer_id in _peer_seats:
			if peer_id != 1:
				_receive_chip_gesture.rpc_id(peer_id, seat, _gesture_server_sequence, hand_id, _room_id, style)
	_receive_chip_gesture(seat, _gesture_server_sequence, hand_id, _room_id, style)

@rpc("authority", "call_remote", "reliable")
func _receive_chip_gesture(seat: int, sequence: int, hand_id: int, room_id: String, style: int = 0) -> void:
	if not ChipGestures.is_valid_style(style) or room_id != _room_id or hand_id != int(state.get("hand_id", -1)) or not _can_play_chips(seat):
		return
	if sequence <= _gesture_received_sequence or sequence > MAX_GESTURE_SEQUENCE:
		return
	_gesture_received_sequence = sequence
	var now := Time.get_ticks_msec()
	# Consume delayed reliable packets without replaying a burst of old sounds on resume.
	if now - int(_gesture_last_received.get(seat, -CHIP_GESTURE_INTERVAL_MS)) < CHIP_GESTURE_INTERVAL_MS:
		return
	_gesture_last_received[seat] = now
	chip_gesture.emit(seat, sequence, style)

func leave_game() -> void:
	_chip_players.clear()
	_settlement_pot_chips.clear()
	_pot_chips.clear()
	_chip_transfers.clear()
	_chip_revision = 0
	_reset_board_gestures()
	_reset_table_prop_gestures()
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	is_local = false
	is_solo = false
	host_name = ""
	host_port = 0
	_bot_levels.clear()
	_bot_policies.clear()
	_next_bot_name = 1
	_solo_first_dealer = -1
	_solo_ai = PokerAI.new()
	_solo_ai.aggression = ai_aggression
	local_seat = -1
	state = {}
	_names = []
	_connected = []
	_peer_seats = {}
	_revision = 0
	_deck_theme_revision = 0
	_paused = false
	_connection_lost = false
	_started = false
	_room_id = ""
	_reset_chip_gestures()
	_engine = EngineScript.new()

func _valid_name(value: String) -> bool:
	var cleaned := value.strip_edges()
	if cleaned.is_empty() or cleaned.length() > 24:
		return false
	for index in cleaned.length():
		if cleaned.unicode_at(index) < 32 or cleaned.unicode_at(index) == 127:
			return false
	return true

func _valid_stack(value: int) -> bool:
	return value >= MIN_STACK and value <= MAX_STACK

func _valid_port(value: int) -> bool:
	return value >= 1024 and value <= 65535

func _on_connected() -> void:
	_register_player.rpc_id(1, _joining_name)

func _on_connection_failed() -> void:
	leave_game()
	status_changed.emit("Connection failed. Check LAN IP, Wi-Fi, and host firewall.")
	state_changed.emit({})

func _on_server_disconnected() -> void:
	_connection_lost = true
	_paused = true
	_reset_board_gestures()
	_reset_table_prop_gestures()
	if not state.is_empty():
		state["paused"] = true
		state["can_start"] = false
		state["legal"] = {}
		state_changed.emit(state.duplicate(true))
	status_changed.emit("Host disconnected. Table paused; create a new room to continue.")

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host or not _peer_seats.has(peer_id):
		return
	var seat: int = _peer_seats[peer_id]
	_peer_seats.erase(peer_id)
	_gesture_last_request.erase(peer_id)
	_gesture_last_accepted.erase(peer_id)
	if _started:
		_connected[seat] = false
		_paused = true
		_reset_board_gestures()
		_reset_table_prop_gestures()
		_publish()
		status_changed.emit("A player disconnected. Table paused; create a new room to continue.")
	else:
		_remove_lobby_seat(seat)
		_publish()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String) -> void:
	if not is_host or is_local:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or _peer_seats.has(sender):
		return
	if _started or _paused:
		_reject_join.rpc_id(sender, "This table has already started. Ask the host to create a new room.")
		return
	if _names.size() >= MAX_PLAYERS or not _valid_name(player_name):
		_reject_join.rpc_id(sender, "Room full or invalid player name.")
		return
	_peer_seats[sender] = _names.size()
	_names.append(player_name.strip_edges())
	_connected.append(true)
	_publish()

@rpc("authority", "call_remote", "reliable")
func _reject_join(message: String) -> void:
	leave_game()
	status_changed.emit(message)
	state_changed.emit({})

@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String, amount: int, hand_id: int, revision: int) -> void:
	if not is_host or is_local:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_seats.has(sender):
		return
	_apply_action(_peer_seats[sender], action, amount, hand_id, revision, sender)

func _apply_action(seat: int, action: String, amount: int, hand_id: int, revision: int, sender: int, selected: Dictionary = {}) -> void:
	if not is_host or _paused or not _started:
		return
	# Recreational/local calls and human RPCs may never act for a bot. Only advance_bots
	# executes bot decisions; LAN human identity is checked again at the mutation boundary.
	if _bot_levels.has(seat) or (not is_local and int(_peer_seats.get(sender, -1)) != seat):
		return
	if hand_id != state.get("hand_id", -1) or revision != _revision:
		_action_error(sender, "Action expired; use the current table state.")
		return
	if seat < 0 or seat >= _names.size() or not ACTIONS.has(action) or amount < 0 or amount > MAX_STACK * MAX_PLAYERS:
		_action_error(sender, "Invalid action.")
		return
	if not selected.is_empty():
		if seat >= _chip_players.size() or not Inventory.contains(_chip_players[seat], selected): return
		var expected := Inventory.value(selected)
		var player: Dictionary = state.players[seat]
		if (action == "raise" and amount - int(player.bet) != expected) or (action == "all_in" and int(player.stack) != expected) or action not in ["raise", "all_in"]: return
	var chip_before: Dictionary = _engine.snapshot(0)
	if not _engine.act(seat, action, amount):
		_action_error(sender, _engine.last_error)
		return
	_sync_chip_transition(chip_before, seat, selected)
	_publish()

func _action_error(peer_id: int, message: String) -> void:
	if peer_id == 1:
		status_changed.emit(message)
	else:
		_receive_status.rpc_id(peer_id, message)

@rpc("authority", "call_remote", "reliable")
func _receive_status(message: String) -> void:
	status_changed.emit(message)

func _publish() -> void:
	_revision += 1
	_publish_snapshot()

func _publish_snapshot() -> void:
	var snapshot := _snapshot_for(local_seat)
	if snapshot.get("board", []) != state.get("board", []):
		_reset_board_gestures(false)
	state = snapshot
	if not is_local and _peer != null:
		for peer_id in _peer_seats:
			if peer_id != 1:
				# Never broadcast: each packet contains only this recipient's private cards.
				_receive_state.rpc_id(peer_id, _snapshot_for(_peer_seats[peer_id]))
	state_changed.emit(state.duplicate(true))

func _snapshot_for(seat: int) -> Dictionary:
	var snapshot: Dictionary
	if not _started:
		var players: Array = []
		for index in _names.size():
			players.append({"name": _names[index], "stack": _stack, "bet": 0, "committed": 0,
				"folded": false, "all_in": false, "cards": [-1, -1], "connected": _connected[index]})
		snapshot = {"phase": "lobby", "hand_id": 0, "dealer": -1, "actor": -1, "board": [],
			"small_blind_seat": -1, "big_blind_seat": -1, "small_blind": 5, "big_blind": 10,
			"pot": 0, "current_bet": 0, "min_raise_to": 20, "players": players, "you": seat, "legal": {}, "result": []}
	else:
		snapshot = _engine.snapshot(seat)
		for index in snapshot.players.size():
			snapshot.players[index]["connected"] = _connected[index]
	snapshot["settlement_pot_chips"] = _settlement_pot_chips.duplicate()
	snapshot["pot_chips"] = _pot_chips.duplicate(true)
	snapshot["chip_transfers"] = _chip_transfers.duplicate(true)
	snapshot["chip_revision"] = _chip_revision
	for index in snapshot.players.size():
		snapshot.players[index]["chips"] = _chip_players[index].duplicate() if index < _chip_players.size() else Inventory.balanced(_stack)
	snapshot["revision"] = _revision
	snapshot["deck_theme"] = deck_theme
	snapshot["deck_theme_revision"] = _deck_theme_revision
	snapshot["room_id"] = _room_id
	snapshot["room_name"] = host_name
	snapshot["host_port"] = host_port
	snapshot["paused"] = _paused
	snapshot["mode"] = "solo" if is_solo else ("local" if is_local else "lan")
	for index in snapshot.players.size():
		snapshot.players[index]["is_bot"] = _bot_levels.has(index)
		snapshot.players[index]["ai_aggression"] = int(_bot_levels.get(index, -1))
	var funded := 0
	for player in snapshot.get("players", []):
		if int(player.get("stack", 0)) > 0:
			funded += 1
	snapshot["can_start"] = not _paused and funded >= 2 and (not _started or snapshot.get("actor", -1) == -1)
	if _paused:
		snapshot["legal"] = {}
	return snapshot

@rpc("authority", "call_remote", "reliable")
func _receive_state(snapshot: Dictionary) -> void:
	var incoming_revision = snapshot.get("revision", -1)
	if is_host or _connection_lost or not incoming_revision is int or incoming_revision < 0 or incoming_revision < state.get("revision", -1):
		return
	var incoming_theme = snapshot.get("deck_theme", 0)
	var incoming_theme_revision = snapshot.get("deck_theme_revision", 0)
	if not incoming_theme is int or incoming_theme < 0 or incoming_theme > 3 or not incoming_theme_revision is int or incoming_theme_revision < 0: return
	if not state.is_empty():
		# A room switch always goes through leave/join, never through a delayed packet.
		if snapshot.get("room_id", "") != _room_id or incoming_theme_revision < _deck_theme_revision: return
		if snapshot.get("revision", -1) == state.get("revision", -1):
			if incoming_theme_revision <= _deck_theme_revision or snapshot.get("hand_id", -1) != state.get("hand_id", -1): return
			# Cosmetic revisions may update only these fields, never cards or legal actions.
			deck_theme = incoming_theme
			_deck_theme_revision = incoming_theme_revision
			state["deck_theme"] = deck_theme
			state["deck_theme_revision"] = _deck_theme_revision
			state_changed.emit(state.duplicate(true))
			return
	var was_paused := _paused
	if snapshot.get("room_id", "") != _room_id or snapshot.get("hand_id", -1) != state.get("hand_id", -1):
		_reset_chip_gestures()
		_reset_board_gestures()
		_reset_table_prop_gestures()
	elif snapshot.get("board", []) != state.get("board", []) or snapshot.get("paused", false):
		_reset_board_gestures(false)
	if snapshot.get("paused", false): _reset_table_prop_gestures()
	_room_id = str(snapshot.get("room_id", ""))
	host_name = str(snapshot.get("room_name", ""))
	host_port = int(snapshot.get("host_port", host_port))
	state = snapshot.duplicate(true)
	deck_theme = incoming_theme
	_deck_theme_revision = incoming_theme_revision
	local_seat = state.get("you", -1)
	_paused = state.get("paused", false)
	state_changed.emit(state.duplicate(true))
	if _paused and not was_paused:
		status_changed.emit("A player disconnected. Table paused; create a new room to continue.")


func submit_chip_action(chips: Dictionary) -> void:
	if state.is_empty() or local_seat < 0 or not Inventory.valid(chips) or Inventory.value(chips) <= 0: return
	if is_host:
		_accept_chip_action(local_seat, chips, int(state.hand_id), int(state.revision), 1)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_chip_action.rpc_id(1, chips, int(state.hand_id), int(state.revision))

@rpc("any_peer", "call_remote", "reliable")
func _request_chip_action(chips: Dictionary, hand: int, revision: int) -> void:
	if not is_host or is_local: return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not _peer_seats.has(sender): return
	_accept_chip_action(int(_peer_seats[sender]), chips, hand, revision, sender)

func _accept_chip_action(seat: int, chips: Dictionary, hand: int, revision: int, sender: int) -> void:
	if not Inventory.valid(chips) or Inventory.value(chips) <= 0 or seat < 0 or seat >= state.get("players", []).size(): return
	var player: Dictionary = state.players[seat]
	var amount := Inventory.value(chips)
	_apply_action(seat, "all_in" if amount == int(player.stack) else "raise", int(player.bet) + amount, hand, revision, sender, chips)

func exchange_chips(reserved: Dictionary = {}) -> void:
	if state.is_empty(): return
	if is_host:
		_accept_chip_exchange(local_seat, reserved, int(state.hand_id), int(state.revision), 1)
	elif _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_request_chip_exchange.rpc_id(1, reserved, int(state.hand_id), int(state.revision))

@rpc("any_peer", "call_remote", "reliable")
func _request_chip_exchange(reserved: Dictionary, hand: int, revision: int) -> void:
	if not is_host or is_local: return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not _peer_seats.has(sender): return
	_accept_chip_exchange(int(_peer_seats[sender]), reserved, hand, revision, sender)

func _accept_chip_exchange(seat: int, reserved: Dictionary, hand: int, revision: int, sender: int) -> void:
	if not is_host or not _started or _paused or _connection_lost: return
	if seat < 0 or seat >= _chip_players.size() or seat != int(state.get("actor", -1)) or _bot_levels.has(seat): return
	if not is_local and int(_peer_seats.get(sender, -1)) != seat: return
	if hand != int(state.hand_id) or revision != _revision or not Inventory.contains(_chip_players[seat], reserved): return
	var available := Inventory.subtract(_chip_players[seat], reserved)
	_chip_players[seat] = Inventory.add(Inventory.balanced(Inventory.value(available)), reserved)
	_chip_transfers = []
	_chip_revision += 1
	_publish()

func _sync_chip_transition(before: Dictionary, selected_seat: int = -1, selected: Dictionary = {}) -> void:
	var after: Dictionary = _engine.snapshot(0)
	_chip_transfers = []
	# Collect all increases before returning uncalled money or distributing awards.
	for seat in after.players.size():
		var delta := int(after.players[seat].committed) - int(before.players[seat].committed)
		if seat == selected_seat and not selected.is_empty(): delta = Inventory.value(selected)
		if delta <= 0: continue
		var payment: Dictionary
		if seat == selected_seat and not selected.is_empty() and Inventory.value(selected) == delta:
			payment = {"chips": selected.duplicate(), "remaining": Inventory.subtract(_chip_players[seat], selected)}
		else:
			payment = Inventory.take(_chip_players[seat], delta)
		_chip_players[seat] = payment.remaining
		_pot_chips = Inventory.add(_pot_chips, payment.chips)
		_chip_transfers.append({"seat": seat, "chips": payment.chips, "kind": "bet"})
	var awards := {}
	if after.phase == "showdown":
		for award in after.result: awards[int(award.seat)] = int(award.amount)
	for seat in after.players.size():
		# Return uncalled excess before capturing the contested pot for its ceremony.
		var refund := int(after.players[seat].stack) - Inventory.value(_chip_players[seat]) - int(awards.get(seat, 0))
		if refund > 0: _transfer_from_pot(seat, refund, "refund")
	if after.phase == "showdown":
		_settlement_pot_chips = _pot_chips.duplicate()
		for seat in awards:
			_transfer_from_pot(int(seat), int(awards[seat]), "payout")
	_chip_revision += 1

func _transfer_from_pot(seat: int, amount: int, kind: String) -> void:
	var payment := Inventory.take(_pot_chips, amount)
	_pot_chips = payment.remaining
	_chip_players[seat] = Inventory.add(_chip_players[seat], payment.chips)
	_chip_transfers.append({"seat": seat, "chips": payment.chips, "kind": kind})
