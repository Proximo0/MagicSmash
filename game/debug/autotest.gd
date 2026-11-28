extends Node
## Developer harness: `godot --path . -- --autotest[=wave]` plays the game
## with a bot and saves screenshots to user://shots. Not used in normal play.

var t := 0.0
var shots := []
var out_dir := ""
var start_wave := 1
var _chest_shot := false
var _card_shot := false
var _card_drop_shot := false
var _team_shot := false
var _arch_seen := 0.0
var _arch_shot := false
var _victory_shot := false
var _act_shot := false
var end_at := -1.0 # --end=SECONDS[:win] ends the run then (as a win with :win) to capture the results screen
var end_win := false
var perf := false # --perf: once the horde is big, time 300 frames per system and print a table, then quit
var _perf_frames: Array = []
var perf_hide := "" # --perf-hide=name hides one arena layer (decal_layer, ent_layer, hud, fx...) while measuring
var _perf_draws := 0
var _perf_peak := 0
const PERF_FRAMES := 300
const PERF_ENEMIES := 180
var seats := false # --seats: two apprentices join the lobby
var wizard_steps := 0 # --wizard=N steps the first player N wizards to the right in the lobby
var class_pick := -1 # --class=archer: every human seat's roster row takes that class (class icon shots)
var novas_given := 0 # --novas=N: every wizard starts the run with N nova charges (skill mark shots)
var sheet_hero := 0 # --sheet=N: the --heroes shots end on the sheet of the Nth hero (0 mage, 1 knight, 2 archer, 3 priest)
var seat_heroes := false # --seat-heroes: the seats hold their heroes (Net.force_heroes), the guests their presets
var players := 2 # --players=N local players (keyboard plus pads 0..N-2), 1 to 4
var _results_shot := false
var _damage_shot := false
var _damage_shot_at := -1.0
var quit_at := 60.0
var _quit_override := -1.0
var net := ""
## Level-up shots: levelup.png (the first open tray), tab.png (a tab, tray closed, its wizard alive so the head
## marker shows), tray.png (two trays open at once, or one with more draws waiting behind it), lull.png (a lull
## 3.6 s in, its banner up), lull_end.png (the lull over, "THE HORDE RETURNS" up). Each keys on what the arena
## shows, held for LEVEL_SHOT_AFTER seconds.
var _level_seen := {"levelup": 0.0, "tab": 0.0, "tray": 0.0, "lull": 0.0, "lull_end": 0.0, "arrival": 0.0}
var _level_shots := {}
const LEVEL_SHOT_AFTER := {"levelup": 0.4, "tab": 0.75, "tray": 0.4, "lull": 3.6, "lull_end": 0.5, "arrival": 0.9} # tab: its marker
var hand: Array[int] = [] # --hand=quick,magnet,nova: every wizard's offered cards are replaced by these (art shots)
var _hand_offer := {}
var lull_hold := false # --lull: keeps the post-Lich lull running (art shots of the big hand)
var pick_hold := 0.0 # --pick-hold=SECONDS: the bot in slot 0 holds its pick that long
## --fall=SECONDS (2+ players): at that run time slot 1 falls; fallen.png shows her spirit with its clock running,
## fallen_call.png her call's ping, then slot 0 is held in her circle and fallen_ritual.png shows the circle about
## half filled (HUD: DOWN).
var fall_at := -1.0
## --fate=ID[,ID...] (Gamble.TEAM_OUTCOMES ids): from 10 s of run time on, every 12 s slot 0 is dealt the next of
## these fates as if it had paid the team shrine; fate_<id>.png shows each card face up, fate_hud.png the HUD
## 4 s after the last one landed (sealed novas, no potions).
var fates_forced: Array[int] = []
var _fate_next := 10.0
var _fate_shots := {}
var _fate_hud_at := -1.0
var _fall_step := 0
var _fall_t := 0.0
## --hazard=SECONDS: at that run time a fire disc, a flame line and a SAFE disc are laid near the party (Hazards,
## warning HAZARD_WARN s) and one of each reserved bestiary kind stands in a ring around it; hazard_warn.png is
## taken halfway through the warning, hazard_hot.png just after the rows turn hot.
var hazard_at := -1.0
var _hazard_shots := {}
const HAZARD_WARN := 2.0
## --kinds=bloat,coffin[@SECONDS[@RING]]: from that run time (default KINDS_AT) two of each named Bestiary kind stand in a
## ring KINDS_RING px round the party, KINDS_HP x as tough, again every KINDS_EVERY s. Shots key on what they do:
## kinds_ring.png once they stand, kinds_<key>_<state>.png the first time a kind is in each state 1..3 (not the guard,
## whose state is its facing), kinds_row<kind>_warn.png / _hot.png the first time each hazard kind warns (past 40%)
## or burns; kinds_mid.png 5 s and kinds_late.png KINDS_LATE s in.
var kinds_shown: Array[int] = []
var kinds_at := -1.0
var kinds_ring := 95.0 # --kinds=...@SECONDS@RING: the ring's radius, px (a wide one puts arrowed kinds off screen)
var _kinds_shots := {}
var _kinds_next := -1.0
var _kinds_seen := {} # shot key -> frames its condition has held
const KINDS_HOLD := 10 # frames a condition holds before its shot (the arena draws a snapshot behind the World)
const KINDS_AT := 4.0
## --credits: where in the roll the middle picture is taken (0 = start, 1 = end): inside the engine's licence list.
const CREDITS_LIST_AT := 0.5
const KINDS_RING := 95.0
const KINDS_HP := 3.0
const KINDS_EVERY := 12.0
const KINDS_LATE := 20.0
## --boss=chandelier|ghostwriter|lich[,PHASE]: the run starts just before that boss's minute (the Lich: the
## Archlich at the final minute); with PHASE (0, 1, 2) its health is held inside that phase. Each attack step it
## starts is shot BOSS_SHOT_AFTER s in (<boss>_<step>_warn.png) and once one of its rows is hot (<boss>_<step>_hot.png).
const BOSS_KEYS := {"chandelier": Bestiary.CHANDELIER, "ghostwriter": Bestiary.GHOSTWRITER, "lich": Bestiary.LICH}
const BOSS_SHOT_AFTER := 0.45
var boss_key := ""
var boss_phase := -1
var _boss_step := ""
var _boss_step_t := 0.0
var _boss_shots := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			start_wave = int(a.split("=")[1])
		# --tune=field:value,field:value sets live Tuning for this run (for example elite_interval:8 to see chests).
		if a.begins_with("--tune="):
			for kv: String in a.substr(7).split(","):
				var parts := kv.split(":")
				if parts.size() == 2:
					Tuning.shared().set_value(parts[0], float(parts[1]))
		# --seal=N plays the run at difficulty N, -1 (easy) to 9 (Net.seal; World.apply_seal).
		if a.begins_with("--seal="):
			Net.set_seal(int(a.substr(7)))
		if a.begins_with("--end="):
			var spec := a.substr(6).split(":")
			end_at = float(spec[0])
			end_win = spec.size() > 1 and spec[1] == "win"
			quit_at = maxf(quit_at, end_at + 8.0)
		# --quit=SECONDS stops the run early (art and UI loops that only need the first shots).
		if a.begins_with("--quit="):
			_quit_override = float(a.substr(7))
		if a.begins_with("--wizard="):
			wizard_steps = int(a.substr(9))
		if a.begins_with("--fall="):
			fall_at = float(a.substr(7))
		if a.begins_with("--boss="):
			var spec := a.substr(7).split(",")
			boss_key = spec[0]
			boss_phase = int(spec[1]) if spec.size() > 1 else -1
			var sched := Bosses.schedule_from(Tuning.shared())
			for row: Array in sched:
				if int(row[1]) == int(BOSS_KEYS.get(boss_key, -1)) and (boss_key != "lich" or row[2]):
					start_wave = int(float(row[0]) / 60.0)
					break
		if a.begins_with("--hazard="):
			hazard_at = float(a.substr(9))
		if a.begins_with("--kinds="):
			var spec := a.substr(8).split("@")
			kinds_at = float(spec[1]) if spec.size() > 1 else KINDS_AT
			kinds_ring = float(spec[2]) if spec.size() > 2 else KINDS_RING
			for k: String in spec[0].split(","):
				for i: int in range(Bestiary.count()):
					if Bestiary.KINDS[i][Bestiary.K_KEY] == k:
						kinds_shown.append(i)
		if a.begins_with("--fate="):
			for f: String in a.substr(7).split(","):
				fates_forced.append(clampi(int(f), 0, Gamble.TEAM_OUTCOMES.size() - 1))
		if a == "--lull":
			lull_hold = true
		if a.begins_with("--hand="):
			for k: String in a.substr(7).split(","):
				for i: int in range(Upgrades.count()):
					if Upgrades.key(i) == k:
						hand.append(i)
		if a.begins_with("--pick-hold="):
			pick_hold = float(a.substr(12))
		if a.begins_with("--players="):
			players = clampi(int(a.substr(10)), 1, 4)
		if a.begins_with("--perf-hide="):
			perf_hide = a.substr(12)
		if a == "--perf":
			perf = true
			quit_at = 240.0
		if a == "--passive":
			PlayerInput.bot_passive = true
		if a.begins_with("--net="):
			net = a.split("=")[1]
		if a.begins_with("--class="):
			class_pick = Classes.index_of(a.split("=")[1])
		if a.begins_with("--novas="):
			novas_given = int(a.split("=")[1])
		if a.begins_with("--sheet="):
			sheet_hero = int(a.split("=")[1])
		if a.begins_with("--out="):
			out_dir = a.split("=")[1]
		if a.begins_with("--art="): # a folder searched first for pictures, laid out like assets/art (art shots)
			Art.drop_root = a.split("=")[1].rstrip("/") + "/"
			Art.forget()
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	shots = [[1.2, "title_intro"], [4.0, "title_menu"], [4.5, "@lobby"], [5.0, "lobby"], [5.5, "@play"],
		[7.0, "game_wave_banner"], [12.0, "game_a"], [16.0, "game_b"], [22.0, "game_c"], [28.0, "game_d"],
		[36.0, "game_e"], [44.0, "game_f"], [52.0, "game_g"], [58.0, "game_h"]]
	# --seat-heroes: the seats hold their heroes as in a real run (a scripted run seats none otherwise).
	seat_heroes = "--seat-heroes" in OS.get_cmdline_user_args()
	if seat_heroes:
		Net.force_heroes = true
	# --sanctum: walk into the Sanctum from the title, shoot the room, then the opened alcove, then stop.
	if "--sanctum" in OS.get_cmdline_user_args():
		shots = [[1.2, "title_intro"], [3.0, "@sanctum"], [4.5, "sanctum"], [4.6, "@alcove"], [5.6, "sanctum_alcove"]]
		quit_at = 6.0
	# --deeds: the Sanctum's lectern and the Book of Deeds, at the top of the list and scrolled down.
	if "--deeds" in OS.get_cmdline_user_args():
		shots = [[1.2, "title_intro"], [3.0, "@sanctum"], [3.1, "@deeds_near"], [3.4, "deeds_sanctum"], [3.5, "@deeds_book"],
			[4.0, "deeds_book"], [4.1, "@deeds_scroll"], [4.6, "deeds_book_scrolled"]]
		quit_at = 5.2
	# --talk: the Sanctum's talkers (shopkeeper, card reader, Morvane after a loss), then --talk-lull: Morvane in a lull.
	if "--talk" in OS.get_cmdline_user_args():
		shots = [[1.2, "title_intro"], [3.0, "@sanctum"], [3.5, "@talk_shop"], [4.0, "talk_shopkeeper"], [4.1, "@talk_reader"],
			[4.6, "talk_card_reader"], [4.7, "@talk_morvane"], [5.2, "talk_morvane_loss"]]
		quit_at = 5.6
	# --heroes: the Sanctum's mirror: the hero roster, the builder on each step (a mage, so SCHOOL shows), then a sheet.
	if "--heroes" in OS.get_cmdline_user_args():
		shots = [[1.2, "title_intro"], [3.0, "@sanctum"], [3.1, "@heroes_near"], [3.4, "heroes_sanctum"], [3.5, "@heroes_roster"], [4.0, "heroes_roster"],
			[4.1, "@heroes_race"], [4.5, "heroes_builder_race"], [4.6, "@heroes_class"], [5.0, "heroes_builder_class"],
			[5.1, "@heroes_school"], [5.5, "heroes_builder_school"], [5.6, "@heroes_name"], [6.2, "heroes_builder_name"],
			[6.3, "@heroes_confirm"], [6.8, "heroes_builder_confirm"], [6.9, "@heroes_sheet"], [7.4, "heroes_sheet"]]
		quit_at = 7.8
	if "--talk-lull" in OS.get_cmdline_user_args():
		shots = [[4.5, "@lobby"], [5.5, "@play"], [8.0, "@talk_lull"], [9.5, "talk_lull"]]
		quit_at = 10.0
	# --seats: the lobby with one human and two apprentices (seats_lobby), then the run they play (seats_run_*).
	if "--seats" in OS.get_cmdline_user_args():
		players = 1
		seats = true
		shots = [[1.2, "title_intro"], [4.5, "@lobby"], [5.0, "seats_lobby"], [5.5, "@play"], [9.0, "seats_run_a"],
			[24.0, "seats_run_b"], [40.0, "seats_run_c"]]
		quit_at = 41.0
	# --eclipse: click the moon and the castle window on the title, shoot the blood moon and the ghost.
	if "--eclipse" in OS.get_cmdline_user_args():
		shots = [[3.0, "@eclipse"], [5.2, "title_eclipse"]]
		quit_at = 5.6
	# --options: open the options on the title and shoot them, then stop.
	if "--options" in OS.get_cmdline_user_args():
		shots = [[3.0, "@options"], [3.4, "options"]]
		quit_at = 3.8
	# --credits: open the credits on the title and shoot the roll at its start, in the licence list and at its end.
	if "--credits" in OS.get_cmdline_user_args():
		shots = [[3.0, "@credits"], [3.4, "credits"], [3.5, "@credits_list"], [3.9, "credits_licences"],
			[4.0, "@credits_end"], [4.4, "credits_end"]]
		quit_at = 4.8
	# --album: open the card album on the title (with a few cards found, in memory only) and shoot it.
	if "--album" in OS.get_cmdline_user_args():
		shots.insert(2, [4.1, "@album"])
		shots.insert(3, [4.35, "album"])
		shots.insert(4, [4.4, "@menu"])

func _process(delta: float) -> void:
	# A LAN host waits for the client to join before starting the clock again.
	if net == "host" and not shots.is_empty() and shots[0][1] == "@play" and Net.roster.size() < 2:
		return
	t += delta
	if perf:
		_perf_tick()
	var cur = G.main.current if G.main else null
	if lull_hold and cur and "world" in cur and cur.world:
		cur.world.lull_left = 20.0
		for lp: World.Player in cur.world.players.values():
			if lp.choices.is_empty() and lp.pending < 1:
				lp.pending = 1
	if not hand.is_empty() and cur and "world" in cur and cur.world:
		for p: World.Player in cur.world.players.values():
			if not p.choices.is_empty() and _hand_offer.get(p.slot, -1) != p.offer:
				_hand_offer[p.slot] = p.offer
				# Only the listed cards she can still take: a maxed card, or one the slots refuse, would be picked,
				# refused and dealt again on every step, and the tray would stay open for the rest of the run.
				var can: Array[int] = []
				for c: int in hand:
					if Upgrades.available(p.upgrades, c, cur.world.slot_cap(), p.banned):
						can.append(c)
				if not can.is_empty():
					p.choices = can
	# State-keyed shots of the level-up cards and the lull (_level_shot below).
	if cur and "lull_left" in cur:
		_level_shot("levelup", delta, _any_tray(cur, false), false)
		_level_shot("tab", delta, _any_tab(cur), false)
		_level_shot("tray", delta, _any_tray(cur, true), false)
		_level_shot("lull", delta, cur.lull_left > 0.0, false)
		_level_shot("arrival", delta, ArenaFateView._arrival_rect(cur).position.x < 400.0 and ArenaFateView._arrival_rect(cur).size.x > 0.0, false)
		_level_shot("lull_end", delta, cur.banner.t > 0.0 and cur.banner.text == "THE HORDE RETURNS", false)
	# State-keyed shot: the first chest reel, just after it stops on the item.
	if not _chest_shot and cur and "_reveals" in cur:
		for r: Dictionary in cur._reveals:
			if r.t > cur.REEL_SPIN + 0.15:
				_chest_shot = true
				get_viewport().get_texture().get_image().save_png("%s/chest.png" % out_dir)
				print("shot chest")
				break
	# State-keyed shots: a card or rare chest lying on the floor, then the card's notice under the HUD a second in
	# (a card run at once: --tune=card_run_chance:1,card_run_urn:0,loot_moment_from:0,loot_moment_to:0.01).
	if not _card_drop_shot and cur and "vk" in cur:
		for k: Array in cur.vk:
			if int(k[0]) >= World.PK_CARD:
				_card_drop_shot = true
				get_viewport().get_texture().get_image().save_png("%s/card_drop.png" % out_dir)
				print("shot card_drop")
				break
	if not _card_shot and cur and "_cards" in cur and not cur._cards.is_empty() and cur._cards[0].t > 1.0:
		_card_shot = true
		get_viewport().get_texture().get_image().save_png("%s/card.png" % out_dir)
		print("shot card")
	# State-keyed shot: the team shrine's reel halfway through its spin, the clip moment.
	if cur and "world" in cur and cur.world:
		_fate_tick(cur)
	if not _team_shot and cur and "_bets" in cur:
		for b: Dictionary in cur._bets:
			if b.kind == Gamble.TEAM and b.t > b.spin * 0.5:
				_team_shot = true
				get_viewport().get_texture().get_image().save_png("%s/team_shrine.png" % out_dir)
				print("shot team_shrine")
				break
	# State-keyed shots: the Archlich a moment after it appears (--autotest=15), and the victory screen.
	if not _arch_shot and cur and "boss_final" in cur and cur.boss_final and not cur._anyone_picking():
		_arch_seen += delta
		if _arch_seen > 1.5:
			_arch_shot = true
			get_viewport().get_texture().get_image().save_png("%s/archlich.png" % out_dir)
			print("shot archlich")
	if not _victory_shot and cur and "victory" in cur and cur.victory and cur.game_over and cur.game_over_t > 1.2:
		_victory_shot = true
		get_viewport().get_texture().get_image().save_png("%s/victory.png" % out_dir)
		print("shot victory")
	# State-keyed shot: the backdrop halfway through its fade to the next act (--autotest=5 crosses into act II).
	if not _act_shot and cur and "_act_fade" in cur and cur._act_fade >= 1.0:
		_act_shot = true
		get_viewport().get_texture().get_image().save_png("%s/act_fade.png" % out_dir)
		print("shot act_fade")
	if end_at > 0.0 and t >= end_at and cur and "world" in cur and cur.world and cur.world.phase != World.PH_GAMEOVER \
			and not cur.world.is_picking():
		end_at = -1.0
		if end_win:
			cur.world.won = true
			cur.world.emit(World.EV_VICTORY, 240, 140, 0, 0)
		cur.world._end_run()
	if fall_at > 0.0 and cur and "world" in cur and cur.world:
		_fall_tick(cur)
	if hazard_at > 0.0 and cur and "world" in cur and cur.world:
		_hazard_tick(cur.world)
	if kinds_at > 0.0 and cur and "world" in cur and cur.world:
		_kinds_tick(cur.world)
	if not boss_key.is_empty() and cur and "world" in cur and cur.world:
		_boss_tick(cur.world, delta)
	if perf and _perf_frames.size() >= PERF_FRAMES:
		return
	if not _results_shot and cur and "results" in cur and cur.game_over and cur.game_over_t > 3.4:
		_results_shot = true
		get_viewport().get_texture().get_image().save_png("%s/results.png" % out_dir)
		print("shot results")
	if _results_shot and not _damage_shot and cur and "results_page" in cur and cur.game_over and cur.game_over_t > 3.6:
		cur.results_page = ArenaResultsView.DMG_PAGE # the damage page, as the fire press leaves the first
		_damage_shot = true
		_damage_shot_at = t + 0.2
	if _damage_shot and _damage_shot_at > 0.0 and t >= _damage_shot_at:
		_damage_shot_at = -1.0
		get_viewport().get_texture().get_image().save_png("%s/results_damage.png" % out_dir)
		print("shot results_damage")
	while not shots.is_empty() and t >= shots[0][0]:
		var s = shots.pop_front()
		var name: String = s[1]
		if name == "@eclipse":
			var tt = G.main.current
			tt.state = tt.S.MAIN
			tt._title_secret(tt.MOON)
			tt._title_secret(tt.TOP_WINDOW.get_center())
		elif name == "@sanctum":
			G.local_devices = [G.DEV_KBM]
			G.goto_sanctum()
		elif name == "@alcove":
			var view = G.main.current
			view.room.crack_open = true
			view.room.pos = Vector2(404, 48)
			view.room.facing = Vector2.RIGHT
			view.room.in_alcove = true
			view.room._break_pot(0)
			view.room._break_pot(1)
		elif name == "@talk_shop" or name == "@talk_reader" or name == "@talk_morvane":
			var tv = G.main.current
			tv.message_t = 0.0
			tv.dlg.active = false
			for sp: int in range(3):
				Save.profile.first_time(Profile.first_key(sp)) # the shots show the run-based lines, not the first visit's
			if name == "@talk_shop":
				tv._talk(Talk.SHOPKEEPER, {"result": "loss", "act": 1, "seal": 0})
			elif name == "@talk_reader":
				tv._talk(Talk.CARD_READER, {"act": 1, "seal": 0})
			else:
				tv._talk(Talk.MORVANE, {"result": "loss", "seal": 0})
			tv.dlg.finish()
		elif name.begins_with("@deeds_"):
			_deeds_step(name)
		elif name.begins_with("@heroes_"):
			_heroes_step(name)
		elif name == "@talk_lull":
			var ta = G.main.current
			ta.act = 1
			ArenaTalk.start(ta)
		elif name == "@album":
			for i: int in [0, 1, 4, 5, 7, 8, 10]:
				Save.profile.add_card(i)
			Save.profile.add_card(5)
			Save.profile.socket_card(5)
			Save.profile.socket_card(4)
			var album_title = G.main.current
			album_title.album.open()
			album_title.album.sel = 5
			album_title.state = album_title.S.CARDS
		elif name.begins_with("@credits"):
			var credits_title = G.main.current
			if name == "@credits":
				credits_title.credits.open()
				credits_title.credits.scroll_to(-CreditsView.LEAD_IN)  # the opening view, held still for the picture
				credits_title.state = credits_title.S.CREDITS
			else:
				var end: float = credits_title.credits.max_scroll()
				credits_title.credits.scroll_to(end if name == "@credits_end" else end * CREDITS_LIST_AT)
		elif name == "@options":
			var options_title = G.main.current
			options_title.options.open()
			options_title.options.sel = Settings.R_CRASH
			options_title.state = options_title.S.OPTIONS
		elif name == "@menu":
			G.main.current.state = G.main.current.S.MAIN
		elif name == "@lobby":
			G.local_devices = [G.DEV_KBM]
			var title = G.main.current
			if net == "host":
				Net.host_game()
				title.state = 2
			elif net == "join":
				Net.join_game("127.0.0.1")
				title.state = 4
			else:
				Net.start_offline()
				for d in players - 1:
					Net.add_local_device(d)
				title.state = 2
			for _i in wizard_steps:
				Net.cycle_wizard(G.DEV_KBM, 1)
			if class_pick >= 0:
				for e: Dictionary in Net.roster:
					e["cls"] = class_pick
					e["hero"] = Hero.make(Races.HUMAN, class_pick, 0, "TESTER").to_dict()
			if seats:
				Net.add_apprentice()
				Net.add_apprentice()
		elif name == "@play":
			PlayerInput.bot = true
			if net == "join":
				continue
			Net.begin_game()
			await get_tree().process_frame
			var arena = G.main.current
			arena.autotest_pick_hold = pick_hold
			if arena.world and novas_given > 0:
				for q: World.Player in arena.world.players.values():
					q.bombs = novas_given
			if arena.world and start_wave > 1:
				# Jump the run clock to just before the start_wave:00 mark (5 brings the Lich); the horde announces
				# the new minute itself.
				arena.world.wave = start_wave
				arena.world.wave_time = start_wave * 60.0 - 0.5
		else:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [out_dir, name])
			print("shot ", name, " fps=", Engine.get_frames_per_second(),
				" particles=", (G.main.current.fx.parts.size() if "fx" in G.main.current else 0))
	var stop := _quit_override if _quit_override > 0.0 else quit_at
	if t > stop - 0.3 and cur and "lull_left" in cur:
		# Time fallback: a card shot whose state never came is taken anyway, marked as such, so a run always says why.
		for k: String in _level_seen.keys():
			_level_shot(k, 0.0, true, true)
	if t > stop:
		get_tree().quit()


## Takes the shot `name` once `seen` has held for LEVEL_SHOT_AFTER[name] seconds in a row (or at once as a fallback).
func _level_shot(name: String, delta: float, seen: bool, fallback: bool) -> void:
	if _level_shots.has(name):
		return
	_level_seen[name] = float(_level_seen[name]) + delta if seen else 0.0
	if not fallback and float(_level_seen[name]) < float(LEVEL_SHOT_AFTER[name]):
		return
	_level_shots[name] = true
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot %s%s" % [name, " (fallback: the state never showed)" if fallback else ""])


## True while some wizard's tray is open and fully face up (with `more`: two such trays, or one with more draws
## waiting behind its hand).
func _any_tray(cur: Node, more: bool) -> bool:
	if cur.game_over or cur.paused:
		return false
	var open := 0
	for slot: int in cur.vp.keys():
		if cur._tray_shown(slot) and cur._tray_turn(slot, (cur.vp[slot].choices as Array).size() - 1) >= 1.0:
			if not more or cur._draws(slot) > 1:
				return true
			open += 1
	return more and open >= 2


## True while some living wizard's tab shows (draws waiting, tray closed), so its head marker is up too.
func _any_tab(cur: Node) -> bool:
	if cur.game_over or cur.paused:
		return false
	for slot: int in cur.vp.keys():
		if cur._draws(slot) > 0 and not cur._tray_shown(slot) and cur.vp[slot].alive:
			return true
	return false


## Waits for a big horde, then books PERF_FRAMES frames: wall frame time, each system's script time (PerfMeter)
## and draw calls. Prints one PERF line per system and quits.
func _perf_tick() -> void:
	var cur = G.main.current if G.main else null
	if cur == null or not ("world" in cur) or cur.world == null:
		return
	var n: int = cur.world.enemies.size()
	if not PerfMeter.on:
		if n >= PERF_ENEMIES or t > quit_at - 20.0:
			PerfMeter.reset()
			PerfMeter.on = true
			if perf_hide != "" and perf_hide in cur:
				(cur.get(perf_hide) as CanvasItem).visible = false
			_perf_frames.clear()
		return
	_perf_frames.append(Time.get_ticks_usec())
	_perf_draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_perf_peak = maxi(_perf_peak, n)
	if _perf_frames.size() < PERF_FRAMES:
		return
	PerfMeter.on = false
	var gaps: Array = []
	for i in range(1, _perf_frames.size()):
		gaps.append(float(_perf_frames[i] - _perf_frames[i - 1]) / 1000.0)
	gaps.sort()
	var f := float(gaps.size())
	print("PERF frames=%d enemies_peak=%d particles=%d draw_calls=%.0f frame_ms p50=%.1f p95=%.1f" % [
		PERF_FRAMES, _perf_peak, cur.fx.parts.size(), float(_perf_draws) / PERF_FRAMES, gaps[int(f * 0.5)], gaps[int(f * 0.95)]])
	var names: Array = PerfMeter.acc.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return PerfMeter.acc[a] > PerfMeter.acc[b])
	var total := 0.0
	for k: String in names:
		var ms: float = float(PerfMeter.acc[k]) / 1000.0 / PERF_FRAMES
		total += ms
		print("PERF %-14s %6.2f ms/frame" % [k, ms])
	print("PERF %-14s %6.2f ms/frame" % ["total_script", total])
	get_tree().quit()


## --fall: slot 1 falls at fall_at s of run time and calls for help at once (as her nova would); shots of the call's
## ping, of her spirit (clock running) and of a ritual about half done. Bots may raise her before the last one.
func _fall_tick(cur: Node) -> void:
	var w: World = cur.world
	if not w.players.has(1) or w.players.size() < 2:
		return
	var p: World.Player = w.players[1]
	match _fall_step:
		0:
			if w.wave_time >= fall_at and p.alive and not w.is_picking():
				p.invuln = 0.0
				w.hurt_player(p, 99)
				if p.down:
					w.emit(World.EV_CALL, p.pos.x, p.pos.y, p.slot, 0)
					_fall_step = 1
					_fall_t = t
		1:
			if t - _fall_t > 0.3:
				_fall_shot("fallen_call")
				_fall_step = 2
		2:
			if t - _fall_t > 0.8:
				_fall_shot("fallen")
				_fall_step = 3
		3:
			if not p.down:
				print("fallen_ritual: she rose before the shot")
				_fall_step = 4
				return
			var q: World.Player = w.players[0]
			q.pos = p.pos + Vector2(4, 3)
			q.invuln = maxf(q.invuln, 0.5)
			if p.revive >= 0.45:
				_fall_shot("fallen_ritual")
				_fall_step = 4


func _fall_shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


## --fate: deals the forced fates and takes their shots (see fates_forced).
func _fate_tick(cur: Node) -> void:
	var w: World = cur.world
	if not fates_forced.is_empty() and w.phase == World.PH_FIGHT and w.wave_time >= _fate_next:
		_fate_next = w.wave_time + 12.0
		var id: int = fates_forced.pop_front()
		var at := w.party_center()
		WorldShrines._queue_gamble(w, {"t": w.wave_time + w.tune.team_reel, "slot": 0, "kind": Gamble.TEAM, "outcome": id, "stake": 0, "pos": at})
		w.emit(World.EV_SHRINE, at.x, at.y, 0, Gamble.TEAM * 16 + id)
		if fates_forced.is_empty():
			_fate_hud_at = w.wave_time + w.tune.team_reel + 4.0
	for b: Dictionary in cur._bets:
		var key := "fate_%d" % int(b.outcome)
		if b.kind == Gamble.TEAM and b.t > b.spin + 0.6 and not _fate_shots.has(key):
			_fate_shots[key] = true
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, key])
			print("shot ", key)
	if _fate_hud_at > 0.0 and w.wave_time >= _fate_hud_at:
		_fate_hud_at = -1.0
		get_viewport().get_texture().get_image().save_png("%s/fate_hud.png" % out_dir)
		print("shot fate_hud")


## --hazard: lays the rows and the stand-ins once, then takes the two shots (see hazard_at).
func _hazard_tick(w: World) -> void:
	if w.phase != World.PH_FIGHT:
		return
	if not _hazard_shots.has("laid") and w.wave_time >= hazard_at:
		_hazard_shots["laid"] = w.wave_time
		var c := w.party_center()
		w.add_hazard(Hazards.FIRE, c + Vector2(-45, 10), c + Vector2(-45, 10), 22.0, HAZARD_WARN, 3.0, -1, 0, true)
		w.add_hazard(Hazards.FLAME, c + Vector2(20, -50), c + Vector2(90, 30), 6.0, HAZARD_WARN, 3.0, -1, 0, true)
		w.add_hazard(Hazards.SAFE, c + Vector2(60, 50), c + Vector2(60, 50), 28.0, HAZARD_WARN, 0.6, -1, 0, true)
		for t: int in range(Bestiary.BLOAT, Bestiary.count()):
			var at := c + Vector2.from_angle(TAU * (t - Bestiary.BLOAT) / (Bestiary.count() - Bestiary.BLOAT)) * 95.0
			if not Bestiary.has_flag(t, Bestiary.F_BOSS):
				var e := w.spawn_enemy(t, 0, at)
				e.hp = 9999.0
				e.maxhp = 9999.0
	if not _hazard_shots.has("laid"):
		return
	var since: float = w.wave_time - float(_hazard_shots["laid"])
	if since >= HAZARD_WARN * 0.5 and not _hazard_shots.has("warn"):
		_hazard_shots["warn"] = true
		_fall_shot("hazard_warn")
	if since >= HAZARD_WARN + 0.25 and not _hazard_shots.has("hot"):
		_hazard_shots["hot"] = true
		_fall_shot("hazard_hot")


## --kinds: rings the named kinds round the party and takes their shots (see kinds_shown).
func _kinds_tick(w: World) -> void:
	if w.phase != World.PH_FIGHT or w.is_picking():
		return
	if w.wave_time >= kinds_at and (_kinds_next < 0.0 or w.wave_time >= _kinds_next):
		_kinds_next = w.wave_time + KINDS_EVERY
		var c := w.party_center()
		var n := kinds_shown.size() * 2
		for i: int in range(n):
			var e := w.spawn_enemy(kinds_shown[i % kinds_shown.size()], 0, c + Vector2.from_angle(TAU * i / n + 0.3) * kinds_ring)
			e.hp *= KINDS_HP
			e.maxhp = e.hp
		if not _kinds_shots.has("start"):
			_kinds_shots["start"] = w.wave_time
	if not _kinds_shots.has("start"):
		return
	var since: float = w.wave_time - float(_kinds_shots["start"])
	var keyed: Array = [["kinds_ring", since >= 0.5], ["kinds_mid", since >= 5.0], ["kinds_late", since >= KINDS_LATE]]
	for e: World.Enemy in w.enemies:
		var st: int = e.state % KindsLibrary.HOUND_SLOT_STEP if e.type == Bestiary.HOUND else e.state
		if e.type in kinds_shown and e.type != Bestiary.GUARD and st > 0 and st < 4 and since >= 0.3:
			keyed.append(["kinds_%s_%d" % [Bestiary.KINDS[e.type][Bestiary.K_KEY], st], true])
	for h: Hazards.Hazard in w.hazards:
		keyed.append(["kinds_row%d_%s" % [h.kind, "warn" if h.warn > 0.0 else "hot"], h.warn < h.warn0 * 0.6 if h.warn > 0.0 else h.hot > 0.0])
	var seen := {}
	for shot: Array in keyed:
		if shot[1] and not _kinds_shots.has(shot[0]) and not seen.has(shot[0]):
			seen[shot[0]] = true
			_kinds_seen[shot[0]] = int(_kinds_seen.get(shot[0], 0)) + 1
			if _kinds_seen[shot[0]] >= KINDS_HOLD:
				_kinds_shots[shot[0]] = true
				_fall_shot(shot[0])


## --boss: holds the boss's health inside the asked phase and shoots each attack step's warning and hot rows.
func _boss_tick(w: World, delta: float) -> void:
	var e: World.Enemy = w.boss
	if e == null or e.dead or e.entering or w.phase != World.PH_FIGHT:
		return
	if boss_phase >= 0:
		var lines: Array = [1.0, 0.75, 0.35, 0.0] if e.final else [1.0, Bosses.PHASE_AT, 0.0]
		var hi: float = lines[mini(boss_phase, lines.size() - 2)]
		var lo: float = lines[mini(boss_phase, lines.size() - 2) + 1]
		var f := e.hp / e.maxhp
		if f > hi - 0.01 or f < lo + 0.02:
			e.hp = e.maxhp * (lo + 0.6 * (hi - lo))
	var step := "%d" % e.state
	if e.type == Bestiary.GHOSTWRITER and BossGhostwriter.word_of(w.boss_arg) != BossGhostwriter.WORD_NONE:
		step = BossGhostwriter.WORDS[BossGhostwriter.word_of(w.boss_arg)].to_lower() + ("_%d" % e.state)
	if step != _boss_step:
		_boss_step = step
		_boss_step_t = 0.0
	_boss_step_t += delta
	var name := "%s_%s" % [boss_key, step]
	if _boss_step_t >= BOSS_SHOT_AFTER and not _boss_shots.has(name + "_warn"):
		var warning := false
		for h: Hazards.Hazard in w.hazards:
			warning = warning or (h.owner == e.id and h.warn > 0.0)
		if warning:
			_boss_shots[name + "_warn"] = true
			_fall_shot(name + "_warn")
	if not _boss_shots.has(name + "_hot"):
		for h: Hazards.Hazard in w.hazards:
			if h.owner == e.id and h.fired and h.hot > 0.0 and h.kind != Hazards.LANE:
				_boss_shots[name + "_hot"] = true
				_fall_shot(name + "_hot")
				break


## One setup step of the --deeds shots: a profile with some deeds earned (never saved: scripted runs write nothing).
func _deeds_step(name: String) -> void:
	var view = G.main.current
	var prof: Profile = Save.profile
	match name:
		"@deeds_near":
			view.room.pos = Sanctum.THINGS[Sanctum.DEEDS][1] + Vector2(10, 12)
		"@deeds_book":
			for api: String in ["ARCHLICH", "SOLO_WIN", "TEN_MINUTES", "EVOLVE", "WIN_MAGE", "WIN_HUMAN", "EVO_FIRE", "WIN_SEAL_8",
					"KILLS_1K"]:
				prof.deeds[api] = true
			view.deeds_book.open(prof)
			view.deeds_book.sel = 4
			view.deeds_open = true
		"@deeds_scroll":
			view.deeds_book._select(34)


## One setup step of the --heroes shots: a few heroes in the profile (never saved: scripted runs write nothing), the
## roster open over the Sanctum, then the builder on each step and a sheet.
func _heroes_step(name: String) -> void:
	var view = G.main.current
	var prof: Profile = Save.profile
	var ro: HeroRoster = view.roster
	var b: HeroBuilder = ro.builder
	match name:
		"@heroes_near":
			view.room.pos = Sanctum.THINGS[Sanctum.MIRROR][1] + Vector2(10, 10)
		"@heroes_roster":
			prof.heroes = [Hero.make(Races.HUMAN, Classes.MAGE, 1, "MORVANE"), Hero.make(Races.ORC, Classes.KNIGHT, 0, "GRAKK"),
				Hero.make(Races.ELF, Classes.ARCHER, 0, "SYLVANAS"), Hero.make(Races.DWARF, Classes.PRIEST, 0, "BRUNA")]
			prof.heroes[0].add_xp(900)
			prof.heroes[1].add_xp(250)
			prof.hero = 0
			prof.runs = 14
			prof.wins = 3
			for i: int in [0, 4, 5]:
				prof.add_card(i)
			ro.open(prof, G.DEV_KBM)
			ro.sel = 1
			view.roster_open = true
		"@heroes_race":
			ro.do_action(HeroRoster.A_NEW)
			b.sel = Races.ORC
		"@heroes_class":
			b.choose(Races.ORC)
			b.sel = Classes.PALADIN
		"@heroes_school":
			b.choose(Classes.MAGE)
			b.sel = 1
		"@heroes_name":
			b.choose(1)
			b.ouija.text = "ASHEN"
			b.ouija.row = 2
			b.ouija.col = 4
		"@heroes_confirm":
			b.submit_name()
		"@heroes_sheet":
			b.active = false
			prof.heroes[sheet_hero].sockets[Cards.socket(4)] = Cards.key(4)
			ro.sheet.open(prof, sheet_hero)
			ro.sheet.sel = 2
