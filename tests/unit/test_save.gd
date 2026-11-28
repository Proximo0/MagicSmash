extends TestCase
## Save: the safe write and read of profile.json and settings.json (game/autoload/save.gd). Every test works in
## its own temporary folder, never in user://.

var _dir := ""


func _fresh_dir(name: String) -> String:
	_dir = "/tmp/ms_test_save_%s_%d" % [name, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(_dir)
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	return _dir + "/profile.json"


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup() -> void:
	Save.tmp_filter = Callable()
	for f: String in DirAccess.get_files_at(_dir) + DirAccess.get_directories_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	DirAccess.remove_absolute(_dir)


func test_damaged_profile_loads_the_backup_and_is_kept_aside() -> void:
	var path := _fresh_dir("damaged")
	var good := Profile.new()
	good.crystals = 77
	_put(path + ".bak", JSON.stringify(good.to_dict()))
	_put(path, "{\"crystals\": 12, \"runs\"")
	var p := Save.read_profile(path, path + ".old", true)
	assert_eq(p.crystals, 77, "the backup was not loaded")
	assert_true(FileAccess.file_exists(path + ".bad"), "the damaged file was not kept aside")
	assert_false(FileAccess.file_exists(path), "the damaged file is still in place to be written over")
	_cleanup()


func test_damaged_profile_without_backup_is_kept_not_overwritten() -> void:
	var path := _fresh_dir("nobak")
	_put(path, "not json at all")
	var p := Save.read_profile(path, path + ".old", true)
	assert_eq(p.crystals, 0)
	assert_eq(FileAccess.get_file_as_string(path + ".bad"), "not json at all")
	_cleanup()


func test_cut_short_write_leaves_the_last_good_profile() -> void:
	var path := _fresh_dir("cut")
	var p := Profile.new()
	p.crystals = 40
	assert_true(Save.write_json(path, p.to_dict()))
	p.crystals = 55
	assert_true(Save.write_json(path, p.to_dict()))
	assert_eq(Save.read_profile(path, path + ".old", true).crystals, 55)
	# A save cut short: the real file is torn.
	_put(path, "{\"crystals\": 5")
	var back := Save.read_profile(path, path + ".old", true)
	assert_eq(back.crystals, 40, "the last good profile (the backup) was not restored")
	_cleanup()


func test_a_failed_write_changes_nothing() -> void:
	var path := _fresh_dir("fail")
	var p := Profile.new()
	p.crystals = 9
	assert_true(Save.write_json(path, p.to_dict()))
	assert_false(Save.write_json(_dir + "/missing_folder/profile.json", p.to_dict()))
	assert_eq(Save.read_profile(path, path + ".old", true).crystals, 9)
	_cleanup()


func test_scripted_reads_leave_a_damaged_file_alone() -> void:
	var path := _fresh_dir("scripted")
	_put(path, "garbage")
	Save.read_profile(path, path + ".old")
	assert_true(FileAccess.file_exists(path), "a scripted read moved player data")
	_cleanup()


func test_damaged_settings_load_the_backup() -> void:
	var path := _fresh_dir("settings")
	var s := Settings.new()
	s.music = 2
	_put(path + ".bak", JSON.stringify(s.to_dict()))
	_put(path, "{")
	assert_eq(Save.read_settings(path, true).music, 2)
	_cleanup()


func test_a_write_that_fails_at_the_same_path_leaves_the_real_file_alone() -> void:
	var path := _fresh_dir("samepath")
	assert_true(Save.write_json(path, {"crystals": 9}))
	var before := FileAccess.get_file_as_bytes(path)
	DirAccess.make_dir_absolute(path + ".tmp") # the temporary file cannot be opened
	assert_false(Save.write_json(path, {"crystals": 500}))
	assert_eq(FileAccess.get_file_as_bytes(path), before, "a failed write changed the real file")
	_cleanup()


func test_a_damaged_main_file_never_replaces_a_good_backup() -> void:
	var path := _fresh_dir("badmain")
	_put(path + ".bak", JSON.stringify({"crystals": 3}))
	_put(path, "{\"crystals\": 12, \"runs\"")
	assert_true(Save.write_json(path, {"crystals": 20}))
	var bak: Variant = Save._parse(FileAccess.get_file_as_string(path + ".bak"))
	assert_true(bak is Dictionary, "the backup was overwritten with the damaged file")
	assert_eq(int(bak.crystals), 3)
	_cleanup()


func test_a_temporary_file_that_does_not_parse_never_replaces_the_real_file() -> void:
	var path := _fresh_dir("badtmp")
	assert_true(Save.write_json(path, {"crystals": 9}))
	var before := FileAccess.get_file_as_bytes(path)
	Save.tmp_filter = func(t: String) -> String: return t.left(t.length() / 2)
	assert_false(Save.write_json(path, {"crystals": 500, "runs": 4}))
	Save.tmp_filter = Callable()
	assert_eq(FileAccess.get_file_as_bytes(path), before, "a torn temporary file replaced the real file")
	assert_false(FileAccess.file_exists(path + ".tmp"), "the torn temporary file was left behind")
	_cleanup()


func test_every_damaged_copy_is_kept() -> void:
	var path := _fresh_dir("keepall")
	_put(path, "first bad")
	Save.read_json(path, true)
	_put(path, "second bad")
	Save.read_json(path, true)
	assert_eq(FileAccess.get_file_as_string(path + ".bad"), "first bad")
	var kept := 0
	for f: String in DirAccess.get_files_at(_dir):
		if f.begins_with("profile.json.bad."):
			assert_eq(FileAccess.get_file_as_string(_dir + "/" + f), "second bad")
			kept += 1
	assert_eq(kept, 1, "the second damaged file was not kept")
	_cleanup()


func test_a_damaged_backup_is_kept_aside_too() -> void:
	var path := _fresh_dir("badbak")
	_put(path, "bad main")
	_put(path + ".bak", "bad backup")
	assert_eq(Save.read_profile(path, path + ".old", true).crystals, 0)
	assert_false(FileAccess.file_exists(path + ".bak"), "the damaged backup is still there to be written over")
	assert_eq(FileAccess.get_file_as_string(path + ".bak.bad"), "bad backup")
	_cleanup()


func test_a_failed_rename_keeps_the_temporary_file_and_it_is_loaded() -> void:
	var path := _fresh_dir("rename")
	DirAccess.make_dir_absolute(path) # a folder where the file belongs: the rename fails
	assert_false(Save.write_json(path, {"crystals": 31}))
	assert_true(FileAccess.file_exists(path + ".tmp"), "the only copy of the newest data was deleted")
	DirAccess.remove_absolute(path)
	var p := Save.read_profile(path, path + ".old", true)
	assert_eq(p.crystals, 31, "the temporary file was not used when the main file is missing")
	_cleanup()


func test_a_wrong_typed_profile_loads_the_backup_and_is_kept_aside() -> void:
	var path := _fresh_dir("wrongtype")
	var good := Profile.new()
	good.crystals = 77
	_put(path + ".bak", JSON.stringify(good.to_dict()))
	_put(path, "{\"crystals\": 40, \"runs\": [1, 2]}")
	var p := Save.read_profile(path, path + ".old", true)
	assert_eq(p.crystals, 77, "the backup was not loaded")
	assert_eq(FileAccess.get_file_as_string(path + ".bad"), "{\"crystals\": 40, \"runs\": [1, 2]}")
	assert_false(FileAccess.file_exists(path), "the wrong-typed file is still in place to be written over")
	_cleanup()


func test_a_wrong_typed_profile_without_backup_starts_fresh_and_is_kept() -> void:
	var path := _fresh_dir("wrongnobak")
	for text: String in ["{\"crystals\": {\"a\": 1}}", "{\"unlocks\": {\"vigor\": [2]}}", "{\"wins\": null}",
			"{\"heroes\": [{\"level\": [3]}]}", "{\"heroes\": [{\"points\": [1, {}]}]}"]:
		_put(path, text)
		var p := Save.read_profile(path, path + ".old", true)
		assert_true(p != null, text)
		assert_eq(p.crystals, 0, text)
		assert_eq(FileAccess.get_file_as_string(path + ".bad"), text, text)
		DirAccess.remove_absolute(path + ".bad")
	_cleanup()


func test_a_wrong_typed_settings_file_loads_the_backup_or_the_defaults() -> void:
	var path := _fresh_dir("wrongsettings").get_base_dir() + "/settings.json"
	var good := Settings.new()
	good.music = 2
	_put(path + ".bak", JSON.stringify(good.to_dict()))
	_put(path, "{\"music\": 3, \"shake\": \"no\"}")
	assert_eq(Save.read_settings(path, true).music, 2, "the backup was not loaded")
	assert_eq(FileAccess.get_file_as_string(path + ".bad"), "{\"music\": 3, \"shake\": \"no\"}")
	DirAccess.remove_absolute(path + ".bak")
	DirAccess.remove_absolute(path + ".bad")
	_put(path, "{\"sound\": [1]}")
	var s := Save.read_settings(path, true)
	assert_true(s != null)
	assert_eq(s.sound, Settings.new().sound, "not the defaults")
	assert_eq(FileAccess.get_file_as_string(path + ".bad"), "{\"sound\": [1]}")
	_cleanup()


func test_a_newer_profile_loads_and_is_never_written_over() -> void:
	var path := _fresh_dir("newer")
	var text := "{\"version\": 3, \"crystals\": 50, \"runs\": 4, \"future\": {\"rune\": 9}}"
	_put(path, text)
	var p := Save.read_profile(path, path + ".old", true)
	assert_eq(p.crystals, 50, "loaded as well as it can")
	assert_true(p.newer)
	assert_false(Save.write_profile(path, p), "wrote over a newer build's save")
	var save: Node = (Save.get_script() as GDScript).new()
	save.profile = p
	assert_true(save.newer_save())
	save.finish_run({"score": 10, "seconds": 120.0, "kills": 40, "liches": 0, "won": false})
	assert_true(save.profile.newer, "finish_run cleared the mark")
	assert_false(Save.write_profile(path, save.profile))
	assert_eq(FileAccess.get_file_as_string(path), text, "the newer file's bytes changed")
	assert_false(FileAccess.file_exists(path + ".bak"))
	assert_false(FileAccess.file_exists(path + ".tmp"))
	save.free()
	_cleanup()


func test_a_newer_profile_with_a_changed_type_is_not_damage() -> void:
	var path := _fresh_dir("newertype")
	var text := "{\"version\": 3, \"crystals\": {\"gold\": 50}}"
	_put(path, text)
	var p := Save.read_profile(path, path + ".old", true)
	assert_true(p.newer, "a newer build's file was treated as damage")
	assert_eq(p.crystals, 0, "an empty profile to play on")
	assert_false(Save.write_profile(path, p), "wrote over a newer build's save")
	assert_eq(FileAccess.get_file_as_string(path), text, "the newer file's bytes changed")
	assert_false(FileAccess.file_exists(path + ".bad"), "the newer file was put aside")
	_cleanup()


func test_version_2_and_1_profiles_are_not_newer_and_still_save() -> void:
	var path := _fresh_dir("older")
	for v: int in [2, 1]:
		_put(path, "{\"version\": %d, \"crystals\": 9}" % v)
		var p := Save.read_profile(path, path + ".old", true)
		assert_eq(p.crystals, 9)
		assert_false(p.newer, "version %d marked newer" % v)
		p.crystals = 10
		assert_true(Save.write_profile(path, p))
		assert_eq(Save.read_profile(path, path + ".old", true).crystals, 10)
	var none := Save.read_profile(path + ".none", path + ".old", true)
	assert_false(none.newer, "a fresh profile is not newer")
	_cleanup()
