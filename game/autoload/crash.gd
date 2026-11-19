extends Node
## Crash and error reports to Sentry (docs/sentry.md). The sentry-godot addon is fetched by `tools/fetch_sentry.sh`
## into the git-ignored `addons/sentry`; the DSN lives in a git-ignored `config/sentry_credentials.cfg`
## ([sentry] dsn="..."), looked for in res://config/, then next to the executable, then user://.
## Nothing starts without the addon, without a DSN, in a scripted run (bots, sims, tests, captures), in the editor,
## or when the player turns CRASH REPORTS off in the options. A report carries the game version, the platform's
## crash data and the run's seed; no name, no IP address (send_default_pii stays off).

const FILE := "sentry_credentials.cfg"

var started := false


func _ready() -> void:
	set_enabled(Save.settings.crash_reports)
	# `-- --sentry-test` sends one message, to check a build reaches Sentry.
	if started and Flags.args.has("sentry-test"):
		Engine.get_singleton("SentrySDK").call("capture_message", "Magic Smash %s: test report" % G.VERSION)


## Starts or stops reporting. The options call it whenever CRASH REPORTS changes.
func set_enabled(on: bool) -> void:
	if not _may_run() or on == started:
		return
	var sdk: Object = Engine.get_singleton("SentrySDK")
	if not on:
		sdk.call("close")
		started = false
		return
	var dsn := _dsn()
	if dsn.is_empty():
		return
	sdk.call("init", func(o: Object) -> void:
		o.set("dsn", dsn)
		o.set("release", "magic-smash@" + G.VERSION)
		o.set("environment", "debug" if OS.is_debug_build() else "production")
		o.set("send_default_pii", false)
	)
	started = bool(sdk.call("is_enabled"))


## Labels the reports that follow (the run's seed, how many wizards), so a crash can be replayed.
func tag(key: String, value: String) -> void:
	if started:
		Engine.get_singleton("SentrySDK").call("set_tag", key, value)


func _may_run() -> bool:
	if Flags.is_scripted_run() or not Engine.has_singleton("SentrySDK"):
		return false
	return not OS.has_feature("editor") or Flags.args.has("sentry-test")


func _dsn() -> String:
	for dir: String in ["res://config/", OS.get_executable_path().get_base_dir() + "/", "user://"]:
		var cfg := ConfigFile.new()
		if cfg.load(dir + FILE) == OK:
			var dsn := String(cfg.get_value("sentry", "dsn", "")).strip_edges()
			if not dsn.is_empty():
				return dsn
	return ""
