class_name SpritesWizards
## The four wizards: ASCII maps for their parts, their palettes, and the code that puts frames together.
## `Sprites.build_all` calls `add_all` once, before it packs the atlas.
##
## A frame is a skirt (hem and feet), a torso (arms), a head and a hat laid over each other in a 14 x 20 box,
## then given its 1 px outline, which makes the sprite 16 x 22. Torso, head and hat move down a pixel together on
## the low frames of a cycle (the bob). The four wizards share skirts and torsos and differ in head, hat and
## palette. Keys: wiz<n>_<down|up|side>_<frame>[c], where frame is i0 i1 (idle) or w0 w1 w2 w3 (walk) and a
## trailing c is the same frame with the arms in the casting pose. Older code's wiz<n>_<dir>_a and _b still work.

## The canvas of every frame, and where the 14 x 20 box of the parts sits in it.
const CW := 18
const CH := 24
const OX := 2
const OY := 3
const BOX_W := 14

const DIRS := ["down", "up", "side"]
## [frame, skirt, bob, hat variant]
const FRAMES := [["i0", "stand", 0, 0], ["i1", "stand", 1, 1], ["w0", "stepa", 1, 0], ["w1", "pass", 0, 1],
	["w2", "stepb", 1, 0], ["w3", "pass", 0, 1]]

# --- Skirts: rows 15 to 19 of the box ---------------------------------------
const SKIRT := {
	"down": {
		"stand": [
			"...lPPPPPPPp..",
			"..lPPPpPPPpp..",
			"..lPPPpPPPppq.",
			".lTTTTTTTTTTt.",
			"...BB....Bb...",
		],
		"pass": [
			"...lPPPPPPPp..",
			"..lPPPpPPPpp..",
			"..lPPPpPPPpp..",
			"..lTTTTTTTTt..",
			"....BB..Bb....",
		],
		"stepa": [
			"...lPPPPPPPp..",
			"..lPPPpPPPpp..",
			".lPPPPpPPPpp..",
			".lTTTTTTTTTt..",
			"..BBB.........",
		],
		"stepb": [
			"...lPPPPPPPp..",
			"..lPPPpPPPpp..",
			"..lPPPpPPPPpq.",
			"..lTTTTTTTTTt.",
			".........BBb..",
		],
	},
	"up": {
		"stand": [
			"...lPPPPPPPp..",
			"..lPPPPPpPpp..",
			"..lPPPPPpPppq.",
			".lTTTTTTTTTTt.",
			"...BB....Bb...",
		],
		"pass": [
			"...lPPPPPPPp..",
			"..lPPPPPpPpp..",
			"..lPPPPPpPpp..",
			"..lTTTTTTTTt..",
			"....BB..Bb....",
		],
		"stepa": [
			"...lPPPPPPPp..",
			"..lPPPPPpPpp..",
			".lPPPPPPpPpp..",
			".lTTTTTTTTTt..",
			".........Bb...",
		],
		"stepb": [
			"...lPPPPPPPp..",
			"..lPPPPPpPpp..",
			"..lPPPPPpPPpq.",
			"..lTTTTTTTTTt.",
			"...BB.........",
		],
	},
	"side": {
		"stand": [
			"...lPPPPPPp...",
			"...lPPPPPPp...",
			"..lPPPpPPPpp..",
			"..lTTTTTTTTt..",
			"....BB..BBb...",
		],
		"pass": [
			"...lPPPPPPp...",
			"...lPPPPPPp...",
			"...lPPpPPPp...",
			"...lTTTTTTt...",
			".....BBBb.....",
		],
		"stepa": [
			"...lPPPPPPp...",
			"..lPPPPPPPpp..",
			".lPPPPpPPPPpp.",
			".lTTTTTTTTTTt.",
			"..BB......BBb.",
		],
		"stepb": [
			"...lPPPPPPp...",
			"..lPPPPPPPpp..",
			".lPPPPpPPPPpp.",
			".lTTTTTTTTTTt.",
			"..Bb......bbb.",
		],
	},
}

# --- Torsos: [relaxed, casting with the staff in the right hand, the same in the left], each [first row in the
# box, rows]. The staff hand stays where it is (the arena draws the staff) and the free hand goes up; from the
# side the arm reaches forward along the staff, so there is one casting pose. Right is the picture's right.
const TORSO := {
	"down": [
		[11, [
			"...LRRRRRRr...",
			".LLRRRRRRRRrr.",
			".TTdRRRRRRdTt.",
			".SSdRRRRRRdSs.",
			"...UUUUUUUUu..",
		]],
		[10, [
			"SS............",
			"TT.LRRRRRRr...",
			".LLRRRRRRRRrr.",
			"..dLRRRRRRdTt.",
			"...LRRRRRRdSs.",
			"...UUUUUUUUu..",
		]],
		[10, [
			"............Ss",
			"...LRRRRRRr.Tt",
			".LLRRRRRRRRrr.",
			".TTdRRRRRRrd..",
			".SSdRRRRRRRr..",
			"...UUUUUUUUu..",
		]],
	],
	"up": [
		[11, [
			"...LRRRRRRr...",
			".LLRRRRRRRRrr.",
			".TTdRRRRRRdTt.",
			".SSdRRRRRRdSs.",
			"...UUUUUUUUu..",
		]],
		[10, [
			"SS............",
			"TT.LRRRRRRr...",
			".LLRRRRRRRRrr.",
			"..dLRRRRRRdTt.",
			"...LRRRRRRdSs.",
			"...UUUUUUUUu..",
		]],
		[10, [
			"............Ss",
			"...LRRRRRRr.Tt",
			".LLRRRRRRRRrr.",
			".TTdRRRRRRrd..",
			".SSdRRRRRRRr..",
			"...UUUUUUUUu..",
		]],
	],
	"side": [
		[11, [
			"....LRRRRr....",
			"...LRdLRRr....",
			"...LRdTTRr....",
			"...LRdSSRr....",
			"...UUUUUUu....",
		]],
		[11, [
			"....LRRRRr....",
			"...LRRLLRr....",
			"...LRdLLLLTSS.",
			"...LRRddddr...",
			"...UUUUUUu....",
		]],
	],
}
## The letter a casting frame's key ends with, per torso pose.
const POSES := ["", "c", "d"]

# --- Heads and hats, per wizard: [first row in the box, rows, second variant of the rows] -------
const HEAD := [
	{ # VIOLET: a long white beard
		"down": [9, [
			"...sSESSESs...",
			"...WWSssSWW...",
			"..WWWWvvWWWw..",
			"...WWWWWWww...",
			"....WWWWww....",
			".....WWww.....",
			"......Wv......",
		]],
		"up": [9, [
			"...WWWWWWww...",
			"...WWWWWWww...",
			"....WWWwwv....",
		]],
		"side": [9, [
			"....WWSSESs...",
			"....WWWSSSSS..",
			"....WWWWWWWw..",
			".....WWWWWww..",
			"......WWWww...",
			".......Wwv....",
		]],
	},
	{ # CRIMSON: a dark face with burning eyes inside the hood
		"down": [9, [
			".GHVVeVVeVVhh.",
			"..HhVVVVVVhh..",
			"...hhVVVVhh...",
		]],
		"up": [9, [
			".GHHHHHHHhhhh.",
			"..GHHHHHHhhh..",
			"...hhhhhhhh...",
		]],
		"side": [9, [
			".GHHHHHVVVeVh.",
			"..GHHHHhVVVh..",
			"...hhhhhhhh...",
		]],
	},
	{ # EMERALD: frost-blue hair and a fur mantle
		"down": [9, [
			"..hIISSSSIIh..",
			"..FIFFFFFFIFf.",
			"..fIfFfFfFIff.",
			"...I......I...",
		]],
		"up": [9, [
			"..GHHHHHHhhh..",
			"..FFFFFFFFFFf.",
			"..fFfFfFfFfff.",
		]],
		"side": [9, [
			"...hHHIISSs...",
			"..FFFFIFFFFf..",
			"..fFfFIfFfFf..",
			"......I.......",
		]],
	},
	{ # AMBER: a long moustache under the hat's shadow
		"down": [9, [
			"....sESSEs....",
			"....MMSSMM....",
			"....M.ss.M....",
			"....M....M....",
		]],
		"up": [9, [
			"....mMMMMM....",
			"....mMMMMM....",
			".....mMMM.....",
			"......mM......",
			"......Mm......",
			"......mM......",
		]],
		"side": [9, [
			".....MSSEs....",
			".....MSSSMM...",
			"......SsS.M...",
			"..........M...",
		]],
	},
]

const HAT := [
	{ # VIOLET: a tall crooked cone with a wide brim and a gold band
		"down": [0, [
			"..........Hh..",
			"........GHHh..",
			".......GHHhh..",
			"......GGHHh...",
			".....GGHHHhh..",
			".....GHHHHhh..",
			"....yYYYCYYy..",
			".GGGHHHHHHhhh.",
			"GGHHHHhhhhhhgg",
		]],
		"up": [0, [
			"..GH..........",
			"..GHHh........",
			"..GGHHh.......",
			"...GHHHh......",
			"..GGHHHHh.....",
			"..GHHHHHhh....",
			"..YYYYYYYy....",
			".GGGHHHHHHhhh.",
			"GGHHHHHHHHhhgg",
		]],
		"side": [0, [
			"...hH.........",
			"...GHHh.......",
			"....GHHh......",
			"....GGHHh.....",
			"....GGHHHh....",
			"....GHHHHhh...",
			"....YYYYYYy...",
			".GGHHHHHHHHHhh",
			"..gghhhhhhhhg.",
		]],
	},
	{ # CRIMSON: a hood crowned with tongues of flame that flicker
		"down": [0, [
			"......F.......",
			".....Ff...F...",
			"..F..fHf.Ff...",
			"..fF.GHHffHh..",
			"..GHfGHHHHHh..",
			".GGHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHVVVVVVHhh.",
			".GHVVVVVVVVhh.",
		], [
			".......F......",
			"..F...fF...F..",
			"..fF..Hf..Ff..",
			"..GH.GHHf.Hh..",
			"..GHHGHHHfHh..",
			".GGHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHVVVVVVHhh.",
			".GHVVVVVVVVhh.",
		]],
		"up": [0, [
			"......F.......",
			".....Ff...F...",
			"..F..fHf.Ff...",
			"..fF.GHHffHh..",
			"..GHfGHHHHHh..",
			".GGHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHhhh.",
		], [
			".......F......",
			"..F...fF...F..",
			"..fF..Hf..Ff..",
			"..GH.GHHf.Hh..",
			"..GHHGHHHfHh..",
			".GGHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHhhh.",
		]],
		"side": [0, [
			"....F.........",
			"...Ff...F.....",
			".F.fHf.Ff.....",
			".fFGHHffHh....",
			"..GHHHHHHHh...",
			".GGHHHHHHHHh..",
			".GHHHHHHHHHh..",
			".GHHHHHHVVVh..",
			".GHHHHHVVVVVh.",
		], [
			".....F........",
			".F..fF..F.....",
			".fF.Hf..Ff....",
			"..GHGHHf.Hh...",
			"..GHHHHHfHh...",
			".GGHHHHHHHHh..",
			".GHHHHHHHHHh..",
			".GHHHHHHVVVh..",
			".GHHHHHVVVVVh.",
		]],
	},
	{ # EMERALD: a pointed hood whose tip leans over
		"down": [0, [
			".........Hh...",
			".......GHHh...",
			".....GGHHHh...",
			"...GGHHHHHHh..",
			"..GHHHHHHHHHh.",
			".GHHIIIIIIHHh.",
			".GHISSSSSSIHh.",
			".GHISESSESIHh.",
			".GHISSssSSIhh.",
		]],
		"up": [0, [
			"...GH.........",
			"...GHHh.......",
			"...GHHHHh.....",
			"..GGHHHHHHh...",
			".GGHHHHHHHHh..",
			".GHHHHHHHHHHh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHHhh.",
			".GHHHHHHHHhhh.",
		]],
		"side": [0, [
			"...hH.........",
			"...GHHh.......",
			"....GHHHh.....",
			"...GGHHHHHh...",
			"..GHHHHHHHHh..",
			"..GHHHHIIIIh..",
			"..GHHHISSSSs..",
			"..GHHHISSESs..",
			"..GHHHISSSSS..",
		]],
	},
	{ # AMBER: a wide straw cone with a cyan band
		"down": [1, [
			"......gg......",
			".....GHHh.....",
			"....CCCCcc....",
			"...GGGHHhhh...",
			"..GGHGHHhHhh..",
			".GGGHGHHhHhhh.",
			"GGGHHGHHHhHhhg",
			".gggggggggggg.",
		]],
		"up": [1, [
			"......gg......",
			".....GHHh.....",
			"....CCCCcc....",
			"...GGGHHhhh...",
			"..GGHGHHhHhh..",
			".GGGHGHHhHhhh.",
			"GGGHHGHHHhHhhg",
			".gggggggggggg.",
		]],
		"side": [1, [
			"......gg......",
			".....GHHh.....",
			"....CCCCcc....",
			"...GGGHHhhh...",
			"..GGHGHHhHhh..",
			".GGGHGHHhHhhh.",
			"GGGHHGHHHhHhhg",
			".gggggggggggg.",
		]],
	},
]

const SKIN := Color("ffd2a6")
const SKIN_DARK := Color("c98a6b")
const BONE := [Color("e8dcc0"), Color("b7a98e"), Color("7d705c")]
const GOLD := [Color("ffd94d"), Color("c48a10")]
const LEATHER := [Color("7a2f14"), Color("4a1a0c")]


static func add_all() -> void:
	_wz_check()
	for w in 4:
		var pal := palette(w)
		for dir: String in DIRS:
			for f: Array in FRAMES:
				for pose in (TORSO[dir] as Array).size():
					var key := "wiz%d_%s_%s%s" % [w, dir, f[0], POSES[pose]]
					Sprites._add(key, frame_rows(w, dir, f[1], f[2], pose, f[3]), pal)
			Sprites.alias("wiz%d_%s_a" % [w, dir], "wiz%d_%s_i0" % [w, dir])
			Sprites.alias("wiz%d_%s_b" % [w, dir], "wiz%d_%s_w0" % [w, dir])
			Sprites.alias("wiz%d_%s_cast" % [w, dir], "wiz%d_%s_i0c" % [w, dir])


## The key of a wizard's frame. `step` counts walk frames and `beat` idle ones (any whole numbers). `casting` picks
## the pose with the free hand raised: the hand away from the staff, which is on the picture's right when
## `staff_right` (from the side there is one casting pose).
static func frame_key(w: int, dir: String, moving: bool, step: int, beat: int, casting: bool, staff_right: bool) -> String:
	var key := "wiz%d_%s_%s%d" % [w, dir, "w" if moving else "i", posmod(step, 4) if moving else posmod(beat, 2)]
	if casting:
		key += "c" if dir == "side" or staff_right else "d"
	return key


## Where the staff is gripped, from the wizard's feet point: at the hand hanging by the side in the front and back
## views (it changes hands as the aim crosses the middle, and never lies over the face), in front of the belt
## from the side.
static func grip(dir: String, aim: Vector2) -> Vector2:
	if dir == "side":
		return Vector2(1.0 if aim.x >= 0.0 else -1.0, -6.0)
	return Vector2(5.0 if aim.x >= 0.0 else -5.0, -6.0)


## The colours behind a wizard's map letters.
static func palette(w: int) -> Dictionary:
	var c: Dictionary = Sprites.PLAYER_COLORS[w]
	var pal := {
		"K": Sprites.OUTLINE, "E": Sprites.INK, "V": Sprites.INK,
		"L": c.fx, "R": c.robe, "r": c.shade, "d": c.deep,
		"l": c.fx, "P": c.robe, "p": c.shade, "q": c.deep,
		"G": c.fx, "H": c.robe, "h": c.shade, "g": c.deep,
		"S": SKIN, "s": SKIN_DARK,
		"W": BONE[0], "w": BONE[1], "v": BONE[2],
		"Y": GOLD[0], "y": GOLD[1], "C": Color("fff6c0"),
		"T": GOLD[0], "t": GOLD[1], "U": c.shade, "u": c.deep,
		"B": LEATHER[0], "b": LEATHER[1],
	}
	match w:
		1:
			pal["e"] = Color("ffcf5a")
			pal["F"] = Color("ffcf5a")
			pal["f"] = Color("ff9a3c")
			pal["T"] = Color("ff9a3c")
			pal["t"] = Color("c85a1e")
		2:
			pal["F"] = BONE[0]
			pal["f"] = BONE[1]
			pal["I"] = Color("8fe3ff")
			pal["i"] = Color("4fa3d8")
			pal["T"] = BONE[0]
			pal["t"] = BONE[1]
		3:
			pal["M"] = LEATHER[1]
			pal["m"] = LEATHER[0]
			pal["G"] = Color("fff6c0")
			pal["H"] = Color("ffe58a")
			pal["h"] = Color("c48a10")
			pal["g"] = Color("7a3d0a")
			pal["C"] = Color("4dfff0")
			pal["c"] = Color("158f86")
			pal["T"] = Color("4dfff0")
			pal["t"] = Color("158f86")
			pal["U"] = Color("4dfff0")
			pal["u"] = Color("158f86")
			pal["l"] = c.robe
			pal["P"] = c.shade
			pal["p"] = c.deep
			pal["q"] = Color("4f2606")
	return pal


## One frame as map rows, outline included. `pose` is the torso (0 relaxed, 1 and 2 casting); `variant` picks a
## hat's second drawing when it has one.
static func frame_rows(w: int, dir: String, skirt: String, bob: int, pose: int, variant: int = 0) -> Array:
	var grid := PackedByteArray()
	grid.resize(CW * CH)
	grid.fill(46) # "."
	_wz_blit(grid, SKIRT[dir][skirt], 15, 0)
	var torso: Array = TORSO[dir][pose]
	_wz_blit(grid, torso[1], torso[0], bob)
	var head: Array = HEAD[w][dir]
	_wz_blit(grid, head[1], head[0], bob)
	var hat: Array = HAT[w][dir]
	_wz_blit(grid, hat[2] if variant == 1 and hat.size() > 2 else hat[1], hat[0], bob)
	_wz_outline(grid)
	var rows: Array = []
	for y in CH:
		rows.append(grid.slice(y * CW, (y + 1) * CW).get_string_from_ascii())
	return rows


## Reports a part whose rows are not all BOX_W wide (it would be laid in off centre) to Sprites.problems.
static func _wz_check() -> void:
	var parts := {}
	for dir: String in DIRS:
		for k: String in SKIRT[dir]:
			parts["skirt %s %s" % [dir, k]] = SKIRT[dir][k]
		for i in (TORSO[dir] as Array).size():
			parts["torso %s %d" % [dir, i]] = TORSO[dir][i][1]
		for w in 4:
			parts["head %d %s" % [w, dir]] = HEAD[w][dir][1]
			for v in range(1, (HAT[w][dir] as Array).size()):
				parts["hat %d %s %d" % [w, dir, v]] = HAT[w][dir][v]
	for name: String in parts:
		var rows: Array = parts[name]
		for j in rows.size():
			if (rows[j] as String).length() != BOX_W:
				Sprites.problems.append("wizard %s: row %d is %d wide, not %d" % [name, j, (rows[j] as String).length(), BOX_W])


## Lays a part's rows into the canvas; `row` is its first row in the box. Clear cells leave what is there.
static func _wz_blit(grid: PackedByteArray, rows: Array, row: int, dy: int) -> void:
	for j in rows.size():
		var line: String = rows[j]
		var y := OY + row + j + dy
		for i in line.length():
			var ch := line.unicode_at(i)
			if ch != 46 and y >= 0 and y < CH and OX + i < CW:
				grid[y * CW + OX + i] = ch


## Gives every clear cell that touches a drawn one (up, down, left or right) the outline.
static func _wz_outline(grid: PackedByteArray) -> void:
	var src := grid.duplicate()
	for y in CH:
		for x in CW:
			if src[y * CW + x] != 46:
				continue
			if (x > 0 and src[y * CW + x - 1] != 46) or (x < CW - 1 and src[y * CW + x + 1] != 46) \
					or (y > 0 and src[(y - 1) * CW + x] != 46) or (y < CH - 1 and src[(y + 1) * CW + x] != 46):
				grid[y * CW + x] = 75 # "K"
