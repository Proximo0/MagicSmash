extends SceneTree
## Playtest: SmashBot personas play whole runs in the pure simulation and the tool reports where the game is too
## hard, too easy, dull or unfair. One compact table per persona and party size, then one line starting PLAYTEST.
## Usage: godot --headless --path . -s tools/playtest.gd -- [--runs=6] [--wizards=1,2,4]
##   [--persona=novice,casual,veteran] [--seed=1] [--minutes=25] [--tune=field:value,...] [--seal=N] [--reading=<key>]
##   [--json=/tmp/out.json] [--party=casual,apprentice,...] [--hero=knight,archer:elf,...] [--profile=FILE]
##   [--meta=key:value,...]
## --meta passes Profile.bonuses keys to World.apply_meta for every run (over --profile's), e.g.
## --meta=start_level:2,redraws:1 (THE HEAD START 2, THE SECOND GLANCE 1); the PLAYTEST line names them. A key
## apply_meta does not read is refused; a second --meta adds to the first.
## --profile plays every run from a saved profile (a tools/career.gd checkpoint): its unlocks for every seat, its
## heroes (levels, stat points) for the human seats in seat order.
## --party plays one party of the named seats instead of the persona x wizards groups: a persona name seats a
## human bot, "apprentice" seats an apprentice (World plays it, WorldApprentices); e.g. --party=casual,apprentice.
## A seat is persona[:class[:race]] (apprentice too), e.g. --party=casual:knight,casual:priest,apprentice:archer;
## --hero=class[:race],... plays each persona x wizards group once per hero, every seat that class. No class: as before.
## Seeds run from --seed to --seed + runs - 1; every group plays the same seeds. How to read it: docs/bots.md.

## The work lives in tools/playtest_lib.gd, loaded after the autoloads so game classes compile.


func _init() -> void:
	call_deferred("_main")


func _main() -> void:
	var lib: RefCounted = (load("res://tools/playtest_lib.gd") as GDScript).new()
	quit(lib.call("run"))
