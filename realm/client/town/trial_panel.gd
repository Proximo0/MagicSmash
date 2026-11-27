class_name TrialPanel
extends NodePanel
## THE CLASS TRIAL (rules section 3, vault row 5): five minutes alone against the horde, THE TRIAL WARDEN at the
## third. It asks class level 10 and no key; a party waits in town. Passing it is kept for good and is what the
## trainer asks before he gives a job at level 40 (for coin: the price is the gateway's, `job_change_cost`). The
## gateway's WORLD Trial reply says it all (WorldWire.trial); ENTER is its VaultOpen (WorldWire.vault_open), and the
## field client takes her in like a field gate. Back from it, this screen opens again with how it went.

## The trial's length and its boss's minute (realm/core VAULTS row 5).
const MINUTES: int = 5
const BOSS_MINUTE: int = 3

## The outing she came back with ({} when opened at the station).
var back_from: Dictionary = {}
var need_label: Label
var level_label: Label
var alone_label: Label
var state_label: Label
var job_label: Label
var result_label: Label
var enter_btn: Button
var _entering: bool = false


func opened() -> void:
	title = "THE CLASS TRIAL"
	super.opened()


func build() -> void:
	label("Five minutes alone against the horde. THE TRIAL WARDEN comes at the third minute and again until he falls. Win, and the trainer will teach you a job when you reach level 40.", Vector2(0, 0), 14, UiKit.BONE, 832)
	label("WHAT IT ASKS", Vector2(0, 66), 13, UiKit.GOLD)
	need_label = label("", Vector2(0, 90), 15, UiKit.BONE, 832)
	level_label = label("", Vector2(0, 116), 15, UiKit.BONE, 832)
	alone_label = label("You go in alone: your party waits in town. No vault key is needed.", Vector2(0, 142), 15, UiKit.BONE, 832)
	label("WHERE YOU STAND", Vector2(0, 182), 13, UiKit.GOLD)
	state_label = label("", Vector2(0, 206), 17, UiKit.BONE, 832)
	job_label = label("", Vector2(0, 236), 13, UiKit.BONE_DIM, 832)
	result_label = label("", Vector2(0, 270), 16, UiKit.GOLD, 832)
	enter_btn = add_button("ENTER THE TRIAL", "enter", func() -> void: enter(), body, Vector2(0, 330), Vector2(260, 40))
	add_button("READ IT AGAIN", "refresh", func() -> void: refresh(), body, Vector2(276, 330), Vector2(200, 40))
	shell.data_changed.connect(_show)
	_show()
	refresh.call_deferred()


func _exit_tree() -> void:
	if shell != null and shell.data_changed.is_connected(_show):
		shell.data_changed.disconnect(_show)


func refresh() -> void:
	if busy:
		return
	busy = true
	await shell.refresh_heroes()
	if not is_instance_valid(self):
		return
	await shell.refresh_trial()
	if not is_instance_valid(self):
		return
	busy = false
	_show()


func _show() -> void:
	if not is_instance_valid(enter_btn):
		return
	var t: Dictionary = shell.trial
	var level: int = int(shell.hero.get("level", 1))
	var need: int = int(t.get("level", 10))
	var passed: bool = bool(t.get("passed", false))
	need_label.text = "CLASS LEVEL %d" % need
	var fit: bool = level >= need
	if fit:
		level_label.text = "YOU ARE LEVEL %d: YOU MAY ENTER" % level
	else:
		level_label.text = "YOU ARE LEVEL %d: COME BACK AT LEVEL %d" % [level, need]
	level_label.add_theme_color_override("font_color", UiKit.GOOD if fit else UiKit.BAD)
	if t.is_empty():
		state_label.text = "THE TRIAL MASTER IS LOOKING YOU UP..."
		job_label.text = ""
	elif passed:
		state_label.text = "YOU HAVE PASSED THE CLASS TRIAL"
		state_label.add_theme_color_override("font_color", UiKit.GOOD)
	else:
		state_label.text = "YOU HAVE NOT PASSED IT YET"
		state_label.add_theme_color_override("font_color", UiKit.BONE)
	if not t.is_empty():
		var job: int = int(t["job"])
		if job < GameNames.JOBS.size():
			job_label.text = "YOU ARE A %s." % GameNames.JOBS[job]
		else:
			job_label.text = "A JOB AT LEVEL %d: THE TRAINER ASKS %s COIN AT YOUR LEVEL, AFTER THE TRIAL." % [int(t["job_level"]), GameNames.commas(int(t["job_price"]))]
	if not back_from.is_empty():
		if passed:
			result_label.text = "YOU PASSED THE CLASS TRIAL. %s COIN AND %s XP CAME BACK WITH YOU." % [GameNames.commas(int(back_from["coin"])), GameNames.commas(int(back_from["xp"]))]
			result_label.add_theme_color_override("font_color", UiKit.GOOD)
		else:
			result_label.text = "THE TRIAL BEAT YOU THIS TIME. %s COIN FOR THE MINUTES YOU STOOD. TRY AGAIN WHEN YOU ARE READY." % GameNames.commas(int(back_from["coin"]))
			result_label.add_theme_color_override("font_color", UiKit.BAD)
	enter_btn.disabled = busy or _entering or passed or not fit or t.is_empty()
	enter_btn.text = "PASSED" if passed else "ENTER THE TRIAL"


## Asks the gateway for the trial's ticket and goes in. Returns "" or the refusal (also shown).
func enter() -> String:
	if _entering:
		return ""
	_entering = true
	_show()
	var err: String = await shell.go_trial()
	if not err.is_empty() and is_instance_valid(self):
		_entering = false
		say(err, true)
		_show()
	return err
