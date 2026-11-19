extends Node
## Developer harness: `godot --path . -- --autotest[=wave]` plays the game
## with a bot and saves screenshots to user://shots. Not used in normal play.

var t := 0.0
var shots := []
var out_dir := ""
var start_wave := 1
var _chest_shot := false
var _team_shot := false
var _arch_seen := 0.0
var _arch_shot := false
var _victory_shot := false
var end_at := -1.0 # --end=SECONDS[:win] ends the run then (as a win with :win) to capture the results screen
var end_win := false
var wizard_steps := 0 # --wizard=N steps the first player N wizards to the right in the lobby
var _results_shot := false
var quit_at := 60.0
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
		if a.begins_with("--wizard="):
			wizard_steps = int(a.substr(9))
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

func _process(delta: float) -> void:
	# A LAN host waits for the client to join before starting the clock again.
	if net == "host" and not shots.is_empty() and shots[0][1] == "@play" and Net.roster.size() < 2:
		return
	t += delta
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
	if end_at > 0.0 and t >= end_at and cur and "world" in cur and cur.world and cur.world.phase != World.PH_GAMEOVER \
			and not cur.world.is_picking():
		end_at = -1.0
		if end_win:
			cur.world.won = true
			cur.world.emit(World.EV_VICTORY, 240, 140, 0, 0)
		cur.world._end_run()
	if not _results_shot and cur and "results" in cur and cur.game_over and cur.game_over_t > 3.4:
		_results_shot = true
		get_viewport().get_texture().get_image().save_png("%s/results.png" % out_dir)
		print("shot results")
	while not shots.is_empty() and t >= shots[0][0]:
		var s = shots.pop_front()
		var name: String = s[1]
		if name == "@lobby":
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
				Net.add_local_device(0)
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
	if t > quit_at:
		get_tree().quit()
