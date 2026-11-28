extends TestCase
## Settings: the options rows (game/logic/settings.gd).


func test_volumes_stop_at_their_ends() -> void:
	var s := Settings.new()
	s.music = Settings.VOL_MAX
	assert_false(s.adjust(Settings.R_MUSIC, 1), "already at the top")
	assert_eq(s.music, Settings.VOL_MAX)
	s.sound = 0
	assert_false(s.adjust(Settings.R_SOUND, -1), "already at the bottom")
	assert_true(s.adjust(Settings.R_SOUND, 1))
	assert_eq(s.sound, 1)


func test_display_wraps_and_shake_toggles() -> void:
	var s := Settings.new()
	s.display = Settings.FULLSCREEN
	s.adjust(Settings.R_DISPLAY, 1)
	assert_eq(s.display, 0)
	assert_eq(s.window_scale(), 2)
	s.adjust(Settings.R_DISPLAY, -1)
	assert_true(s.is_fullscreen())
	var was := s.shake
	s.adjust(Settings.R_SHAKE, 1)
	assert_eq(s.shake, not was)


func test_every_row_has_a_label_and_value() -> void:
	var s := Settings.new()
	for r: int in Settings.row_count():
		assert_false(Settings.label(r).is_empty())
		assert_false(s.value_text(r).is_empty())


func test_round_trip_and_clamping() -> void:
	var s := Settings.new()
	s.music = 2
	s.sound = 7
	s.display = 3
	s.shake = false
	var back := Settings.from_dict(s.to_dict())
	assert_eq(back.to_dict(), s.to_dict())
	var bad := Settings.from_dict({"music": 99, "sound": -4, "display": 12})
	assert_eq(bad.music, Settings.VOL_MAX)
	assert_eq(bad.sound, 0)
	assert_eq(bad.display, Settings.DISPLAY_NAMES.size() - 1)
	assert_true(bad.shake, "missing keys keep their defaults")


func test_the_tutorial_flag_survives_a_save() -> void:
	var s := Settings.new()
	s.seen_tutorial = true
	assert_true(Settings.from_dict(s.to_dict()).seen_tutorial)
	assert_false(Settings.from_dict({}).seen_tutorial)


func test_crash_reports_are_on_until_the_player_turns_them_off() -> void:
	var s := Settings.new()
	assert_true(s.crash_reports)
	assert_true(Settings.from_dict({}).crash_reports, "an old settings file keeps them on")
	assert_true(s.adjust(Settings.R_CRASH, 1))
	assert_false(s.crash_reports)
	assert_eq(s.value_text(Settings.R_CRASH), "OFF")
	assert_false(Settings.from_dict(s.to_dict()).crash_reports)


func test_the_window_is_fitted_to_the_screen() -> void:
	var s := Settings.new()
	s.display = 1
	assert_eq(s.fit_scale(Vector2i(1366, 728)), 2, "x3 does not fit 1366x728")
	s.display = 2
	assert_eq(s.fit_scale(Vector2i(1920, 1040)), 3, "x4 does not fit 1920x1040")
	s.display = 0
	assert_eq(s.fit_scale(Vector2i(1920, 1040)), 2)
	assert_eq(s.fit_scale(Vector2i(300, 200)), 1, "never below 1")


func test_the_rows_come_in_the_audited_order() -> void:
	var names: Array = []
	for r: int in Settings.row_count():
		names.append(Settings.label(r))
	assert_eq(names, ["MUSIC", "SOUND", "DISPLAY", "SCALING", "VSYNC", "FRAME CAP", "SCREEN SHAKE", "SCREEN FLASH",
		"CRASH REPORTS", "RESET PROGRESS"])
	assert_eq(Settings.R_RESET, Settings.row_count() - 1)


func test_labels_and_values_fit_the_panel() -> void:
	var s := Settings.new()
	for r: int in Settings.row_count():
		assert_true(Settings.label(r).length() <= Settings.LABEL_MAX, "label too long: " + Settings.label(r))
		for k in 8:
			assert_true(s.value_text(r).length() <= Settings.VALUE_MAX, "value too long: " + s.value_text(r))
			s.adjust(r, 1)


func test_scaling_wraps_and_picks_the_stretch_mode() -> void:
	var s := Settings.new()
	assert_eq(s.value_text(Settings.R_SCALING), "PIXEL PERFECT")
	assert_eq(s.stretch_mode(), Window.CONTENT_SCALE_STRETCH_INTEGER)
	assert_true(s.adjust(Settings.R_SCALING, 1))
	assert_eq(s.value_text(Settings.R_SCALING), "FILL")
	assert_eq(s.stretch_mode(), Window.CONTENT_SCALE_STRETCH_FRACTIONAL)
	s.adjust(Settings.R_SCALING, 1)
	assert_eq(s.scaling, Settings.SCALE_PIXEL, "wraps")


func test_vsync_is_on_by_default_and_toggles() -> void:
	var s := Settings.new()
	assert_true(s.vsync)
	assert_eq(s.value_text(Settings.R_VSYNC), "ON")
	assert_true(s.adjust(Settings.R_VSYNC, 1))
	assert_false(s.vsync)
	assert_eq(s.value_text(Settings.R_VSYNC), "OFF")


func test_the_frame_cap_steps_through_its_values() -> void:
	var s := Settings.new()
	assert_eq(s.max_fps(), 0, "uncapped by default")
	assert_eq(s.value_text(Settings.R_CAP), "OFF")
	var seen: Array = []
	for k in 5:
		s.adjust(Settings.R_CAP, 1)
		seen.append(s.max_fps())
	assert_eq(seen, [60, 120, 144, 240, 0], "wraps back to OFF")
	s.adjust(Settings.R_CAP, -1)
	assert_eq(s.max_fps(), 240)
	assert_eq(s.value_text(Settings.R_CAP), "240")


func test_screen_flash_caps_or_removes_a_flash() -> void:
	var s := Settings.new()
	assert_eq(s.value_text(Settings.R_FLASH), "ON")
	assert_eq(s.flash_alpha(0.8), 0.8)
	assert_true(s.strobes())
	s.adjust(Settings.R_FLASH, 1)
	assert_eq(s.value_text(Settings.R_FLASH), "SOFT")
	assert_eq(s.flash_alpha(0.8), Settings.FLASH_SOFT_ALPHA)
	assert_eq(s.flash_alpha(0.1), 0.1, "a faint flash stays as it is")
	assert_false(s.strobes())
	s.adjust(Settings.R_FLASH, 1)
	assert_eq(s.value_text(Settings.R_FLASH), "OFF")
	assert_eq(s.flash_alpha(0.8), 0.0)
	assert_false(s.strobes())
	assert_eq(Settings.FLASH_SOFT_ALPHA, 0.2)


func test_the_new_rows_survive_a_save_and_an_old_file_gets_defaults() -> void:
	var s := Settings.new()
	s.scaling = Settings.SCALE_FILL
	s.vsync = false
	s.frame_cap = 3
	s.flash = Settings.FLASH_SOFT
	s.last_window = 2
	assert_eq(Settings.from_dict(s.to_dict()).to_dict(), s.to_dict())
	var old := Settings.from_dict({"music": 3, "sound": 4, "display": 2, "shake": false, "crash_reports": true})
	assert_eq(old.scaling, Settings.SCALE_PIXEL)
	assert_true(old.vsync)
	assert_eq(old.frame_cap, 0)
	assert_eq(old.flash, Settings.FLASH_ON)
	assert_eq(old.music, 3)
	var bad := Settings.from_dict({"scaling": 9, "frame_cap": -2, "flash": 77, "last_window": 8})
	assert_eq(bad.scaling, Settings.SCALE_FILL)
	assert_eq(bad.frame_cap, 0)
	assert_eq(bad.flash, Settings.FLASH_OFF)
	assert_eq(bad.last_window, Settings.FULLSCREEN - 1)


func test_damaged_new_values_are_refused_like_the_old_ones() -> void:
	assert_true(Settings.from_dict({"scaling": [1]}) == null)
	assert_true(Settings.from_dict({"frame_cap": {}}) == null)
	assert_true(Settings.from_dict({"flash": null}) == null)
	assert_true(Settings.from_dict({"vsync": "yes"}) == null)
	assert_true(Settings.from_dict({"vsync": false, "flash": 1}) != null)


func test_fullscreen_switches_back_to_the_last_window() -> void:
	var s := Settings.new()
	s.display = 2
	s.toggle_fullscreen()
	assert_true(s.is_fullscreen())
	s.toggle_fullscreen()
	assert_eq(s.display, 2, "back to the x4 window it left")
	s.display = 0
	s.toggle_fullscreen()
	s.toggle_fullscreen()
	assert_eq(s.display, 0)
	s.display = 1
	s.adjust(Settings.R_DISPLAY, 1)
	s.adjust(Settings.R_DISPLAY, 1)
	assert_true(s.is_fullscreen())
	s.toggle_fullscreen()
	assert_eq(s.display, 2, "stepping the row also remembers the window")


func test_scaling_for_a_screen_fills_when_whole_steps_leave_too_much_black() -> void:
	assert_eq(Settings.scaling_for(Vector2i(1280, 800)), Settings.SCALE_FILL, "x2 covers 75% of the width")
	assert_eq(Settings.scaling_for(Vector2i(1366, 768)), Settings.SCALE_FILL, "x2 covers 70%")
	assert_eq(Settings.scaling_for(Vector2i(1920, 1080)), Settings.SCALE_PIXEL, "x4 covers all")
	assert_eq(Settings.scaling_for(Vector2i(1920, 1200)), Settings.SCALE_PIXEL, "x4 covers 90% of the height")
	assert_eq(Settings.scaling_for(Vector2i(2560, 1440)), Settings.SCALE_PIXEL, "x5 covers 94%")
	assert_eq(Settings.scaling_for(Vector2i(3840, 2160)), Settings.SCALE_PIXEL, "x8 covers all")
	assert_eq(Settings.scaling_for(Vector2i(300, 200)), Settings.SCALE_FILL, "smaller than one step")


func test_a_first_run_is_fullscreen_with_the_scaling_chosen() -> void:
	var s := Settings.first_run(Vector2i(1366, 768))
	assert_true(s.is_fullscreen())
	assert_eq(s.scaling, Settings.SCALE_FILL)
	assert_eq(s.display, Settings.FULLSCREEN)
	var big := Settings.first_run(Vector2i(1920, 1080))
	assert_eq(big.scaling, Settings.SCALE_PIXEL)
	assert_eq(big.last_window, 1, "the window it leaves to is x3")


func test_reset_keeps_the_old_profile_aside_and_starts_a_fresh_one() -> void:
	var dir := OS.get_temp_dir().path_join("ms_test_reset_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/profile.json"
	var p := Profile.new()
	p.high_score = 1234
	assert_true(Save.write_profile(path, p))
	var before := FileAccess.get_file_as_bytes(path).size()
	assert_true(Save.reset_profile_at(path))
	assert_eq(FileAccess.get_file_as_bytes(path + Save.RESET_SUFFIX).size(), before, "the old profile is the backup")
	var fresh: Profile = Save.read_profile(path, path + ".old")
	assert_eq(fresh.high_score, 0)
	assert_true(FileAccess.file_exists(path), "a fresh profile was written")
	# a second reset keeps the first backup too
	assert_true(Save.write_profile(path, p))
	assert_true(Save.reset_profile_at(path))
	var kept := 0
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("profile.json" + Save.RESET_SUFFIX):
			kept += 1
	assert_eq(kept, 2)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


func test_reset_never_acts_in_a_scripted_run() -> void:
	assert_false(Save.reset_progress(), "a scripted run never resets")
