class_name DungeonRoom
extends RefCounted

var rect: Rect2i = Rect2i()
var polygon: PackedVector2Array
var doors: Array[DungeonDoor] = []


func get_center() -> Vector2i:
	return rect.get_center()


func door_count() -> int:
	return doors.size()


func count_doors_with_state(state: DungeonDoor.State) -> int:
	var n := 0
	for door in doors:
		if door.state == state:
			n += 1
	return n


func get_free_door_indices() -> Array[int]:
	var result: Array[int] = []
	for i in doors.size():
		if doors[i].state == DungeonDoor.State.FREE:
			result.append(i)
	return result
