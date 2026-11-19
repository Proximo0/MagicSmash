extends SceneTree
## Steam achievement icons (64x64, the size Steamworks asks for) drawn from the tarot emblems: a dark card face
## with a gold double frame and the emblem at 3x. Each achievement gets an unlocked icon and a grey locked one.
## Headless: godot --headless --path . -s tools/achievement_icons.gd -- [--out=docs/achievements]

## Achievement API name -> TarotArt emblem key.
const ICONS := {
	"ARCHLICH": "sun", "SOLO_WIN": "wisdom", "PARTY_WIN": "nova", "FLAWLESS": "life", "LICH": "death",
	"TEN_MINUTES": "regen", "BLESSED": "quick", "CURSED": "magnet", "JACKPOT": "power", "ULTRA": "w_star",
	"EVOLVE": "w_arcane", "COMBO_200": "w_storm", "SEAL": "w_rune", "OMENS": "w_fire",
}
const SIZE := 64
const SCALE := 3
const FACE_TOP := Color("2a1650")
const FACE_BOTTOM := Color("5a2660")
const GOLD := Color("ffd23d")
const GOLD_DARK := Color("8a6a1a")
const INK := Color("0b0716")


func _init() -> void:
	var out := "docs/achievements"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out)
	var made := 0
	for row: Array in Achievements.LIST:
		var api: String = row[0]
		if not ICONS.has(api):
			push_error("no icon for achievement " + api)
			continue
		var img := _icon(ICONS[api])
		img.save_png("%s/%s.png" % [out, api.to_lower()])
		_lock(img).save_png("%s/%s_locked.png" % [out, api.to_lower()])
		made += 1
	print("ACHIEVEMENT_ICONS %d written to %s" % [made, out])
	quit(0 if made == Achievements.LIST.size() else 1)


func _icon(key: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var c := FACE_TOP.lerp(FACE_BOTTOM, float(y) / SIZE)
		for x in SIZE:
			img.set_pixel(x, y, c)
	_frame(img, 0, INK)
	_frame(img, 1, GOLD)
	_frame(img, 2, INK)
	_frame(img, 4, GOLD_DARK)
	for s in 9:
		img.set_pixel(8 + (s * 23) % 48, 7 + (s * 13) % 20, Color(1, 1, 1, 0.7))
	var em := TarotArt.emblem(key).get_image()
	var off := (SIZE - 16 * SCALE) / 2
	for y in 16:
		for x in 16:
			var p := em.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			for dy in SCALE:
				for dx in SCALE:
					img.set_pixel(off + x * SCALE + dx, off + y * SCALE + dy, p)
	return img


func _frame(img: Image, inset: int, c: Color) -> void:
	for i in range(inset, SIZE - inset):
		img.set_pixel(i, inset, c)
		img.set_pixel(i, SIZE - 1 - inset, c)
		img.set_pixel(inset, i, c)
		img.set_pixel(SIZE - 1 - inset, i, c)


func _lock(src: Image) -> Image:
	var img := src.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			var p := img.get_pixel(x, y)
			var g := (p.r * 0.3 + p.g * 0.59 + p.b * 0.11) * 0.55
			img.set_pixel(x, y, Color(g, g, g * 1.15, p.a))
	return img
