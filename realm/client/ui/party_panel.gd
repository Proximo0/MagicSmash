class_name PartyPanel
extends PanelBase
## The party (job T1): up to eight heroes. The leader invites, removes, hands over the lead and calls the party to
## a field (every member's ticket then shares one copy of it). Anyone leaves, answers invitations and follows a call.

var name_text: String = ""


func opened() -> void:
	title = "THE PARTY"
	frame_rect = Rect2(140, 40, 680, 460)
	shell.social_changed.connect(queue_redraw)


func _leader() -> bool:
	return not shell.party.is_empty() and int(shell.party["leader"]) == shell.hero_id()


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	var p: Dictionary = shell.party
	if p.is_empty():
		UiKit.text(self, Vector2(x, y), "You are in no party. Invite a hero by name.", 13, UiKit.BONE_DIM)
	else:
		UiKit.text(self, Vector2(x, y), "%d OF 8" % p["members"].size(), 14, UiKit.GOLD)
		var cp: Array = p["copy"]
		if not cp.is_empty():
			UiKit.text(self, Vector2(x + 560, y), "%s, COPY %d" % [GameNames.FIELDS[clampi(int(cp[0]), 0, GameNames.FIELDS.size() - 1)], int(cp[1]) + 1], 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		var ry: float = y + 28
		for m in p["members"]:
			var r := Rect2(x, ry, 520, 28)
			draw_rect(r, Color(0.06, 0.05, 0.06))
			draw_rect(r, Color(UiKit.GOLD_DIM, 0.3), false, 1.0)
			draw_circle(r.position + Vector2(12, 14), 4.0, UiKit.GOOD if bool(m["online"]) else UiKit.BONE_DIM)
			var lead: bool = int(m["hero"]) == int(p["leader"])
			UiKit.text(self, r.position + Vector2(26, 6), String(m["name"]) + ("  (LEADER)" if lead else ""), 13, UiKit.GOLD if lead else UiKit.BONE)
			UiKit.text(self, Vector2(r.end.x - 130, r.position.y + 6), "LV %d %s" % [int(m["level"]), GameNames.class_name_of(int(m["class"]))], 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
			if _leader() and int(m["hero"]) != shell.hero_id():
				button("kick:%d" % int(m["hero"]), Rect2(r.end.x - 120, ry + 2, 54, 24), "KICK", true, false, 11)
				button("lead:%d" % int(m["hero"]), Rect2(r.end.x - 62, ry + 2, 58, 24), "LEAD", true, false, 11)
			ry += 32.0
	# Invitations to us.
	var iy: float = y + 28
	var ix: float = x + 540
	for inv in shell.invites:
		if String(inv["kind"]) != "party":
			continue
		UiKit.text(self, Vector2(ix, iy), String(inv["name"]), 12, UiKit.BONE)
		button("pa:%d" % int(inv["id"]), Rect2(ix, iy + 16, 56, 22), "JOIN", true, false, 11)
		button("pd:%d" % int(inv["id"]), Rect2(ix + 60, iy + 16, 56, 22), "NO", true, false, 11)
		iy += 48.0
	# The foot: invite by name, leave, call or follow.
	var by: float = inner.end.y - 104
	if p.is_empty() or _leader():
		UiKit.text(self, Vector2(x, by - 20), "INVITE A HERO (TYPE A NAME, ENTER)", 11, UiKit.BONE_DIM)
		var box := Rect2(x, by, 300, 28)
		UiKit.frame(self, box, UiKit.GOLD, Color(0.04, 0.035, 0.045, 0.95))
		UiKit.text(self, box.position + Vector2(8, 6), name_text + ("_" if int(time * 2.0) % 2 == 0 else ""), 13, UiKit.BONE)
		button("invite", Rect2(x + 310, by, 100, 28), "INVITE", not name_text.is_empty(), false, 12)
	if not p.is_empty():
		button("leave", Rect2(inner.end.x - 160, by, 160, 28), "LEAVE PARTY", true, false, 12)
		if _leader():
			UiKit.text(self, Vector2(x, by + 40), "CALL THE PARTY TO", 11, UiKit.BONE_DIM)
			for f in GameNames.FIELDS.size():
				button("go:%d" % f, Rect2(x + f * 124.0, by + 58, 118, 28), GameNames.FIELDS[f].replace("THE ", ""), true, false, 10)
		elif shell.field_call >= 0:
			button("follow", Rect2(x, by + 58, 360, 28), "FOLLOW TO " + GameNames.FIELDS[clampi(shell.field_call, 0, 5)], true, false, 12)


func press_body(id: String) -> void:
	var h: int = shell.hero_id()
	if id == "invite":
		_invite()
	elif id == "leave":
		shell.social(GwWire.soc_hero(GwWire.T_SOC_PARTY_LEAVE, h))
	elif id.begins_with("kick:"):
		shell.social(GwWire.soc_id(GwWire.T_SOC_PARTY_KICK, h, int(id.substr(5))))
	elif id.begins_with("lead:"):
		shell.social(GwWire.soc_id(GwWire.T_SOC_PARTY_LEAD, h, int(id.substr(5))))
	elif id.begins_with("pa:") or id.begins_with("pd:"):
		var who: int = int(id.substr(3))
		shell.remove_invite("party", who)
		shell.social(GwWire.soc_answer(GwWire.T_SOC_PARTY_ANSWER, h, who, id.begins_with("pa:")))
	elif id.begins_with("go:"):
		_go(int(id.substr(3)))
	elif id == "follow":
		close()
		shell.go_field(shell.field_call)


func _invite() -> void:
	var n: String = name_text.strip_edges()
	name_text = ""
	if not n.is_empty():
		shell.social(GwWire.soc_str(GwWire.T_SOC_PARTY_INVITE, shell.hero_id(), n), "INVITED")


## The leader's call: the party is told, then she takes her own ticket (the first one fixes the copy).
func _go(field: int) -> void:
	var r: Dictionary = await shell.act(GwWire.soc_party_go(shell.hero_id(), field))
	if int(r["t"]) == GwWire.R_OK:
		close()
		var err: String = await shell.go_field(field)
		if not err.is_empty() and shell.top() != null:
			shell.top().say(err, true)


func key_body(e: InputEventKey) -> bool:
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		_invite()
		return true
	name_text = ChatPanel.edit_text(e, name_text, 16)
	return true
