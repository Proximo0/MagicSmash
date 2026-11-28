extends TestCase


func test_state_hash_changes_with_provider() -> void:
	var f: Node = load("res://game/autoload/flags.gd").new()
	var before: int = f.state_hash()
	f.register_hash(func() -> int: return 7)
	assert_true(f.state_hash() != before)
	f.free()


func test_debug_args_allowed_only_for_editor_debug_or_playtest() -> void:
	var f: Node = load("res://game/autoload/flags.gd").new()
	assert_true(f.debug_args_allowed(true, false, false))
	assert_true(f.debug_args_allowed(false, true, false))
	assert_true(f.debug_args_allowed(false, false, true))
	assert_true(not f.debug_args_allowed(false, false, false))
	f.free()


func test_release_drops_debug_flags_but_keeps_smoke_and_seed() -> void:
	var f: Node = load("res://game/autoload/flags.gd").new()
	var parsed: Dictionary = {"autotest": "1", "capture": "1", "scripted": "1", "dev": "1", "hero": "elf,mage", "smoke": "20", "seed": "7"}
	var rel: Dictionary = f.without_debug_args(parsed, false)
	assert_eq(rel, {"smoke": "20", "seed": "7"})
	assert_eq(f.without_debug_args(parsed, true), parsed)
	assert_eq(parsed.size(), 7)  # the input is not changed
	f.free()


func test_smoke_counts_as_scripted_in_any_build() -> void:
	var f: Node = load("res://game/autoload/flags.gd").new()
	# The tests run headless, where every run is scripted: the flag half of the rule is checked on its own.
	assert_true(f.has_scripted_arg(f.without_debug_args({"smoke": "1"}, false)))
	assert_true(not f.has_scripted_arg(f.without_debug_args({"autotest": "1", "capture": "1", "scripted": "1"}, false)))
	assert_true(f.has_scripted_arg({"autotest": "1"}))
	assert_true(not f.has_scripted_arg({"seed": "7", "hero": "elf,mage"}))
	f.args = f.without_debug_args({"dev": "1"}, false)
	assert_true(not f.dev_menu())
	f.free()


func test_windows_presets_version_follows_g_version() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	for sec: String in ["preset.0.options", "preset.3.options"]:
		assert_eq(cfg.get_value(sec, "application/file_version"), G.VERSION + ".0")
		assert_eq(cfg.get_value(sec, "application/product_version"), G.VERSION + ".0")
	for sec: String in ["preset.0.options", "preset.1.options", "preset.3.options", "preset.4.options"]:
		assert_eq(cfg.get_value(sec, "binary_format/embed_pck"), false)
	assert_eq(cfg.get_value("preset.0", "custom_features"), "")
	assert_eq(cfg.get_value("preset.3", "custom_features"), "playtest")
	assert_eq(cfg.get_value("preset.4", "custom_features"), "playtest")
