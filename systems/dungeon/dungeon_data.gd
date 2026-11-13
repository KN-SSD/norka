class_name DungeonData
extends RefCounted

## Wynik generatora — same dane (żadnych Node'ów).

var seed_used: int = 0
var rooms: Array[DungeonRoom] = []
var corridors: Array[Rect2i] = []


func get_bounds() -> Rect2i:
	if rooms.is_empty() and corridors.is_empty():
		return Rect2i()

	var merged: Rect2i
	var first := true

	for room in rooms:
		if first:
			merged = room.rect
			first = false
		else:
			merged = merged.merge(room.rect)

	for rect in corridors:
		if first:
			merged = rect
			first = false
		else:
			merged = merged.merge(rect)

	return merged
