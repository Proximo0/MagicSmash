extends RefCounted
## Writes THIRD_PARTY_NOTICES.txt from the engine itself: Godot's licence, each third-party component with its
## copyright lines and licence name, then the full text of each licence named. Adds the Sentry addon when
## addons/sentry is present (its licence read from the addon's own files, then the sentry-native and Crashpad texts from tools/notices/). No licence text is written by hand.
## Usage: godot --headless --path . -s tools/tool.gd -- notices [out-file]   (default THIRD_PARTY_NOTICES.txt)

const RULE := "================================================================"
const SENTRY_DIR := "res://addons/sentry"
## The licence texts of what the Sentry addon bundles (tools/notices/SOURCES.md): [heading, file], read only when the addon is there.
const SENTRY_PARTS: Array = [
	["sentry-native (the Sentry Native SDK inside the addon)", "res://tools/notices/sentry-native.LICENSE"],
	["Crashpad (Sentry's build, inside the addon)", "res://tools/notices/crashpad.LICENSE"],
]
const SENTRY_LICENCES: PackedStringArray = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE"]


func run(args: PackedStringArray) -> int:
	var out_path: String = args[0] if not args.is_empty() else "THIRD_PARTY_NOTICES.txt"
	var lines: PackedStringArray = []
	lines.append("Four of Wands: third-party notices")
	lines.append("This game is made with the Godot Engine and the components below.")
	lines.append("")
	lines.append(RULE)
	lines.append("Godot Engine")
	lines.append(RULE)
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append(RULE)
	lines.append("Third-party components in the Godot Engine")
	lines.append(RULE)
	var used: Dictionary = {}
	for comp: Dictionary in Engine.get_copyright_info():
		lines.append("")
		lines.append(str(comp.get("name", "")))
		for part: Dictionary in comp.get("parts", []):
			for f: String in part.get("files", []):
				lines.append("  Files: " + f)
			for c: String in part.get("copyright", []):
				lines.append("  Copyright: " + c)
			var lic: String = str(part.get("license", ""))
			lines.append("  Licence: " + lic)
			for name: String in lic.split(" and "):
				used[name.strip_edges()] = true
	var sentry: String = _sentry_notice()
	if sentry != "":
		lines.append("")
		lines.append(RULE)
		lines.append("Sentry for Godot (crash reports)")
		lines.append(RULE)
		lines.append(sentry)
		for part: Array in SENTRY_PARTS:
			if not FileAccess.file_exists(part[1]):
				printerr("notices: missing %s" % part[1])
				return 1
			lines.append("")
			lines.append(RULE)
			lines.append(part[0])
			lines.append(RULE)
			lines.append(FileAccess.get_file_as_string(part[1]))
	lines.append("")
	lines.append(RULE)
	lines.append("Licence texts")
	lines.append(RULE)
	var texts: Dictionary = Engine.get_license_info()
	var names: Array = used.keys()
	names.sort()
	for name: String in names:
		if texts.has(name):
			lines.append("")
			lines.append("--- " + name + " ---")
			lines.append(str(texts[name]))
	for name: String in texts.keys():
		if not used.has(name):
			lines.append("")
			lines.append("--- " + str(name) + " ---")
			lines.append(str(texts[name]))
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("notices: cannot write %s" % out_path)
		return 1
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("NOTICES ok %s components=%d licences=%d sentry=%s" % [out_path, Engine.get_copyright_info().size(), texts.size(), sentry != ""])
	return 0


## The addon's licence text from its own folder, "" when the addon is not there.
func _sentry_notice() -> String:
	if not DirAccess.dir_exists_absolute(SENTRY_DIR):
		return ""
	for n: String in SENTRY_LICENCES:
		var p: String = SENTRY_DIR + "/" + n
		if FileAccess.file_exists(p):
			return FileAccess.get_file_as_string(p)
	return ""
