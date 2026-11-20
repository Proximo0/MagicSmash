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
var wizard_steps := 0 # --wizard=N steps the first player N wizards to the right in the lobby
var players := 2 # --players=N local players (keyboard plus pads 0..N-2), 1 to 4
var _results_shot := false
var quit_at := 60.0
var _quit_override := -1.0
var net := ""
var _pick_seen := 0.0
var _pick_shot := false

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
		if a.begins_with("--out="):
			out_dir = a.split("=")[1]
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	shots = [[1.2, "title_intro"], [4.0, "title_menu"], [4.5, "@lobby"], [5.0, "lobby"], [5.5, "@play"],
		[7.0, "game_wave_banner"], [12.0, "game_a"], [16.0, "game_b"], [22.0, "game_c"], [28.0, "game_d"],
		[36.0, "game_e"], [44.0, "game_f"], [52.0, "game_g"], [58.0, "game_h"]]
	# --sanctum: walk into the Sanctum from the title, shoot the room, then the opened alcove, then stop.
	if "--sanctum" in OS.get_cmdline_user_args():
		shots = [[1.2, "title_intro"], [3.0, "@sanctum"], [4.5, "sanctum"], [4.6, "@alcove"], [5.6, "sanctum_alcove"]]
		quit_at = 6.0
	# --eclipse: click the moon and the castle window on the title, shoot the blood moon and the ghost.
	if "--eclipse" in OS.get_cmdline_user_args():
		shots = [[3.0, "@eclipse"], [5.2, "title_eclipse"]]
		quit_at = 5.6
	# --options: open the options on the title and shoot them, then stop.
	if "--options" in OS.get_cmdline_user_args():
		shots = [[3.0, "@options"], [3.4, "options"]]
		quit_at = 3.8
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
	# State-keyed shot: the first level-up pick screen, once it has been up for a moment.
	var cur = G.main.current if G.main else null
	if not _pick_shot and cur and cur.has_method("_anyone_picking") and cur._anyone_picking():
		_pick_seen += delta
		if _pick_seen > 0.4:
			_pick_shot = true
			get_viewport().get_texture().get_image().save_png("%s/levelup.png" % out_dir)
			print("shot levelup")
	# State-keyed shot: the first chest reel, just after it stops on the item.
	if not _chest_shot and cur and "_reveals" in cur:
		for r: Dictionary in cur._reveals:
			if r.t > cur.REEL_SPIN + 0.15:
				_chest_shot = true
				get_viewport().get_texture().get_image().save_png("%s/chest.png" % out_dir)
				print("shot chest")
				break
	# State-keyed shots: a card or rare chest lying on the floor (--tune=card_chance:0.05), then the card reveal
	# once its face has turned over.
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
	if perf and _perf_frames.size() >= PERF_FRAMES:
		return
	if not _results_shot and cur and "results" in cur and cur.game_over and cur.game_over_t > 3.4:
		_results_shot = true
		get_viewport().get_texture().get_image().save_png("%s/results.png" % out_dir)
		print("shot results")
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
		elif name == "@play":
			PlayerInput.bot = true
			if net == "join":
				continue
			Net.begin_game()
			await get_tree().process_frame
			var arena = G.main.current
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
	if t > (_quit_override if _quit_override > 0.0 else quit_at):
		get_tree().quit()


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
