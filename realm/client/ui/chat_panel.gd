class_name ChatPanel
extends PanelBase
## Chat (job T1): the channels past the town room's say (TOWN, TRADE, PARTY, GUILD, WHISPER), her friends, and the
## friend requests waiting. Type and press Enter; a line starting with / is a command: /w NAME TEXT, /r TEXT,
## /t /p /g TEXT (one line to town, party or guild), /friend NAME, /ignore NAME, /unignore NAME, /report NAME TEXT.
## The server filters, limits and silences; what it refuses shows as a toast.

const LOG_LINES: int = 18
const CHANNELS: Array[int] = [GwWire.CHAN_TOWN, GwWire.CHAN_TRADE, GwWire.CHAN_PARTY, GwWire.CHAN_GUILD, GwWire.CHAN_WHISPER]
const CHAN_COLOURS: Array[Color] = [Color(0.88, 0.84, 0.72), Color(0.88, 0.84, 0.72), Color(0.95, 0.8, 0.45), Color(0.9, 0.62, 0.45), Color(0.55, 0.8, 0.5), Color(0.7, 0.6, 0.95)]
const INPUT_MAX: int = 200

var chan: int = GwWire.CHAN_TOWN
var text: String = ""
var reply_to: String = ""


func opened() -> void:
	title = "CHAT"
	frame_rect = Rect2(80, 30, 800, 480)
	shell.social_changed.connect(queue_redraw)


## One key into a line of text: a character, backspace. Returns the new text (Enter and Escape are the caller's).
static func edit_text(e: InputEventKey, s: String, max_len: int) -> String:
	if e.keycode == KEY_BACKSPACE:
		return s.left(maxi(0, s.length() - 1))
	if e.unicode >= 32 and e.unicode != 127 and s.length() < max_len:
		return s + char(e.unicode)
	return s


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	for i in CHANNELS.size():
		button("chan:%d" % CHANNELS[i], Rect2(x + i * 104.0, y, 98, 26), GwWire.CHAN_NAMES[CHANNELS[i]], true, CHANNELS[i] == chan, 12)
	# The log of this channel.
	var log_r := Rect2(x, y + 34, 540, inner.size.y - 100)
	UiKit.frame(self, log_r, UiKit.GOLD_DIM, Color(0.03, 0.026, 0.034, 0.9))
	var lines: Array[Dictionary] = []
	for l in shell.chat_lines:
		if int(l["chan"]) == chan:
			lines.append(l)
	var from: int = maxi(0, lines.size() - LOG_LINES)
	var ly: float = log_r.position.y + 6
	for i in range(from, lines.size()):
		var l: Dictionary = lines[i]
		var who: String = String(l["from"])
		if chan == GwWire.CHAN_WHISPER:
			who = "%s > %s" % [l["from"], l["to"]]
		UiKit.text(self, Vector2(log_r.position.x + 8, ly), "%s: %s" % [who, l["text"]], 12, CHAN_COLOURS[chan])
		ly += 16.0
	if lines.is_empty():
		UiKit.text(self, log_r.position + Vector2(8, 6), "Nothing said here yet.", 12, UiKit.BONE_DIM)
	# The input line.
	var box := Rect2(x, log_r.end.y + 8, 540, 26)
	UiKit.frame(self, box, UiKit.GOLD, Color(0.04, 0.035, 0.045, 0.95))
	var cur: String = "_" if int(time * 2.0) % 2 == 0 else ""
	var hint: String = "TO %s" % GwWire.CHAN_NAMES[chan] if chan != GwWire.CHAN_WHISPER else "/w NAME TEXT  (or /r TEXT)"
	UiKit.text(self, box.position + Vector2(8, 5), (text + cur) if not text.is_empty() else hint + cur, 13, UiKit.BONE if not text.is_empty() else UiKit.BONE_DIM)
	UiKit.text(self, Vector2(x, box.end.y + 6), "/w /r /t /p /g  /friend /ignore /unignore /report NAME TEXT", 10, UiKit.BONE_DIM)
	# Friends and their requests.
	var fx: float = x + 556
	UiKit.text(self, Vector2(fx, y + 4), "FRIENDS", 14, UiKit.GOLD)
	var fy: float = y + 30
	for inv in shell.invites:
		if String(inv["kind"]) != "friend":
			continue
		UiKit.text(self, Vector2(fx, fy), String(inv["name"]), 12, UiKit.BONE)
		button("fa:%d" % int(inv["id"]), Rect2(fx + 100, fy - 4, 48, 22), "YES", true, false, 11)
		button("fd:%d" % int(inv["id"]), Rect2(fx + 152, fy - 4, 48, 22), "NO", true, false, 11)
		fy += 26.0
	var shown: int = 0
	for f in shell.friends:
		if shown >= 12:
			break
		var online: bool = bool(f["online"])
		var r := Rect2(fx, fy, 200, 22)
		hit("fw:" + String(f["name"]), r)
		draw_rect(r, Color(0.1, 0.085, 0.09) if hover_id == "fw:" + String(f["name"]) else Color(0.06, 0.05, 0.06))
		draw_circle(r.position + Vector2(9, 11), 4.0, UiKit.GOOD if online else UiKit.BONE_DIM)
		UiKit.text(self, r.position + Vector2(20, 3), String(f["name"]), 12, UiKit.BONE if online else UiKit.BONE_DIM)
		if online:
			UiKit.text(self, Vector2(r.end.x - 6, r.position.y + 3), "FIELD" if int(f["place"]) == 2 else "TOWN", 10, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		fy += 24.0
		shown += 1
	if shell.friends.is_empty():
		UiKit.text(self, Vector2(fx, fy), "NONE YET: /friend NAME", 11, UiKit.BONE_DIM)


func press_body(id: String) -> void:
	if id.begins_with("chan:"):
		chan = int(id.trim_prefix("chan:"))
	elif id.begins_with("fa:") or id.begins_with("fd:"):
		var acct: int = int(id.substr(3))
		shell.remove_invite("friend", acct)
		shell.social(GwWire.soc_answer(GwWire.T_SOC_FRIEND_ANSWER, shell.hero_id(), acct, id.begins_with("fa:")))
	elif id.begins_with("fw:"):
		chan = GwWire.CHAN_WHISPER
		reply_to = id.substr(3)
		text = "/w %s " % reply_to


func key_body(e: InputEventKey) -> bool:
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		var t: String = text
		text = ""
		send(t)
		return true
	text = edit_text(e, text, INPUT_MAX)
	return true


## Sends a typed line: a command or a line on the current channel.
func send(line: String) -> void:
	var t: String = line.strip_edges()
	if t.is_empty():
		return
	var h: int = shell.hero_id()
	if not t.begins_with("/"):
		if chan == GwWire.CHAN_WHISPER:
			if reply_to.is_empty():
				say("Whisper with /w NAME TEXT.", true)
				return
			shell.act(GwWire.soc_talk(h, chan, reply_to, t))
		else:
			shell.act(GwWire.soc_talk(h, chan, "", t))
		return
	var parts: PackedStringArray = t.substr(1).split(" ", false, 2)
	var cmd: String = parts[0].to_lower() if parts.size() > 0 else ""
	var arg: String = parts[1] if parts.size() > 1 else ""
	var rest: String = parts[2] if parts.size() > 2 else ""
	match cmd:
		"w", "whisper", "tell":
			if arg.is_empty() or rest.is_empty():
				say("/w NAME TEXT", true)
				return
			reply_to = arg
			chan = GwWire.CHAN_WHISPER
			shell.act(GwWire.soc_talk(h, GwWire.CHAN_WHISPER, arg, rest))
		"r", "reply":
			var body: String = (arg + " " + rest).strip_edges()
			var who: String = reply_target()
			if who.is_empty() or body.is_empty():
				say("NO ONE TO REPLY TO", true)
				return
			shell.act(GwWire.soc_talk(h, GwWire.CHAN_WHISPER, who, body))
		"t", "p", "g", "trade":
			var ch: int = {"t": GwWire.CHAN_TOWN, "p": GwWire.CHAN_PARTY, "g": GwWire.CHAN_GUILD, "trade": GwWire.CHAN_TRADE}[cmd]
			var body2: String = (arg + " " + rest).strip_edges()
			if not body2.is_empty():
				shell.act(GwWire.soc_talk(h, ch, "", body2))
		"friend":
			shell.social(GwWire.soc_str(GwWire.T_SOC_FRIEND_ADD, h, arg), "REQUEST SENT")
		"ignore":
			shell.social(GwWire.soc_ignore(h, arg, true), "IGNORED")
		"unignore":
			shell.social(GwWire.soc_ignore(h, arg, false), "NO LONGER IGNORED")
		"report":
			shell.act(GwWire.soc_report(h, arg, 4, rest), "REPORT SENT")
		_:
			say("UNKNOWN COMMAND", true)



## Who /r answers: the last hero who whispered to her, else the last she whispered to.
func reply_target() -> String:
	var mine: String = String(shell.hero.get("name", ""))
	for i in range(shell.chat_lines.size() - 1, -1, -1):
		var l: Dictionary = shell.chat_lines[i]
		if int(l["chan"]) == GwWire.CHAN_WHISPER and String(l["from"]) != mine:
			return String(l["from"])
	return reply_to
