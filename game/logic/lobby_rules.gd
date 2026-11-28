class_name LobbyRules
extends RefCounted
## What one press does in the lobby, by who pressed it (pure: plain values in, an action out; the title carries it
## out). Rules: only the device in the first seat (P1) adds or removes apprentices and leaves the lobby (asking
## first when another human is seated); another seated device's back frees its own seat only; an unseated device
## can only join (confirm).

const B_NONE := 0
const B_BACK := 1
const B_CONFIRM := 2
const B_ADD := 3
const B_REMOVE := 4

const NONE := 0
const LEAVE := 1 ## P1 leaves the lobby for the title
const ASK := 2 ## open the "leave the lobby?" question
const CLOSE := 3 ## close the question, stay
const LEAVE_SEAT := 4 ## this device's seat is freed, nothing else changes
const ADD_APPRENTICE := 5
const REMOVE_APPRENTICE := 6
const JOIN := 7 ## this unseated device takes a seat

const NO_DEVICE := -99

## `seated`: the local human devices in seat order (P1 first). `other_human`: a second human holds a seat (a local
## device or a LAN client; apprentices do not count). `asking`: the leave question is open.
static func decide(dev: int, seated: Array[int], other_human: bool, asking: bool, button: int) -> int:
	var p1: int = seated[0] if not seated.is_empty() else NO_DEVICE
	if asking:
		if dev != p1:
			return NONE
		if button == B_CONFIRM:
			return LEAVE
		return CLOSE if button == B_BACK else NONE
	if not seated.has(dev):
		if button == B_CONFIRM:
			return JOIN
		return LEAVE if button == B_BACK and seated.is_empty() else NONE
	match button:
		B_BACK:
			if dev != p1:
				return LEAVE_SEAT
			return ASK if other_human else LEAVE
		B_ADD:
			return ADD_APPRENTICE if dev == p1 else NONE
		B_REMOVE:
			return REMOVE_APPRENTICE if dev == p1 else NONE
	return NONE
