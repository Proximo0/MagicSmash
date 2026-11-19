extends Node
## Developer harness: `godot --path . -- --autotest[=wave]` plays the game
## with a bot and saves screenshots to user://shots. Not used in normal play.

var t := 0.0
var shots := []
var out_dir := ""
var start_wave := 1
var quit_at := 60.0
var net := ""
var _pick_seen := 0.0
var _pick_shot := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			start_wave = int(a.split("=")[1])
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
		elif name == "@play":
			PlayerInput.bot = true
			if net == "join":
				continue
			Net.begin_game()
			await get_tree().process_frame
			var arena = G.main.current
			if arena.world and start_wave > 1:
				arena.world.wave = start_wave
				arena.world.events.append([World.EV_WAVE, 0, 0, start_wave, 1 if start_wave % 5 == 0 else 0])
		else:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [out_dir, name])
			print("shot ", name, " fps=", Engine.get_frames_per_second(),
				" particles=", (G.main.current.fx.parts.size() if "fx" in G.main.current else 0))
	if t > quit_at:
		get_tree().quit()
