extends SceneTree
const Discovery = preload("res://scripts/lan_discovery.gd")
const META := {"room_id": "fixture-room-0123456789", "host_name": "朋友的牌桌", "port": 27846, "player_count": 1, "max_players": 6, "started": false}
var checks := 0
var failures := 0
var role := "unit"

class LocalClient extends Discovery:
	func _broadcast_targets(_interfaces: Array) -> Array[String]:
		return ["127.0.0.1"]

class BroadcastClient extends Discovery:
	func _broadcast_targets(interfaces: Array) -> Array[String]:
		var targets := super._broadcast_targets(interfaces)
		targets.erase("127.0.0.1")
		return targets
	func _handle_reply(packet: PackedByteArray, address: String, source_port: int, now: int) -> void:
		var envelope := _decode(packet, "room")
		if not envelope.get("room") is Dictionary or envelope.room.get("room_id") != META.room_id:
			return
		super._handle_reply(packet, address, source_port, now)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DISCOVERY: " + label)

func _packet(nonce: String, metadata: Dictionary) -> PackedByteArray:
	return JSON.stringify({"magic": Discovery.MAGIC, "version": Discovery.VERSION, "kind": "room", "nonce": nonce, "room": metadata}).to_utf8_buffer()

func _wait_room(client: Node, timeout: float = 3.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while client.rooms.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame

func _run() -> void:
	if role == "host":
		await _host_process()
	elif role == "client":
		await _client_process()
	else:
		await _unit()
	await process_frame
	await process_frame
	print("DISCOVERY_TEST role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)

func _unit() -> void:
	var host := Discovery.new()
	var client := LocalClient.new()
	var second := LocalClient.new()
	root.add_child(host)
	root.add_child(client)
	root.add_child(second)
	var metadata := META.duplicate(true)
	metadata["cards"] = [0, 1]
	metadata["address"] = "8.8.8.8"
	check(host._validate_metadata(metadata) == META, "host advertises only public whitelisted metadata")
	for item in [["room_id", ""], ["room_id", "bad id"], ["host_name", "x\ny"], ["host_name", "x".repeat(49)], ["port", 0], ["port", 65536], ["port", true], ["port", 27846.5], ["player_count", 7], ["max_players", 1], ["started", 0]]:
		var bad := META.duplicate(true)
		bad[item[0]] = item[1]
		check(host._validate_metadata(bad).is_empty(), "invalid metadata rejected: " + str(item[0]))
	check(host.start_host(META) == OK, "host binds discovery port independently of game transport")
	check(client.start_search() == OK and second.start_search() == OK, "two clients search simultaneously")
	check(client._search_socket.get_local_port() != second._search_socket.get_local_port() and client._search_socket.get_local_port() != Discovery.DISCOVERY_PORT,
		"client sockets use different ephemeral ports")
	await _wait_room(client)
	await _wait_room(second)
	check(client.rooms.size() == 1 and second.rooms.size() == 1, "real UDP queries discover host and deduplicate interfaces")
	if not client.rooms.is_empty():
		check(client.rooms[0].host_name == META.host_name and client.rooms[0].joinable, "Unicode host name survives escaped JSON and open room can join")
		check(client.rooms[0].size() == 8 and client.rooms[0].port == 27846, "room contains only public metadata and derived connection fields")
		var copy: Array = client.rooms
		copy[0].host_name = "mutated"
		check(client.rooms[0].host_name == META.host_name, "published room arrays cannot mutate internal discovery cache")
	var before: Array = client.rooms
	var now := Time.get_ticks_msec()
	for edit in [["version", 2], ["version", true], ["kind", "search"], ["magic", "other-game"], ["nonce", "bad"]]:
		var envelope: Dictionary = JSON.parse_string(_packet(client._nonce, META).get_string_from_utf8())
		envelope[edit[0]] = edit[1]
		client._handle_reply(JSON.stringify(envelope).to_utf8_buffer(), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
		check(client.rooms == before, "incompatible protocol envelope rejected: " + str(edit[0]))
	for packet in [PackedByteArray(), "{".to_utf8_buffer(), "x".repeat(769).to_utf8_buffer(), PackedByteArray([255, 254, 253]), _packet("0".repeat(32), META)]:
		client._handle_reply(packet, "192.168.1.5", Discovery.DISCOVERY_PORT, now)
		check(client.rooms == before, "malformed, oversized, invalid-encoding or stale-token reply ignored")
	var tampered := META.duplicate()
	tampered["address"] = "8.8.8.8"
	client._handle_reply(_packet(client._nonce, tampered), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(client.rooms == before, "payload-supplied source address rejected")
	client._handle_reply(_packet(client._nonce, META), "192.168.1.5", 12345, now)
	check(client.rooms == before, "reply from wrong source port ignored")
	client._handle_reply(_packet(client._nonce, META), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(client.rooms.size() == 1 and client.rooms[0].address == "192.168.1.5", "connection address comes only from actual packet source")
	client._handle_reply(_packet(client._nonce, META), "127.0.0.1", Discovery.DISCOVERY_PORT, now)
	check(client.rooms[0].address == "192.168.1.5", "loopback duplicate cannot replace usable LAN address")
	var started := META.duplicate()
	started.started = true
	client._handle_reply(_packet(client._nonce, started), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(client.rooms[0].started and not client.rooms[0].joinable, "started rooms are marked not joinable")
	started.started = false
	started.player_count = 6
	client._handle_reply(_packet(client._nonce, started), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(not client.rooms[0].joinable, "full room cannot be joined")
	var saved_refresh: int = client._last_refresh
	client.refresh()
	check(client._last_refresh == saved_refresh, "rapid manual refresh is throttled")
	var targets: Array = host._broadcast_targets([{"addresses": ["192.168.7.42", "192.168.7.43", "10.2.3.4", "127.0.0.1", "::1"]}])
	check(targets == ["255.255.255.255", "127.0.0.1", "192.168.7.255", "10.2.3.255"], "broadcast candidates include unique local /24 fallbacks without IPv6 or scanning")
	host._reply_at.clear()
	host._rate_count = 0
	var query := JSON.stringify({"magic": Discovery.MAGIC, "version": 1, "kind": "search", "nonce": client._nonce}).to_utf8_buffer()
	for index in range(60): host._handle_query(query, "127.0.0.1", client._search_socket.get_local_port(), now)
	check(host._reply_at.size() == 1 and host._rate_count == 1, "duplicate requests get at most one response per half-second")
	for index in range(60): host._handle_query(query, "127.0.0.1", 30000 + index, now)
	check(host._rate_count == 24, "global response budget limits many forged client endpoints")
	for index in range(40):
		var entry := META.duplicate()
		entry.room_id = "bounded-room-%d" % index
		client._handle_reply(_packet(client._nonce, entry), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(client.rooms.size() == Discovery.MAX_ROOMS, "room list remains bounded under valid-looking advertisements")
	client._expire(now + Discovery.TTL_MSEC + 1)
	check(client.rooms.is_empty(), "stale rooms expire and disappear")
	client.stop_search()
	client._handle_reply(_packet("0".repeat(32), META), "192.168.1.5", Discovery.DISCOVERY_PORT, now)
	check(client.rooms.is_empty() and client._search_socket == null, "stopped search closes socket and rejects delayed replies")
	host._reply_at.clear()
	host._rate_count = 0
	var closing := LocalClient.new()
	root.add_child(closing)
	var callbacks: Array = []
	closing.rooms_changed.connect(func(found: Array):
		if not found.is_empty():
			callbacks.append(found.size())
			closing.stop_search())
	check(closing.start_search() == OK, "callback cancellation search starts")
	await create_timer(0.15).timeout
	check(callbacks == [1] and closing._search_socket == null, "room callback can stop search during packet drain without late notifications")
	closing.queue_free()
	host.stop_host()
	second.stop_search()
	check(not host.is_processing() and not second.is_processing(), "idle discovery nodes do not poll")
	host.queue_free()
	client.queue_free()
	second.queue_free()

func _host_process() -> void:
	var host := Discovery.new()
	root.add_child(host)
	check(host.start_host(META) == OK, "process host binds UDP 27847")
	if failures:
		host.queue_free()
		return
	print("DISCOVERY_HOST_READY")
	await create_timer(3.0).timeout
	check(not host._reply_at.is_empty(), "host received a real broadcast search")
	var metadata := META.duplicate()
	metadata.player_count = 2
	metadata.started = true
	host.update_host(metadata)
	await create_timer(3.0).timeout
	host.stop_host()
	print("DISCOVERY_HOST_STOPPED")
	await create_timer(0.2).timeout
	host.queue_free()

func _client_process() -> void:
	var client := BroadcastClient.new()
	root.add_child(client)
	check(client.start_search() == OK, "process client opens ephemeral socket")
	await _wait_room(client, 2.5)
	check(client.rooms.size() == 1, "broadcast-only client discovers real separate host process")
	if client.rooms.is_empty():
		client.queue_free()
		return
	check(not str(client.rooms[0].address).begins_with("127."), "two-process discovery used broadcast/LAN path without loopback fallback")
	check(client.rooms[0].joinable and client.rooms[0].host_name == META.host_name, "first advertisement is open lobby with correct Unicode name")
	print("DISCOVERY_FOUND address=%s client_port=%s" % [client.rooms[0].address, client._search_socket.get_local_port()])
	var deadline := Time.get_ticks_msec() + 6500
	while not client.rooms.is_empty() and not client.rooms[0].started and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not client.rooms.is_empty() and client.rooms[0].started and not client.rooms[0].joinable and client.rooms[0].player_count == 2,
		"automatic refresh receives live host metadata and disables started table")
	deadline = Time.get_ticks_msec() + 10000
	while not client.rooms.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.rooms.is_empty(), "disconnected host expires under real monotonic time")
	client.stop_search()
	client.queue_free()
