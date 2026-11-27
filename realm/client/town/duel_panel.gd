class_name DuelPanel
extends NodePanel
## Duels in the training yard (docs/realm/pvp.md, "Duels"): challenge a hero of this town by name or from the
## heroes standing near you; a challenge waits 30 seconds for her ACCEPT or REFUSE (this screen opens over the town
## when a challenge comes). The fight is the gateway's: steer with the walking keys, your weapon swings by itself,
## a down or three minutes ends it, and both of you are told who won. Calls: SOCIAL 0x5F (challenge, accept,
## decline); pushes 0xB0 kinds 12 to 15 (Shell._on_duel). Nothing is won or lost but the honour.

const NEAR_MAX: int = 12

var name_edit: LineEdit
var near_list: ItemList
var offer_label: Label
var accept_btn: Button
var refuse_btn: Button
var state_label: Label
var result_label: Label


func opened() -> void:
	title = "THE DUEL RING"
	super.opened()


func build() -> void:
	offer_label = label("", Vector2(0, 0), 16, UiKit.GOLD, 520)
	accept_btn = add_button("ACCEPT", "accept", func() -> void: answer(true), body, Vector2(540, 0), Vector2(140, 34))
	refuse_btn = add_button("REFUSE", "refuse", func() -> void: answer(false), body, Vector2(692, 0), Vector2(140, 34))
	label("CHALLENGE A HERO OF THIS TOWN BY NAME", Vector2(0, 52), 13, UiKit.GOLD)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(0, 74)
	name_edit.size = Vector2(280, 32)
	name_edit.max_length = 16
	name_edit.focus_mode = Control.FOCUS_ALL
	name_edit.placeholder_text = "A hero's name"
	name_edit.text_submitted.connect(func(_t: String) -> void: challenge(name_edit.text))
	body.add_child(name_edit)
	add_button("CHALLENGE", "challenge", func() -> void: challenge(name_edit.text), body, Vector2(292, 74), Vector2(150, 32))
	label("OR ONE STANDING NEAR YOU", Vector2(0, 122), 13, UiKit.GOLD)
	near_list = item_list(Vector2(0, 144), Vector2(440, 170))
	near_list.item_activated.connect(func(i: int) -> void: challenge(near_list.get_item_text(i).get_slice("  ", 0)))
	add_button("CHALLENGE THE CHOSEN", "challenge_near", func() -> void: _challenge_chosen(), body, Vector2(0, 322), Vector2(240, 32))
	label("HOW A DUEL GOES", Vector2(470, 122), 13, UiKit.GOLD)
	label("Steer with the walking keys; your weapon swings by itself. The first down, or three minutes, ends it. Leaving the town forfeits. Nothing is won or lost but the honour.", Vector2(470, 144), 13, UiKit.BONE_DIM, 362)
	state_label = label("", Vector2(470, 260), 14, UiKit.BONE, 362)
	result_label = label("", Vector2(470, 300), 15, UiKit.GOLD, 362)
	shell.social_changed.connect(_show)
	_show()


func _exit_tree() -> void:
	if shell != null and shell.social_changed.is_connected(_show):
		shell.social_changed.disconnect(_show)


## The heroes of the room nearest her first (the town's own roster and positions).
func nearby() -> Array[String]:
	var out: Array[String] = []
	var ts: TownScreen = shell.base as TownScreen
	if ts == null or not ts.members.has(ts.me):
		return out
	var at: Vector2 = ts.shown(ts.me)
	var ids: Array = ts.members.keys().filter(func(id: int) -> bool: return id != ts.me)
	ids.sort_custom(func(a: int, b: int) -> bool: return ts.shown(a).distance_to(at) < ts.shown(b).distance_to(at))
	for id in ids.slice(0, NEAR_MAX):
		out.append(String(ts.members[id]["name"]))
	return out


func _show() -> void:
	if not is_instance_valid(near_list):
		return
	var offer: Dictionary = shell.duel_offer
	if offer.is_empty():
		offer_label.text = "NO ONE HAS CHALLENGED YOU"
		offer_label.add_theme_color_override("font_color", UiKit.BONE_DIM)
	else:
		offer_label.text = "%s CHALLENGES YOU TO A DUEL" % String(offer["name"]).to_upper()
		offer_label.add_theme_color_override("font_color", UiKit.GOLD)
	accept_btn.disabled = offer.is_empty() or busy
	refuse_btn.disabled = offer.is_empty() or busy
	var ts: TownScreen = shell.base as TownScreen
	near_list.clear()
	unreg_prefix("near:")
	for n in nearby():
		var lv: String = ""
		if ts != null:
			for id in ts.members:
				if String(ts.members[id]["name"]) == n:
					lv = "  LEVEL %d %s" % [int(ts.members[id]["level"]), GameNames.class_name_of(int(ts.members[id]["class"]))]
		var i: int = near_list.add_item(n + lv)
		near_list.set_item_metadata(i, n)
		reg("near:" + n, near_list, func() -> void:
			near_list.select(i)
			challenge(n))
	if near_list.item_count == 0:
		near_list.add_item("No one else stands here.")
		near_list.set_item_disabled(0, true)
		near_list.set_item_selectable(0, false)
	if shell.duel.is_empty():
		state_label.text = ""
	else:
		state_label.text = "YOU ARE IN A DUEL WITH %s." % String(shell.duel["name"]).to_upper()
	result_label.text = Shell.duel_result_text(shell.duel_result)


func _challenge_chosen() -> void:
	var s: PackedInt32Array = near_list.get_selected_items()
	if s.is_empty() or near_list.get_item_metadata(s[0]) == null:
		say("CHOOSE A HERO IN THE LIST FIRST", true)
		return
	challenge(String(near_list.get_item_metadata(s[0])))


## Challenges `who` by name. Returns the gateway's reply.
func challenge(who: String) -> Dictionary:
	var n: String = who.strip_edges()
	if n.is_empty():
		say("WRITE A HERO'S NAME FIRST", true)
		return {}
	var r: Dictionary = await do(GwWire.soc_duel(shell.hero_id(), GwWire.DUEL_CHALLENGE, n), "YOU CHALLENGE %s: SHE HAS 30 SECONDS TO ANSWER" % n.to_upper(), false)
	if is_instance_valid(self):
		_show()
	return r


## Accepts or refuses the challenge waiting for her.
func answer(yes: bool) -> Dictionary:
	var offer: Dictionary = shell.duel_offer
	if offer.is_empty():
		return {}
	var op: int = GwWire.DUEL_ACCEPT if yes else GwWire.DUEL_DECLINE
	var r: Dictionary = await do(GwWire.soc_duel(shell.hero_id(), op, String(offer["name"])), "" if yes else "YOU REFUSE %s" % String(offer["name"]).to_upper(), false)
	if int(r.get("t", -1)) == GwWire.R_OK and not yes:
		shell.duel_offer = {}
	elif int(r.get("t", -1)) == GwWire.R_ERR and int(r.get("code", 0)) == GwWire.E_MISSING:
		# The challenge ran out (30 s) or was taken back.
		shell.duel_offer = {}
	if is_instance_valid(self):
		_show()
	return r
