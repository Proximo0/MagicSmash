extends SceneTree
## Playtest: SmashBot personas play whole runs in the pure simulation and the tool reports where the game is too
## hard, too easy, dull or unfair. One compact table per persona and party size, then one line starting PLAYTEST.
## Usage: godot --headless --path . -s tools/playtest.gd -- [--runs=6] [--wizards=1,2,4]
##   [--persona=novice,casual,veteran] [--seed=1] [--minutes=16] [--tune=field:value,...] [--seal=N]
##   [--json=/tmp/out.json] [--party=casual,apprentice,...]
## --party plays one party of the named seats instead of the persona x wizards groups: a persona name seats a
## human bot, "apprentice" seats an apprentice (World plays it, WorldApprentices); e.g. --party=casual,apprentice.
## Seeds run from --seed to --seed + runs - 1; every group plays the same seeds. How to read it: docs/bots.md.

## The work lives in tools/playtest_lib.gd, loaded after the autoloads so game classes compile.


func _init() -> void:
	call_deferred("_main")


func _main() -> void:
	var lib: RefCounted = (load("res://tools/playtest_lib.gd") as GDScript).new()
	quit(lib.call("run"))
