class_name Main
extends Node
## The entry scene. With `--server=host:port` (or --shots, --bot) it is the bare field client as before (the
## lockstep checks, the frame-rate station); otherwise it is the shell: title, login, heroes, town, and from a
## field gate the field client.
##   godot --path realm/client [-- --gateway=127.0.0.1:7700]

const FIELD_FLAGS: PackedStringArray = ["server", "shots", "bot", "fake", "zooms"]


func _ready() -> void:
	var gateway: String = ""
	var field_only: bool = false
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if FIELD_FLAGS.has(kv[0]):
			field_only = true
		elif kv[0] == "gateway" and kv.size() > 1:
			gateway = kv[1]
	if field_only:
		add_child(RealmClient.new())
		return
	var shell := Shell.new()
	if not gateway.is_empty():
		shell.set_gateway(gateway)
	add_child(shell)
	shell.show_base(TitleScreen.new(), "title")
