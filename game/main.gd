extends Node
## Root node: swaps between the title screen and a match.

var current: Node = null

func _ready() -> void:
	G.main = self
	if G.is_mobile:
		# Phones come in odd sizes; fill the screen instead of integer steps.
		get_tree().root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	else:
		# The SCALING option (Save.apply_settings keeps it up to date once the player changes it).
		get_tree().root.content_scale_stretch = Save.settings.stretch_mode()
	# Flags.args drops --autotest in a release export (Flags.debug_args_allowed); --smoke runs in every build.
	if Flags.args.has("autotest"):
		add_child(preload("res://game/debug/autotest.gd").new())
	if Flags.args.has("smoke"):
		add_child(preload("res://game/debug/smoke.gd").new())
	show_title()

func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	add_child(n)

func show_title() -> void:
	Engine.time_scale = 1.0
	_swap(preload("res://game/ui/title.gd").new())

func show_sanctum() -> void:
	Engine.time_scale = 1.0
	_swap(preload("res://game/sanctum/sanctum_view.gd").new())

func show_game() -> void:
	_swap(preload("res://game/arena/arena.gd").new())
