extends Node
## Small, unauthenticated LAN advertisements. The ENet host still authorizes joins.
signal rooms_changed(rooms: Array)
signal status_changed(message: String)

const DISCOVERY_PORT := 27847
const VERSION := 1
const MAGIC := "neon-pot-lan"
const MAX_PACKET := 768
const MAX_ROOMS := 32
const REFRESH_MSEC := 2000
const TTL_MSEC := 6500
const META_KEYS := ["room_id", "host_name", "port", "player_count", "max_players", "started"]
var rooms: Array:
	get: return _room_list()
var _host_socket: PacketPeerUDP
var _search_socket: PacketPeerUDP
var _host_metadata: Dictionary = {}
var _found: Dictionary = {}
var _seen_at: Dictionary = {}
var _reply_at: Dictionary = {}
var _nonce := ""
var _next_refresh := 0
var _last_refresh := -10000
var _rate_epoch := 0
var _rate_count := 0
var _targets: Array[String] = []

func _ready() -> void:
	set_process(_host_socket != null or _search_socket != null)

func start_host(metadata: Dictionary) -> Error:
	var clean := _validate_metadata(metadata)
	if clean.is_empty():
		status_changed.emit("Invalid room discovery metadata.")
		return ERR_INVALID_DATA
	stop_host()
	var socket := PacketPeerUDP.new()
	var error := socket.bind(DISCOVERY_PORT, "0.0.0.0", 16384)
	if error != OK:
		socket.close()
		status_changed.emit("Room discovery port is unavailable. Please retry.")
		return error
	_host_socket = socket
	_host_metadata = clean
	set_process(true)
	return OK

func update_host(metadata: Dictionary) -> void:
	_host_metadata = _validate_metadata(metadata)
	if _host_metadata.is_empty():
		status_changed.emit("Invalid room discovery metadata.")

func stop_host() -> void:
	if _host_socket != null: _host_socket.close()
	_host_socket = null
	_host_metadata.clear()
	_reply_at.clear()
	_rate_count = 0
	set_process(_search_socket != null)

func start_search() -> Error:
	stop_search()
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		status_changed.emit("Could not initialize room search.")
		return ERR_CANT_CREATE
	var socket := PacketPeerUDP.new()
	# Each searcher binds its own ephemeral port, including same-PC test clients.
	var error := socket.bind(0, "0.0.0.0", 32768)
	if error != OK:
		socket.close()
		status_changed.emit("Could not open room search. Check Wi-Fi and retry.")
		return error
	socket.set_broadcast_enabled(true)
	_search_socket = socket
	_nonce = bytes.hex_encode()
	_last_refresh = -10000
	set_process(true)
	refresh()
	return OK

func refresh() -> void:
	if _search_socket == null: return
	var now := Time.get_ticks_msec()
	if now - _last_refresh < 500: return
	_last_refresh = now
	_next_refresh = now + REFRESH_MSEC
	_targets = _broadcast_targets(IP.get_local_interfaces())
	var packet := JSON.stringify({"magic": MAGIC, "version": VERSION, "kind": "search", "nonce": _nonce}).to_utf8_buffer()
	var sent := false
	for address in _targets:
		if _search_socket.set_dest_address(address, DISCOVERY_PORT) == OK:
			sent = _search_socket.put_packet(packet) == OK or sent
	if not sent: status_changed.emit("Search could not send. Check Wi-Fi and retry.")

func stop_search() -> void:
	if _search_socket != null: _search_socket.close()
	_search_socket = null
	_nonce = ""
	_targets.clear()
	_found.clear()
	_seen_at.clear()
	rooms_changed.emit([])
	set_process(_host_socket != null)

func _exit_tree() -> void:
	# Do not emit UI callbacks during teardown.
	if _host_socket != null: _host_socket.close()
	if _search_socket != null: _search_socket.close()
	_host_socket = null
	_search_socket = null

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# A bounded amount of work per frame, even if a peer floods the socket.
	if _host_socket != null:
		for unused in range(mini(16, _host_socket.get_available_packet_count())):
			if _host_socket == null: break
			var packet := _host_socket.get_packet()
			_handle_query(packet, _host_socket.get_packet_ip(), _host_socket.get_packet_port(), now)
	if _search_socket != null:
		for unused in range(mini(32, _search_socket.get_available_packet_count())):
			if _search_socket == null: break
			var packet := _search_socket.get_packet()
			_handle_reply(packet, _search_socket.get_packet_ip(), _search_socket.get_packet_port(), now)
		_expire(now)
		if now >= _next_refresh: refresh()

func _decode(packet: PackedByteArray, kind: String) -> Dictionary:
	if packet.is_empty() or packet.size() > MAX_PACKET: return {}
	# Validate before conversion and use the non-logging JSON parser so arbitrary
	# network bytes cannot fill the game log with decoder/parser errors.
	if not _valid_utf8(packet): return {}
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK: return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary: return {}
	var expected := 5 if kind == "room" else 4
	if parsed.size() != expected or parsed.get("magic") != MAGIC or not _whole(parsed.get("version"), VERSION, VERSION) or parsed.get("kind") != kind:
		return {}
	if not parsed.get("nonce") is String or not _hex_nonce(parsed.nonce): return {}
	return parsed

func _valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var lead: int = bytes[index]
		if lead < 128:
			index += 1
			continue
		var count := 1 if lead >= 0xC2 and lead <= 0xDF else (2 if lead >= 0xE0 and lead <= 0xEF else (3 if lead >= 0xF0 and lead <= 0xF4 else -1))
		if count < 0 or index + count >= bytes.size(): return false
		var first: int = bytes[index + 1]
		if (lead == 0xE0 and first < 0xA0) or (lead == 0xED and first >= 0xA0) or (lead == 0xF0 and first < 0x90) or (lead == 0xF4 and first > 0x8F): return false
		for offset in range(1, count + 1):
			if bytes[index + offset] < 0x80 or bytes[index + offset] > 0xBF: return false
		index += count + 1
	return true

func _handle_query(packet: PackedByteArray, address: String, port: int, now: int) -> void:
	if _host_socket == null or _host_metadata.is_empty() or not _unicast_ipv4(address) or port < 1: return
	var message := _decode(packet, "search")
	if message.is_empty(): return
	if now - _rate_epoch >= 1000:
		_rate_epoch = now
		_rate_count = 0
	if _rate_count >= 24: return
	var key := address + ":" + str(port)
	if now - int(_reply_at.get(key, -10000)) < 500: return
	if _reply_at.size() >= 128:
		for old in _reply_at.keys():
			if now - int(_reply_at[old]) >= 2000: _reply_at.erase(old)
		if _reply_at.size() >= 128: return
	_reply_at[key] = now
	_rate_count += 1
	var reply := {"magic": MAGIC, "version": VERSION, "kind": "room", "nonce": message.nonce, "room": _host_metadata}
	if _host_socket.set_dest_address(address, port) == OK:
		_host_socket.put_packet(JSON.stringify(reply).to_utf8_buffer())

func _handle_reply(packet: PackedByteArray, address: String, source_port: int, now: int) -> void:
	if _search_socket == null or source_port != DISCOVERY_PORT or not _unicast_ipv4(address): return
	var message := _decode(packet, "room")
	if message.is_empty() or message.nonce != _nonce or not message.get("room") is Dictionary: return
	# Reject unexpected network fields instead of accepting payload-supplied IPs.
	if message.room.size() != META_KEYS.size(): return
	var room := _validate_metadata(message.room)
	if room.is_empty(): return
	var key: String = room.room_id
	if not _found.has(key) and _found.size() >= MAX_ROOMS: return
	room["address"] = address
	room["joinable"] = not room.started and room.player_count < room.max_players
	if _found.has(key):
		# A host may answer via loopback and its LAN interface. Keep the usable LAN IP.
		var old_address: String = _found[key].address
		if address.begins_with("127.") and not old_address.begins_with("127."):
			room.address = old_address
	_seen_at[key] = now
	if _found.get(key, {}) != room:
		_found[key] = room
		rooms_changed.emit(_room_list())

func _expire(now: int) -> void:
	var changed := false
	for key in _seen_at.keys():
		if now - int(_seen_at[key]) > TTL_MSEC:
			_seen_at.erase(key)
			_found.erase(key)
			changed = true
	if changed: rooms_changed.emit(_room_list())

func _room_list() -> Array:
	var result: Array = []
	var ids := _found.keys()
	ids.sort()
	for key in ids: result.append(_found[key].duplicate(true))
	return result

func _validate_metadata(metadata: Dictionary) -> Dictionary:
	for key in META_KEYS:
		if not metadata.has(key): return {}
	if not metadata.room_id is String or not metadata.host_name is String or not metadata.started is bool: return {}
	if metadata.room_id.is_empty() or metadata.room_id.length() > 64 or metadata.host_name.strip_edges().is_empty() or metadata.host_name.length() > 48: return {}
	for character in metadata.room_id:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": return {}
	for character in metadata.host_name:
		var code: int = character.unicode_at(0)
		if code < 32 or code == 127 or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069): return {}
	if not _whole(metadata.port, 1, 65535) or not _whole(metadata.max_players, 2, 6) or not _whole(metadata.player_count, 1, int(metadata.max_players)): return {}
	var result := {"room_id": metadata.room_id, "host_name": metadata.host_name, "port": int(metadata.port),
		"player_count": int(metadata.player_count), "max_players": int(metadata.max_players), "started": metadata.started}
	return result

func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

func _hex_nonce(value: String) -> bool:
	if value.length() != 32: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

func _unicast_ipv4(address: String) -> bool:
	if not address.is_valid_ip_address() or ":" in address: return false
	var octets := address.split(".")
	return octets.size() == 4 and int(octets[0]) > 0 and int(octets[0]) < 224 and address != "255.255.255.255"

func _broadcast_targets(interfaces: Array) -> Array[String]:
	var result: Array[String] = ["255.255.255.255", "127.0.0.1"]
	# Godot 4.6 exposes interface addresses, not masks/broadcast addresses:
	# docs.godotengine.org/en/4.6/classes/class_ip.html#class-ip-method-get-local-interfaces
	# These /24 candidates supplement limited broadcast; they are not inferred
	# authoritative subnet masks. No subnet scan or multicast lock is involved.
	for interface in interfaces:
		if not interface is Dictionary: continue
		for address in interface.get("addresses", []):
			if not address is String or not _unicast_ipv4(address) or address.begins_with("127."): continue
			var pieces: PackedStringArray = address.split(".")
			var broadcast := "%s.%s.%s.255" % [pieces[0], pieces[1], pieces[2]]
			if not result.has(broadcast): result.append(broadcast)
			if result.size() >= 18: return result
	return result
