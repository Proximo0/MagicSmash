extends RefCounted
## The coverage robot's plan without playing (tests/bot/bot_cover.gd): one line a row `ROW <family> <key>
## cover|pending|unbuilt`, then `COVERAGE rows=R cover=C pending=P unbuilt=U`. With `--gate` the exit status is 1
## unless P and U are both 0 (stage 3's gate, docs/stage3_brief.md § 1).
## Usage: godot --headless --path . -s tools/tool.gd -- coverage [--gate]

const CoverBot := preload("res://tests/bot/bot_cover.gd")


func run(args: PackedStringArray) -> int:
	var counts := {"cover": 0, "pending": 0, "unbuilt": 0}
	var rows: Array = CoverBot.plan()
	for row: Array in rows:
		print("ROW %s %s %s" % [row[0].call("family"), row[1], row[2]])
		counts[row[2]] = int(counts[row[2]]) + 1
	print("COVERAGE rows=%d cover=%d pending=%d unbuilt=%d" % [rows.size(), counts.cover, counts.pending, counts.unbuilt])
	if args.has("--gate") and (int(counts.pending) > 0 or int(counts.unbuilt) > 0):
		return 1
	return 0
