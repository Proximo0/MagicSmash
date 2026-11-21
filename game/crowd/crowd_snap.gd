class_name CrowdSnap
extends RefCounted
## One decoded snapshot of protocol A (docs/realm/crowd_test.md): every position is already absolute field px.
## Monsters are sorted by id. `mflag` per monster: kind 0..2 bits 0-2 are the kind, bits 3-5 health in eighths,
## bit 6 elite, bit 7 hurt.

var tick: int = 0
var origin_x: int = 0
var origin_y: int = 0
var my_x: float = 0.0
var my_y: float = 0.0
var my_health: int = 0
var my_level: int = 0
var players_in_field: int = 0
var monsters_in_field: int = 0
## Server tick time in ms.
var tick_ms: float = 0.0
var recv_s: float = 0.0
var has_header: bool = false

var pid: PackedInt32Array = PackedInt32Array()
var px: PackedFloat32Array = PackedFloat32Array()
var py: PackedFloat32Array = PackedFloat32Array()
## class | race << 3
var pkind: PackedByteArray = PackedByteArray()
## bit 0 faces left, bit 1 moving, bit 2 hurt
var pflag: PackedByteArray = PackedByteArray()

var cx: PackedFloat32Array = PackedFloat32Array()
var cy: PackedFloat32Array = PackedFloat32Array()

var mid: PackedInt32Array = PackedInt32Array()
var mx: PackedFloat32Array = PackedFloat32Array()
var my: PackedFloat32Array = PackedFloat32Array()
var mflag: PackedByteArray = PackedByteArray()


## Appends the lists of another part (the header stays this one's).
func append_part(o: CrowdSnap) -> void:
	pid.append_array(o.pid)
	px.append_array(o.px)
	py.append_array(o.py)
	pkind.append_array(o.pkind)
	pflag.append_array(o.pflag)
	cx.append_array(o.cx)
	cy.append_array(o.cy)
	mid.append_array(o.mid)
	mx.append_array(o.mx)
	my.append_array(o.my)
	mflag.append_array(o.mflag)


## Index of the same player in `prev` (by id), or -1; filled by `match_previous`.
var pprev: PackedInt32Array = PackedInt32Array()
## Index of the same monster in `prev` (by id), or -1.
var mprev: PackedInt32Array = PackedInt32Array()


## Matches players (by id) and monsters (by id, both lists sorted) of this snapshot to `prev`, once, so that
## drawing between the two costs a lookup per figure.
func match_previous(prev: CrowdSnap) -> void:
	var ids := {}
	for i in prev.pid.size():
		ids[prev.pid[i]] = i
	pprev.resize(pid.size())
	for i in pid.size():
		pprev[i] = ids.get(pid[i], -1)
	mprev.resize(mid.size())
	var j: int = 0
	var pn: int = prev.mid.size()
	for i in mid.size():
		var id: int = mid[i]
		while j < pn and prev.mid[j] < id:
			j += 1
		mprev[i] = j if j < pn and prev.mid[j] == id else -1
