extends SceneTree
## The field client's pieces with no server: the art by file name with stand-ins, the sound hooks, the effect
## rows and events, the HUD's reads, the input mapping. Prints one line, FIELD_TEST ok|FAILED ..., and exits 1
## on failure.
## godot --headless --path realm/client -s res://tests/field_test.gd

var _problems: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_art()
	_props()
	_anim()
	_sound()
	_sfx()
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


func _props() -> void:
	var sites := PackedFloat32Array()
	for i in 15:
		sites.append(1000.0 + 300.0 * i)
		sites.append(2000.0 + 50.0 * i)
	var seen: int = 0
	for cy in 40:
		for cx in 40:
			var a: Array = FieldProps.prop_in_cell(3, cx, cy, 6400.0, sites)
			_check(a == FieldProps.prop_in_cell(3, cx, cy, 6400.0, sites), "prop scatter is deterministic")
			if not a.is_empty():
				seen += 1
				_check(FieldProps.is_clear(a[1], sites), "a prop stands clear of the sites")
	_check(seen > 20 and seen < 400, "props are sparse (%d)" % seen)
	_check(FieldProps.hash3(1, 2, 3, 4) == FieldProps.hash3(1, 2, 3, 4) and FieldProps.hash3(1, 2, 3, 4) != FieldProps.hash3(2, 2, 3, 4), "prop hash depends on the field")
	_check(not FieldProps.is_clear(Vector2(1000, 2000), sites), "no prop on the gate")


func _art() -> void:
	_check(RealmLink.kind_count() == 42, "the core has 42 kinds, got %d" % RealmLink.kind_count())
	_check(FieldArt.kind_key("plague rat") == "enemy_plague_rat", "kind key of a two-word name")
	_check(FieldArt.boss_key("THE GOAT PROPHET") == "boss_goat_prophet" and FieldArt.boss_key("MOTHER OF LEECHES") == "boss_mother_of_leeches", "a boss's art key is its slug")
	var kinds: Array[Dictionary] = FieldArt.monster_entries()
	var bosses: Array[Dictionary] = FieldArt.boss_entries(kinds)
	_check(bosses.size() == FieldArt.BOSS_ART and int(bosses[0]["anim"]) == 8 and bosses[0]["art"] == "walk", "each of the first bosses has art: its own or its carrier's")
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
	var old_style: Dictionary = FieldArt.entry_for("ground_0a", "res://ground")
	_check(not old_style.has("atk_n") and old_style["art"] == "still", "art without strips keeps the old defaults")
	var scare: Dictionary = FieldArt.entry_for(FieldArt.kind_key("scarecrow"))
	_check(scare["art"] == "walk" and int(scare["anim"]) == 8 and is_equal_approx(float(scare["fps"]), 12.0), "the scarecrow is an 8-frame walk strip at 12 fps")
	_check(is_equal_approx(float(scare["scale"]), 0.4667), "monsters are drawn at the heroes' scale")
	_check(int(scare["atk_n"]) == 8 and int(scare["hit_n"]) == 4 and int(scare["die_n"]) == 8, "a monster's atk, hit and die counts come from its sidecar")
	var scare_tex: Texture2D = scare["tex"]
	_check(scare_tex.get_width() % 8 == 0 and scare_tex.get_width() / 8 > 100, "monster frames are wider than the old stills")
	for m in ["bloated pilgrim", "penitent", "gravedigger", "hanged man", "wood witch", "bark wight", "lumberer", "drowned", "goat cultist"]:
		var me: Dictionary = FieldArt.entry_for(FieldArt.kind_key(m))
		_check(me.get("art", "") == "walk" and int(me.get("anim", 0)) == 8, "%s is an 8-frame walk strip" % m)
	# The batch builds an atlas from these.
	var holder := Node.new()
	var batch := RealmBatch.new(holder, kinds, 1)
	_check(batch.count == 0, "a batch starts empty")
	holder.free()
	# The ground: a tile for each of the six fields, shown by FieldGround.
	var soil := FieldGround.new()
	_check(soil.field == -1 and soil.material == null, "no ground before a field is known")
	for f in 6:
		soil.set_field(f, 1000.0)
		_check(soil.field == f and soil.material != null and soil.size == Vector2(1000, 1000), "field %d has its ground tile" % f)
	soil.set_field(77, 1000.0)
	_check(soil.field == 5, "a field with no tile keeps the ground that was shown")
	soil.set_scale_px(0.1)
	_check(is_equal_approx(float((soil.material as ShaderMaterial).get_shader_parameter("detail")), FieldGround.MIN_DETAIL), "far out the ground fades toward its mean colour")
	soil.free()


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
		{"tex": ImageTexture.create_from_image(img), "anim": 8, "fps": 16.0, "scale": 0.25, "art": "walk", "hover": 10.0}]
	var b := RealmBatch.new(holder, mixed, 1)
	var info: PackedVector4Array = b.material.get_shader_parameter("info")
	_check(info[0].x == 4.0 and info[1].x == 8.0 and info[0].z == 8.0 and info[1].z == 16.0, "one batch holds strips of 4 and 8 frames with their own fps")
	_check(info[0].w == 0.0 and info[1].w == 10.0, "a floating kind's hover reaches the shader")
	_check(float(FieldArt.entry_for("enemy_carrion_crow").get("hover", 0.0)) > 0.0 and float(FieldArt.entry_for("enemy_plague_rat").get("hover", 1.0)) == 0.0, "the crow's sidecar says it floats, the rat's does not")
	var shadow_info: PackedVector4Array = b.shadow_material.get_shader_parameter("info") if b.shadow_material != null else PackedVector4Array()
	_check(b.shadow_material != null and b._shadows.size() == 2 and shadow_info.size() > 1 and shadow_info[1].w == 10.0 and holder.get_child_count() == 4, "a batch with a floating kind sets up its blob shadow")
	holder.free()
	var flat: Array[Dictionary] = [{"tex": ImageTexture.create_from_image(img), "anim": 4, "fps": 8.0, "scale": 0.5, "art": "walk"}]
	var holder_flat := Node.new()
	var bf := RealmBatch.new(holder_flat, flat, 1)
	_check(bf.shadow_material == null and bf._shadows.is_empty() and holder_flat.get_child_count() == 2, "a batch with no floating kind has no shadow")
	holder_flat.free()
	# With strips: entry 0 has a die strip of 2 frames, entry 1 none; they sit after the main entries (2 + 3 * kind + 2 for die).
	var with_die: Array[Dictionary] = [
		{"tex": ImageTexture.create_from_image(img), "anim": 4, "fps": 8.0, "scale": 0.5, "art": "walk", "die": ImageTexture.create_from_image(img), "die_n": 2},
		{"tex": ImageTexture.create_from_image(img), "anim": 8, "fps": 16.0, "scale": 0.25, "art": "walk"}]
	var holder2 := Node.new()
	var bs := RealmBatch.new(holder2, with_die, 1, false, true)
	var sr: PackedVector4Array = bs.material.get_shader_parameter("rects")
	var sa: PackedVector4Array = bs.material.get_shader_parameter("info")
	_check(int(bs.material.get_shader_parameter("extra_base")) == 2, "extra strips start after the main entries")
	_check(sa[2 + 2].x == 2.0 and sr[2 + 2].z == 40.0 and sr[2 + 0].z == 0.0 and sr[2 + 3 + 2].z == 0.0, "a die strip is packed for the kind that has one, none for the rest")
	holder2.free()
	_atlas()


## The atlas is shelves: 42 strips of 8 frames of 150 x 93 fit in one texture, every rect inside it, none overlapping.
func _atlas() -> void:
	var sizes: Array[Vector2i] = []
	for i in 42:
		sizes.append(Vector2i(8 * 150, 93))
	var lay: Dictionary = RealmBatch.layout(sizes)
	var size: Vector2i = lay["size"]
	var at: Array[Vector2i] = []
	at.assign(lay["at"])
	_check(at.size() == 42, "a place for every strip")
	_check(size.x <= 16384 and size.y <= 16384, "42 strips of 8 x 150 x 93 fit the texture limit: %s" % size)
	var bounds := Rect2i(Vector2i.ZERO, size)
	var ok_inside: bool = true
	var overlaps: int = 0
	for i in at.size():
		var r := Rect2i(at[i], sizes[i])
		if not bounds.encloses(r):
			ok_inside = false
		for j in range(i + 1, at.size()):
			if r.intersects(Rect2i(at[j], sizes[j])):
				overlaps += 1
	_check(ok_inside, "every strip lies inside the atlas")
	_check(overlaps == 0, "no two strips overlap, got %d" % overlaps)
	# A strip wider than a shelf gets a shelf of its own; stills pack side by side as before.
	var odd_sizes: Array[Vector2i] = [Vector2i(30, 20), Vector2i(5000, 10), Vector2i(30, 20)]
	var odd: Dictionary = RealmBatch.layout(odd_sizes, 4096)
	var odd_at: Array[Vector2i] = []
	odd_at.assign(odd["at"])
	_check(odd_at[1].y > odd_at[0].y and odd_at[2].y > odd_at[1].y, "a wide strip stands on its own shelf")
	var still_sizes: Array[Vector2i] = [Vector2i(20, 24), Vector2i(26, 28)]
	var stills: Dictionary = RealmBatch.layout(still_sizes)
	var still_size: Vector2i = stills["size"]
	_check(still_size == Vector2i(20 + 26 + 4, 30), "stills sit in one shelf, 1 px apart: %s" % still_size)
	# A batch of all 42 builds with the monsters' settings and keeps each strip's frame count.
	var img := Image.create(8 * 150, 93, false, Image.FORMAT_RGBA8)
	var entries: Array[Dictionary] = []
	for i in 42:
		entries.append({"tex": ImageTexture.create_from_image(img), "anim": 8, "fps": 12.0, "scale": 0.4667, "art": "walk"})
	var holder := Node.new()
	var b := RealmBatch.new(holder, entries, 1, false)
	var anims: PackedVector4Array = b.material.get_shader_parameter("info")
	var rects: PackedVector4Array = b.material.get_shader_parameter("rects")
	# Two vec4 arrays of MAX_FRAMES and a few scalars: a uniform block is promised only 16 KB.
	_check(RealmBatch.MAX_FRAMES * 16 * 2 + 256 <= 16384, "the figures' uniforms fit a 16 KB block")
	_check(anims[41].x == 8.0 and rects[41].z == 150.0 and rects[41].w == 93.0, "the last of 42 strips keeps 8 frames of 150 x 93")
	_check(float(b.material.get_shader_parameter("bob_stills")) == 0.0, "the monsters' batch does not bob stills")
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
	var with_strips: Dictionary = FieldArt.hero_entry(1, 1)
	var now: float = Time.get_ticks_msec() / 1000.0
	layer.hero_entry = with_strips
	layer.hit_at = now
	layer._draw_hero()
	_check(layer.last_state == A.HIT and layer.last_tint == Color.WHITE, "a hit hero with a hit strip draws it, no flash")
	var bare: Dictionary = with_strips.duplicate()
	for k in ["atk", "hit", "die", "atk_n", "hit_n", "die_n"]:
		bare.erase(k)
	layer.hero_entry = bare
	layer.hit_at = now
	layer._draw_hero()
	_check(layer.last_state == A.HIT and layer.last_tint.r > 1.0, "a hit hero with no strip draws with the flash")
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
	var ev := PackedInt32Array([FieldFx.EV_GRANT, 3, 5, 0, 0, 10, 10, 0, FieldFx.EV_DOWN, 4, 0, 0, 0, 10, 10, 0, FieldFx.EV_BANK, 9, 40, 1, 0, 0, 0, 0])
	s.from_events(ev, 3)
	_check(int(s.played.get("down", 0)) == 1, "an ally's fall makes the down bleep")
	_check(int(s.played.get("level", 0)) == 1, "the level bleep is rate limited")
	_check(not s.played.has("bank"), "another hero's bank is silent")
	s.free()


func _sfx() -> void:
	var x := Sfx.new()
	x._ready()
	var missing: PackedStringArray = []
	for f in Sfx.files():
		if x._streams.get(f) == null:
			missing.append(f)
	_check(missing.is_empty(), "every listed sound loads, missing: %s" % ", ".join(missing))
	_check(Sfx.files().size() >= 27, "the sound list has the whole pass")
	var ok: int = 0
	for i in 1000:
		var group: String = Sfx.GROUPS.keys()[i % Sfx.GROUPS.size()]
		if x.request(group, 0.0, 1000.0):
			ok += 1
	_check(x.busy() <= Sfx.VOICES, "no more voices than the cap, got %d" % x.busy())
	_check(ok <= Sfx.GROUPS.size() + Sfx.VOICES and ok < 1000, "1000 requests in one frame start few, got %d" % ok)
	var kills: int = 0
	for i in 500:
		if x.request("mon_small", 0.0, 1000.0):
			kills += 1
	_check(kills == 0, "a flood of one sound inside its window starts none more")
	_check(not x.request("no_such_sound"), "an unknown sound is refused")
	for p in x._voices:
		p.stop()
	x.free()


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
		FieldFx.EV_GRANT, 3, 7, 0, 0, 60, 60, 0,
		FieldFx.EV_GRANT, 8, 7, 0, 0, 60, 60, 0,
		FieldFx.EV_DOWN, 8, 0, 0, 0, 70, 70, 0])
	fx.events(ev)
	# A burst, my draw granted (words and a ring), another's (a ring, no words), another's down (words).
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
