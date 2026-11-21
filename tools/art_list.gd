extends SceneTree
## Lists every picture the game can show (Art.wanted) as PRESENT or MISSING with its pixel size, where it was
## found, and any file in the art folders that no key wants. Run: godot --headless --path . -s tools/art_list.gd


func _initialize() -> void:
	var present := 0
	var wanted := Art.wanted()
	for w: Array in wanted:
		var group: String = w[0]
		var key: String = w[1]
		var path := Art.find(group, key)
		if path.is_empty():
			print("MISSING  %s/%s" % [group, key])
			continue
		present += 1
		var img := Art.image(group, key)
		var size := "%dx%d" % [img.get_width(), img.get_height()] if img else "unreadable"
		print("PRESENT  %s/%s  %s  %s" % [group, key, size, path.get_base_dir().get_base_dir().get_base_dir()])
	var strays := 0
	for root: String in Art.roots():
		for f: Array in Art.listed(root):
			if not wanted.has(f):
				strays += 1
				print("STRAY    %s%s/%s.png (no key wants it)" % [root, f[0], f[1]])
	print("ART present=%d missing=%d stray=%d" % [present, wanted.size() - present, strays])
	quit()
