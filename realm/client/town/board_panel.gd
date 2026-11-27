class_name BoardPanel
extends NodePanel
## The world board: what the realm is doing. For each of the six fields the next tide (or how long the running
## one lasts), the field boss that rises next and when, how many heroes stand in its copies; the world boss's
## next ride, the queue for a place, the vaults open. All of it is the server's WORLD board (BOARD, docs/realm/
## world.md); the client turns its ticks (20 a second) into words and changes nothing.

const TICK_HZ: int = 20

var tree: Tree
var world_label: Label
var queue_label: Label
var clock_label: Label
var board: Dictionary = {}
var _timer: Timer


func opened() -> void:
	title = "THE WORLD BOARD"
	super.opened()


func build() -> void:
	tree = Tree.new()
	tree.position = Vector2(0, 0)
	tree.size = Vector2(832, 230)
	tree.columns = 4
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.select_mode = Tree.SELECT_ROW
	tree.focus_mode = Control.FOCUS_ALL
	for i in 4:
		tree.set_column_title(i, ["FIELD", "THE TIDE", "THE NEXT BOSS", "HEROES"][i])
		tree.set_column_expand(i, i == 0)
		tree.set_column_custom_minimum_width(i, [210, 140, 330, 90][i])
	body.add_child(tree)
	world_label = label("", Vector2(0, 244), 15, UiKit.GOLD, 832)
	queue_label = label("", Vector2(0, 276), 14, UiKit.BONE, 832)
	clock_label = label("", Vector2(0, 306), 12, UiKit.BONE_DIM, 832)
	add_button("READ IT AGAIN", "refresh", func() -> void: refresh(), body, Vector2(0, 336), Vector2(200, 34))
	_timer = Timer.new()
	_timer.wait_time = 5.0
	_timer.timeout.connect(func() -> void: refresh())
	add_child(_timer)
	_timer.start()
	refresh.call_deferred()


func _secs(ticks: int) -> String:
	return span_text(ticks / TICK_HZ)


func refresh() -> void:
	if busy:
		return
	busy = true
	var r: Dictionary = await shell.act(WorldWire.board())
	if not is_instance_valid(self):
		return
	busy = false
	if int(r["t"]) != WorldWire.R_WORLD or int(r.get("k", -1)) != WorldWire.K_BOARD:
		return
	board = r
	_show()


func _show() -> void:
	tree.clear()
	var root: TreeItem = tree.create_item()
	var heroes_in: Dictionary = {}
	for c in board["copies"]:
		heroes_in[int(c[0])] = int(heroes_in.get(int(c[0]), 0)) + int(c[2])
	for f in board["fields"]:
		var n: int = int(f["field"])
		var ti: TreeItem = tree.create_item(root)
		ti.set_text(0, GameNames.FIELDS[n] if n < GameNames.FIELDS.size() else "FIELD %d" % (n + 1))
		if int(f["tide_left"]) > 0:
			ti.set_text(1, "RUNNING: %s LEFT" % _secs(int(f["tide_left"])))
			ti.set_custom_color(1, UiKit.BAD)
		else:
			ti.set_text(1, "IN %s" % _secs(int(f["tide_in"])))
		var b: int = int(f["boss"])
		ti.set_text(2, "%s IN %s" % [GameNames.BOSSES[b] if b < GameNames.BOSSES.size() else "A BOSS", _secs(int(f["boss_in"]))])
		ti.set_text(3, str(int(heroes_in.get(n, 0))))
		ti.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
	var wf: int = int(board["world_field"])
	world_label.text = "THE PALE RIDER COMES TO %s IN %s" % [GameNames.FIELDS[wf] if wf < GameNames.FIELDS.size() else "THE FIELDS", _secs(int(board["world_in"]))]
	var q: int = int(board["queue"])
	queue_label.text = ("NO ONE WAITS" if q == 0 else "%d WAIT" % q) + " FOR A PLACE IN A FIELD.  %d VAULT%s OPEN." % [int(board["vaults"]), "" if int(board["vaults"]) == 1 else "S"]
	clock_label.text = "THE REALM HAS STOOD %s" % span_text(int(board["clock"]) / TICK_HZ)
