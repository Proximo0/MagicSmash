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


func test_a_first_run_picks_the_largest_scale_that_fits() -> void:
	assert_eq(Settings.best_display(Vector2i(1366, 728)), 0, "x2 is the largest that fits")
	assert_eq(Settings.best_display(Vector2i(1920, 1040)), 1, "x3")
	assert_eq(Settings.best_display(Vector2i(3840, 2100)), 2, "capped at x4")
