class_name ArenaArtFloor
extends RefCounted
## Paving for the arena backdrops: packs an area with uneven rectangular slabs (flagstones, planks, marble) and
## paints them on an ArenaArtCanvas. Slabs differ from their neighbours by a shade at most, their joints are a
## darker shade of the same stone, and the texture inside a slab comes from large soft patches, so the floor
## stays the quietest thing on screen.

## A slab in the packed list: [x, y, w, h, flags]; the rectangle includes its joint (last column and last row).
const STRIDE := 5
## Slab flags.
const WORN := 1 # polished by feet: the lightest stone, no dark patches, faint joints
const DAMP := 2 # by a wall: the darkest stone, deeper joints
const FLAT := 8 # no patches at all (a dressed slab that will be engraved)
const DARKER := 16 # of the darker stone, whatever the dice say (the dark squares of a chequered floor)


## Soft patches for slab texture: a low-frequency noise field over the whole picture, one byte per pixel. It is
## made at a quarter of the size and scaled up, so patches have smooth outlines. `stretch` widens them; with
## `rows` 1 the field keeps every row, for the long thin streaks of wood grain.
static func patches(w: int, h: int, noise_seed: int, frequency: float, stretch: float = 1.6, rows: int = 4) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 2
	var sw := maxi(8, int(w / (4.0 * stretch)))
	var sh := maxi(8, h / rows)
	var img := n.get_image(sw, sh, false, false, true)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return img.get_data()


## Packs `area` with slabs on a lattice of roughly `cell`-sized cells whose lines are nudged a little, so the
## joints line up the way cut stone does without forming a grid. `sizes` rows are [cells wide, cells high,
## weight]. Returns [x, y, w, h, 0] per slab.
static func pack(area: Rect2i, cell: Vector2i, rng: RandomNumberGenerator, sizes: Array, nudge: float = 0.16) -> PackedInt32Array:
	var ncx := maxi(1, roundi(float(area.size.x) / cell.x))
	var ncy := maxi(1, roundi(float(area.size.y) / cell.y))
	var xs := _lattice(area.position.x, area.size.x, ncx, rng, nudge)
	var ys := _lattice(area.position.y, area.size.y, ncy, rng, nudge)
	var used := PackedByteArray()
	used.resize(ncx * ncy)
	var total := 0.0
	for s: Array in sizes:
		total += float(s[2])
	var out := PackedInt32Array()
	for cy in ncy:
		for cx in ncx:
			if used[cy * ncx + cx] != 0:
				continue
			var sw := 1
			var sh := 1
			# A few tries for a slab that fits here; a single cell always does.
			for attempt in 6:
				var r := rng.randf() * total
				var pick: Array = sizes[0]
				for s: Array in sizes:
					r -= float(s[2])
					if r <= 0.0:
						pick = s
						break
				var tw: int = pick[0]
				var th: int = pick[1]
				if cx + tw > ncx or cy + th > ncy:
					continue
				var free := true
				for yy in th:
					for xx in tw:
						if used[(cy + yy) * ncx + cx + xx] != 0:
							free = false
				if free:
					sw = tw
					sh = th
					break
			for yy in sh:
				for xx in sw:
					used[(cy + yy) * ncx + cx + xx] = 1
			out.append_array(PackedInt32Array([xs[cx], ys[cy], xs[cx + sw] - xs[cx], ys[cy + sh] - ys[cy], 0]))
	return out


static func _lattice(start: int, length: int, n: int, rng: RandomNumberGenerator, nudge: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var step := float(length) / n
	for k in n + 1:
		var v := start + step * k
		if k > 0 and k < n:
			v += rng.randf_range(-nudge, nudge) * step
		out.append(roundi(v))
	return out


## Paints packed slabs. `style` keys:
##   ramps: Array[int]   first palette index of three ramps of the same stone (16 shades, dark to light): the
##                       ordinary one, one a fraction of a shade darker and one a fraction lighter. Slabs differ
##                       by which they are cut from, so neighbours are never a whole shade apart by default
##   mid: int            the shade a slab sits at
##   joint: int          shades below `mid` for the joints
##   stray: float        chance that a slab is a whole shade off `mid`
##   dark: float         chance that an ordinary slab is of the darker stone
##   patch: PackedByteArray  from `patches`
##   patch_lo, patch_hi: int  byte thresholds: below is a darker patch, above a lighter one
##   bevel: float        chance of a faint lit top edge
##   chips: float        chance of a knocked corner
## `ids`, when given, receives a slab number per pixel (for measuring the step between neighbours).
static func paint(cv: ArenaArtCanvas, slabs: PackedInt32Array, style: Dictionary, rng: RandomNumberGenerator,
		ids: PackedInt32Array = PackedInt32Array(), first_id: int = 0) -> void:
	var px := cv.px
	var w := cv.w
	var h := cv.h
	var ramps: Array = style.ramps
	var mid: int = style.mid
	var joint_d: int = style.joint
	var stray: float = style.stray
	var dark: float = style.dark
	var patch: PackedByteArray = style.patch
	var p_lo: int = style.patch_lo
	var p_hi: int = style.patch_hi
	var bevel: float = style.bevel
	var chips: float = style.chips
	var want_ids := ids.size() == w * h
	var count := slabs.size() / STRIDE
	for s in count:
		var x0 := slabs[s * STRIDE]
		var y0 := slabs[s * STRIDE + 1]
		var sw := slabs[s * STRIDE + 2] - 1
		var sh := slabs[s * STRIDE + 3] - 1
		var flags := slabs[s * STRIDE + 4]
		if sw < 1 or sh < 1:
			continue
		var fam := 1 if rng.randf() < dark else 0
		var base := mid
		if rng.randf() < stray:
			base += 1 if rng.randf() < 0.5 else -1
			fam = 0
		var lo_t := p_lo
		var hi_t := p_hi
		var joint := mid - joint_d
		if flags & WORN != 0:
			fam = 2
			base = mid
			lo_t = p_lo - 40
			joint += 2
		if flags & DARKER != 0:
			fam = 1
			base = mid
		if flags & DAMP != 0:
			fam = 1
			base = mini(base, mid)
			hi_t = p_hi + 30
			joint -= 1
		var first: int = ramps[fam]
		if flags & FLAT != 0:
			lo_t = -1
			hi_t = 256
		base = clampi(base, 2, 13)
		var b := first + base
		# Each slab reads the patch field somewhere else, so patches stop at the joints like real stone.
		var ox := rng.randi_range(0, maxi(0, w - sw - 1)) - x0
		var oy := rng.randi_range(0, h - 1)
		var id := first_id + s
		for yy in sh:
			var k := (y0 + yy) * w + x0
			var nk := ((y0 + yy + oy) % h) * w + x0 + ox
			for xx in sw:
				var m := patch[nk]
				if m > hi_t:
					px[k] = b + 1
				elif m < lo_t:
					px[k] = b - 1
				else:
					px[k] = b
				k += 1
				nk += 1
		if want_ids:
			for yy in sh:
				var k := (y0 + yy) * w + x0
				for xx in sw:
					ids[k] = id
					k += 1
		# Joints: the right and bottom edge of the rectangle, a darker shade of the family's stone.
		var jc: int = ramps[0] + clampi(joint, 0, 15)
		cv.rect(x0 + sw, y0, 1, sh + 1, jc)
		cv.rect(x0, y0 + sh, sw, 1, jc)
		# A faint lit lip along part of the top edge and a shaded one along the bottom: the slab has thickness.
		if rng.randf() < bevel and sw > 6:
			var a := rng.randi_range(0, sw / 3)
			var n := rng.randi_range(sw / 3, sw - a)
			cv.shade_rect(x0 + a, y0, n, 1, 1)
		if rng.randf() < bevel * 0.7 and sw > 6:
			var a := rng.randi_range(0, sw / 2)
			cv.shade_rect(x0 + a, y0 + sh - 1, rng.randi_range(sw / 4, sw - a), 1, -1)
		# Worn corners: the joint swallows the corner pixel; now and then a bigger chip.
		for corner in 4:
			var cx := x0 if corner % 2 == 0 else x0 + sw - 1
			var cy := y0 if corner < 2 else y0 + sh - 1
			var r := rng.randf()
			if r < chips and sw > 8 and sh > 6:
				var dx := 1 if corner % 2 == 0 else -1
				var dy := 1 if corner < 2 else -1
				cv.put(cx, cy, jc)
				cv.put(cx + dx, cy, jc)
				cv.put(cx, cy + dy, jc)
				if rng.randf() < 0.4:
					cv.put(cx + dx * 2, cy, jc)
			elif r < 0.55:
				cv.put(cx, cy, jc)
