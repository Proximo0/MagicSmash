extends Node
## LAN networking: ENet host/client, UDP broadcast discovery, the player
## roster, input upload and state snapshots. The host runs the simulation;
## clients send their inputs and draw what the host tells them.

signal roster_changed
signal game_started
signal snapshot_received(snap: Dictionary)
signal connection_failed(reason: String)
signal games_found_changed

enum Mode { OFFLINE, HOST, CLIENT }

const GAME_PORT := 24680
const DISCOVERY_PORT := 24681
const MAGIC := "MAGICSMASH1"

var mode := Mode.OFFLINE
## Array of {slot:int, peer:int, device:int, wizard:int, ai:bool, race:int, cls:int, look:int, cls_level:int}. An
## ai row is an apprentice (device G.DEV_AI) the host plays; none exist yet. race, cls, look and cls_level are
## reserved (0) for races and classes.
var roster: Array = []
## The difficulty the host chose for the next run (World.SEAL_EASY..World.SEAL_MAX, 0 normal); travels with the roster.
var seal := 0
## slot -> PackedFloat32Array input from remote clients (host only)
var remote_inputs := {}
var my_peer := 1
var found_games := {} # ip -> {name, players, seen}
var host_name := "WIZARD"

var _broadcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0
var in_game := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var n := OS.get_environment("USERNAME")
	if n.is_empty():
		n = OS.get_environment("USER")
	if not n.is_empty():
		host_name = n.to_upper().left(10)

func is_host() -> bool:
	return mode != Mode.CLIENT

func is_online() -> bool:
	return mode != Mode.OFFLINE

# ------------------------------------------------------------------ setup --
func start_offline() -> void:
	shutdown()
	mode = Mode.OFFLINE
	my_peer = 1
	roster.clear()
	for d in G.local_devices:
		_add_to_roster(1, d)
	roster_changed.emit()

func host_game() -> bool:
	shutdown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, 8)
	if err != OK:
		connection_failed.emit("COULD NOT OPEN PORT %d" % GAME_PORT)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	my_peer = 1
	roster.clear()
	for d in G.local_devices:
		_add_to_roster(1, d)
	_broadcast = PacketPeerUDP.new()
	_broadcast.set_broadcast_enabled(true)
	_broadcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	roster_changed.emit()
	return true

func join_game(ip: String) -> void:
	shutdown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		connection_failed.emit("BAD ADDRESS")
		return
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	roster.clear()

func start_discovery() -> void:
	stop_discovery()
	found_games.clear()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null

func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null

func shutdown() -> void:
	in_game = false
	if _broadcast:
		_broadcast.close()
		_broadcast = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	remote_inputs.clear()

func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out

func _process(delta: float) -> void:
	if _broadcast and mode == Mode.HOST and not in_game:
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			var msg := "%s|%s|%d" % [MAGIC, host_name, roster.size()]
			_broadcast.put_packet(msg.to_utf8_buffer())
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 3 and parts[0] == MAGIC:
				if not found_games.has(ip):
					changed = true
				found_games[ip] = {"name": parts[1], "players": int(parts[2]), "seen": Time.get_ticks_msec()}
		for ip in found_games.keys():
			if Time.get_ticks_msec() - int(found_games[ip].seen) > 4000:
				found_games.erase(ip)
				changed = true
		if changed:
			games_found_changed.emit()

# ---------------------------------------------------------------- roster --
func _add_to_roster(peer: int, device: int) -> int:
	if roster.size() >= G.MAX_PLAYERS:
		return -1
	var used := []
	for r in roster:
		used.append(r.slot)
	for s in G.MAX_PLAYERS:
		if not used.has(s):
			roster.append({"slot": s, "peer": peer, "device": device, "wizard": Wizards.first_free(s, _wizards_taken(-1)),
				"ai": false, "race": 0, "cls": 0, "look": 0, "cls_level": 0})
			roster.sort_custom(func(a, b): return a.slot < b.slot)
			return s
	return -1

## Called by the lobby when a local device presses fire.
func add_local_device(device: int) -> void:
	if G.local_devices.has(device):
		return
	if mode == Mode.CLIENT:
		G.local_devices.append(device)
		_request_join.rpc_id(1, device)
		return
	if _add_to_roster(1, device) >= 0:
		G.local_devices.append(device)
		_push_roster()

func remove_local_device(device: int) -> void:
	G.local_devices.erase(device)
	if mode == Mode.CLIENT:
		_request_leave.rpc_id(1, device)
		return
	for r in roster.duplicate():
		if r.peer == 1 and r.device == device:
			roster.erase(r)
	_push_roster()

## Wizards (Wizards index) picked by everyone in the roster except `slot`.
func _wizards_taken(slot: int) -> Array:
	var out := []
	for r in roster:
		if r.slot != slot:
			out.append(int(r.get("wizard", r.slot)))
	return out

## slot -> picked wizard, for World.new.
func wizard_picks() -> Dictionary:
	var out := {}
	for r in roster:
		out[r.slot] = int(r.get("wizard", r.slot))
	return out

## slot -> the roster extras World copies onto each Player untouched: ai, race, cls, look, cls_level.
func seat_builds() -> Dictionary:
	var out := {}
	for r in roster:
		out[r.slot] = {"ai": bool(r.get("ai", false)), "race": int(r.get("race", 0)), "cls": int(r.get("cls", 0)),
			"look": int(r.get("look", 0)), "cls_level": int(r.get("cls_level", 0))}
	return out

## Called by the lobby when a local device steps left (-1) or right (+1) through the wizards.
func cycle_wizard(device: int, dir: int) -> void:
	if mode == Mode.CLIENT:
		_request_wizard.rpc_id(1, device, dir)
		return
	_cycle_wizard(1, device, dir)

func _cycle_wizard(peer: int, device: int, dir: int) -> void:
	for r in roster:
		if r.peer == peer and r.device == device:
			r.wizard = Wizards.cycle(int(r.get("wizard", r.slot)), signi(dir), _wizards_taken(r.slot))
	_push_roster()

@rpc("any_peer", "reliable")
func _request_wizard(device: int, dir: int) -> void:
	if mode != Mode.HOST or in_game:
		return
	_cycle_wizard(multiplayer.get_remote_sender_id(), device, dir)

## This machine's human seats (apprentices left out).
func my_slots() -> Array:
	var out := []
	for r in roster:
		if r.peer == my_peer and not bool(r.get("ai", false)):
			out.append(r)
	return out

## The apprentice seats (the host plays them).
func ai_slots() -> Array:
	var out := []
	for r in roster:
		if bool(r.get("ai", false)):
			out.append(r)
	return out

## The host picks the Seal for the next run; clients follow with the roster. Ignored on a client.
func set_seal(level: int) -> void:
	if mode == Mode.CLIENT:
		return
	seal = clampi(level, World.SEAL_EASY, World.SEAL_MAX)
	_push_roster()

func _push_roster() -> void:
	roster_changed.emit()
	if mode == Mode.HOST:
		_sync_roster.rpc(roster, seal)

@rpc("any_peer", "reliable")
func _request_join(device: int) -> void:
	if mode != Mode.HOST or in_game:
		return
	var peer := multiplayer.get_remote_sender_id()
	_add_to_roster(peer, device)
	_push_roster()

@rpc("any_peer", "reliable")
func _request_leave(device: int) -> void:
	if mode != Mode.HOST:
		return
	var peer := multiplayer.get_remote_sender_id()
	for r in roster.duplicate():
		if r.peer == peer and r.device == device:
			roster.erase(r)
	_push_roster()

@rpc("authority", "reliable")
func _sync_roster(r: Array, s: int) -> void:
	roster = r
	seal = s
	roster_changed.emit()

func _on_peer_connected(id: int) -> void:
	if mode == Mode.HOST:
		_sync_roster.rpc_id(id, roster, seal)

func _on_peer_disconnected(id: int) -> void:
	if mode != Mode.HOST:
		return
	for r in roster.duplicate():
		if r.peer == id:
			roster.erase(r)
			remote_inputs.erase(r.slot)
	_push_roster()

func _on_connected() -> void:
	my_peer = multiplayer.get_unique_id()
	for d in G.local_devices:
		_request_join.rpc_id(1, d)

func _on_failed() -> void:
	shutdown()
	connection_failed.emit("COULD NOT CONNECT")

func _on_server_gone() -> void:
	shutdown()
	G.title_message = "HOST LEFT THE GAME"
	connection_failed.emit("HOST LEFT THE GAME")
	G.goto_title()

# ------------------------------------------------------------- game flow --
func begin_game() -> void:
	if mode == Mode.HOST:
		_start.rpc()
	_start()

@rpc("authority", "reliable")
func _start() -> void:
	in_game = true
	game_started.emit()
	G.goto_game()

func end_to_lobby() -> void:
	in_game = false

## Client -> host, every physics frame.
func send_input(slot: int, data: PackedFloat32Array) -> void:
	if mode == Mode.CLIENT:
		_input_packet.rpc_id(1, slot, data)

@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _input_packet(slot: int, data: PackedFloat32Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	for r in roster:
		if r.slot == slot and r.peer == peer:
			remote_inputs[slot] = data
			return

## Host -> clients.
func send_snapshot(snap: Dictionary) -> void:
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_snap.rpc(snap)

@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _snap(snap: Dictionary) -> void:
	snapshot_received.emit(snap)

func send_back_to_title() -> void:
	if mode == Mode.HOST:
		_to_title.rpc()

@rpc("authority", "reliable")
func _to_title() -> void:
	in_game = false
	G.goto_title()
