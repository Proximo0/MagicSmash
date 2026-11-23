extends SceneTree
## The field client's pieces with no server: the art by file name with stand-ins, the sound hooks, the effect
## rows and events, the HUD's reads, the input mapping. Prints one line, FIELD_TEST ok|FAILED ..., and exits 1
## on failure.
## godot --headless --path realm/client -s res://tests/field_test.gd

var _problems: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_art()
	_anim()
	_sound()
	_fx()
	_hud()
	_input()
	var ok: bool = _problems.is_empty()
	print("FIELD_TEST %s checks=%d%s" % ["ok" if ok else "FAILED", _checks, "" if ok else " problems=\"%s\"" % "; ".join(_problems)])
	quit(0 if ok else 1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_problems.append(what)


func _art() -> void:
	_check(RealmLink.kind_count() == 42, "the core has 42 kinds, got %d" % RealmLink.kind_count())
	_check(FieldArt.kind_key("plague rat") == "enemy_plague_rat", "kind key of a two-word name")
	var kinds: Array[Dictionary] = FieldArt.monster_entries()
	_check(kinds.size() == 42, "42 monster entries, got %d" % kinds.size())
	var sum: Dictionary = FieldArt.art_summary(kinds)
	# The Tower's eight are drawn; every other kind has a stand-in until its picture arrives.
	_check(int(sum["still"]) + int(sum["walk"]) >= 8, "the Tower's eight pictures are found by name: %s" % sum)
	_check(int(sum["stand-in"]) + int(sum["still"]) + int(sum["walk"]) == 42, "every kind has a picture")
	for e in kinds:
		var t: Texture2D = e["tex"]
		_check(t != null and t.get_width() > 4 and t.get_height() > 4, "a picture or a stand-in with a size")
		_check(int(e["anim"]) >= 1 and float(e["scale"]) > 0.0, "anim and scale are set")
	var heroes: Array[Dictionary] = FieldArt.hero_entries()
	_check(heroes.size() == 24, "24 hero entries, got %d" % heroes.size())
	var walk: Dictionary = FieldArt.hero_entry(1, 1)
	_check(walk["art"] == "walk" and int(walk["anim"]) == 8 and float(walk["scale"]) < 0.5, "elf knight is the 8-frame walk strip from its sidecar")
	_check((walk["tex"] as Texture2D).get_width() % 8 == 0, "a strip of eight whole frames")
	_check(is_equal_approx(float(walk["fps"]), 12.0), "the sidecar sets 12 fps")
	_check(int(walk["atk_n"]) == 8 and int(walk["hit_n"]) == 4 and int(walk["die_n"]) == 8, "atk, hit and die frame counts come from the sidecar")
	_check((walk["atk"] as Texture2D).get_width() % 8 == 0 and (walk["hit"] as Texture2D).get_width() % 4 == 0, "strips of whole frames")
	_sidecar()
	var novice: Dictionary = FieldArt.hero_entry(0, 0)
	_check(novice["art"] == "walk", "human novice is a walk strip")
	_check(int(FieldArt.art_summary(heroes)["walk"]) == 24, "all 24 heroes have walk strips")
	var old_style: Dictionary = FieldArt.entry_for("enemy_guard")
	_check(not old_style.has("atk_n"), "art without strips keeps the old defaults")
	# The batch builds an atlas from these.
	var holder := Node.new()
	var batch := RealmBatch.new(holder, kinds, 1)
	_check(batch.count == 0, "a batch starts empty")
	holder.free()


## A strip's frames, fps and scale come from its .json next to it; a bad count falls back to 4.
func _sidecar() -> void:
	var dir: String = OS.get_temp_dir().path_join("field_test_sidecar")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("hero_x_y_walk.json"), FileAccess.WRITE)
	f.store_string('{"frames":8,"fps":16,"scale":0.25}')
	f.close()
	var p: Dictionary = FieldArt.walk_params("hero_x_y", dir, 320)
	_check(int(p["anim"]) == 8 and is_equal_approx(float(p["fps"]), 16.0) and is_equal_approx(float(p["scale"]), 0.25), "sidecar sets 8 frames, 16 fps, scale 0.25")
	_check(int(FieldArt.walk_params("hero_x_y", dir, 322)["anim"]) == 4, "a frame count that does not divide the width falls back to 4")
	var d: Dictionary = FieldArt.walk_params("hero_none", dir, 168)
	_check(int(d["anim"]) == 4 and is_equal_approx(float(d["scale"]), 0.5), "no sidecar: 4 frames at 0.5")
	DirAccess.remove_absolute(dir.path_join("hero_x_y_walk.json"))
	DirAccess.remove_absolute(dir)
	# Two strips of different frame counts share one atlas.
	var img := Image.create(80, 10, false, Image.FORMAT_RGBA8)
	var holder := Node.new()
	var mixed: Array[Dictionary] = [
		{"tex": ImageTexture.create_from_image(img), "anim": 4, "fps": 8.0, "scale": 0.5, "art": "walk"},
		{"tex": ImageTexture.create_from_image(img), "anim": 8, "fps": 16.0, "scale": 0.25, "art": "walk"}]
	var b := RealmBatch.new(holder, mixed, 1)
	var rates: PackedFloat32Array = b.material.get_shader_parameter("rates")
	var anims: PackedFloat32Array = b.material.get_shader_parameter("anims")
	_check(anims[0] == 4.0 and anims[1] == 8.0 and rates[0] == 8.0 and rates[1] == 16.0, "one batch holds strips of 4 and 8 frames with their own fps")
	holder.free()


func _anim() -> void:
	var A := FieldAnim
	_check(A.state_of(true, 0.05, 9.0, true) == A.HIT, "a fresh hit is the hit state")
	_check(A.state_of(true, 9.0, 0.1, true) == A.ATTACK, "a fresh attack is the attack state")
	_check(A.state_of(true, 9.0, 9.0, true) == A.WALK and A.state_of(true, 9.0, 9.0, false) == A.IDLE, "walk or idle")
	_check(A.state_of(false, 0.0, 0.0, true) == A.DIE, "death wins")
	_check(A.tint(A.HIT, false, 0.0, Color.WHITE).r > 1.0, "a hit with no strip flashes white")
	_check(A.tint(A.HIT, true, 0.0, Color.WHITE) == Color.WHITE, "a hit with a strip does not flash")
	_check(A.tint(A.DIE, false, 9.0, Color(0.5, 0.5, 0.5, 0.4)).a < 0.5, "a death fades to the dead colour")
	_check(A.tilt(A.DIE, false, 9.0, false) > 0.5 and A.tilt(A.DIE, false, 9.0, true) < -0.5, "a death tilts, mirrored with the flip")
	_check(A.tilt(A.DIE, true, 9.0, false) == 0.0 and A.tilt(A.WALK, false, 9.0, false) == 0.0, "no tilt with a strip or alive")
	_check(A.frame_at(0.0, 0.3, 3) == 0 and A.frame_at(0.2, 0.3, 3) == 2 and A.frame_at(5.0, 0.3, 3) == 2, "frames run then hold")
	_check(A.strip_for({"atk": null}, A.ATTACK) == null and A.strip_for({}, A.DIE) == null, "a missing strip falls back")
	# The hero layer draws with the fallbacks: a hit hero flashes, a dead one fades and tilts.
	var layer := RealmLayer.new()
	layer.is_ground = false
	layer.hero_entry = FieldArt.hero_entry(1, 1)
	var now: float = Time.get_ticks_msec() / 1000.0
	layer.hit_at = now
	layer._draw_hero()
	_check(layer.last_state == A.HIT and layer.last_tint.r > 1.0, "a hit hero draws with the flash")
	layer.hit_at = -100.0
	layer.hero_alive = false
	layer.died_at = -100.0
	layer._draw_hero()
	_check(layer.last_state == A.DIE and layer.last_tint.a < 0.5, "a dead hero draws faded")
	layer.free()


func _sound() -> void:
	var s := FieldSound.new()
	s.muted = true
	s._ready()
	for _i in 100:
		s.hook("kill")
	_check(int(s.played.get("kill", 0)) == 1, "a hundred kills in one instant make one bleep")
	s.hook("level")
	s.hook("nonsense")
	_check(int(s.played.get("level", 0)) == 1 and not s.played.has("nonsense"), "known hooks play, unknown ones do not")
	var ev := PackedInt32Array([FieldFx.EV_LEVEL, 3, 5, 0, 0, 10, 10, 0, FieldFx.EV_DOWN, 4, 0, 0, 0, 10, 10, 0, FieldFx.EV_BANK, 9, 40, 1, 0, 0, 0, 0])
	s.from_events(ev, 3)
	_check(int(s.played.get("down", 0)) == 1, "an ally's fall makes the down bleep")
	_check(int(s.played.get("level", 0)) == 1, "the level bleep is rate limited")
	_check(not s.played.has("bank"), "another hero's bank is silent")
	s.free()


func _fx() -> void:
	var fx := FieldFx.new()
	fx.my_id = 3
	var rows := PackedFloat32Array([
		FieldFx.FX_SWING, 100, 100, 0.5, 110, 72, 1, 0,
		FieldFx.FX_RING, 100, 100, 96, -1, 4, 0, 0,
		FieldFx.FX_BOLT, 100, 100, 300, 120, 2, 60, 0,
		FieldFx.FX_ZONE, 200, 200, 90, 1, 100, 5, 0,
		FieldFx.FX_STATUS, 100, 100, 3, 0, 0, 0, 1])
	fx.ingest(rows)
	_check(fx._items.size() == 3, "a swing, a ring and a bolt are transient effects, a zone and a status are state: %d" % fx._items.size())
	var ev := PackedInt32Array([
		FieldFx.EV_KILL, -1, 4, 2, 1, 50, 50, 0,
		FieldFx.EV_LEVEL, 3, 7, 0, 0, 60, 60, 0,
		FieldFx.EV_LEVEL, 8, 7, 0, 0, 60, 60, 0,
		FieldFx.EV_DOWN, 8, 0, 0, 0, 70, 70, 0])
	fx.events(ev)
	# A burst, my level (words and a ring), another's level (a ring, no words), another's down (words).
	_check(fx._items.size() == 3 + 1 + 2 + 1 + 1, "events add bursts and words: %d" % fx._items.size())
	for i in 2000:
		fx._add({"k": 20, "x": 0.0, "y": 0.0, "a": 3, "b": 0.0, "c": "ffffff", "t": 0.0, "life": 1.0})
	_check(fx._items.size() <= FieldFx.MAX_ITEMS, "effects are capped at %d" % FieldFx.MAX_ITEMS)
	fx.free()


func _hud() -> void:
	var hud := FieldHud.new()
	hud.card_rects = [Rect2(10, 10, 20, 20), Rect2(40, 10, 20, 20)]
	_check(hud.card_at(Vector2(15, 15)) == 0 and hud.card_at(Vector2(45, 15)) == 1 and hud.card_at(Vector2(5, 5)) == -1, "a click finds its card")
	_check(FieldHud.clock(20 * 125) == "2:05", "the clock reads minutes and seconds")
	_check(FieldHud.TIDE_EVERY_TICKS == 36000 and FieldHud.TIDE_LEN_TICKS == 6000, "a tide every 30 minutes for 5")
	_check(RealmLink.card_name(1) == "STRENGTH" and RealmLink.potion_name(0) == "HEALING DRAUGHT", "names come from the core's tables")
	_check(String(RealmLink.skill_info(1)["name"]) == "PROVOKE" and RealmLink.class_name(5) == "PALADIN", "skill and class names")
	hud.free()


func _input() -> void:
	_check(RealmClient._dir_code(0, 0) == 0 and RealmClient._dir_code(1, 0) == 1 and RealmClient._dir_code(0, 1) == 3, "direction codes")
	_check(RealmClient._dir_code(-1, -1) == 6 and RealmClient._dir_code(1, -1) == 8, "diagonal direction codes")
	# The BLOOD MARK's rite (rules section 14): its key holds interact and the mark, and the module sends the core's
	# IN_INTERACT (0x80) and IN_MARK (0x4000) in the one input word; plain interact sends no mark.
	var rite: int = RealmClient.held_buttons(func(a: String) -> bool: return a == "mark")
	_check(rite == RealmClient.BTN_INTERACT | RealmClient.BTN_MARK, "the rite's key holds interact and the mark: %d" % rite)
	var word: int = RealmLink.input_word(0, rite, 0)
	_check(word & 0x4000 != 0 and word & 0x80 != 0, "the input word carries IN_MARK and interact: %x" % word)
	var bank: int = RealmLink.input_word(0, RealmClient.held_buttons(func(a: String) -> bool: return a == "interact"), 0)
	_check(bank & 0x80 != 0 and bank & 0x4000 == 0, "plain interact sends no mark: %x" % bank)
	_check(ShellSettings.key("mark") == KEY_G and ShellSettings.key("interact") == KEY_F, "the rite has its own rebindable key")
	var sites := PackedFloat32Array([0, 0, 500, 500, 100, 100, 900, 900])
	_check(RealmClient.stone_near(sites, Vector2(130, 120)) == 0 and RealmClient.stone_near(sites, Vector2(300, 300)) == -1, "a waystone is near within 48 px")
	var hud := FieldHud.new()
	hud.hero = {"marked": true}
	_check(hud.marked(), "the HUD reads the mark from the hero view")
	hud.free()
