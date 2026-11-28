extends TestCase
## The saved-state robot runs start only inside a private save folder (tests/bot/bot_heroes.gd, save_is_private;
## the folder comes from tools/private_save.sh). The rule that keeps a robot off a player's own save.

const BotHeroes := preload("res://tests/bot/bot_heroes.gd")


func test_a_user_folder_inside_the_private_folder_is_private() -> void:
	assert_true(BotHeroes.save_is_private("/tmp/private_save.abc", "/tmp/private_save.abc/godot/app_userdata/Four of Wands"))
	assert_true(BotHeroes.save_is_private("/tmp/private_save.abc/", "/tmp/private_save.abc/godot"))
	assert_true(BotHeroes.save_is_private("/tmp/private_save.abc", "/tmp/private_save.abc"))


func test_windows_slashes_and_case_do_not_matter() -> void:
	assert_true(BotHeroes.save_is_private("C:/Users/RUNNER~1/AppData/Local/Temp/private_save.abc",
		"c:\\users\\runner~1\\appdata\\local\\temp\\private_save.abc\\Godot\\app_userdata\\Four of Wands"))
	assert_true(BotHeroes.save_is_private("C:\\Temp\\private_save.abc", "C:/Temp/private_save.abc/Godot/app_userdata/x"))


func test_the_players_own_folder_is_not_private() -> void:
	assert_false(BotHeroes.save_is_private("", "C:/Users/someone/AppData/Roaming/Godot/app_userdata/Four of Wands"),
		"no private folder was made")
	assert_false(BotHeroes.save_is_private("/tmp/private_save.abc", "C:/Users/someone/AppData/Roaming/Godot/app_userdata/Four of Wands"),
		"the folder was made but the engine did not use it (Windows without APPDATA set)")
	assert_false(BotHeroes.save_is_private("/tmp/private_save.abc", "/home/someone/.local/share/godot/app_userdata/Four of Wands"))


func test_a_folder_that_only_starts_with_the_same_letters_is_not_private() -> void:
	assert_false(BotHeroes.save_is_private("/tmp/private_save.abc", "/tmp/private_save.abcd/godot"))
	assert_false(BotHeroes.save_is_private("/tmp/private_save.abc", "/tmp"))


func test_this_test_run_knows_the_systems_temp_folder() -> void:
	# The save tests write there (tests/unit/test_save.gd): it must be a real folder on every system.
	assert_true(DirAccess.dir_exists_absolute(OS.get_temp_dir()), OS.get_temp_dir())
