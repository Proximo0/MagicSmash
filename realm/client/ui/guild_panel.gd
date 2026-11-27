class_name GuildPanel
extends PanelBase
## The guild (job T1): up to 100 heroes under four ranks. Without one she can found one or answer an invitation. In
## one she sees the roster, the message of the day and the board; one text box does what the mode button says (invite,
## post, message of the day), and the ranks decide who may (the leader sets them; the server judges every call).

const PERM_INVITE: int = 1
const PERM_KICK: int = 2
const PERM_POST: int = 16
const PERM_MOTD: int = 32
const PERM_RANKS: int = 128
const MODES: Array[String] = ["INVITE", "POST", "NOTICE"]
const ROWS: int = 9

var text: String = ""
var mode: int = 1


func opened() -> void:
	title = "THE GUILD"
	frame_rect = Rect2(80, 30, 800, 480)
	shell.social_changed.connect(queue_redraw)


func _may(bit: int) -> bool:
	if shell.guild.is_empty():
		return false
	var rank: int = int(shell.guild["my_rank"])
	return rank == 0 or (int(shell.guild["perms"][rank]) & bit) == bit


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	var g: Dictionary = shell.guild
	if g.is_empty():
		_no_guild(inner)
		return
	UiKit.text(self, Vector2(x, y), String(g["name"]), 20, UiKit.GOLD)
	UiKit.text(self, Vector2(inner.end.x, y + 4), "%s  ·  %d %s" % [GwWire.RANK_NAMES[clampi(int(g["my_rank"]), 0, 3)], g["members"].size(), "MEMBER" if g["members"].size() == 1 else "MEMBERS"], 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	UiKit.text(self, Vector2(x, y + 28), String(g["motd"]) if not String(g["motd"]).is_empty() else "No notice posted.", 12, UiKit.BONE if not String(g["motd"]).is_empty() else UiKit.BONE_DIM)
	# Roster.
	var first: int = scroll_of("roster")
	var ry: float = y + 54
	for i in range(first, mini(g["members"].size(), first + ROWS)):
		var m: Dictionary = g["members"][i]
		var r := Rect2(x, ry, 400, 26)
		draw_rect(r, Color(0.06, 0.05, 0.06))
		draw_circle(r.position + Vector2(10, 13), 4.0, UiKit.GOOD if bool(m["online"]) else UiKit.BONE_DIM)
		UiKit.text(self, r.position + Vector2(22, 5), String(m["name"]), 12, UiKit.BONE if bool(m["online"]) else UiKit.BONE_DIM)
		UiKit.text(self, Vector2(r.end.x - 154, r.position.y + 5), GwWire.RANK_NAMES[clampi(int(m["rank"]), 0, 3)], 11, UiKit.GOLD_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		var below: bool = int(g["my_rank"]) < int(m["rank"])
		var acct: int = int(m["account"])
		if below and _may(PERM_RANKS):
			button("up:%d" % acct, Rect2(r.end.x - 148, ry + 1, 28, 24), "+", int(m["rank"]) > int(g["my_rank"]) + 1 or int(g["my_rank"]) == 0, false, 11)
			button("dn:%d" % acct, Rect2(r.end.x - 118, ry + 1, 28, 24), "-", int(m["rank"]) < 3, false, 11)
		if below and _may(PERM_KICK):
			button("kick:%d" % acct, Rect2(r.end.x - 84, ry + 1, 80, 24), "REMOVE", true, false, 10)
		ry += 28.0
	if g["members"].size() > ROWS:
		UiKit.text(self, Vector2(x + 400, ry), "%d-%d of %d (wheel)" % [first + 1, mini(g["members"].size(), first + ROWS), g["members"].size()], 10, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	# Board.
	var bx: float = x + 420
	UiKit.text(self, Vector2(bx, y + 54), "BOARD", 14, UiKit.GOLD)
	var by: float = y + 78
	var board: Array = g["board"]
	for i in range(maxi(0, board.size() - 6), board.size()):
		var p: Dictionary = board[i]
		by = UiKit.paragraph(self, Vector2(bx, by), "%s: %s" % [p["author"], p["text"]], 340.0, 12, UiKit.BONE) + 6.0
	if board.is_empty():
		UiKit.text(self, Vector2(bx, by), "NOTHING POSTED", 12, UiKit.BONE_DIM)
	# The box and its mode.
	var fy: float = inner.end.y - 70
	for i in MODES.size():
		var perm: int = [PERM_INVITE, PERM_POST, PERM_MOTD][i]
		button("mode:%d" % i, Rect2(x + i * 84.0, fy - 30, 78, 24), MODES[i], _may(perm), mode == i, 11)
	var box := Rect2(x, fy, 470, 28)
	UiKit.frame(self, box, UiKit.GOLD, Color(0.04, 0.035, 0.045, 0.95))
	UiKit.text(self, box.position + Vector2(8, 6), text + ("_" if int(time * 2.0) % 2 == 0 else ""), 13, UiKit.BONE)
	button("send", Rect2(x + 480, fy, 90, 28), "SEND", not text.is_empty(), false, 12)
	button("leave", Rect2(inner.end.x - 150, fy, 150, 28), "LEAVE GUILD", true, false, 12)
	for inv in shell.invites:
		if String(inv["kind"]) == "guild":
			UiKit.text(self, Vector2(x, inner.end.y - 14), "A GUILD INVITES YOU: LEAVE THIS ONE FIRST", 10, UiKit.BONE_DIM)
			break


func _no_guild(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	UiKit.text(self, Vector2(x, y), "YOU ARE IN NO GUILD.", 14, UiKit.BONE_DIM)
	var iy: float = y + 34
	for inv in shell.invites:
		if String(inv["kind"]) != "guild":
			continue
		UiKit.text(self, Vector2(x, iy), "%s (FROM %s)" % [inv["what"], inv["name"]], 13, UiKit.BONE)
		button("ga:%d" % int(inv["id"]), Rect2(x + 520, iy - 4, 70, 24), "JOIN", true, false, 11)
		button("gd:%d" % int(inv["id"]), Rect2(x + 596, iy - 4, 70, 24), "NO", true, false, 11)
		iy += 32.0
	var fy: float = inner.end.y - 70
	UiKit.text(self, Vector2(x, fy - 22), "FOUND A GUILD (3 TO 20 LETTERS)", 11, UiKit.BONE_DIM)
	var box := Rect2(x, fy, 400, 28)
	UiKit.frame(self, box, UiKit.GOLD, Color(0.04, 0.035, 0.045, 0.95))
	UiKit.text(self, box.position + Vector2(8, 6), text + ("_" if int(time * 2.0) % 2 == 0 else ""), 13, UiKit.BONE)
	button("create", Rect2(x + 410, fy, 110, 28), "FOUND", not text.is_empty(), false, 12)


func press_body(id: String) -> void:
	var h: int = shell.hero_id()
	if id == "create":
		_send()
	elif id == "send":
		_send()
	elif id == "leave":
		shell.social(GwWire.soc_hero(GwWire.T_SOC_GUILD_LEAVE, h))
	elif id.begins_with("mode:"):
		mode = int(id.substr(5))
	elif id.begins_with("ga:") or id.begins_with("gd:"):
		var gid: int = int(id.substr(3))
		shell.remove_invite("guild", gid)
		shell.social(GwWire.soc_answer(GwWire.T_SOC_GUILD_ANSWER, h, gid, id.begins_with("ga:")))
	elif id.begins_with("kick:"):
		shell.social(GwWire.soc_id(GwWire.T_SOC_GUILD_KICK, h, int(id.substr(5))))
	elif id.begins_with("up:") or id.begins_with("dn:"):
		var acct: int = int(id.substr(3))
		for m in shell.guild["members"]:
			if int(m["account"]) == acct:
				var to: int = int(m["rank"]) + (-1 if id.begins_with("up:") else 1)
				shell.social(GwWire.soc_guild_rank(h, acct, clampi(to, 0, 3)))


func _send() -> void:
	var t: String = text.strip_edges()
	text = ""
	if t.is_empty():
		return
	var h: int = shell.hero_id()
	if shell.guild.is_empty():
		shell.social(GwWire.soc_str(GwWire.T_SOC_GUILD_CREATE, h, t), "GUILD FOUNDED")
		return
	var tag: int = [GwWire.T_SOC_GUILD_INVITE, GwWire.T_SOC_GUILD_POST, GwWire.T_SOC_GUILD_MOTD][mode]
	shell.social(GwWire.soc_str(tag, h, t), "INVITED" if mode == 0 else "")


func wheel_body(dir: int) -> void:
	if not shell.guild.is_empty():
		scroll_by("roster", dir, shell.guild["members"].size(), ROWS)


func key_body(e: InputEventKey) -> bool:
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		_send()
		return true
	text = ChatPanel.edit_text(e, text, 200)
	return true
