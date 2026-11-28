extends Node
## LAN networking: ENet host/client, UDP broadcast discovery, the player
## roster, input upload and state snapshots. The host runs the simulation;
## clients send their inputs and draw what the host tells them.

signal roster_changed
signal game_started
signal snapshot_received(snap: Dictionary)
signal connection_failed(reason: String)
signal games_found_changed
## Run-ending and saved-data events (RELIABLE_EVENTS) from the host, by reliable RPC (client only).
signal events_received(evs: Array)

enum Mode { OFFLINE, HOST, CLIENT }

const GAME_PORT := 24680
const DISCOVERY_PORT := 24681
const MAGIC := "MAGICSMASH3" # 3: joins carry the seat; 2: longer snapshot and roster rows. Older builds do not see these games

var mode := Mode.OFFLINE
## Array of {slot:int, peer:int, device:int, wizard:int, ai:bool, away:bool, race:int, cls:int, look:int,
## cls_level:int}. An ai row is an apprentice (device G.DEV_AI, add_apprentice) the host plays. An away row is a
## human seat whose device has been silent for Tuning.seat_silence s: the host plays it as an apprentice until the
## device speaks again (check_silence). A human seat of a played run also has hero (the cleaned Hero.to_dict) and
## race, cls, look, cls_level (the hero's level) copied from it. An apprentice's hero is {}; it carries cls (the
## role it fills, apprentice_class), race 0 and cls_level 1, and the World makes it that hero (WorldApprentices).
var roster: Array = []
## This machine's seats' heroes: device -> index into Save.profile.heroes, or -1 for a guest (Hero.new(), earns
## nothing). Empty in a scripted run, so those seats get no hero (unless force_heroes, for tests).
var seat_heroes := {}
var force_heroes := false
## The wizards of this session's apprentices, kept across runs: start_offline and host_game seat them again.
var kept_apprentices: Array[int] = []
## Events a LAN client must not lose (they end the run or change saved data): they go by reliable RPC
## (send_events), never inside the unreliable snapshot.
const RELIABLE_EVENTS: Array[int] = [World.EV_VICTORY, World.EV_RESULTS, World.EV_GAMEOVER, World.EV_CARD, World.EV_CHEST,
	World.EV_PICK]
## The roles an apprentice fills, first missing first, and the class that fills each: [Classes.ROLE_*, Classes.*].
const APPRENTICE_ROLES: Array = [[Classes.ROLE_TANK, Classes.KNIGHT], [Classes.ROLE_HEALER, Classes.PRIEST],
	[Classes.ROLE_RANGED, Classes.ARCHER], [Classes.ROLE_DAMAGE, Classes.MAGE]]
## slot -> Time.get_ticks_msec() when its device last spoke (host: remote packets and hellos, connected pads).
var _heard := {}
var _hello_timer := 0.0
var _close_gen := 0
## True while the host waits a moment before closing (send_back_to_title): the title leaves that close alone.
var closing := false
## The difficulty the host chose for the next run (World.SEAL_EASY..World.SEAL_MAX, 0 normal); travels with the roster.
var seal := 0
## The Reading the host's table kept for the next run (a Readings key, "" for none). The host's only: clients learn
## the card from the snapshot header (World.W_READING).
var reading := ""
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
		host_name = clean_name(n)

## A name the pixel font can draw: upper case, only its glyphs (spaces kept, runs collapsed and trimmed; no "|",
## which would break the discovery packet), at most 10 characters, "WIZARD" when nothing is left. Also applied to
## names that arrive off the network.
static func clean_name(n: String) -> String:
	var out := ""
	for ch: String in n.to_upper():
		if ch == " " or (ch != "|" and PixelFont.GLYPHS.has(ch)):
			if ch != " " or not out.ends_with(" "):
				out += ch
	out = out.strip_edges().left(10).strip_edges()
	return "WIZARD" if out.is_empty() else out

func is_host() -> bool:
	return mode != Mode.CLIENT

## True when the roster holds a seat on another machine. The roster, not the connected peers: an uninvited
## connection must not un-pause the world.
func has_remote_players() -> bool:
	for r in roster:
		if r.peer != my_peer:
			return true
	return false

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
	_seat_kept()
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
	_seat_kept()
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
	closing = false
	_close_gen += 1
	if _broadcast:
		_broadcast.close()
		_broadcast = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	remote_inputs.clear()
	seat_heroes.clear()

func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out

func _process(delta: float) -> void:
	if mode != Mode.CLIENT:
		check_silence(Time.get_ticks_msec(), Input.get_connected_joypads())
	elif multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		# A client says hello once a second, so the host hears its seats at the lobby and on the results screen too.
		_hello_timer -= delta
		if _hello_timer <= 0.0 and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_hello_timer = 1.0
			_hello.rpc_id(1)
	if _broadcast and mode == Mode.HOST and not in_game:
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			var msg := "%s|%s|%d|%s" % [MAGIC, host_name, roster.size(), G.VERSION]
			_broadcast.put_packet(msg.to_utf8_buffer())
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 4 and parts[0] == MAGIC and parts[3] == G.VERSION: # other versions stay hidden
				if not found_games.has(ip):
					changed = true
				found_games[ip] = {"name": clean_name(parts[1]), "players": int(parts[2]), "seen": Time.get_ticks_msec()}
		for ip in found_games.keys():
			if Time.get_ticks_msec() - int(found_games[ip].seen) > 4000:
				found_games.erase(ip)
				changed = true
		if changed:
			games_found_changed.emit()

# ---------------------------------------------------------------- roster --
## Seats a device (G.DEV_AI: an apprentice) and returns its slot, or -1 when every seat is taken. A human takes the
## highest apprentice's seat when there is one (keeping its wizard), else the lowest free seat.
func _add_to_roster(peer: int, device: int) -> int:
	var ai := device == G.DEV_AI
	if not ai:
		var aps := ai_slots()
		if not aps.is_empty():
			var r: Dictionary = aps[aps.size() - 1]
			r.peer = peer
			r.device = device
			r.ai = false
			r.away = false
			r.merge({"race": 0, "cls": 0, "look": 0, "cls_level": 0, "hero": {}}, true) # the apprentice's class leaves with it
			_heard[int(r.slot)] = Time.get_ticks_msec()
			_seat_local_hero(r)
			return int(r.slot)
	if roster.size() >= G.MAX_PLAYERS:
		return -1
	var used := []
	for r in roster:
		used.append(r.slot)
	for s in G.MAX_PLAYERS:
		if not used.has(s):
			roster.append({"slot": s, "peer": peer, "device": device, "wizard": Wizards.first_free(s, _wizards_taken(-1)),
				"ai": ai, "away": false, "race": 0, "cls": apprentice_class() if ai else 0, "look": 0, "cls_level": 1 if ai else 0,
				"hero": {}})
			roster.sort_custom(func(a, b): return a.slot < b.slot)
			_heard[s] = Time.get_ticks_msec()
			_seat_local_hero(_row_of(s))
			return s
	return -1

func _row_of(slot: int) -> Dictionary:
	for r: Dictionary in roster:
		if int(r.slot) == slot:
			return r
	return {}

func _heroes_wanted() -> bool:
	return force_heroes or not Flags.is_scripted_run()

## Profile hero indices the other local seats hold (never -1).
func _heroes_taken(device: int) -> Array[int]:
	var out: Array[int] = []
	for d: Variant in seat_heroes:
		if int(d) != device and int(seat_heroes[d]) >= 0:
			out.append(int(seat_heroes[d]))
	return out

## The hero a new local seat starts on: the profile's active hero, else the first no other local seat holds, else
## -1 (a guest).
func _first_free_hero(device: int) -> int:
	var heroes: Array = Save.profile.heroes
	var taken := _heroes_taken(device)
	var pref: int = Save.profile.hero
	if pref >= 0 and pref < heroes.size() and not taken.has(pref):
		return pref
	for i in heroes.size():
		if not taken.has(i):
			return i
	return -1

## The guest heroes by seat slot: a preset of [race, class] each (the four different heroes a fresh table shows),
## slot 3 the last one repeating past slot 3.
const GUEST_PRESETS: Array = [[Races.HUMAN, Classes.MAGE], [Races.ELF, Classes.ARCHER], [Races.DWARF, Classes.KNIGHT],
	[Races.ORC, Classes.PRIEST]]

## The guest hero of seat `slot`: level 1, no cards, named after its class. Never stored, earns nothing.
func guest_hero(slot: int) -> Hero:
	var pr: Array = GUEST_PRESETS[clampi(slot, 0, GUEST_PRESETS.size() - 1)]
	return Hero.make(int(pr[0]), int(pr[1]), 0, Classes.class_name_of(int(pr[1])))

## The hero a seat index stands for: the saved one, or seat `slot`'s guest for -1 or a stale index.
func hero_at(idx: int, slot: int = 0) -> Hero:
	var heroes: Array = Save.profile.heroes
	return heroes[idx] if idx >= 0 and idx < heroes.size() else guest_hero(slot)

## The slot of this machine's human seat on `device` (0 when it has none yet).
func _slot_of_device(device: int) -> int:
	for r: Dictionary in roster:
		if int(r.peer) == my_peer and int(r.device) == device and not bool(r.get("ai", false)):
			return int(r.slot)
	return 0

## The saved hero index of a local device's seat (-1 a guest or none).
func hero_of(device: int) -> int:
	return int(seat_heroes.get(device, -1))

## A fresh local human row (host or offline) takes its device's hero: seat_heroes keeps the index.
func _seat_local_hero(r: Dictionary) -> void:
	if r.is_empty() or bool(r.ai) or int(r.peer) != my_peer or not _heroes_wanted():
		return
	var d := int(r.device)
	if not seat_heroes.has(d):
		seat_heroes[d] = _first_free_hero(d)
	_fill_hero(r, hero_at(int(seat_heroes[d]), int(r.slot)).to_dict())

## Stores a hero on a row, cleaned (Hero.from_dict clamps whatever came in), with the extras copied from it. The
## wizard colour follows a mage's school when free, else stays or takes the first free one.
func _fill_hero(r: Dictionary, d: Dictionary) -> void:
	var h := Hero.from_dict(d)
	r.hero = h.to_dict()
	r.race = h.race
	r.cls = h.cls
	r.look = h.look
	r.cls_level = h.level
	r.wizard = Wizards.first_free(h.school if h.cls == Classes.MAGE else int(r.get("wizard", r.slot)), _wizards_taken(int(r.slot)))

## Human seats on this machine.
func _local_seat_count() -> int:
	var n := 0
	for r: Dictionary in roster:
		if int(r.peer) == my_peer and not bool(r.get("ai", false)):
			n += 1
	return n

## Local seat `device` takes the saved hero `idx` (-1: guest). False when another local seat holds it or it
## does not exist. The host fills its row; a client tells the host (`_submit_hero`).
func set_seat_hero(device: int, idx: int) -> bool:
	if not _heroes_wanted() or not G.local_devices.has(device):
		return false
	if idx >= Save.profile.heroes.size() or idx < -1 or _heroes_taken(device).has(idx):
		return false
	seat_heroes[device] = idx
	_send_seat_hero(device)
	return true

func _send_seat_hero(device: int) -> void:
	var d: Dictionary = hero_at(hero_of(device), _slot_of_device(device)).to_dict()
	if mode == Mode.CLIENT:
		_submit_hero.rpc_id(1, device, d)
		return
	for r: Dictionary in roster:
		if int(r.peer) == my_peer and int(r.device) == device and not bool(r.ai):
			_fill_hero(r, d)
	_push_roster()

## The lobby's left and right: step `device`'s seat through the saved heroes no other local seat holds, then the
## guest when there are fewer heroes than local seats.
func step_seat_hero(device: int, dir: int) -> void:
	if not _heroes_wanted():
		return
	var cur := hero_of(device)
	var taken := _heroes_taken(device)
	var opts: Array[int] = []
	for i in Save.profile.heroes.size():
		if not taken.has(i):
			opts.append(i)
	if cur < 0 or Save.profile.heroes.size() < _local_seat_count():
		opts.append(-1)
	if opts.is_empty():
		return
	var at := opts.find(cur)
	var next := opts[wrapi((at if at >= 0 else 0) + signi(dir), 0, opts.size())]
	set_seat_hero(device, next)

## After the hero list changed (the roster screen): every local seat re-reads its hero, a vanished one becoming the
## first free hero or a guest.
func refresh_seat_heroes() -> void:
	if not _heroes_wanted():
		return
	for d: Variant in seat_heroes.keys():
		var idx := int(seat_heroes[d])
		if idx >= Save.profile.heroes.size() or _heroes_taken(int(d)).has(idx):
			seat_heroes[d] = _first_free_hero(int(d))
		_send_seat_hero(int(d))

## Hero `removed` was just deleted from the profile: every local seat's held index follows the shift (one lower above
## her), and a seat that held her takes the first free hero. Call it once per deletion, before refresh_seat_heroes.
func hero_removed(removed: int) -> void:
	var lost: Array[int] = []
	for d: Variant in seat_heroes.keys():
		var held := int(seat_heroes[d])
		seat_heroes[d] = Profile.index_after_removal(held, removed)
		if held == removed:
			lost.append(int(d))
	for d: int in lost:
		seat_heroes[d] = _first_free_hero(d)

## The profile hero indices this machine's human seats play, each once, no guests (G.run_heroes).
func played_heroes() -> Array[int]:
	var out: Array[int] = []
	for r: Dictionary in my_slots():
		var idx := hero_of(int(r.device))
		if idx >= 0 and idx < Save.profile.heroes.size() and not out.has(idx):
			out.append(idx)
	return out

## Client -> host: the hero of one of its seats, cleaned here before it is kept.
@rpc("any_peer", "reliable")
func _submit_hero(device: int, d: Dictionary) -> void:
	if mode != Mode.HOST or in_game:
		return
	var peer := multiplayer.get_remote_sender_id()
	for r: Dictionary in roster:
		if int(r.peer) == peer and int(r.device) == device and not bool(r.get("ai", false)):
			_fill_hero(r, d)
	_push_roster()

## Seats an apprentice (host or offline, at the lobby): its slot, or -1 when every seat is taken.
func add_apprentice() -> int:
	if mode == Mode.CLIENT or in_game:
		return -1
	var s := _add_to_roster(1, G.DEV_AI)
	if s >= 0:
		_push_roster()
	return s

## The class a new apprentice takes: the one that fills the party's first missing role, in APPRENTICE_ROLES order
## (a solo mage's first apprentice is a KNIGHT, the second a PRIEST, the third an ARCHER); a PALADIN counts as a
## tank. Every role filled: a MAGE. It plays as a HUMAN of class level 1 (WorldApprentices.take_class).
func apprentice_class() -> int:
	var have: Array[int] = []
	for r: Dictionary in roster:
		have.append(_party_role(int(r.get("cls", 0))))
	return _missing_role_class(have)

## The role class `c` fills in a party: its own, a PALADIN's support counting as the tank.
func _party_role(c: int) -> int:
	var role := Classes.role(c)
	return Classes.ROLE_TANK if role == Classes.ROLE_SUPPORT else role

## The class for the first APPRENTICE_ROLES role that `have` lacks (a MAGE when it lacks none).
func _missing_role_class(have: Array[int]) -> int:
	for i: int in range(APPRENTICE_ROLES.size()):
		if not have.has(int(APPRENTICE_ROLES[i][0])):
			return int(APPRENTICE_ROLES[i][1])
	return Classes.MAGE

## Deals the apprentices their classes again, seat by seat, counting the humans' classes first: the roster changed
## (a human picked another hero, joined, left, or a client's hero arrived), and the party must not end up with two
## tanks and no healer. Outside a run only (_push_roster): a run's classes are the ones it started with.
func _fill_apprentice_roles() -> void:
	var have: Array[int] = []
	for r: Dictionary in roster:
		if not bool(r.get("ai", false)):
			have.append(_party_role(int(r.get("cls", 0))))
	for r: Dictionary in ai_slots():
		var c := _missing_role_class(have)
		r.merge({"race": 0, "cls": c, "look": 0, "cls_level": 1, "hero": {}}, true)
		have.append(_party_role(c))

## Unseats an apprentice: `slot`, or the highest apprentice by default. False when there is none to remove.
func remove_apprentice(slot := -1) -> bool:
	if mode == Mode.CLIENT or in_game:
		return false
	var aps := ai_slots()
	for i in range(aps.size() - 1, -1, -1):
		if slot < 0 or int(aps[i].slot) == slot:
			roster.erase(aps[i])
			_push_roster()
			return true
	return false

## Seats this session's kept apprentices again (start_offline, host_game), each with its wizard when that is free.
func _seat_kept() -> void:
	for wz: int in kept_apprentices.duplicate():
		var s := _add_to_roster(1, G.DEV_AI)
		if s < 0:
			break
		for r in roster:
			if r.slot == s and not _wizards_taken(s).has(wz):
				r.wizard = wz

## The host hears its seats: a human seat whose device has been silent for Tuning.seat_silence s turns away (an
## apprentice plays it) until the device speaks again. Remote seats speak with their input packets and hellos;
## local pads by being connected (`pads`); the keyboard always speaks. Scripted runs leave local seats alone.
func check_silence(now: int, pads: Array) -> void:
	var limit := int(Tuning.shared().seat_silence * 1000.0)
	var changed := false
	for r in roster:
		if bool(r.get("ai", false)):
			continue
		var slot := int(r.slot)
		var local: bool = r.peer == my_peer
		if local and (int(r.device) < 0 or pads.has(int(r.device)) or Flags.is_scripted_run()):
			_heard[slot] = now
		if not _heard.has(slot):
			_heard[slot] = now
		var silent: bool = now - int(_heard[slot]) > limit
		if silent != bool(r.get("away", false)):
			r.away = silent
			changed = true
			if silent:
				remote_inputs.erase(slot)
	if changed:
		_push_roster()

## A remote seat spoke (an input packet or a hello).
func _note_heard(slot: int) -> void:
	_heard[slot] = Time.get_ticks_msec()
	for r in roster:
		if int(r.slot) == slot and bool(r.get("away", false)):
			r.away = false
			_push_roster()

## Called by the lobby when a local device presses fire.
func add_local_device(device: int) -> void:
	if G.local_devices.has(device):
		return
	if mode == Mode.CLIENT:
		G.local_devices.append(device)
		_request_join.rpc_id(1, device, G.VERSION, World.P_FLOATS)
		if _heroes_wanted():
			seat_heroes[device] = _first_free_hero(device)
			_send_seat_hero(device)
		return
	if _add_to_roster(1, device) >= 0:
		G.local_devices.append(device)
		_push_roster()

func remove_local_device(device: int) -> void:
	G.local_devices.erase(device)
	seat_heroes.erase(device)
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

## slot -> the roster extras World copies onto each Player untouched: ai (an apprentice, or an away seat), away, race,
## cls, look, cls_level.
func seat_builds() -> Dictionary:
	var out := {}
	for r in roster:
		out[r.slot] = {"ai": played_by_ai(r), "away": bool(r.get("away", false)), "race": int(r.get("race", 0)), "cls": int(r.get("cls", 0)),
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

## This machine's human seats (apprentices left out; on the host, away seats too: the World plays them).
func my_slots() -> Array:
	var out := []
	for r in roster:
		if r.peer == my_peer and not bool(r.get("ai", false)) and not (is_host() and bool(r.get("away", false))):
			out.append(r)
	return out

## True when the World plays a roster row: an apprentice, or a human seat gone silent.
static func played_by_ai(r: Dictionary) -> bool:
	return bool(r.get("ai", false)) or bool(r.get("away", false))

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
	if mode != Mode.CLIENT:
		if not in_game:
			_fill_apprentice_roles()
		kept_apprentices.clear()
		for r in ai_slots():
			kept_apprentices.append(int(r.get("wizard", r.slot)))
	roster_changed.emit()
	if mode == Mode.HOST:
		_sync_roster.rpc(roster, seal)

## A client asks for a seat for one of its devices. The host answers every join: a seat (the roster), or a
## refusal (_refused) for another version or snapshot layout, a run already on, or a full table.
@rpc("any_peer", "reliable")
func _request_join(device: int, version: String, layout: int) -> void:
	if mode != Mode.HOST:
		return
	var peer := multiplayer.get_remote_sender_id()
	var why := join_refusal(version, layout)
	if why.is_empty() and _add_to_roster(peer, device) < 0:
		why = "THE GAME IS FULL"
	if not why.is_empty():
		_refused.rpc_id(peer, why, device)
		return
	_push_roster()

## Why the host refuses a join from `version` with snapshot rows of `layout` floats ("" when it does not).
func join_refusal(version: String, layout: int) -> String:
	if version != G.VERSION or layout != World.P_FLOATS:
		return "HOST HAS VERSION %s" % G.VERSION
	if in_game:
		return "A RUN IS ON: JOIN AFTER IT"
	return ""

## Host -> a client it refused: a client without a seat leaves (the title shows why); one that has a seat only
## drops the device that asked.
@rpc("authority", "reliable")
func _refused(reason: String, device: int) -> void:
	G.local_devices.erase(device)
	for r in roster:
		if r.peer == my_peer:
			return # seated already: only this device stays out
	_leave_refused.call_deferred(reason)

func _leave_refused(reason: String) -> void:
	shutdown()
	connection_failed.emit(reason)

## Client -> host once a second: this machine's seats are not silent.
@rpc("any_peer", "unreliable")
func _hello() -> void:
	var peer := multiplayer.get_remote_sender_id()
	for r in roster:
		if r.peer == peer:
			_note_heard(int(r.slot))

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
	_throttle_off(id)
	if mode == Mode.HOST and not in_game:
		_sync_roster.rpc_id(id, roster, seal)

## ENet's defaults for the throttle's interval and acceleration; the deceleration is set to 0.
const THROTTLE_INTERVAL_MS := 5000
const THROTTLE_ACCEL := 2
## ENet's packet throttle drops unreliable snapshots after a frame hitch (docs/online.md): off for every peer.
func _throttle_off(id: int) -> void:
	var ep := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if ep == null:
		return
	var pp := ep.get_peer(id)
	if pp != null:
		pp.throttle_configure(THROTTLE_INTERVAL_MS, THROTTLE_ACCEL, 0)

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
	_throttle_off(1)
	for d in G.local_devices:
		_request_join.rpc_id(1, d, G.VERSION, World.P_FLOATS)

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
		multiplayer.multiplayer_peer.refuse_new_connections = true # nobody joins a run on
	_start()

@rpc("authority", "reliable")
func _start() -> void:
	in_game = true
	G.run_heroes.assign(played_heroes())
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
	var inp := clean_input(data)
	if inp.is_empty():
		return
	for r in roster:
		if r.slot == slot and r.peer == peer:
			remote_inputs[slot] = inp
			_note_heard(slot)
			return

## A remote input packet made safe, or empty to drop it: 6 or 8 numbers, all finite; the move at most 1 long and
## the aim a direction (a mouse aim is a screen offset, so it is normalised, not clamped).
static func clean_input(data: PackedFloat32Array) -> PackedFloat32Array:
	if data.size() != 6 and data.size() != 8:
		return PackedFloat32Array()
	for v: float in data:
		if not is_finite(v):
			return PackedFloat32Array()
	var out := data.duplicate()
	var move := Vector2(out[0], out[1]).limit_length(1.0)
	var aim := Vector2(out[2], out[3])
	if aim.length() > 1.0:
		aim = aim.normalized()
	out[0] = move.x
	out[1] = move.y
	out[2] = aim.x
	out[3] = aim.y
	return out

## Host -> clients.
func send_snapshot(snap: Dictionary) -> void:
	if mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_snap.rpc(snap)

@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _snap(snap: Dictionary) -> void:
	snapshot_received.emit(snap)

## Host -> clients: the events in `evs` that must arrive (RELIABLE_EVENTS), in order, by reliable RPC on their own
## channel; returns the rest for the snapshot.
func send_events(evs: Array) -> Array:
	var sure := []
	var rest := []
	for ev: Array in evs:
		(sure if RELIABLE_EVENTS.has(int(ev[0])) else rest).append(ev)
	if not sure.is_empty() and mode == Mode.HOST and multiplayer.get_peers().size() > 0:
		_events.rpc(sure)
	return rest

@rpc("authority", "reliable", "call_remote", 3)
func _events(evs: Array) -> void:
	events_received.emit(evs)

## The host leaves a LAN game: clients go back to the title first, the host closes a moment later so the message
## is delivered (a client closes its own side when it arrives, with no HOST LEFT message).
func send_back_to_title() -> void:
	if mode != Mode.HOST:
		shutdown()
		return
	_to_title.rpc()
	in_game = false
	closing = true
	if _broadcast:
		_broadcast.close()
		_broadcast = null
	var gen := _close_gen
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void:
		if gen == _close_gen:
			shutdown())

@rpc("authority", "reliable")
func _to_title() -> void:
	in_game = false
	_close_quietly.call_deferred()

func _close_quietly() -> void:
	shutdown()
	G.goto_title()
