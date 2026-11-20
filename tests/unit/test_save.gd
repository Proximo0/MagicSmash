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
	for f: String in DirAccess.get_files_at(_dir):
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
