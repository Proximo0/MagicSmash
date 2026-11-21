class_name HeroRoster
extends RefCounted
## STUB (the real screen is written by another worker): the list of saved heroes, to pick, show, make or delete.

var active := false
## The index chosen when it closed with a pick; -1 when it closed with back.
var picked := -1


func open(_profile: Profile, _device: int = -99) -> void:
	pass


## True when the screen closed on this event.
func handle(_event: InputEvent) -> bool:
	return false


func update(_delta: float) -> void:
	pass


func draw(_ci: CanvasItem, _t: float) -> void:
	pass
